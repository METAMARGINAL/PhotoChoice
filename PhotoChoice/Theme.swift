import AppKit
import Combine
import SwiftUI

// Темы 2.0 (холст «PhotoChoice: темы 2.0»): у каждой одна идея.
// «Плёнка» — контрольный лист с красным карандашом, «Жидкое стекло» — капсулы как в macOS 26,
// «Нейтраль» — серый без оттенка с колонкой папок, «Световой стол» — светлый дневной режим.
// Просмотр, рисование и сравнение всегда тёмные: белое поле искажает яркость снимка.

// MARK: - Выбор пользователя

nonisolated enum ThemeDirection: String, CaseIterable, Identifiable, Sendable {
    case film, glass, neutral, table

    var id: String { rawValue }

    var title: String {
        switch self {
        case .film: "Плёнка"
        case .glass: "Жидкое стекло"
        case .neutral: "Нейтраль"
        case .table: "Световой стол"
        }
    }

    var tagline: String {
        switch self {
        case .film: "Контрольный лист и красный карандаш"
        case .glass: "Фото на весь экран, стеклянные капсулы"
        case .neutral: "Серый без оттенка, папки всегда на виду"
        case .table: "Светлый стол с отпечатками, тёмный пульт"
        }
    }

    /// Есть светлый и тёмный варианты (переключаются режимом оформления)
    var hasLight: Bool { self == .glass }

    /// Всегда светлая (кроме просмотра)
    var alwaysLight: Bool { self == .table }
}

nonisolated enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Как в системе"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }
}

// MARK: - Палитра

nonisolated struct ThemePalette: Sendable {
    var canvas, app, surface1, surface2, surface3, overlay: Color
    var line, lineStrong: Color
    var text1, text2, text3: Color
    var accent, accentFill, onAccent, selection, selectionFill, focus: Color
    var success, warning, danger, edge: Color
    var keyFill, keyLine, keyText, toastFill: Color
    var histR, histG, histB, clipHigh, clipLow: Color
}

extension Color {
    /// Цвет sRGB из 0xRRGGBB
    nonisolated init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    nonisolated static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

extension ThemePalette {
    /// «Плёнка»: края плёнки тёплые, номера кадров янтарные, выбор — красный карандаш
    nonisolated static let film = ThemePalette(
        canvas: Color(hex: 0x0E0E0E), app: Color(hex: 0x0E0E0E),
        surface1: Color(hex: 0x171717), surface2: Color(hex: 0x1F1F1F), surface3: Color(hex: 0x2C2C2C),
        overlay: .rgba(22, 22, 22, 0.94),
        line: Color(hex: 0x262626), lineStrong: Color(hex: 0x5A5650),
        text1: Color(hex: 0xECE9E4), text2: Color(hex: 0xA9A59E), text3: Color(hex: 0x8C8881),
        accent: Color(hex: 0xE8A13A), accentFill: Color(hex: 0xECE9E4), onAccent: Color(hex: 0x111111),
        selection: Color(hex: 0xF2493C), selectionFill: .rgba(242, 73, 60, 0.12), focus: Color(hex: 0xF2493C),
        success: Color(hex: 0x8FCF7A), warning: Color(hex: 0xE3A64A), danger: Color(hex: 0xF2493C), edge: Color(hex: 0xE8A13A),
        keyFill: Color(hex: 0x242424), keyLine: .clear, keyText: Color(hex: 0xECE9E4),
        toastFill: .rgba(22, 22, 22, 0.94),
        histR: Color(hex: 0xFF5A52), histG: Color(hex: 0x4ED36A), histB: Color(hex: 0x4C8DFF),
        clipHigh: Color(hex: 0xFF4D4D), clipLow: Color(hex: 0x4D8DFF)
    )

