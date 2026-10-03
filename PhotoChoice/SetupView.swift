import AppKit
import SwiftUI

/// Стартовый экран: исходная папка, папки назначения, оформление
struct SetupView: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme
    @AppStorage("themeDirection") private var direction: ThemeDirection = .studio
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let c = theme.c
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                sourceCard
                destinationsCard
                if let error = session.errorMessage {
                    errorBox(error)
                }
                actions
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
        .background(c.app)
        .onChange(of: session.includeSubfolders) { _, _ in
            session.refreshSourceSummary()
        }
    }

    // MARK: - Заголовок

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("PhotoChoice")
                    .font(theme.titleFont)
                    .tracking(theme.isQuiet ? -0.3 : 0)
                    .foregroundStyle(theme.c.text1)
                Text("Откройте папку со съёмкой и раскладывайте кадры одной клавишей: 1–9 — в папку, Delete — в корзину, Z — отмена.")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.c.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button {
                openSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paintpalette")
                    Text("Оформление…")
                }
            }
            .buttonStyle(PCButtonStyle())
            .help("Тема и светлый/тёмный режим (⌘,)")
        }
    }

    // MARK: - Исходная папка

    private var sourceCard: some View {
        card("01", "Исходная папка") {
            HStack(spacing: 10) {
                field {
                    Image(systemName: "folder")
                        .foregroundStyle(theme.c.text2)
                    Text(session.sourceURL.map { PathDisplay.short($0) } ?? "Не выбрана")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(session.sourceURL == nil ? theme.c.text3 : theme.c.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                Button("Выбрать…") {
                    session.chooseSource()
                }
                .buttonStyle(PCButtonStyle())
            }
            PCCheckbox(
                isOn: $session.includeSubfolders,
                title: "Включая вложенные папки",
                detail: session.sourceSummary.map { "· \($0)" }
            )
        }
    }

    // MARK: - Папки назначения

    private var destinationsCard: some View {
        card("02", "Папки назначения", trailing: "клавиши 1–9") {
            if session.destinations.isEmpty {
                Text("Если ничего не добавить, при старте внутри исходной папки создастся папка «Отобранные».")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.c.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(session.destinations.enumerated()), id: \.element.id) { item in
                        if item.offset > 0 {
                            Rectangle()
                                .fill(theme.c.line)
                                .frame(height: 1)
                        }
                        destinationRow(item.element)
                    }
                }
            }
            Button {
                session.addDestination()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Добавить папку…")
                }
            }
            .buttonStyle(PCButtonStyle(kind: .ghost))
            .padding(.leading, -12)
        }
    }

    private func destinationRow(_ destination: Destination) -> some View {
        HStack(spacing: 12) {
            KeyCap(destination.shortcut, size: .large)
            VStack(alignment: .leading, spacing: 1) {
                Text(destination.name)
                    .font(.system(size: 13, weight: theme.isQuiet ? .medium : .semibold))
                    .foregroundStyle(theme.c.text1)
                Text(PathDisplay.short(destination.url))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.c.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button {
                session.removeDestination(destination)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(PCIconButtonStyle(danger: true))
            .help("Убрать папку из списка (сама папка не удаляется)")
        }
        .padding(.vertical, 7)
    }

    // MARK: - Ошибка и действия

    private func errorBox(_ text: String) -> some View {
        let c = theme.c
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(c.warning)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.isQuiet ? c.warning : c.text1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.isQuiet ? 0 : 12)
        .padding(.vertical, theme.isQuiet ? 0 : 8)
        .background {
            if !theme.isQuiet {
                RoundedRectangle(cornerRadius: theme.rMd)
                    .fill(c.warning.opacity(theme.isLight ? 0.16 : 0.08))
                RoundedRectangle(cornerRadius: theme.rMd)
                    .stroke(c.warning, lineWidth: 1)
            }
        }
    }

    private var actions: some View {
        HStack {
            Text(session.sourceURL == nil ? "Выберите папку со съёмкой" : "Тема: \(direction.title)")
                .font(.system(size: 12))
                .foregroundStyle(theme.c.text3)
            Spacer()
            Button {
                session.startReview()
            } label: {
                HStack(spacing: 8) {
                    Text("Начать полноэкранный просмотр")
                    KeyCap("↩")
                }
            }
            .buttonStyle(PCButtonStyle(kind: .primary, big: true))
            .keyboardShortcut(.defaultAction)
            .disabled(session.sourceURL == nil)
        }
    }

    // MARK: - Карточка и поле

    private func card<Content: View>(
        _ number: String,
        _ title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 0) {
                    if theme.isContact {
                        // «Контакт»: номер как краевая печать плёнки
                        Text("\(number) ▸ ")
                            .font(theme.edgeFont)
                            .tracking(1)
                            .foregroundStyle(theme.c.edge)
                    }
                    Text(title)
                        .font(theme.headingFont)
                        .foregroundStyle(theme.c.text1)
                }
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.c.text3)
                }
            }
            content()
        }
        .padding(theme.isQuiet
                 ? EdgeInsets(top: 14, leading: 0, bottom: 0, trailing: 0)
                 : EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background { cardBackground }
    }

    @ViewBuilder
    private var cardBackground: some View {
        let c = theme.c
        switch theme.direction {
        case .studio, .contact:
            RoundedRectangle(cornerRadius: theme.rLg)
                .fill(c.surface1)
                .overlay(RoundedRectangle(cornerRadius: theme.rLg).stroke(c.line, lineWidth: 1))
        case .glass:
            if theme.isLight {
                RoundedRectangle(cornerRadius: theme.rMd)
                    .fill(c.surface1)
                    .shadow(color: .black.opacity(0.08), radius: 0.5)
            } else {
                RoundedRectangle(cornerRadius: theme.rMd)
                    .fill(Color.white.opacity(0.05))
            }
        case .quiet:
            VStack(spacing: 0) {
                Rectangle().fill(c.line).frame(height: 1)
                Spacer(minLength: 0)
            }
        }
    }

    private func field<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, theme.isQuiet ? 0 : 10)
        .frame(height: 28)
        .background { fieldBackground }
    }

    @ViewBuilder
    private var fieldBackground: some View {
        let c = theme.c
        switch theme.direction {
        case .quiet:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle().fill(c.lineStrong).frame(height: 1)
            }
        case .glass:
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.isLight ? c.app : c.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.line, lineWidth: 1))
        case .studio, .contact:
            RoundedRectangle(cornerRadius: theme.rMd)
                .fill(c.surface2)
                .overlay(RoundedRectangle(cornerRadius: theme.rMd).stroke(c.lineStrong, lineWidth: 1))
        }
    }
}

// MARK: - Пути

enum PathDisplay {
    /// Настоящая домашняя папка (в песочнице NSHomeDirectory указывает на контейнер)
    static let realHome: String = {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }()

    /// «/Users/egor/Pictures/…» → «~/Pictures/…»
    static func short(_ url: URL) -> String {
        let path = url.path
        guard path.hasPrefix(realHome + "/") else { return path }
        return "~" + path.dropFirst(realHome.count)
    }
}
