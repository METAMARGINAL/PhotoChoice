import AppKit
import Combine
import SwiftUI

// Темы оформления по дизайн-системе PhotoChoice: четыре направления,
// у «Студии» и «Стекла» есть светлые варианты. Значения — из tokens.json.
// Светлыми бывают только стартовое окно, сетка и панель в сетке;
// просмотр, рисование и сравнение всегда тёмные.

// MARK: - Выбор пользователя

nonisolated enum ThemeDirection: String, CaseIterable, Identifiable, Sendable {
    case studio, glass, quiet, contact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio: "Студия"
        case .glass: "Стекло"
        case .quiet: "Тишина"
        case .contact: "Контакт"
        }
    }

    var tagline: String {
        switch self {
        case .studio: "Строго и плотно, янтарный акцент"
        case .glass: "Стеклянные капсулы macOS 26"
        case .quiet: "Только фото и чёрное поле"
        case .contact: "Контактный лист и сейфлайт"
        }
    }

    var hasLight: Bool { self == .studio || self == .glass }
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
    nonisolated static let studio = ThemePalette(
        canvas: Color(hex: 0x1F1F1F), app: Color(hex: 0x242424),
        surface1: Color(hex: 0x2B2B2B), surface2: Color(hex: 0x333333), surface3: Color(hex: 0x3D3D3D),
        overlay: .rgba(30, 30, 30, 0.88),
        line: Color(hex: 0x3A3A3A), lineStrong: Color(hex: 0x8A8A8A),
        text1: Color(hex: 0xEBEBEB), text2: Color(hex: 0xB8B8B8), text3: Color(hex: 0x9D9D9D),
        accent: Color(hex: 0xF2A93B), accentFill: Color(hex: 0xF2A93B), onAccent: Color(hex: 0x1A1A1A),
        selection: Color(hex: 0xF2A93B), selectionFill: .rgba(242, 169, 59, 0.16), focus: Color(hex: 0xF2A93B),
        success: Color(hex: 0x5CCB8A), warning: Color(hex: 0xFFC857), danger: Color(hex: 0xFF6B61), edge: Color(hex: 0x9D9D9D),
        keyFill: Color(hex: 0x3A3A3A), keyLine: Color(hex: 0x5C5C5C), keyText: Color(hex: 0xEBEBEB),
        toastFill: .rgba(36, 36, 36, 0.94),
        histR: Color(hex: 0xFF5A52), histG: Color(hex: 0x4ED36A), histB: Color(hex: 0x4C8DFF),
        clipHigh: Color(hex: 0xFF4D4D), clipLow: Color(hex: 0x4D8DFF)
    )

    nonisolated static let glass = ThemePalette(
        canvas: Color(hex: 0x0D0D0D), app: Color(hex: 0x141414),
        surface1: Color(hex: 0x1C1C1E), surface2: Color(hex: 0x2C2C2E), surface3: Color(hex: 0x3A3A3C),
        overlay: .rgba(44, 44, 46, 0.55),
        line: .rgba(255, 255, 255, 0.10), lineStrong: .rgba(255, 255, 255, 0.42),
        text1: Color(hex: 0xFFFFFF), text2: Color(hex: 0xC7C7CC), text3: Color(hex: 0xA1A1A8),
        accent: Color(hex: 0x3D9BFF), accentFill: Color(hex: 0x0A6FDB), onAccent: Color(hex: 0xFFFFFF),
        selection: Color(hex: 0x3D9BFF), selectionFill: .rgba(61, 155, 255, 0.20), focus: Color(hex: 0x3D9BFF),
        success: Color(hex: 0x30D158), warning: Color(hex: 0xFFD60A), danger: Color(hex: 0xFF453A), edge: Color(hex: 0xA1A1A8),
        keyFill: .rgba(255, 255, 255, 0.14), keyLine: .rgba(255, 255, 255, 0.22), keyText: Color(hex: 0xFFFFFF),
        toastFill: .rgba(40, 40, 42, 0.55),
        histR: Color(hex: 0xFF6159), histG: Color(hex: 0x4CD964), histB: Color(hex: 0x4D9BFF),
        clipHigh: Color(hex: 0xFF453A), clipLow: Color(hex: 0x3D9BFF)
    )

    nonisolated static let quiet = ThemePalette(
        canvas: Color(hex: 0x000000), app: Color(hex: 0x050505),
        surface1: Color(hex: 0x0F0F0F), surface2: Color(hex: 0x171717), surface3: Color(hex: 0x222222),
        overlay: .rgba(0, 0, 0, 0.55),
        line: Color(hex: 0x1F1F1F), lineStrong: Color(hex: 0x727272),
        text1: Color(hex: 0xF5F5F5), text2: Color(hex: 0xB0B0B0), text3: Color(hex: 0x8F8F8F),
        accent: Color(hex: 0xFFFFFF), accentFill: Color(hex: 0xF5F5F5), onAccent: Color(hex: 0x000000),
        selection: Color(hex: 0xFFFFFF), selectionFill: .rgba(255, 255, 255, 0.06), focus: Color(hex: 0xFFFFFF),
        success: Color(hex: 0x8FD6A8), warning: Color(hex: 0xE6C87A), danger: Color(hex: 0xF08A80), edge: Color(hex: 0x8F8F8F),
        keyFill: .clear, keyLine: .clear, keyText: Color(hex: 0xF5F5F5),
        toastFill: .clear,
        histR: Color(hex: 0xE07A74), histG: Color(hex: 0x7FC98F), histB: Color(hex: 0x7A9FE0),
        clipHigh: Color(hex: 0xF5F5F5), clipLow: Color(hex: 0x8F8F8F)
    )

    nonisolated static let contact = ThemePalette(
        canvas: Color(hex: 0x161616), app: Color(hex: 0x1A1A1A),
        surface1: Color(hex: 0x202020), surface2: Color(hex: 0x292929), surface3: Color(hex: 0x333333),
        overlay: .rgba(22, 22, 22, 0.9),
        line: Color(hex: 0x333333), lineStrong: Color(hex: 0x848484),
        text1: Color(hex: 0xEFEAE4), text2: Color(hex: 0xBDB5AB), text3: Color(hex: 0x9F968B),
        accent: Color(hex: 0xFF6A3D), accentFill: Color(hex: 0xFF6A3D), onAccent: Color(hex: 0x1A0C06),
        selection: Color(hex: 0xFF6A3D), selectionFill: .rgba(255, 106, 61, 0.12), focus: Color(hex: 0xFF6A3D),
        success: Color(hex: 0x8FCF7A), warning: Color(hex: 0xE3A64A), danger: Color(hex: 0xFF5470), edge: Color(hex: 0x9F968B),
        keyFill: .clear, keyLine: Color(hex: 0x5C5C5C), keyText: Color(hex: 0xEFEAE4),
        toastFill: .rgba(22, 22, 22, 0.92),
        histR: Color(hex: 0xFF5A52), histG: Color(hex: 0x4ED36A), histB: Color(hex: 0x4C8DFF),
        clipHigh: Color(hex: 0xFF4D4D), clipLow: Color(hex: 0x4D8DFF)
    )

    nonisolated static let studioLight = ThemePalette(
        canvas: Color(hex: 0x1F1F1F), app: Color(hex: 0xECECEC),
        surface1: Color(hex: 0xF7F7F7), surface2: Color(hex: 0xFFFFFF), surface3: Color(hex: 0xE0E0E0),
        overlay: .rgba(250, 250, 250, 0.92),
        line: Color(hex: 0xD6D6D6), lineStrong: Color(hex: 0x7A7A7A),
        text1: Color(hex: 0x1C1C1C), text2: Color(hex: 0x4A4A4A), text3: Color(hex: 0x666666),
        accent: Color(hex: 0x9C5A06), accentFill: Color(hex: 0xF2A93B), onAccent: Color(hex: 0x1A1A1A),
        selection: Color(hex: 0xB06804), selectionFill: .rgba(242, 169, 59, 0.24), focus: Color(hex: 0xB06804),
        success: Color(hex: 0x1B7F45), warning: Color(hex: 0x8A5D00), danger: Color(hex: 0xC0352B), edge: Color(hex: 0x666666),
        keyFill: Color(hex: 0xFFFFFF), keyLine: Color(hex: 0xB5B5B5), keyText: Color(hex: 0x1C1C1C),
        toastFill: .rgba(255, 255, 255, 0.96),
        histR: Color(hex: 0xFF5A52), histG: Color(hex: 0x4ED36A), histB: Color(hex: 0x4C8DFF),
        clipHigh: Color(hex: 0xFF4D4D), clipLow: Color(hex: 0x4D8DFF)
    )

    nonisolated static let glassLight = ThemePalette(
        canvas: Color(hex: 0x0D0D0D), app: Color(hex: 0xF2F2F2),
        surface1: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xEBEBEB), surface3: Color(hex: 0xDEDEDE),
        overlay: .rgba(255, 255, 255, 0.62),
        line: .rgba(0, 0, 0, 0.10), lineStrong: .rgba(0, 0, 0, 0.50),
        text1: Color(hex: 0x1D1D1F), text2: Color(hex: 0x48484A), text3: Color(hex: 0x666669),
        accent: Color(hex: 0x0062CC), accentFill: Color(hex: 0x0062CC), onAccent: Color(hex: 0xFFFFFF),
        selection: Color(hex: 0x0070E8), selectionFill: .rgba(0, 122, 255, 0.14), focus: Color(hex: 0x0070E8),
        success: Color(hex: 0x1F7A36), warning: Color(hex: 0x8A6000), danger: Color(hex: 0xC9001A), edge: Color(hex: 0x666669),
        keyFill: .rgba(0, 0, 0, 0.06), keyLine: .rgba(0, 0, 0, 0.16), keyText: Color(hex: 0x1D1D1F),
        toastFill: .rgba(255, 255, 255, 0.66),
        histR: Color(hex: 0xFF6159), histG: Color(hex: 0x4CD964), histB: Color(hex: 0x4D9BFF),
        clipHigh: Color(hex: 0xFF453A), clipLow: Color(hex: 0x3D9BFF)
    )
}

