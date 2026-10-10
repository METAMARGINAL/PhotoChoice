import CoreGraphics
import Foundation

// Умный отбор, этап 2 (docs/SmartCulling.md §5.3): правила брака.
// Вердикты не хранятся — считаются из сырых метрик кэша, поэтому смена строгости и порогов срабатывает сразу.
// Пороги настраиваются в панели «Калибровка брака» (DefectTuning). Принцип: при сомнении кадр НЕ помечаем.

/// Причина брака
nonisolated enum DefectReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case blur
    case eyesClosed
    case overexposed
    case underexposed
    case tilted
    case accidental
    /// Заметно мягче лучшего кадра своей серии
    case softer
    /// Решение модели, обученной на ручной разметке (DefectModel)
    case learned

    var id: String { rawValue }

    /// Причины с собственными правилами (без решения модели)
    static var rules: [DefectReason] { allCases.filter { $0 != .learned } }

    var title: String {
        switch self {
        case .blur: "Размыто"
        case .eyesClosed: "Закрыты глаза"
        case .overexposed: "Пересвет"
        case .underexposed: "Темно"
        case .tilted: "Завален горизонт"
        case .accidental: "Случайный кадр"
        case .softer: "Мягче соседей"
        case .learned: "По вашей разметке"
        }
    }
}

/// Пометка: причина, уверенность 0…1 и понятное пояснение
nonisolated struct Defect: Sendable {
    let reason: DefectReason
    let confidence: Double
    let detail: String
}

/// Строгость: с какой уверенности кадр попадает в «Брак»
nonisolated enum DefectStrictness: String, CaseIterable, Identifiable, Sendable {
    case soft
    case normal
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: "Мягко"
        case .normal: "Обычно"
        case .strict: "Строго"
        }
    }

    var threshold: Double {
        switch self {
        case .soft: 0.8
        case .normal: 0.6
        case .strict: 0.4
        }
    }
}