    nonisolated static let glass = ThemePalette(
        canvas: Color(hex: 0x0A0A0B), app: Color(hex: 0x0A0A0B),
        surface1: Color(hex: 0x1A1A1C), surface2: Color(hex: 0x2C2C2E), surface3: Color(hex: 0x3A3A3C),
        overlay: .rgba(46, 46, 52, 0.5),
        line: .rgba(255, 255, 255, 0.12), lineStrong: .rgba(255, 255, 255, 0.42),
        text1: Color(hex: 0xFFFFFF), text2: .rgba(255, 255, 255, 0.76), text3: .rgba(255, 255, 255, 0.6),
        accent: Color(hex: 0x3D9BFF), accentFill: Color(hex: 0x0A84FF), onAccent: Color(hex: 0xFFFFFF),
        selection: Color(hex: 0x3D9BFF), selectionFill: .rgba(61, 155, 255, 0.20), focus: Color(hex: 0x3D9BFF),
        success: Color(hex: 0x30D158), warning: Color(hex: 0xFFD60A), danger: Color(hex: 0xFF453A), edge: .rgba(255, 255, 255, 0.6),
        keyFill: .rgba(255, 255, 255, 0.2), keyLine: .clear, keyText: Color(hex: 0xFFFFFF),
        toastFill: .rgba(40, 40, 42, 0.55),
        histR: Color(hex: 0xFF6159), histG: Color(hex: 0x4CD964), histB: Color(hex: 0x4D9BFF),
        clipHigh: Color(hex: 0xFF453A), clipLow: Color(hex: 0x3D9BFF)
    )

    nonisolated static let glassLight = ThemePalette(
        canvas: Color(hex: 0x0A0A0B), app: Color(hex: 0xF2F2F2),
        surface1: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xEBEBEB), surface3: Color(hex: 0xDEDEDE),
        overlay: .rgba(255, 255, 255, 0.62),
        line: .rgba(0, 0, 0, 0.10), lineStrong: .rgba(0, 0, 0, 0.50),
        text1: Color(hex: 0x1D1D1F), text2: Color(hex: 0x48484A), text3: Color(hex: 0x666669),
        accent: Color(hex: 0x0062CC), accentFill: Color(hex: 0x0A84FF), onAccent: Color(hex: 0xFFFFFF),
        selection: Color(hex: 0x0070E8), selectionFill: .rgba(0, 122, 255, 0.14), focus: Color(hex: 0x0070E8),
        success: Color(hex: 0x1F7A36), warning: Color(hex: 0x8A6000), danger: Color(hex: 0xC9001A), edge: Color(hex: 0x666669),
        keyFill: .rgba(0, 0, 0, 0.07), keyLine: .clear, keyText: Color(hex: 0x1D1D1F),
        toastFill: .rgba(255, 255, 255, 0.66),
        histR: Color(hex: 0xFF6159), histG: Color(hex: 0x4CD964), histB: Color(hex: 0x4D9BFF),
        clipHigh: Color(hex: 0xFF453A), clipLow: Color(hex: 0x3D9BFF)
    )

    /// «Нейтраль»: серый без оттенка — интерфейс не влияет на то, как выглядит цвет кадра
    nonisolated static let neutral = ThemePalette(
        canvas: Color(hex: 0x2B2B2B), app: Color(hex: 0x1E1E1E),
        surface1: Color(hex: 0x242424), surface2: Color(hex: 0x2E2E2E), surface3: Color(hex: 0x3A3A3A),
        overlay: .rgba(36, 36, 36, 0.94),
        line: Color(hex: 0x333333), lineStrong: Color(hex: 0x727272),
        text1: Color(hex: 0xE8E8E8), text2: Color(hex: 0xB4B4B4), text3: Color(hex: 0x959595),
        accent: Color(hex: 0xFFFFFF), accentFill: Color(hex: 0xECECEC), onAccent: Color(hex: 0x161616),
        selection: Color(hex: 0xFFFFFF), selectionFill: .rgba(255, 255, 255, 0.08), focus: Color(hex: 0xFFFFFF),
        success: Color(hex: 0x7CC992), warning: Color(hex: 0xE6C35C), danger: Color(hex: 0xF0786C), edge: Color(hex: 0x959595),
        keyFill: Color(hex: 0x3A3A3A), keyLine: .clear, keyText: Color(hex: 0xE8E8E8),
        toastFill: Color(hex: 0x161616),
        histR: Color(hex: 0xFF5A52), histG: Color(hex: 0x4ED36A), histB: Color(hex: 0x4C8DFF),
        clipHigh: Color(hex: 0xFF4D4D), clipLow: Color(hex: 0x4D8DFF)
    )

