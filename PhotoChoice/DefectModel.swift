import CoreGraphics
import Foundation

// Умный отбор: модель брака, обученная на ручной разметке пользователя («Это брак» / «Это норма»).
// Не нейросеть по картинкам, а логистическая регрессия по числам анализа: резкость в 100 %,
// сравнение с соседями по серии, качество лица, яркость, пересвет… Хватает 30–50 размеченных кадров,
// обучается за доли секунды, и видно, какие признаки решили. Всё считается на этом Mac.

/// Признаки кадра для модели. nil — признака нет (лиц нет, кадр вне серии): подставляется среднее
nonisolated enum DefectFeatures {
    struct Feature {
        let name: String
        /// Как сказать человеку, если признак тянет кадр в брак
        let phrase: String
    }

    static let all: [Feature] = [
        Feature(name: "full_detail", phrase: "мало деталей в 100 %"),
        Feature(name: "full_sharpness", phrase: "резкость в 100 %"),
        Feature(name: "detail", phrase: "мало мелких деталей"),
        Feature(name: "sharpness", phrase: "резкость объекта"),
        Feature(name: "rel_sharpness", phrase: "мягче соседей по серии"),
        Feature(name: "rel_detail", phrase: "меньше деталей, чем у соседей"),
        Feature(name: "face_quality", phrase: "качество лица"),
        Feature(name: "rel_face_quality", phrase: "лицо хуже, чем у соседей"),
        Feature(name: "eyes", phrase: "глаза"),
        Feature(name: "face_luma", phrase: "яркость лиц или объекта"),
        Feature(name: "mean_luma", phrase: "яркость кадра"),
        Feature(name: "clip_white", phrase: "пересвет"),
        Feature(name: "clip_low", phrase: "провалы в тенях"),
        Feature(name: "aesthetics", phrase: "эстетическая оценка"),
        Feature(name: "tilt", phrase: "наклон горизонта"),
        Feature(name: "has_faces", phrase: "лица в кадре")
    ]

    private static func log1(_ value: Double?) -> Double? {
        value.map { log(1 + max(0, $0)) }
    }

    static func vector(_ m: PhotoMetrics, _ c: PhotoContext?) -> [Double?] {
        let mainFaces = m.faces.filter { $0.rect.width * $0.rect.height >= 0.015 }
        let eyes = mainFaces.compactMap { face -> Double? in
            guard let l = face.leftEye, let r = face.rightEye else { return nil }
            return max(l, r)
        }.min()
        return [
            m.fullDetailRatio,
            log1(m.fullSharpness),
            m.detailRatio ?? m.detailRatioGlobal,
            log1(m.sharpness),
            c?.relSharpness.map { log(max($0, 0.02)) },
            c?.relDetail,
            SeriesGrouping.faceQuality(m),
            c?.relFaceQuality,
            eyes,
            mainFaces.compactMap(\.luma).min() ?? m.subjectLuma,
            m.meanLuma,
            m.clipWhite,
            m.clipLow,
            m.aesthetics,
            m.horizonAngle.map { min(abs($0), 10) },
            mainFaces.isEmpty ? 0 : 1
        ]
    }
}