/// Сведения о папке целиком: резкость можно сравнивать со «средней» по папке
nonisolated struct FolderStats: Sendable {
    /// Медиана резкости объекта; nil — кадров пока слишком мало для сравнения
    var medianSharpness: Double?
    /// Медиана резкости в 100 % (у глаз или в центре объекта)
    var medianFullSharpness: Double? = nil

    static func make(_ metrics: [PhotoMetrics]) -> FolderStats {
        FolderStats(
            medianSharpness: median(metrics.map(\.sharpness)),
            medianFullSharpness: median(metrics.compactMap(\.fullSharpness))
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        // Меньше 20 кадров — «средняя по папке» ничего не значит: в маленькой папке разные сцены (по разметке — 3 ложных «Размыто» из 3)
        let sorted = values.filter { $0 > 0 }.sorted()
        guard sorted.count >= 20 else { return nil }
        return sorted[sorted.count / 2]
    }
}

// MARK: - Настройка порогов

/// Пороги причин. Значение порога — граница при строгости «Обычно» (уверенность 0.6);
/// «Строго» и «Мягко» сдвигают границу в ту или другую сторону
nonisolated struct DefectTuning: Codable, Equatable, Sendable {
    var blurOn = true
    /// Резкость в 100 % относительно медианы папки, ниже — «размыто»
    var blurShare = 0.35

    var eyesOn = true
    /// Открытость глаза (высота / ширина контура), ниже — «закрыты»
    var eyesOpen = 0.10

    var overOn = true
    /// Доля почти белых пикселей кадра, выше — «пересвет»
    var overWhite = 0.04

    var darkOn = true
    /// Яркость лиц (или объекта, если лиц нет), ниже — «темно»
    var darkLuma = 0.127

    var tiltOn = true
    /// Наклон горизонта в градусах, выше — «завален» (до 10°, больше — скорее задумано)
    var tiltAngle = 6.0

    var accidentalOn = true

    var softerOn = true
    /// Резкость в 100 % относительно самого резкого соседа по серии, ниже — «мягче соседей»
    var softerRatio = 0.45

    static let standard = DefectTuning()

    func isOn(_ reason: DefectReason) -> Bool {
        switch reason {
        case .blur: blurOn
        case .eyesClosed: eyesOn
        case .overexposed: overOn
        case .underexposed: darkOn
        case .tilted: tiltOn
        case .accidental: accidentalOn
        case .softer: softerOn
        case .learned: true
        }
    }

    mutating func set(_ reason: DefectReason, on: Bool) {
        switch reason {
        case .blur: blurOn = on
        case .eyesClosed: eyesOn = on
        case .overexposed: overOn = on
        case .underexposed: darkOn = on
        case .tilted: tiltOn = on
        case .accidental: accidentalOn = on
        case .softer: softerOn = on
        case .learned: break
        }
    }

    /// Порог причины (nil — у причины нет порога)
    func threshold(_ reason: DefectReason) -> Double? {
        switch reason {
        case .blur: blurShare
        case .eyesClosed: eyesOpen
        case .overexposed: overWhite
        case .underexposed: darkLuma
        case .tilted: tiltAngle
        case .softer: softerRatio
        case .accidental, .learned: nil
        }
    }

    mutating func setThreshold(_ reason: DefectReason, _ value: Double) {
        switch reason {
        case .blur: blurShare = value
        case .eyesClosed: eyesOpen = value
        case .overexposed: overWhite = value
        case .underexposed: darkLuma = value
        case .tilted: tiltAngle = value
        case .softer: softerRatio = value
        case .accidental, .learned: break
        }
    }
}

/// Шкала метрики причины — для графика и ползунка калибровки
nonisolated struct DefectScale: Sendable {
    let range: ClosedRange<Double>
    /// Брак — ниже порога (true) или выше (false)
    let defectBelow: Bool
    let name: String
    let isPercent: Bool
    let isDegrees: Bool
    /// На сколько растёт уверенность при сдвиге метрики на единицу за порог — как в правилах ниже
    let slope: Double

    /// Граница брака при строгости (у порога «Обычно» уверенность 0.6)
    func effective(_ threshold: Double, strictness: DefectStrictness) -> Double {
        let shift = (strictness.threshold - 0.6) / slope
        return defectBelow ? threshold - shift : threshold + shift
    }

    /// Обратное к `effective`: какой порог «Обычно» даёт такую границу при этой строгости
    func base(fromEffective boundary: Double, strictness: DefectStrictness) -> Double {
        let shift = (strictness.threshold - 0.6) / slope
        return defectBelow ? boundary + shift : boundary - shift
    }

    func format(_ value: Double) -> String {
        if isPercent { return String(format: "%.1f %%", value * 100) }
        if isDegrees { return String(format: "%.1f°", value) }
        return String(format: "%.3f", value)
    }

    static func of(_ reason: DefectReason) -> DefectScale? {
        switch reason {
        case .blur:
            DefectScale(range: 0.0...1.5, defectBelow: true, name: "резкость в 100 % к средней по папке", isPercent: true, isDegrees: false, slope: 1.5)
        case .eyesClosed:
            DefectScale(range: 0.0...0.4, defectBelow: true, name: "открытость глаз (худшее лицо)", isPercent: false, isDegrees: false, slope: 10.6)
        case .overexposed:
            DefectScale(range: 0.0...0.2, defectBelow: false, name: "почти белые пиксели", isPercent: true, isDegrees: false, slope: 10)
        case .underexposed:
            DefectScale(range: 0.0...0.6, defectBelow: true, name: "яркость лиц или объекта", isPercent: true, isDegrees: false, slope: 6.4)
        case .tilted:
            DefectScale(range: 0.0...10.0, defectBelow: false, name: "наклон горизонта", isPercent: false, isDegrees: true, slope: 0.1)
        case .softer:
            DefectScale(range: 0.0...1.2, defectBelow: true, name: "резкость относительно лучшего кадра серии", isPercent: true, isDegrees: false, slope: 1.5)
        case .accidental, .learned:
            nil
        }
    }
}

// MARK: - Правила

nonisolated enum DefectRules {
    /// Все кандидаты с уверенностью от 0.3, самые уверенные первыми. Фильтр по строгости — у вызывающего
    static func evaluate(_ m: PhotoMetrics, context: PhotoContext?, stats: FolderStats, tuning: DefectTuning,
                         signals: ModelSignals? = nil) -> [Defect] {
        var found: [Defect?] = []
        if tuning.blurOn { found.append(blur(m, stats, tuning, signals)) }
        if tuning.eyesOn { found.append(eyesClosed(m, tuning)) }
        if tuning.overOn { found.append(overexposed(m, tuning)) }
        if tuning.darkOn { found.append(underexposed(m, tuning)) }
        if tuning.tiltOn { found.append(tilted(m, tuning)) }
        if tuning.accidentalOn { found.append(accidental(m)) }
        if tuning.softerOn { found.append(softer(context, tuning)) }
        return found
            .compactMap { $0 }
            .filter { $0.confidence >= 0.3 }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Значение метрики причины у кадра — то, с чем сравнивается порог (для графика калибровки)
    static func value(_ reason: DefectReason, _ m: PhotoMetrics, context: PhotoContext? = nil,
                      stats: FolderStats? = nil) -> Double? {
        switch reason {
        case .blur:
            if let exposure = m.exposureTime, exposure >= 0.25 { return nil }
            return stats.flatMap { fullShare(m, $0) }
        case .eyesClosed:
            return worstEyes(m)
        case .overexposed:
            return m.clipWhite
        case .underexposed:
            return darkMetric(m)
        case .tilted:
            return m.horizonAngle.map(abs)
        case .softer:
            return context?.relSharpness
        case .accidental, .learned:
            return nil
        }
    }

    // MARK: Помощники

    private static func clamp(_ x: Double, _ cap: Double) -> Double {
        min(cap, max(0, x))
    }

    /// 0 при `zero`, 1 при `one`, линейно между ними (работает в обе стороны)
    private static func ramp(_ x: Double, _ zero: Double, _ one: Double) -> Double {
        guard zero != one else { return x >= one ? 1 : 0 }
        return min(1, max(0, (x - zero) / (one - zero)))
    }

    private static func percent(_ share: Double) -> String {
        let value = share * 100
        return value < 10 ? String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",") : "\(Int(value.rounded()))"
    }

    /// Крупные лица: ≥ 1.5 % кадра и не меньше половины самого крупного лица; мелкие лица на фоне не в счёт
    private static func mainFaces(_ m: PhotoMetrics) -> [FaceMetrics] {
        let area = { (face: FaceMetrics) in face.rect.width * face.rect.height }
        guard let largest = m.faces.map(area).max() else { return [] }
        return m.faces.filter { area($0) >= 0.015 && area($0) >= largest * 0.5 }
    }

    // MARK: Размыто

    /// Резкость в 100 % к медиане папки. «Доля мелких деталей» на 1280 px больше не решает:
    /// на портретах она меряет гладкую кожу и шумодав, а не фокус (docs/SmartCulling-ML.md §1)
    private static func fullShare(_ m: PhotoMetrics, _ stats: FolderStats) -> Double? {
        guard let full = m.fullSharpness, full > 0, let median = stats.medianFullSharpness, median > 0 else { return nil }
        return full / median
    }

    /// Второе мнение MobileCLIP для «Размыто». По разметке 5 папок: на ложных пометках модель давала 0.30–0.66,
    /// на настоящем смазе — от 0.93. Ниже порога лапласиан, скорее всего, обманулся гладкой кожей или боке
    static let modelBlurAgree = 0.85

    private static func blur(_ m: PhotoMetrics, _ stats: FolderStats, _ t: DefectTuning, _ signals: ModelSignals?) -> Defect? {
        // Длинная выдержка — смаз, скорее всего, задуман
        if let exposure = m.exposureTime, exposure >= 0.25 { return nil }
        guard let share = fullShare(m, stats) else { return nil }
        let confidence = clamp(0.6 + 1.5 * (t.blurShare - share), 0.9)
        guard confidence > 0 else { return nil }
        if let p = signals?.blur, p < modelBlurAgree { return nil }
        let place = m.faces.contains { $0.rect.width * $0.rect.height >= 0.004 } ? "у глаз" : "в объекте"
        let percentText = "\(Int((share * 100).rounded())) %"
        var detail = "Резкость \(place) — \(percentText) от средней по папке"
        if let p = signals?.blur {
            detail += " · модель: размыто \(Int((p * 100).rounded())) %"
        }
        return Defect(reason: .blur, confidence: confidence, detail: detail)
    }

    // MARK: Закрыты глаза

    /// Открытость лица: закрыты должны быть ОБА глаза, поэтому берём более открытый
    private static func openness(_ face: FaceMetrics) -> Double? {
        guard let left = face.leftEye, let right = face.rightEye else { return nil }
        return max(left, right)
    }

    /// Почти фронтальные крупные лица, у которых известны оба глаза
    private static func eyeFaces(_ m: PhotoMetrics) -> [Double] {
        mainFaces(m).filter { abs($0.yaw ?? 0) < 30 }.compactMap(openness)
    }

    private static func worstEyes(_ m: PhotoMetrics) -> Double? {
        eyeFaces(m).min()
    }

    private static func eyesClosed(_ m: PhotoMetrics, _ t: DefectTuning) -> Defect? {
        let faces = eyeFaces(m)
        guard !faces.isEmpty else { return nil }
        let confidences = faces.map { clamp(0.6 + 10.6 * (t.eyesOpen - $0), 0.85) }
        let closed = confidences.filter { $0 >= 0.4 }.count
        guard let strongest = confidences.max(), strongest > 0 else { return nil }
        let detail = faces.count == 1 ? "Глаза закрыты" : "Закрыты глаза — \(max(closed, 1)) из \(faces.count) лиц"
        return Defect(reason: .eyesClosed, confidence: strongest, detail: detail)
    }

    // MARK: Пересвет

    private static func overexposed(_ m: PhotoMetrics, _ t: DefectTuning) -> Defect? {
        // Почти белые пиксели (все каналы ≥ 250). Насыщенные цвета (красный, синий) сюда не попадают
        let white = m.clipWhite ?? 0
        var clipConfidence = 0.0
        if white >= 0.01 {
            clipConfidence = clamp(0.6 + 10 * (white - t.overWhite), 0.95)
            // Окно, лампы, небо за спиной — не брак: по разметке половина ложных «Пересветов» такие.
            // Засчитываем, только если выбито хоть что-то на лицах или на главном объекте
            if let onSubject = subjectWhite(m), onSubject < 0.02 {
                clipConfidence = 0
            }
        }
        // Выбеленные лица
        let faceLuma = mainFaces(m).compactMap(\.luma).max()
        let faceConfidence = faceLuma.map { 0.8 * ramp($0, 0.8, 0.92) } ?? 0

        let confidence = max(clipConfidence, faceConfidence)
        guard confidence > 0 else { return nil }
        let detail = faceConfidence > clipConfidence
            ? "Лица выбелены"
            : "Выбито \(percent(white)) % кадра"
        return Defect(reason: .overexposed, confidence: confidence, detail: detail)
    }

    /// Пересвет на главном: самое выбеленное крупное лицо, без лиц — объект. nil — кэш старый, не мерили
    private static func subjectWhite(_ m: PhotoMetrics) -> Double? {
        let faces = mainFaces(m).compactMap(\.white)
        if !faces.isEmpty { return faces.max() }
        return m.subjectWhite
    }

    // MARK: Темно

    /// Яркость самого тёмного крупного лица, а если лиц нет — главного объекта
    private static func darkMetric(_ m: PhotoMetrics) -> Double? {
        mainFaces(m).compactMap(\.luma).min() ?? m.subjectLuma
    }

    private static func underexposed(_ m: PhotoMetrics, _ t: DefectTuning) -> Defect? {
        var best: (confidence: Double, detail: String)?
        func consider(_ confidence: Double, _ detail: String) {
            if confidence > (best?.confidence ?? 0) { best = (confidence, detail) }
        }

        if let luma = darkMetric(m) {
            let hasFaces = !mainFaces(m).isEmpty
            consider(clamp(0.6 + 6.4 * (t.darkLuma - luma), 0.9),
                     hasFaces ? "Лица в тени — яркость \(percent(luma)) %" : "Тёмный объект — яркость \(percent(luma)) %")
        }
        // Весь кадр тёмный (часто задумано — поэтому вес ниже, кроме явных провалов)
        var dark = 0.75 * ramp(m.meanLuma, 0.16, 0.06)
        if m.clipLow > 0.25 { dark = max(dark, 0.85 * ramp(m.meanLuma, 0.2, 0.08)) }
        consider(dark, "Тёмный кадр — средняя яркость \(percent(m.meanLuma)) %")

        guard let best, best.confidence > 0 else { return nil }
        return Defect(reason: .underexposed, confidence: best.confidence, detail: best.detail)
    }

    // MARK: Горизонт

    private static func tilted(_ m: PhotoMetrics, _ t: DefectTuning) -> Defect? {
        guard let angle = m.horizonAngle.map(abs), angle >= 2, angle <= 10 else { return nil }
        // Не выше 0.7: при «Мягко» не помечается никогда — наклон часто задуман
        let confidence = clamp(0.6 + 0.1 * (angle - t.tiltAngle), 0.7)
        guard confidence > 0 else { return nil }
        return Defect(reason: .tilted, confidence: confidence,
                      detail: "Наклон \(String(format: "%.1f", angle).replacingOccurrences(of: ".", with: ","))°")
    }

    // MARK: Мягче соседей

    private static func softer(_ context: PhotoContext?, _ t: DefectTuning) -> Defect? {
        guard let context, let ratio = context.relSharpness else { return nil }
        // Мелких деталей не меньше, чем у лучшего соседа, — разница в резкости, скорее всего, от сюжета
        if let detail = context.relDetail, detail > 0.02 { return nil }
        let confidence = clamp(0.6 + 1.5 * (t.softerRatio - ratio), 0.9)
        guard confidence > 0 else { return nil }
        let times = ratio > 0 ? 1 / ratio : 10
        let detail = times >= 1.5
            ? "В \(String(format: "%.1f", times).replacingOccurrences(of: ".", with: ",")) раза мягче лучшего кадра серии"
            : "Мягче лучшего кадра серии"
        return Defect(reason: .softer, confidence: confidence, detail: detail)
    }

    // MARK: Случайный кадр

    private static func accidental(_ m: PhotoMetrics) -> Defect? {
        if m.isUtility == true {
            return Defect(reason: .accidental, confidence: 0.65, detail: "Похоже на служебный снимок")
        }
        // Очень низкая эстетика + кадр почти чёрный или белый: земля, карман, ремень
        if let aesthetics = m.aesthetics, aesthetics < -0.3, m.meanLuma < 0.1 || m.meanLuma > 0.9 {
            return Defect(reason: .accidental, confidence: 0.7, detail: "Похоже на случайное срабатывание")
        }
        // Эстетика Vision сильно ниже нуля — по разметке 14 папок все такие кадры брак (11 из 11, нормы ни одной):
        // смаз, промах, неудачный момент. −0.3 — граница «Обычно», −0.4 — «Мягко»
        if let aesthetics = m.aesthetics, aesthetics < -0.2 {
            let confidence = clamp(0.6 + 2 * (-0.3 - aesthetics), 0.9)
            if confidence > 0 {
                return Defect(reason: .accidental, confidence: confidence, detail: "Неудачный кадр: очень низкая эстетическая оценка")
            }
        }
        return nil
    }
}