    /// «Световой стол»: светлый стол, белые отпечатки, тёмные чернила
    nonisolated static let table = ThemePalette(
        canvas: Color(hex: 0x1C1C1C), app: Color(hex: 0xF2F1EF),
        surface1: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xF6F5F3), surface3: Color(hex: 0xECEBE8),
        overlay: .rgba(255, 255, 255, 0.96),
        line: .rgba(20, 20, 25, 0.10), lineStrong: .rgba(20, 20, 25, 0.32),
        text1: Color(hex: 0x1A1B1E), text2: Color(hex: 0x55585E), text3: Color(hex: 0x686B72),
        accent: Color(hex: 0x1A1B1E), accentFill: Color(hex: 0x1A1B1E), onAccent: Color(hex: 0xFFFFFF),
        selection: Color(hex: 0x1A1B1E), selectionFill: .rgba(26, 27, 30, 0.07), focus: Color(hex: 0x1A1B1E),
        success: Color(hex: 0x2F7D4A), warning: Color(hex: 0x9A6400), danger: Color(hex: 0xC8321F), edge: Color(hex: 0x686B72),
        keyFill: Color(hex: 0xECEBE8), keyLine: .clear, keyText: Color(hex: 0x1A1B1E),
        toastFill: Color(hex: 0xFFFFFF),
        histR: Color(hex: 0xE5484D), histG: Color(hex: 0x30A46C), histB: Color(hex: 0x3E7BFA),
        clipHigh: Color(hex: 0xE5484D), clipLow: Color(hex: 0x3E7BFA)
    )

    /// «Световой стол» в просмотре: тёмное поле, пульт тот же
    nonisolated static let tableDark = ThemePalette(
        canvas: Color(hex: 0x1C1C1C), app: Color(hex: 0x1C1C1C),
        surface1: Color(hex: 0x242528), surface2: Color(hex: 0x2B2B2B), surface3: Color(hex: 0x4A4A4A),
        overlay: .rgba(32, 33, 36, 0.94),
        line: .rgba(255, 255, 255, 0.10), lineStrong: .rgba(255, 255, 255, 0.35),
        text1: Color(hex: 0xEEEEEE), text2: Color(hex: 0xB3B3B3), text3: Color(hex: 0x8E9096),
        accent: Color(hex: 0xFFFFFF), accentFill: Color(hex: 0xFFFFFF), onAccent: Color(hex: 0x1A1B1E),
        selection: Color(hex: 0xFFFFFF), selectionFill: .rgba(255, 255, 255, 0.10), focus: Color(hex: 0xFFFFFF),
        success: Color(hex: 0x7CC992), warning: Color(hex: 0xE6C35C), danger: Color(hex: 0xF0786C), edge: Color(hex: 0x8E9096),
        keyFill: .rgba(255, 255, 255, 0.18), keyLine: .clear, keyText: Color(hex: 0xFFFFFF),
        toastFill: Color(hex: 0xFFFFFF),
        histR: Color(hex: 0xFF5A52), histG: Color(hex: 0x4ED36A), histB: Color(hex: 0x4C8DFF),
        clipHigh: Color(hex: 0xFF4D4D), clipLow: Color(hex: 0x4D8DFF)
    )
}

// MARK: - Тема

