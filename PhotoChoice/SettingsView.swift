import AppKit
import SwiftUI

/// Окно «Настройки» (⌘,): страницы слева, в теме главного окна
struct SettingsRoot: View {
    let session: PhotoSession
    @AppStorage(Pref.themeDirection) private var direction: ThemeDirection = .neutral
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system
    @State private var systemIsLight = SystemAppearance.isLight

    private var wantsLight: Bool {
        switch appearance {
        case .system: systemIsLight
        case .light: true
        case .dark: false
        }
    }

    var body: some View {
        let theme = Theme.chrome(direction, wantsLight: wantsLight)
        SettingsShell(session: session)
            .themed(theme)
            .background(theme.c.app)
            .background(WindowAppearance(isLight: theme.isLight))
            .onReceive(SystemAppearance.changes) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    systemIsLight = SystemAppearance.isLight
                }
            }
    }
}

// MARK: - Плитка темы

/// Выбор темы: маленький макет окна в этой теме и подпись
struct ThemeTile: View {
    let direction: ThemeDirection
    let isSelected: Bool
    let light: Bool
    let action: () -> Void

    @Environment(\.theme) private var current
    @State private var hovered = false

    var body: some View {
        let c = current.c
        let shape = RoundedRectangle(cornerRadius: 10)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ThemeMiniPreview(theme: Theme.chrome(direction, wantsLight: light))
                    .frame(height: 112)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(direction.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(c.text1)
                        if direction.hasLight {
                            Text("светлая и тёмная")
                                .font(.system(size: 10.5))
                                .foregroundStyle(c.text3)
                        } else if direction.alwaysLight {
                            Text("светлая")
                                .font(.system(size: 10.5))
                                .foregroundStyle(c.text3)
                        }
                        Spacer(minLength: 0)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(c.text1)
                        }
                    }
                    Text(direction.tagline)
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.text3)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered && !isSelected ? c.surface2 : c.surface1, in: shape)
            .overlay(shape.strokeBorder(isSelected ? c.text1 : c.line, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Тема «\(direction.title)»")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Миниатюрный макет окна темы: как в ней выглядит сетка
struct ThemeMiniPreview: View {
    let theme: Theme

    private let shades: [Double] = [0.42, 0.55, 0.33, 0.48, 0.6, 0.38, 0.5, 0.28]

    var body: some View {
        Group {
            switch theme.direction {
            case .film: film
            case .glass: glass
            case .neutral: neutral
            case .table: table
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
    }

    private func frame(_ i: Int) -> some View {
        Rectangle()
            .fill(Color(white: shades[i % shades.count]))
            .aspectRatio(1.5, contentMode: .fit)
    }

    /// Лента кадров с номерами и обведённым кадром
    private var film: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<4, id: \.self) { col in
                        let i = row * 4 + col
                        VStack(alignment: .leading, spacing: 2) {
                            frame(i)
                            Rectangle().fill(theme.c.edge).frame(width: 6, height: 2)
                        }
                        .padding(2)
                        .background(theme.c.surface1)
                        .overlay {
                            if i == 1 {
                                PencilLoop().stroke(theme.pen, lineWidth: 1.4).padding(-3)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.c.app)
    }

    /// Кадры на весь экран и капсулы поверх
    private var glass: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3B5B7A), Color(hex: 0x1A2430)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(theme.isLight ? 0.4 : 1)
            VStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { col in
                            frame(row * 4 + col)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay {
                                    if row == 0 && col == 1 {
                                        RoundedRectangle(cornerRadius: 3).stroke(Color.white, lineWidth: 1)
                                    }
                                }
                        }
                    }
                }
            }
            .padding(6)
            VStack {
                HStack(spacing: 3) {
                    Capsule().fill(Color.white.opacity(0.35)).frame(width: 18, height: 7)
                    Capsule().fill(Color.white.opacity(0.35)).frame(width: 34, height: 7)
                    Spacer()
                }
                Spacer()
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 60, height: 8)
            }
            .padding(6)
        }
    }

    /// Колонка папок слева, плотная сетка
    private var neutral: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1).fill(theme.c.surface3).frame(width: 5, height: 5)
                        RoundedRectangle(cornerRadius: 1).fill(theme.c.text3).frame(width: 16, height: 2)
                    }
                    .padding(2)
                    .background(i == 0 ? theme.c.surface2 : Color.clear)
                }
                Spacer()
            }
            .padding(5)
            .frame(width: 34)
            .frame(maxHeight: .infinity)
            .background(theme.c.surface1)
            VStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { col in
                            frame(row * 3 + col)
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                                .overlay {
                                    if row == 0 && col == 1 {
                                        RoundedRectangle(cornerRadius: 1).stroke(Color.white, lineWidth: 1)
                                    }
                                }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
        }
        .background(theme.c.app)
    }

    /// Отпечатки на светлом столе и тёмный пульт снизу
    private var table: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { col in
                            VStack(spacing: 0) {
                                frame(row * 3 + col)
                                Color.white.frame(height: 4)
                            }
                            .padding(.horizontal, 1.5)
                            .padding(.top, 1.5)
                            .background(Color.white)
                            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                            .overlay {
                                if row == 0 && col == 1 {
                                    Rectangle().stroke(Color(hex: 0x1A1B1E), lineWidth: 1)
                                }
                            }
                        }
                    }
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0xF2F1EF))
            Rectangle().fill(theme.trayFill).frame(height: 10)
        }
    }
}