/// Обученная модель: вероятность «брак» = σ(bias + Σ wᵢ·zᵢ), zᵢ — признак, приведённый к среднему 0 и разбросу 1
nonisolated struct DefectModel: Codable, Sendable {
    var means: [Double]
    var scales: [Double]
    var weights: [Double]
    var bias: Double
    var badCount: Int
    var goodCount: Int
    /// Доля верных ответов на кадрах, которые модель не видела при обучении (проверка по частям)
    var heldOutAccuracy: Double?
    var trainedAt: Date

    static let minimumPerClass = 8

    private static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    private func standardized(_ x: [Double?]) -> [Double] {
        x.indices.map { i in
            guard i < means.count, let value = x[i] else { return 0 }
            return (value - means[i]) / scales[i]
        }
    }

    func probability(_ x: [Double?]) -> Double {
        let z = standardized(x)
        var sum = bias
        for i in z.indices where i < weights.count {
            sum += weights[i] * z[i]
        }
        return Self.sigmoid(sum)
    }

    /// Два-три признака, сильнее всего потянувшие кадр в брак — для подсказки
    func explanation(_ x: [Double?]) -> String {
        let z = standardized(x)
        let pushes = z.indices
            .filter { i in i < weights.count && x[i] != nil }
            .map { (i: $0, push: weights[$0] * z[$0]) }
            .filter { $0.push > 0.3 }
            .sorted { $0.push > $1.push }
            .prefix(3)
            .map { DefectFeatures.all[$0.i].phrase }
        return pushes.isEmpty ? "Похож на кадры, которые вы отметили как брак" : "Решили: " + pushes.joined(separator: ", ")
    }

    // MARK: Обучение

    /// `population` — все кадры папки (по ним считаются средние и разброс), `samples` — размеченные
    static func train(samples: [(x: [Double?], bad: Bool)], population: [[Double?]]) -> DefectModel? {
        let bad = samples.filter { $0.bad }.count
        let good = samples.count - bad
        guard bad >= minimumPerClass, good >= minimumPerClass else { return nil }
        let count = DefectFeatures.all.count

        var means = [Double](repeating: 0, count: count)
        var scales = [Double](repeating: 1, count: count)
        for i in 0..<count {
            let values = (population + samples.map { $0.x }).compactMap { i < $0.count ? $0[i] : nil }
            guard values.count >= 2 else { continue }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
            means[i] = mean
            scales[i] = max(variance.squareRoot(), 1e-6)
        }
        var model = DefectModel(means: means, scales: scales, weights: [Double](repeating: 0, count: count), bias: 0,
                                badCount: bad, goodCount: good, heldOutAccuracy: nil, trainedAt: Date())
        let rows = samples.map { (z: model.standardized($0.x), bad: $0.bad) }
        (model.weights, model.bias) = fit(rows, count: count)

        // Проверка по частям: 5 раз обучаем без пятой части и смотрим, угадывает ли модель отложенные кадры
        if rows.count >= 15 {
            let order = Array(rows.indices).sorted { ($0 &* 2_654_435_761) % 1_000_003 < ($1 &* 2_654_435_761) % 1_000_003 }
            var correct = 0
            for fold in 0..<5 {
                let test = order.enumerated().filter { $0.offset % 5 == fold }.map { $0.element }
                let testSet = Set(test)
                let train = rows.indices.filter { !testSet.contains($0) }.map { rows[$0] }
                let (w, b) = fit(train, count: count)
                for i in test {
                    var sum = b
                    for j in 0..<count { sum += w[j] * rows[i].z[j] }
                    if (sigmoid(sum) >= 0.5) == rows[i].bad { correct += 1 }
                }
            }
            model.heldOutAccuracy = Double(correct) / Double(rows.count)
        }
        return model
    }

    /// Градиентный спуск с L2-регуляризацией и выравниванием классов (брака обычно меньше нормы)
    private static func fit(_ rows: [(z: [Double], bad: Bool)], count: Int) -> ([Double], Double) {
        var w = [Double](repeating: 0, count: count)
        var b = 0.0
        let bad = Double(max(1, rows.filter { $0.bad }.count))
        let good = Double(max(1, rows.count - rows.filter { $0.bad }.count))
        let weightBad = Double(rows.count) / (2 * bad)
        let weightGood = Double(rows.count) / (2 * good)
        let lambda = 0.05
        let rate = 0.3
        let n = Double(rows.count)
        for _ in 0..<600 {
            var gw = [Double](repeating: 0, count: count)
            var gb = 0.0
            for row in rows {
                var sum = b
                for j in 0..<count { sum += w[j] * row.z[j] }
                let error = (sigmoid(sum) - (row.bad ? 1 : 0)) * (row.bad ? weightBad : weightGood)
                for j in 0..<count { gw[j] += error * row.z[j] }
                gb += error
            }
            for j in 0..<count {
                w[j] -= rate * (gw[j] / n + lambda * w[j])
            }
            b -= rate * gb / n
        }
        return (w, b)
    }
}
