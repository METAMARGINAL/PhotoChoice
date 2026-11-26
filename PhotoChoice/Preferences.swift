import Foundation

// Настройки в одном месте: имена ключей и значения по умолчанию (docs/Settings.md).
// `Pref.register()` — на старте приложения, после неё `UserDefaults.bool(forKey:)` отдаёт правильное умолчание.

/// Функции, которые включаются по отдельности. Выключенная не оставляет клавиш, подсказок и пунктов меню
nonisolated enum Feature: String, CaseIterable, Identifiable, Sendable {
    case transfer, stars, colors, flags, compare, drawing, adjust, info

    var id: String { rawValue }

    /// `featureTransfer`, `featureStars`…
    var key: String { "feature" + rawValue.capitalized }

    var defaultOn: Bool {
        switch self {
        case .transfer, .compare, .drawing, .adjust, .info: true
        case .stars, .colors, .flags: false
        }
    }

    var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    func set(_ on: Bool) { UserDefaults.standard.set(on, forKey: key) }

    var title: String {
        switch self {
        case .transfer: "Перенос по папкам"
        case .stars: "Звёзды"
        case .colors: "Цветовые метки"
        case .flags: "Флаги"
        case .compare: "Сравнение"
        case .drawing: "Рисование"
        case .adjust: "Коррекция"
        case .info: "Сведения о снимке"
        }
    }

    var detail: String {
        switch self {
        case .transfer: "Клавиши 1–9 переносят кадр в выбранные папки"
        case .stars: "Оценка от одной до пяти звёзд"
        case .colors: "Восемь цветов, как в Lightroom и Bridge"
        case .flags: "Оставить или отклонить, без перебора звёзд"
        case .compare: "Два кадра рядом с общим зумом"
        case .drawing: "Пометки поверх кадра, оригинал не меняется"
        case .adjust: "Экспозиция, тени, цвет — ползунками; сохраняется копия"
        case .info: "Параметры съёмки, гистограмма и палитра цветов"
        }
    }

    var keys: [String] {
        switch self {
        case .transfer: ["1–9"]
        case .stars: ["⌥0–5"]
        case .colors: ["⌃0–8"]
        case .flags: ["⌥P", "⌥X", "⌥U"]
        case .compare: ["C"]
        case .drawing: ["D"]
        case .adjust: ["E"]
        case .info: ["I"]
        }
    }
}

/// Режим только расставляет галочки на странице «Функции»; отдельно не хранится
nonisolated enum WorkMode: String, CaseIterable, Identifiable, Sendable {
    case folders, marks, everything, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .folders: "Раскладка по папкам"
        case .marks: "Только оценки"
        case .everything: "Всё вместе"
        case .custom: "Свой набор"
        }
    }

    /// Перенос и оценки (звёзды, цвета, флаги вместе); у «Своего набора» — нет
    var preset: (transfer: Bool, marks: Bool)? {
        switch self {
        case .folders: (true, false)
        case .marks: (false, true)
        case .everything: (true, true)
        case .custom: nil
        }
    }

    static func current(transfer: Bool, stars: Bool, colors: Bool, flags: Bool) -> WorkMode {
        let marks = stars && colors && flags
        let noMarks = !stars && !colors && !flags
        switch (transfer, marks, noMarks) {
        case (true, false, true): return .folders
        case (false, true, false): return .marks
        case (true, true, false): return .everything
        default: return .custom
        }
    }

    func apply() {
        guard let preset else { return }
        Feature.transfer.set(preset.transfer)
        Feature.stars.set(preset.marks)
        Feature.colors.set(preset.marks)
        Feature.flags.set(preset.marks)
    }
}

nonisolated enum Pref {
    static let pairRawJpeg = "pairRawJpeg"
    static let sortByCaptureDate = "sortByCaptureDate"
    static let autoKeepFolder = "autoKeepFolder"
    static let renameOnMove = "renameOnMove"
    static let smartAnalysis = "smartAnalysis"
    static let defectAutoZoom = "defectAutoZoom"
    static let seriesGap = "seriesGap"
    static let peopleEnabled = "peopleEnabled"
    static let qualityModelEnabled = "qualityModelEnabled"
    static let paletteEnabled = "paletteEnabled"
    /// Панели в просмотре гаснут через 2 с покоя
    static let autoHideHUD = "autoHideHUD"
    /// «Нейтраль»: фон под фото в просмотре (номер образца)
    static let surroundTone = "surroundTone"
    static let themeDirection = "themeDirection"

    private static let version = "prefsVersion"

    static func register() {
        var defaults: [String: Any] = [
            pairRawJpeg: true,
            sortByCaptureDate: false,
            autoKeepFolder: true,
            renameOnMove: false,
            smartAnalysis: true,
            defectAutoZoom: false,
            seriesGap: 3.0,
            peopleEnabled: true,
            qualityModelEnabled: true,
            paletteEnabled: true,
            autoHideHUD: false,
            surroundTone: 2
        ]
        for feature in Feature.allCases {
            defaults[feature.key] = feature.defaultOn
        }
        UserDefaults.standard.register(defaults: defaults)
        migrate()
    }

    /// 1: звёзды и цвета были одним флагом `marksEnabled`; темы «Студия», «Тишина», «Контакт» заменены
    private static func migrate() {
        let store = UserDefaults.standard
        guard store.integer(forKey: version) < 1 else { return }
        if store.bool(forKey: "marksEnabled") {
            Feature.stars.set(true)
            Feature.colors.set(true)
        }
        let renamed = ["studio": "neutral", "quiet": "table", "contact": "film"]
        if let old = store.string(forKey: themeDirection), let new = renamed[old] {
            store.set(new, forKey: themeDirection)
        }
        store.set(1, forKey: version)
    }
}
