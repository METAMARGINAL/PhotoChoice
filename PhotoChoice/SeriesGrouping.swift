import CoreGraphics
import Foundation

// Умный отбор: серии (docs/SmartCulling.md §4.1) и сравнение кадра с соседями по серии.
// Серия — цепочка кадров, снятых подряд (интервал ≤ seriesGap) и похожих по отпечатку Vision.
// Внутри серии сцена, свет и ISO одинаковые, поэтому «мягче лучшего соседа» — самый надёжный признак смаза.

/// Положение кадра среди соседей по серии
nonisolated struct PhotoContext: Sendable {
    /// Номер серии (по порядку съёмки) и её размер; кадр вне серии — nil и 1
    var series: Int?
    var seriesSize: Int = 1
    /// Резкость в 100 % относительно самого резкого соседа: 1 — не хуже, 0.4 — в 2,5 раза мягче
    var relSharpness: Double?
    /// Доля мелких деталей минус лучшая у соседей (отрицательная — деталей меньше)
    var relDetail: Double?
    /// Качество лица минус лучшее у соседей
    var relFaceQuality: Double?
}

nonisolated enum SeriesGrouping {
    /// Порог похожести: расстояние между нормированными отпечатками (0 — одинаковые, 2 — противоположные)
    static let maxDistance: Float = 0.75
    /// Если лица совпадают (те же люди на тех же местах), прощаем бо́льшую разницу в общем виде кадра:
    /// человек сменил позу или жест — а сцена та же
    static let maxDistanceSameFaces: Float = 1.0

    /// Серии (≥ 2 кадров) в порядке съёмки
    static func build(_ items: [(url: URL, metrics: PhotoMetrics)], gap: Double) -> [[URL]] {
        let dated = items.compactMap { item -> (url: URL, date: Date, print: [Float]?, faces: [FaceMetrics])? in
            guard let date = item.metrics.captureDate else { return nil }
            return (item.url, date, normalizedPrint(item.metrics), mainFaces(item.metrics))
        }.sorted { $0.date < $1.date }

        var result: [[URL]] = []
        var chain: [URL] = []
        var previous: (date: Date, print: [Float]?, faces: [FaceMetrics])?
        for item in dated {
            var linked = false
            if let previous {
                let interval = item.date.timeIntervalSince(previous.date)
                if interval <= gap {
                    let sameFaces = facesMatch(previous.faces, item.faces)
                    if let a = previous.print, let b = item.print {
                        let d = distance(a, b)
                        linked = d <= maxDistance || (sameFaces && d <= maxDistanceSameFaces)
                    } else {
                        // Без отпечатка — совсем близкие по времени кадры или те же лица
                        linked = interval <= 1 || sameFaces
                    }
                }
            }
            if linked {
                chain.append(item.url)
            } else {
                if chain.count >= 2 { result.append(chain) }
                chain = [item.url]
            }
            previous = (item.date, item.print, item.faces)
        }
        if chain.count >= 2 { result.append(chain) }
        return result
    }

    /// Для калибровки: у каждого кадра — интервал до предыдущего по времени, расстояние отпечатков с ним
    /// и расстояние векторов модели (для серий на этапе E)
    static func previousNeighbor(_ items: [(url: URL, metrics: PhotoMetrics)]) -> [URL: (gap: Double, distance: Double?, clip: Double?)] {
        let dated = items.compactMap { item -> (url: URL, date: Date, print: [Float]?, clip: [Float]?)? in
            guard let date = item.metrics.captureDate else { return nil }
            return (item.url, date, normalizedPrint(item.metrics), ClipVector.unpack(item.metrics.clipFrame))
        }.sorted { $0.date < $1.date }
        var result: [URL: (gap: Double, distance: Double?, clip: Double?)] = [:]
        for i in dated.indices.dropFirst() {
            let a = dated[i - 1]
            let b = dated[i]
            var d: Double?
            if let pa = a.print, let pb = b.print { d = Double(distance(pa, pb)) }
            var clip: Double?
            if let ca = a.clip, let cb = b.clip { clip = ClipVector.distance(ca, cb) }
            result[b.url] = (b.date.timeIntervalSince(a.date), d, clip)
        }
        return result
    }

    /// Контекст каждого кадра серий: насколько он хуже лучшего соседа
    static func contexts(series: [[URL]], metrics: [URL: PhotoMetrics]) -> [URL: PhotoContext] {
        var result: [URL: PhotoContext] = [:]
        for (number, members) in series.enumerated() {
            for url in members {
                guard let m = metrics[url] else { continue }
                // Сравниваем только с кадрами, где резкость мерили там же: у глаз — с лицами, в объекте — без лиц.
                // Иначе портрет проигрывает соседнему кадру без людей, и «мягче соседей» ложное (по разметке — 6 из 6)
                let others = members.filter { $0 != url }.compactMap { metrics[$0] }
                    .filter { focusOnFace($0) == focusOnFace(m) }
                var context = PhotoContext(series: number, seriesSize: members.count)

                if let mine = sharpness(m), let best = others.compactMap(sharpness).max(), best > 0 {
                    context.relSharpness = mine / best
                }
                if let mine = detail(m), let best = others.compactMap(detail).max() {
                    context.relDetail = mine - best
                }
                if let mine = faceQuality(m), let best = others.compactMap(faceQuality).max() {
                    context.relFaceQuality = mine - best
                }
                result[url] = context
            }
        }
        return result
    }

    // MARK: Лучший кадр серии

    /// Итог выбора: лучший кадр и коротко — почему
    struct BestPick: Sendable {
        let url: URL
        let note: String
    }

    /// Лучший кадр серии (docs/SmartCulling.md §4.4), только относительно других кадров этой же серии.
    /// Лица сопоставляются между кадрами по положению: для каждого человека отдельно смотрим глаза и качество лица,
    /// поэтому в групповом фото выигрывает кадр, где никто не моргнул
    static func best(of members: [URL], metrics: (URL) -> PhotoMetrics?) -> BestPick? {
        let frames = members.compactMap { url in metrics(url).map { (url: url, m: $0) } }
        guard frames.count >= 2 else { return nil }

        // «Люди» серии — лица кадра, где их больше всего
        let people = frames.map { mainFaces($0.m) }.max { $0.count < $1.count } ?? []

        let sharp = frames.map { sharpness($0.m) ?? 0 }
        let maxSharp = max(sharp.max() ?? 0, 1e-9)
        let aesthetics = frames.map { $0.m.aesthetics }
        let aMin = aesthetics.compactMap { $0 }.min() ?? 0
        let aMax = aesthetics.compactMap { $0 }.max() ?? 0

        var scored: [(index: Int, score: Double, eyes: Double, quality: Double)] = []
        for (i, frame) in frames.enumerated() {
            let faces = mainFaces(frame.m)
            var eyes = 0.0
            var quality = 0.0
            if !people.isEmpty {
                for person in people {
                    // Тот же человек в этом кадре — ближайшее лицо не дальше 15 % кадра
                    let match = faces.min { center($0).pointDistance(to: center(person)) < center($1).pointDistance(to: center(person)) }
                    guard let face = match, center(face).pointDistance(to: center(person)) <= 0.15 else {
                        eyes += 0.3 // человека не нашли: отвернулся или вышел из кадра
                        continue
                    }
                    if let l = face.leftEye, let r = face.rightEye {
                        // Открыт хотя бы один глаз: 0.08 — закрыт, 0.16 и выше — открыт
                        eyes += min(1, max(0, (max(l, r) - 0.08) / 0.08))
                    } else {
                        eyes += 0.5
                    }
                    quality += face.quality ?? 0.3
                }
                eyes /= Double(people.count)
                quality /= Double(people.count)
            }
            let sharpScore = sharp[i] / maxSharp
            let aestheticsScore = aMax > aMin ? ((aesthetics[i] ?? aMin) - aMin) / (aMax - aMin) : 0.5
            let exposure = 1 - min(1, (frame.m.clipWhite ?? 0) * 8 + max(0, frame.m.clipLow - 0.05) * 4)

            let score = people.isEmpty
                ? 0.7 * sharpScore + 0.15 * aestheticsScore + 0.15 * exposure
                : 0.4 * sharpScore + 0.25 * eyes + 0.15 * quality + 0.1 * aestheticsScore + 0.1 * exposure
            scored.append((i, score, eyes, quality))
        }

        // Наибольшая оценка; при почти равных (< 0.02) — более ранний кадр
        guard let top = scored.max(by: { $0.score < $1.score }) else { return nil }
        let winner = scored.first { top.score - $0.score < 0.02 } ?? top

        var reasons: [String] = []
        if sharp[winner.index] >= maxSharp * 0.98 { reasons.append("самый резкий") }
        if !people.isEmpty {
            if winner.eyes >= 0.95 {
                reasons.append(people.count == 1 ? "глаза открыты" : "у всех открыты глаза")
            }
            if winner.quality >= (scored.map(\.quality).max() ?? 0) - 0.01 {
                reasons.append(people.count == 1 ? "лучшее лицо" : "лучшие лица")
            }
        }
        let note = reasons.isEmpty ? "Лучший по сумме резкости, лиц и экспозиции" : "Лучший: " + reasons.joined(separator: ", ")
        return BestPick(url: frames[winner.index].url, note: note)
    }

    // MARK: Лица

    /// Крупные лица: ≥ 1.5 % кадра и не меньше половины самого крупного
    static func mainFaces(_ m: PhotoMetrics) -> [FaceMetrics] {
        let area = { (face: FaceMetrics) in face.rect.width * face.rect.height }
        guard let largest = m.faces.map(area).max() else { return [] }
        return m.faces.filter { area($0) >= 0.015 && area($0) >= largest * 0.5 }
    }

    private static func center(_ face: FaceMetrics) -> CGPoint {
        CGPoint(x: face.rect.midX, y: face.rect.midY)
    }

    /// Те же люди на тех же местах: столько же крупных лиц, и у каждого есть пара не дальше 12 % кадра
    private static func facesMatch(_ a: [FaceMetrics], _ b: [FaceMetrics]) -> Bool {
        guard !a.isEmpty, a.count == b.count else { return false }
        var free = b.map(center)
        for face in a {
            let point = center(face)
            guard let nearest = free.indices.min(by: { free[$0].pointDistance(to: point) < free[$1].pointDistance(to: point) }),
                  free[nearest].pointDistance(to: point) <= 0.12 else { return false }
            free.remove(at: nearest)
        }
        return true
    }

    // MARK: Помощники

    /// Резкость в 100 % мерили у глаз (есть лицо от 0,4 % кадра), а не в центре объекта — как в PhotoAnalyzer.focusPoint
    private static func focusOnFace(_ m: PhotoMetrics) -> Bool {
        m.faces.contains { $0.rect.width * $0.rect.height >= 0.004 }
    }

    /// Резкость в 100 %, а если её нет — в уменьшенной копии
    static func sharpness(_ m: PhotoMetrics) -> Double? {
        if let full = m.fullSharpness, full > 0 { return full }
        return m.sharpness > 0 ? m.sharpness : nil
    }

    static func detail(_ m: PhotoMetrics) -> Double? {
        m.fullDetailRatio ?? m.detailRatio
    }

    /// Лучшее качество лица в кадре (Vision, 0…1)
    static func faceQuality(_ m: PhotoMetrics) -> Double? {
        m.faces.compactMap(\.quality).max()
    }

    private static func normalizedPrint(_ m: PhotoMetrics) -> [Float]? {
        guard let data = m.featurePrint, let count = m.featurePrintCount, count > 0,
              data.count >= count * MemoryLayout<Float>.size else { return nil }
        var values = [Float](repeating: 0, count: count)
        _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0, count: count * MemoryLayout<Float>.size) }
        let norm = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return nil }
        return values.map { $0 / norm }
    }

    private static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return .infinity }
        var sum: Float = 0
        for i in a.indices {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sum.squareRoot()
    }
}

private extension CGPoint {
    nonisolated func pointDistance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
