import AppKit
import SwiftUI

/// Стартовый экран: исходная папка, папки назначения, оформление. У каждой темы своя раскладка
struct SetupView: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Feature.transfer.key) private var transferOn = true
    @AppStorage(Pref.pairRawJpeg) private var pairRawJpeg = true
    @AppStorage(Pref.renameOnMove) private var renameOnMove = false

    var body: some View {
        Group {
            switch theme.direction {
            case .film: filmLayout
            case .glass: glassLayout
            case .neutral: neutralLayout
            case .table: tableLayout
            }
        }
        .onChange(of: session.includeSubfolders) { _, _ in
            session.refreshSourceSummary()
        }
        .onChange(of: transferOn) { _, _ in
            session.refreshSourceSummary()
        }
    }

    private var subtitle: String {
        transferOn
            ? "Выберите папку со снимками и папки, куда их раскладывать."
            : "Выберите папку со снимками: кадры остаются на месте, вы ставите оценки."
    }

    // MARK: - Плёнка

    private var filmLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock(alignment: .leading)
                card {
                    cardTitle("Исходная папка")
                    filmStrip
                    sourceRow
                }
                if transferOn {
                    card {
                        cardTitle("Папки назначения")
                        destinationList
                        addDestinationRow
                    }
                }
                errorBox
                footer
            }
            .frame(maxWidth: 780)
            .padding(.horizontal, 32)
            .padding(.top, 52)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(theme.c.app)
    }

    /// Кадры исходной папки лентой, с номерами на краю
    private var filmStrip: some View {
        let c = theme.c
        return HStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { i in
                VStack(alignment: .leading, spacing: 0) {
                    PreviewThumb(url: session.sourcePreview.indices.contains(i) ? session.sourcePreview[i] : nil)
                        .aspectRatio(1.5, contentMode: .fit)
                        .clipped()
                    Text("\(i + 1)")
                        .font(Theme.condensed(13))
                        .tracking(0.6)
                        .foregroundStyle(c.edge)
                        .frame(height: 24)
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .background(Color(hex: 0x1B1B1B))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Жидкое стекло

    private var glassLayout: some View {
        ZStack {
            theme.c.app
            if let first = session.sourcePreview.first {
                PreviewThumb(url: first)
                    .blur(radius: 34)
                    .saturation(1.7)
                    .brightness(-0.25)
                    .opacity(theme.isLight ? 0.35 : 1)
                    .clipped()
                    .ignoresSafeArea()
            }
            ScrollView {
                VStack(spacing: 0) {
                    titleBlock(alignment: .center)
                    HStack(alignment: .top, spacing: 22) {
                        glassCard {
                            cardTitle("Исходная папка")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                ForEach(0..<6, id: \.self) { i in
                                    PreviewThumb(url: session.sourcePreview.indices.contains(i) ? session.sourcePreview[i] : nil)
                                        .aspectRatio(1.5, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                            Spacer(minLength: 0)
                            sourceRow
                        }
                        if transferOn {
                            glassCard {
                                cardTitle("Папки назначения")
                                destinationList
                                Spacer(minLength: 0)
                                addDestinationRow
                            }
                        }
                    }
                    .frame(maxWidth: transferOn ? 1142 : 560)
                    .padding(.top, 34)
                    errorBox
                        .frame(maxWidth: 760)
                        .padding(.top, 16)
                    footer
                        .frame(maxWidth: transferOn ? 1142 : 560)
                        .padding(.top, 28)
                }
                .padding(.horizontal, 32)
                .padding(.top, 72)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .topLeading)
        .pcGlass(in: .rect(cornerRadius: 34))
    }

    // MARK: - Нейтраль

    private var neutralLayout: some View {
        let c = theme.c
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock(alignment: .leading)
                    HStack(alignment: .top, spacing: 16) {
                        panel {
                            cardTitle("Исходная папка")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                ForEach(0..<4, id: \.self) { i in
                                    PreviewThumb(url: session.sourcePreview.indices.contains(i) ? session.sourcePreview[i] : nil)
                                        .aspectRatio(1.5, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            sourceRow
                        }
                        panel {
                            if transferOn {
                                cardTitle("Папки назначения")
                                destinationList
                                addDestinationRow
                                Rectangle().fill(c.line).frame(height: 1)
                            }
                            cardTitle("Параметры")
                            VStack(alignment: .leading, spacing: 10) {
                                PCCheckbox(isOn: $pairRawJpeg, title: "Пары RAW и JPEG как один кадр")
                                PCCheckbox(isOn: $session.includeSubfolders, title: "Искать во вложенных папках")
                                if transferOn {
                                    PCCheckbox(isOn: $renameOnMove, title: "Переименовывать по дате съёмки при переносе")
                                }
                            }
                        }
                    }
                    .padding(.top, 26)
                    errorBox
                        .padding(.top, 16)
                }
                .frame(maxWidth: 1040, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.top, 56)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            HStack {
                footer
                    .frame(maxWidth: 1040)
            }
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(Color(hex: 0x222222))
        }
        .background(c.app)
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.c.surface1, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Световой стол

    private var tableLayout: some View {
        ScrollView {
            VStack(spacing: 0) {
                titleBlock(alignment: .center)
                VStack(alignment: .leading, spacing: 16) {
                    card {
                        cardTitle("Исходная папка")
                        HStack(spacing: 26) {
                            fan
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.sourceURL?.lastPathComponent ?? "Папка не выбрана")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(theme.c.text1)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let url = session.sourceURL {
                                    Text(PathDisplay.short(url.deletingLastPathComponent()))
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(theme.c.text2)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                if let summary = session.sourceSummary {
                                    Text(summary)
                                        .font(.system(size: 13.5).monospacedDigit())
                                        .foregroundStyle(theme.c.text2)
                                }
                                PCCheckbox(isOn: $session.includeSubfolders, title: "Включая вложенные папки")
                                    .padding(.top, 8)
                            }
                            Spacer(minLength: 8)
                            Button("Выбрать…") {
                                session.chooseSource()
                            }
                            .buttonStyle(PCButtonStyle())
                        }
                        .padding(.top, 10)
                    }
                    if transferOn {
                        card {
                            cardTitle("Папки назначения")
                            destinationList
                            addDestinationRow
                        }
                    }
                    errorBox
                    footer
                }
                .frame(maxWidth: 720)
                .padding(.top, 34)
            }
            .padding(.horizontal, 32)
            .padding(.top, 64)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(
            RadialGradient(colors: [Color(hex: 0xFBFBFA), Color(hex: 0xECEBE8)], center: .top, startRadius: 0, endRadius: 1200)
        )
    }

    private static let fanAngles: [Double] = [-7, 0, 7]
    private static let fanDrops: [CGFloat] = [22, 6, 24]

    /// Три отпечатка веером
    private var fan: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { i in
                VStack(spacing: 0) {
                    PreviewThumb(url: session.sourcePreview.indices.contains(i) ? session.sourcePreview[i] : nil)
                        .aspectRatio(1.5, contentMode: .fit)
                        .clipped()
                }
                .padding(.horizontal, 5)
                .padding(.top, 5)
                .padding(.bottom, 16)
                .frame(width: 124)
                .background(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 0.5, y: 1)
                .shadow(color: Color.black.opacity(0.24), radius: 8, y: 6)
                .rotationEffect(.degrees(Self.fanAngles[i]))
                .offset(x: CGFloat(i) * 50, y: Self.fanDrops[i])
            }
        }
        .frame(width: 230, height: 150, alignment: .topLeading)
    }

    // MARK: - Общие части

    private func titleBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: theme.isGlass || theme.isTable ? 8 : 6) {
            Text("Новый отбор")
                .font(theme.titleFont)
                .tracking(theme.isTable ? -1.2 : (theme.isGlass ? -1 : -0.5))
                .foregroundStyle(theme.c.text1)
            Text(subtitle)
                .font(.system(size: theme.isGlass || theme.isTable ? 16 : 14))
                .foregroundStyle(theme.c.text2)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(theme.headingFont)
            .foregroundStyle(theme.c.text1)
    }

    /// Карточка «Плёнки» и «Стола»
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(.horizontal, theme.isTable ? 26 : 22)
        .padding(.vertical, theme.isTable ? 22 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if theme.isTable {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 1, y: 1)
                    .shadow(color: Color.black.opacity(0.2), radius: 16, y: 14)
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x151515))
            }
        }
    }

    /// Путь исходной папки, сводка и «Выбрать…»
    private var sourceRow: some View {
        let c = theme.c
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 18))
                    .foregroundStyle(c.text3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.sourceURL.map { PathDisplay.short($0) } ?? "Папка не выбрана")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(session.sourceURL == nil ? c.text3 : c.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let summary = session.sourceSummary {
                        Text(summary)
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(c.text2)
                    }
                }
                Spacer(minLength: 8)
                Button("Выбрать…") {
                    session.chooseSource()
                }
                .buttonStyle(PCButtonStyle())
            }
            if !theme.isNeutral {
                PCCheckbox(isOn: $session.includeSubfolders, title: "Включая вложенные папки")
            }
        }
    }

    @ViewBuilder
    private var destinationList: some View {
        if session.destinations.isEmpty {
            Text(PhotoSession.autoKeepFolder
                 ? "Если ничего не добавить, клавиша 1 будет переносить в папку «Отобранные» внутри исходной. Она появится при первом переносе."
                 : "Папок назначения нет: кадры можно удалять, копировать и сравнивать.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.c.text2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: theme.isGlass ? 10 : 8) {
                ForEach(session.destinations) { destination in
                    destinationRow(destination)
                }
            }
        }
    }

    private func destinationRow(_ destination: Destination) -> some View {
        let c = theme.c
        let shape = RoundedRectangle(cornerRadius: theme.isGlass ? 20 : (theme.isTable ? 10 : 8))
        return HStack(spacing: 12) {
            KeyCap(destination.shortcut, size: theme.isGlass ? .large : .regular, target: true)
            if theme.isGlass || theme.isNeutral {
                VStack(alignment: .leading, spacing: 1) {
                    Text(destination.name)
                        .font(.system(size: theme.isGlass ? 15 : 13.5, weight: .semibold))
                        .foregroundStyle(c.text1)
                    path(destination)
                }
            } else {
                Text(destination.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.text1)
                path(destination)
            }
            Spacer(minLength: 8)
            Button {
                session.removeDestination(destination)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(PCIconButtonStyle(danger: true))
            .help("Убрать папку из списка (сама папка не удаляется)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: theme.isGlass ? 56 : (theme.isTable ? 46 : (theme.isNeutral ? 44 : 42)))
        .background {
            if theme.isGlass {
                shape.fill(Color.white.opacity(theme.isLight ? 0.5 : 0.1))
            } else {
                shape.fill(theme.isTable ? c.surface2 : (theme.isNeutral ? c.surface2 : Color(hex: 0x1B1B1B)))
            }
        }
    }

    private func path(_ destination: Destination) -> some View {
        Text(PathDisplay.short(destination.url))
            .font(.system(size: 12.5))
            .foregroundStyle(theme.c.text3)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var addDestinationRow: some View {
        HStack(spacing: 14) {
            Button {
                session.addDestination()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Добавить папку")
                }
            }
            .buttonStyle(PCButtonStyle())
            Text("До девяти папок, клавиши 1–9. Корзина всегда на Delete.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.c.text3)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var errorBox: some View {
        if let text = session.errorMessage {
            let c = theme.c
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(c.warning)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(c.warning.opacity(theme.isLight ? 0.14 : 0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// «Оформление…» слева, «Начать просмотр ↩» справа
    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                openSettings()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "paintpalette")
                    Text("Оформление…")
                }
            }
            .buttonStyle(PCButtonStyle(big: theme.isGlass))
            .help("Тема, функции и прочие настройки (⌘,)")
            Spacer(minLength: 12)
            Button {
                session.startReview()
            } label: {
                HStack(spacing: 12) {
                    Text("Начать просмотр")
                    KeyCap("↩")
                }
            }
            .buttonStyle(PCButtonStyle(kind: .primary, big: true))
            .keyboardShortcut(.defaultAction)
            .disabled(session.sourceURL == nil)
        }
    }
}

/// Миниатюра кадра исходной папки на стартовом экране (заполняет рамку)
private struct PreviewThumb: View {
    let url: URL?

    @Environment(\.theme) private var theme
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(theme.isLight ? theme.c.surface3 : Color(hex: 0x222222))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = ThumbnailLoader.cached(url) {
                image = cached.image
                return
            }
            let loaded = await ThumbnailLoader.load(url)
            if !Task.isCancelled { image = loaded?.image }
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