nonisolated struct Theme: Sendable {
    let direction: ThemeDirection
    let isLight: Bool
    let c: ThemePalette

    /// `light` — хочется светлого (режим оформления); «Световой стол» светлый всегда, кроме просмотра (`light: false`)
    static func make(_ direction: ThemeDirection, light: Bool) -> Theme {
        let useLight = light && (direction.hasLight || direction.alwaysLight)
        let palette: ThemePalette
        switch (direction, useLight) {
        case (.film, _): palette = .film
        case (.glass, false): palette = .glass
        case (.glass, true): palette = .glassLight
        case (.neutral, _): palette = .neutral
        case (.table, false): palette = .tableDark
        case (.table, true): palette = .table
        }
        return Theme(direction: direction, isLight: useLight, c: palette)
    }

    /// Стартовое окно, сетка и настройки: учитывает, что «Световой стол» светлый всегда
    static func chrome(_ direction: ThemeDirection, wantsLight: Bool) -> Theme {
        make(direction, light: direction.alwaysLight || wantsLight)
    }

    static let `default` = Theme.make(.neutral, light: false)

    var isFilm: Bool { direction == .film }
    var isGlass: Bool { direction == .glass }
    var isNeutral: Bool { direction == .neutral }
    var isTable: Bool { direction == .table }

    /// Красный карандаш «Плёнки»
    var pen: Color { Color(hex: 0xF2493C) }

    /// Нижний пульт «Светового стола» — тёмный и в сетке, и в просмотре
    var trayFill: Color { Color(hex: 0x1A1B1E) }

    // MARK: Радиусы

    var rSm: CGFloat {
        switch direction {
        case .film: 2
        case .glass: 8
        case .neutral: 4
        case .table: 2
        }
    }

    var rMd: CGFloat {
        switch direction {
        case .film: 5
        case .glass: 18
        case .neutral: 7
        case .table: 10
        }
    }

    var rLg: CGFloat {
        switch direction {
        case .film: 12
        case .glass: 32
        case .neutral: 10
        case .table: 18
        }
    }

    /// Радиус кнопок и полей; у «Стекла» кнопки — капсулы (считается от высоты)
    var rControl: CGFloat {
        switch direction {
        case .film: 7
        case .glass: 999
        case .neutral: 6
        case .table: 9
        }
    }

    // MARK: Каркас

    var topbarHeight: CGFloat {
        switch direction {
        case .film: 56
        case .glass: 52
        case .neutral: 44
        case .table: 64
        }
    }

    /// Высота строки подсказок (у «Стекла» — капсула с отступом снизу)
    var hintbarHeight: CGFloat {
        switch direction {
        case .film: 52
        case .glass: 54
        case .neutral: 34
        case .table: 48
        }
    }

    /// Сколько места снизу занимает строка подсказок вместе с отступом
    var hintbarReserve: CGFloat {
        isGlass ? hintbarHeight + 16 : hintbarHeight
    }

    var panelWidth: CGFloat {
        switch direction {
        case .film: 320
        case .glass: 332
        case .neutral: 300
        case .table: 320
        }
    }

    /// Сколько ширины забирает панель сведений (у «Стекла» она плавает с отступами)
    var panelReserve: CGFloat {
        isGlass ? panelWidth + 24 : panelWidth
    }

    /// Зазор между ячейками по горизонтали; у «Плёнки» кадры идут лентой
    var gridGap: CGFloat {
        switch direction {
        case .film: 2
        case .glass: 8
        case .neutral: 12
        case .table: 22
        }
    }

    /// Зазор между рядами
    var gridRowGap: CGFloat {
        switch direction {
        case .film: 20
        case .glass: 8
        case .neutral: 16
        case .table: 24
        }
    }

    /// Поля сетки по краям
    var gridPadding: CGFloat {
        switch direction {
        case .film: 28
        case .glass: 12
        case .neutral: 18
        case .table: 40
        }
    }

    /// Поля вокруг фото в просмотре: по горизонтали и вертикали
    var stageInsets: (h: CGFloat, v: CGFloat) {
        switch direction {
        case .film: (40, 64)
        case .glass: (24, 84)
        case .neutral: (32, 24)
        case .table: (40, 66)
        }
    }

    // MARK: Шрифты

    /// Узкий шрифт номеров плёнки
    static func condensed(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    var titleFont: Font {
        switch direction {
        case .film: .system(size: 28, weight: .semibold)
        case .glass: .system(size: 36, weight: .bold)
        case .neutral: .system(size: 24, weight: .semibold)
        case .table: .system(size: 40, weight: .bold)
        }
    }

    var headingFont: Font {
        switch direction {
        case .film: .system(size: 15, weight: .semibold)
        case .glass: .system(size: 19, weight: .bold)
        case .neutral: .system(size: 14, weight: .semibold)
        case .table: .system(size: 16, weight: .semibold)
        }
    }

    var bodyFont: Font { .system(size: 13) }

    var captionFont: Font { .system(size: 11) }

    /// Подписи секций: «Съёмка», «Камера»
    var labelFont: Font {
        switch direction {
        case .film: .system(size: 13, weight: .semibold)
        case .glass: .system(size: 13, weight: .semibold)
        case .neutral: .system(size: 12, weight: .semibold)
        case .table: .system(size: 13, weight: .semibold)
        }
    }

    var labelTracking: CGFloat { 0 }

    var labelUppercased: Bool { false }

    var labelColor: Color {
        switch direction {
        case .film, .table: c.text1
        case .glass: c.text2
        case .neutral: c.text3
        }
    }

    /// Счётчик, проценты — цифры не прыгают
    var numFont: Font {
        switch direction {
        case .film: Theme.condensed(18).monospacedDigit()
        case .glass: .system(size: 13, weight: .semibold).monospacedDigit()
        case .neutral: .system(size: 13).monospacedDigit()
        case .table: .system(size: 13).monospacedDigit()
        }
    }

    var exifFont: Font {
        switch direction {
        case .film: Theme.condensed(30).monospacedDigit()
        case .glass: .system(size: 21, weight: .bold).monospacedDigit()
        case .neutral: .system(size: 15, weight: .semibold).monospacedDigit()
        case .table: .system(size: 24, weight: .semibold).monospacedDigit()
        }
    }

    var keyFont: Font {
        switch direction {
        case .glass: .system(size: 12, weight: .bold)
        default: .system(size: 11.5, weight: .semibold)
        }
    }

    var toastFont: Font {
        switch direction {
        case .film: .system(size: 18, weight: .semibold)
        case .glass: .system(size: 19, weight: .semibold)
        case .neutral: .system(size: 16, weight: .semibold)
        case .table: .system(size: 17, weight: .semibold)
        }
    }

    /// Номера кадров, «краевая печать»
    var edgeFont: Font { Theme.condensed(15) }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .default
    /// Клавиша лежит на акцентной заливке (внутри главной кнопки)
    @Entry var keyOnAccent: Bool = false
    /// Клавиша лежит на тёмном пульте «Светового стола»
    @Entry var keyOnTray: Bool = false
}

extension View {
    /// Применяет тему к поддереву: токены, системные контролы и акцент
    func themed(_ theme: Theme) -> some View {
        environment(\.theme, theme)
            .environment(\.colorScheme, theme.isLight ? .light : .dark)
            .tint(theme.isNeutral || theme.isTable || theme.isFilm ? theme.c.text2 : theme.c.accentFill)
    }

    /// Подпись секции в стиле темы
    func themeLabel(_ theme: Theme) -> some View {
        font(theme.labelFont)
            .tracking(theme.labelTracking)
            .foregroundStyle(theme.labelColor)
    }
}

// MARK: - Системное оформление

enum SystemAppearance {
    /// Оформление macOS (не окна): светлое ли оно сейчас
    static var isLight: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    /// Уведомление о переключении светлой/тёмной темы macOS
    static var changes: NotificationCenter.Publisher {
        DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
    }
}

/// Ставит окну светлое или тёмное оформление — чтобы заголовок окна и системные панели совпадали с темой
struct WindowAppearance: NSViewRepresentable {
    let isLight: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)
        DispatchQueue.main.async {
            view.window?.appearance = appearance
        }
    }
}

/// «Нейтраль»: фон под фото в просмотре — от чёрного до светло-серого, все без оттенка
nonisolated enum SurroundTone {
    static let tones: [UInt32] = [0x000000, 0x1E1E1E, 0x2B2B2B, 0x767676, 0xBDBDBD]
    static let titles = ["Чёрный", "Тёмный", "Серый", "Средне-серый 18 %", "Светлый"]

    static func color(_ index: Int) -> Color {
        Color(hex: tones[min(max(index, 0), tones.count - 1)])
    }
}