// MARK: - Тема

nonisolated struct Theme: Sendable {
    let direction: ThemeDirection
    let isLight: Bool
    let c: ThemePalette

    static func make(_ direction: ThemeDirection, light: Bool) -> Theme {
        let useLight = light && direction.hasLight
        let palette: ThemePalette
        switch (direction, useLight) {
        case (.studio, false): palette = .studio
        case (.studio, true): palette = .studioLight
        case (.glass, false): palette = .glass
        case (.glass, true): palette = .glassLight
        case (.quiet, _): palette = .quiet
        case (.contact, _): palette = .contact
        }
        return Theme(direction: direction, isLight: useLight, c: palette)
    }

    static let `default` = Theme.make(.studio, light: false)

    var isStudio: Bool { direction == .studio }
    var isGlass: Bool { direction == .glass }
    var isQuiet: Bool { direction == .quiet }
    var isContact: Bool { direction == .contact }

    // MARK: Радиусы

    var rSm: CGFloat {
        switch direction {
        case .studio: 3
        case .glass: 8
        case .quiet: 0
        case .contact: 2
        }
    }

    var rMd: CGFloat {
        switch direction {
        case .studio: 5
        case .glass: 14
        case .quiet: 2
        case .contact: 4
        }
    }

    var rLg: CGFloat {
        switch direction {
        case .studio: 8
        case .glass: 24
        case .quiet: 4
        case .contact: 8
        }
    }

    /// Радиус кнопок и полей; у «Стекла» кнопки — капсулы (считается от высоты)
    var rControl: CGFloat {
        switch direction {
        case .studio: 5
        case .glass: 999
        case .quiet: 2
        case .contact: 4
        }
    }

    // MARK: Каркас

    var topbarHeight: CGFloat {
        switch direction {
        case .studio: 36
        case .glass: 52
        case .quiet: 28
        case .contact: 44
        }
    }

    /// Высота строки подсказок (у «Стекла» — капсула с отступом снизу)
    var hintbarHeight: CGFloat {
        switch direction {
        case .studio: 30
        case .glass: 44
        case .quiet: 32
        case .contact: 40
        }
    }

    /// Сколько места снизу занимает строка подсказок вместе с отступом
    var hintbarReserve: CGFloat {
        isGlass ? hintbarHeight + 16 : hintbarHeight
    }

    var panelWidth: CGFloat {
        switch direction {
        case .studio: 300
        case .glass: 320
        case .quiet: 280
        case .contact: 312
        }
    }

    /// Сколько ширины забирает панель сведений (у «Стекла» она плавает с отступами)
    var panelReserve: CGFloat {
        isGlass ? panelWidth + 24 : panelWidth
    }

    var gridGap: CGFloat {
        switch direction {
        case .studio: 4
        case .glass: 12
        case .quiet: 2
        case .contact: 10
        }
    }

    /// Поля вокруг фото в просмотре: по горизонтали и вертикали
    var stageInsets: (h: CGFloat, v: CGFloat) {
        switch direction {
        case .studio: (40, 64)
        case .glass: (24, 76)
        case .quiet: (0, 30)
        case .contact: (40, 64)
        }
    }

    /// Интерфейс поверх фото прячется через 2 с простоя
    var autoHidesHUD: Bool { isGlass || isQuiet }

    // MARK: Шрифты

    var titleFont: Font {
        switch direction {
        case .studio: .system(size: 20, weight: .semibold)
        case .glass: .system(size: 26, weight: .bold)
        case .quiet: .system(size: 30, weight: .light)
        case .contact: .system(size: 30, weight: .semibold, design: .serif)
        }
    }

    var headingFont: Font {
        switch direction {
        case .studio: .system(size: 13, weight: .semibold)
        case .glass: .system(size: 15, weight: .semibold)
        case .quiet: .system(size: 13, weight: .medium)
        case .contact: .system(size: 15, weight: .semibold, design: .serif)
        }
    }

    var bodyFont: Font { .system(size: 13) }

    var captionFont: Font { .system(size: 11) }

    /// Метки секций: СЪЁМКА, ФАЙЛ
    var labelFont: Font {
        switch direction {
        case .studio: .system(size: 10.5, weight: .semibold)
        case .glass: .system(size: 11, weight: .semibold)
        case .quiet: .system(size: 10, weight: .medium)
        case .contact: .system(size: 10, weight: .semibold, design: .monospaced)
        }
    }

    var labelTracking: CGFloat {
        switch direction {
        case .studio: 0.63
        case .glass: 0
        case .quiet: 1.2
        case .contact: 1.0
        }
    }

    var labelUppercased: Bool { !isGlass }

    var labelColor: Color { isContact ? c.edge : (isGlass ? c.text2 : c.text3) }

    /// Счётчик, проценты — цифры не прыгают
    var numFont: Font {
        switch direction {
        case .studio: .system(size: 12, weight: .medium, design: .monospaced)
        case .glass: .system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
        case .quiet: .system(size: 11, design: .monospaced)
        case .contact: .system(size: 11, weight: .semibold, design: .monospaced)
        }
    }

    var exifFont: Font {
        switch direction {
        case .studio: .system(size: 17, weight: .medium, design: .monospaced)
        case .glass: .system(size: 19, weight: .semibold, design: .rounded).monospacedDigit()
        case .quiet: .system(size: 22, weight: .light).monospacedDigit()
        case .contact: .system(size: 19, weight: .semibold, design: .serif).monospacedDigit()
        }
    }

    var keyFont: Font {
        switch direction {
        case .studio: .system(size: 11, weight: .semibold, design: .monospaced)
        case .glass: .system(size: 12, weight: .bold, design: .rounded)
        case .quiet: .system(size: 11, weight: .medium, design: .monospaced)
        case .contact: .system(size: 11, weight: .semibold, design: .monospaced)
        }
    }

    var toastFont: Font {
        switch direction {
        case .studio: .system(size: 15, weight: .semibold)
        case .glass: .system(size: 17, weight: .semibold, design: .rounded)
        case .quiet: .system(size: 30, weight: .light)
        case .contact: .system(size: 14, weight: .bold, design: .monospaced)
        }
    }

    /// Номера кадров, «краевая печать»
    var edgeFont: Font { .system(size: 10, weight: .semibold, design: .monospaced) }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .default
    /// Клавиша лежит на акцентной заливке (внутри главной кнопки)
    @Entry var keyOnAccent: Bool = false
}

extension View {
    /// Применяет тему к поддереву: токены, системные контролы и акцент
    func themed(_ theme: Theme) -> some View {
        environment(\.theme, theme)
            .environment(\.colorScheme, theme.isLight ? .light : .dark)
            .tint(theme.c.accentFill)
    }

    /// Метка секции в стиле темы (капитель с разрядкой и т. п.)
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
