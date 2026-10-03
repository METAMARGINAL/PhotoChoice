import AppKit
import SwiftUI

/// Окно «Настройки» (⌘,): тема оформления и светлый/тёмный режим
struct SettingsRoot: View {
    @AppStorage("themeDirection") private var direction: ThemeDirection = .studio
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
        let theme = Theme.make(direction, light: wantsLight)
        SettingsView()
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

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @AppStorage("themeDirection") private var direction: ThemeDirection = .studio
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system
    @AppStorage("pairRawJpeg") private var pairRawJpeg = true
    @AppStorage("renameOnMove") private var renameOnMove = false
    @AppStorage("renameStyle") private var renameStyle: RenameStyle = .dateTimeOriginal

    var body: some View {
        let c = theme.c
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Оформление")
                    .font(theme.headingFont)
                    .foregroundStyle(c.text1)
                Text("Тема меняет цвета, шрифты и плотность интерфейса. Фон под фото всегда нейтральный.")
                    .font(theme.bodyFont)
                    .foregroundStyle(c.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(ThemeDirection.allCases) { option in
                    ThemeTile(
                        direction: option,
                        isSelected: option == direction,
                        light: theme.isLight
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) { direction = option }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Режим")
                        .font(theme.bodyFont)
                        .foregroundStyle(c.text2)
                    Picker("Режим", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!direction.hasLight)
                    Spacer(minLength: 0)
                }
                Text(direction.hasLight
                     ? "Светлыми становятся стартовое окно и сетка. Просмотр, рисование и сравнение всегда тёмные, чтобы белое поле не искажало яркость снимка."
                     : "У темы «\(direction.title)» только тёмный вариант.")
                    .font(.system(size: 11))
                    .foregroundStyle(c.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(c.line).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Отбор")
                    .font(theme.headingFont)
                    .foregroundStyle(c.text1)
                PCCheckbox(isOn: $pairRawJpeg, title: "Объединять RAW и JPEG одного кадра")
                Text("Файлы с одинаковым именем в одной папке (DSC_0452.NEF и DSC_0452.JPG) показываются одной карточкой и переносятся, удаляются и возвращаются вместе. Изменение применится при следующем запуске просмотра.")
                    .font(.system(size: 11))
                    .foregroundStyle(c.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(c.line).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Переименование по метаданным")
                    .font(theme.headingFont)
                    .foregroundStyle(c.text1)
                PCCheckbox(isOn: $renameOnMove, title: "Переименовывать кадры при переносе в папку назначения")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(RenameStyle.allCases) { style in
                        renameOption(style)
                    }
                }
                .padding(.leading, 24)
                .disabled(!renameOnMove)
                .opacity(renameOnMove ? 1 : 0.45)
                Text("Имя собирается из даты и времени съёмки (EXIF), а если их нет — из даты изменения файла. Так кадры с разных карт и после сброса счётчика камеры не совпадают по именам и сами встают по порядку съёмки. Меняется только имя: содержимое и дата изменения файла остаются прежними. Пара RAW + JPEG получает общее имя. В исходной папке ничего не переименовывается, в корзину файлы уходят со старым именем, Z возвращает прежнее имя.")
                    .font(.system(size: 11))
                    .foregroundStyle(c.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        }
        .scrollIndicators(.visible)
        // Окно настроек фиксированной высоты; всё, что не влезло, прокручивается
        .frame(width: 600, height: 620)
    }

    /// Вариант шаблона: переключатель, название и пример имени
    private func renameOption(_ style: RenameStyle) -> some View {
        let c = theme.c
        let isOn = renameStyle == style
        return Button {
            renameStyle = style
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isOn ? c.accent : c.text3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(style.title)
                        .font(theme.bodyFont)
                        .foregroundStyle(c.text1)
                    Text(style.example)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(c.text2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Плитка темы

/// Выбор темы: маленький макет окна в палитре этой темы и подпись
struct ThemeTile: View {
    let direction: ThemeDirection
    let isSelected: Bool
    let light: Bool
    let action: () -> Void

    @Environment(\.theme) private var current
    @State private var hovered = false

    var body: some View {
        let c = current.c
        let shape = RoundedRectangle(cornerRadius: max(current.rMd, 6))
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ThemeMiniPreview(theme: Theme.make(direction, light: light))
                    .frame(height: 120)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(direction.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(c.text1)
                        if direction.hasLight {
                            Text("светлая и тёмная")
                                .font(.system(size: 10))
                                .foregroundStyle(c.text3)
                        }
                        Spacer(minLength: 0)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(c.selection)
                        }
                    }
                    Text(direction.tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(c.text3)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? c.selectionFill : (hovered ? c.surface3 : c.surface1), in: shape)
            .overlay(shape.stroke(isSelected ? c.selection : c.line, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Тема «\(direction.title)»")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Миниатюрный макет окна в палитре темы: полоса сверху, сетка кадров, подсказки
struct ThemeMiniPreview: View {
    let theme: Theme

    private let shades: [Double] = [0.42, 0.55, 0.33, 0.48, 0.6, 0.38, 0.5, 0.28]

    var body: some View {
        let c = theme.c
        let gap = max(theme.gridGap / 3, 1.5)
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(c.accent).frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1).fill(c.text3).frame(width: 24, height: 3)
                Spacer(minLength: 0)
                Capsule().fill(c.accentFill).frame(width: 14, height: 5)
            }
            .padding(.horizontal, 6)
            .frame(height: 12)
            .background(theme.isQuiet || theme.isGlass ? Color.clear : c.surface1)

            VStack(spacing: gap) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<4, id: \.self) { col in
                            cell(row * 4 + col)
                        }
                    }
                }
            }
            .padding(gap + 2)
            .frame(maxHeight: .infinity)

            if theme.isStudio || theme.isContact {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(c.keyFill)
                            .overlay(RoundedRectangle(cornerRadius: 1).stroke(c.keyLine, lineWidth: 0.5))
                            .frame(width: 6, height: 5)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 9)
                .background(c.surface1)
            } else if theme.isGlass {
                Capsule()
                    .fill(c.overlay)
                    .overlay(Capsule().stroke(c.line, lineWidth: 0.5))
                    .frame(width: 44, height: 7)
                    .padding(.bottom, 3)
            }
        }
        .background(c.app)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
    }

    private func cell(_ i: Int) -> some View {
        let c = theme.c
        let radius = min(theme.rSm, 2)
        return RoundedRectangle(cornerRadius: radius)
            .fill(Color(white: shades[i]))
            .aspectRatio(1.5, contentMode: .fit)
            .padding(theme.isGlass ? 1.5 : 0)
            .background {
                if theme.isGlass {
                    RoundedRectangle(cornerRadius: 3).fill(c.surface1)
                }
            }
            .overlay {
                if i == 5 {
                    RoundedRectangle(cornerRadius: radius + 1)
                        .stroke(c.selection, lineWidth: 1.5)
                        .padding(-1.5)
                }
            }
    }
}
