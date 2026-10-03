import AppKit
import SwiftUI

/// Сетка всех фото. Вход/выход в полноэкранный просмотр — F, двойной клик или Return
struct GridView: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme
    @State private var gridWidth: CGFloat = 0
    /// Выделенные кадры (⌘A, ⌘‑клик, ⇧‑клик) — для копирования; текущий кадр — session.index
    @State private var selection: Set<URL> = []

    private let defaultSize: CGFloat = 230

    private var spacing: CGFloat { theme.gridGap }
    private var padding: CGFloat { max(theme.gridGap, 8) }

    /// Число колонок считаем сами, чтобы стрелки ↑↓ прыгали ровно на строку
    private var columnCount: Int {
        let usable = gridWidth - padding * 2
        guard usable > 0 else { return 1 }
        return max(1, Int((usable + spacing) / (session.gridThumbSize + spacing)))
    }

    var body: some View {
        let c = theme.c
        VStack(spacing: 0) {
            topbar
            HStack(spacing: 0) {
                grid
                if session.showInfo, let url = session.currentPhoto {
                    InfoPanel(url: url, companions: session.companions(of: url))
                        .padding(theme.isGlass ? 12 : 0)
                        .transition(.move(edge: .trailing))
                }
            }
            HintBar(groups: [
                HintGroup(title: "Выбор", hints: [
                    Hint("←", "→", "↑", "↓", label: "кадр"),
                    Hint("↩", label: "просмотр"),
                    Hint("⌘A", label: "все"),
                    Hint("⌘C", label: "копировать")
                ]),
                HintGroup(title: "Отбор", hints: [
                    Hint("1–9", label: "в папку"),
                    Hint("⌫", label: "корзина"),
                    Hint("Z", label: "отмена")
                ]),
                HintGroup(title: "Вид", hints: [
                    Hint("I", label: "инфо"),
                    Hint("C", label: "сравнить"),
                    Hint("Esc", label: "выйти")
                ])
            ])
        }
        .background(theme.isContact ? c.canvas : c.app)
        .overlay { ToastOverlay(toast: session.toast) }
        .background(
            KeyCatcher(
                onKeyDown: { handleEvent($0) },
                onMagnify: { delta, _, _ in
                    session.setGridSize(session.gridThumbSize * (1 + delta))
                },
                onCopy: { copyFiles(currentTargets) },
                onSelectAll: { selectAll() }
            )
        )
    }

    // MARK: - Верхняя панель

    private var topbar: some View {
        let c = theme.c
        return HStack(spacing: 12) {
            capsuleGroup {
                Button {
                    session.stopReview()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Выйти")
                    }
                }
                .buttonStyle(PCButtonStyle(kind: .ghost))
                .help("К выбору папки (Esc)")
            }

            if theme.isStudio || theme.isContact {
                Rectangle().fill(c.line).frame(width: 1, height: 16)
            }

            capsuleGroup(text: true) {
                HStack(spacing: 12) {
                    Text(session.sourceURL?.lastPathComponent ?? "")
                        .font(folderFont)
                        .foregroundStyle(theme.isQuiet ? c.text2 : c.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    counter
                    if !selection.isEmpty {
                        Text("выбрано \(selection.count)")
                            .font(theme.numFont)
                            .foregroundStyle(c.accent)
                    }
                }
            }

            Spacer(minLength: 12)

            capsuleGroup {
                HStack(spacing: 6) {
                    Button {
                        session.startCompare()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Сравнить")
                            KeyCap("C", size: .small)
                        }
                    }
                    .buttonStyle(PCButtonStyle(kind: .ghost))
                    .help("Сравнить выбранный кадр с соседним")

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { session.showInfo.toggle() }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(PCIconButtonStyle(isOn: session.showInfo))
                    .help("Сведения о снимке (I)")
                }
            }

            capsuleGroup(text: true) {
                HStack(spacing: 8) {
                    Button {
                        session.setGridSize(session.gridThumbSize / 1.2)
                    } label: {
                        Image(systemName: "photo").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Мельче (−)")

                    Slider(
                        value: Binding(
                            get: { session.gridThumbSize },
                            set: { session.setGridSize($0) }
                        ),
                        in: PhotoSession.gridSizeRange
                    )
                    .controlSize(.small)
                    .frame(width: 120)
                    .help("Размер миниатюр")

                    Button {
                        session.setGridSize(session.gridThumbSize * 1.2)
                    } label: {
                        Image(systemName: "photo").font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .help("Крупнее (+)")
                }
                .foregroundStyle(c.text2)
            }
        }
        .padding(.horizontal, theme.isGlass ? 16 : 12)
        .padding(.top, theme.isGlass ? 12 : 0)
        .frame(height: theme.topbarHeight + (theme.isGlass ? 8 : 0))
        .background(theme.isGlass || theme.isQuiet ? Color.clear : c.surface1)
        .overlay(alignment: .bottom) {
            if !theme.isGlass && !theme.isQuiet {
                Rectangle().fill(c.line).frame(height: 1)
            }
        }
    }

    private var folderFont: Font {
        switch theme.direction {
        case .contact: .system(size: 15, weight: .semibold, design: .serif)
        case .quiet: .system(size: 12)
        case .studio, .glass: .system(size: 13, weight: .semibold)
        }
    }

    /// «12 / 480» — текущий кадр ярче
    private var counter: some View {
        let c = theme.c
        let total = session.photos.count
        let current = total == 0 ? 0 : session.index + 1
        return HStack(spacing: 0) {
            Text("\(current)")
                .fontWeight(.semibold)
                .foregroundStyle(theme.isContact ? c.edge : c.text1)
            Text(" / \(total)")
                .foregroundStyle(theme.isContact ? c.edge : c.text2)
        }
        .font(theme.numFont)
        .tracking(theme.isContact ? 0.9 : 0)
    }

    /// У «Стекла» группы — плавающие стеклянные капсулы; у остальных — просто содержимое
    @ViewBuilder
    private func capsuleGroup<Content: View>(text: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        if theme.isGlass {
            content()
                .padding(.horizontal, text ? 16 : 6)
                .frame(height: 40)
                .glassEffect(.regular, in: .capsule)
        } else {
            content()
        }
    }

    // MARK: - Сетка

    private var grid: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
                            count: columnCount
                        ),
                        spacing: spacing
                    ) {
                        ForEach(Array(session.photos.enumerated()), id: \.element) { item in
                            GridCell(
                                url: item.element,
                                number: item.offset + 1,
                                isSelected: item.offset == session.index || selection.contains(item.element),
                                compact: session.gridThumbSize < 160 || theme.isQuiet,
                                hasNotes: session.hasAnnotations(item.element),
                                extras: session.companions(of: item.element).map { $0.pathExtension.uppercased() }
                            )
                            .id(item.element)
                            .onTapGesture(count: 2) {
                                session.open(item.offset)
                            }
                            .simultaneousGesture(
                                TapGesture().onEnded { click(item.offset) }
                            )
                            .gesture(
                                DragGesture(minimumDistance: 6)
                                    .onChanged { _ in startDrag(item.offset) }
                            )
                            .contextMenu { contextMenu(item.offset) }
                        }
                    }
                    .padding(padding)
                }
                .onAppear {
                    gridWidth = geo.size.width
                    DispatchQueue.main.async {
                        scrollToCurrent(proxy, anchor: .center, animated: false)
                    }
                }
                .onChange(of: geo.size.width) { _, width in
                    gridWidth = width
                }
                .onChange(of: session.currentPhoto) { _, _ in
                    scrollToCurrent(proxy, anchor: nil, animated: true)
                }
                .onChange(of: columnCount) { _, _ in
                    scrollToCurrent(proxy, anchor: .center, animated: false)
                }
            }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, anchor: UnitPoint?, animated: Bool) {
        guard let url = session.currentPhoto else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(url, anchor: anchor)
            }
        } else {
            proxy.scrollTo(url, anchor: anchor)
        }
    }

    // MARK: - Выбор и копирование

    /// Клик: просто — один кадр; ⌘ — добавить/убрать; ⇧ — диапазон от текущего
    private func click(_ index: Int) {
        guard session.photos.indices.contains(index) else { return }
        let url = session.photos[index]
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.isEmpty, let current = session.currentPhoto {
                selection.insert(current)
            }
            if selection.contains(url) {
                selection.remove(url)
            } else {
                selection.insert(url)
            }
        } else if flags.contains(.shift) {
            let range = min(session.index, index)...max(session.index, index)
            selection.formUnion(range.compactMap { session.photos.indices.contains($0) ? session.photos[$0] : nil })
        } else {
            selection = []
        }
        session.select(index)
    }

    private func selectAll() {
        selection = Set(session.photos)
        session.flash("Выбрано \(session.photos.count)", key: "⌘A")
    }

    /// Что копировать сейчас: выделение, а если его нет — текущий кадр
    private var currentTargets: [URL] {
        let alive = session.photos.filter { selection.contains($0) }
        if !alive.isEmpty { return alive }
        return session.currentPhoto.map { [$0] } ?? []
    }

    /// Для клика правой кнопкой или перетаскивания: выделение, если кадр в нём, иначе только этот кадр
    private func targets(for index: Int) -> [URL] {
        guard session.photos.indices.contains(index) else { return [] }
        let url = session.photos[index]
        if selection.contains(url) {
            return session.photos.filter { selection.contains($0) }
        }
        return [url]
    }

    /// Все файлы кадров, включая парные RAW
    private func files(of urls: [URL]) -> [URL] {
        urls.flatMap { [$0] + session.companions(of: $0) }
    }

    /// Кладёт файлы в буфер обмена — вставляются в Finder, почту, мессенджеры как файлы
    private func copyFiles(_ urls: [URL]) {
        let all = files(of: urls)
        guard !all.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(all.map { $0 as NSURL })
        let word = PhotoSession.plural(all.count, "файл", "файла", "файлов")
        session.flash("Скопировано · \(all.count) \(word)", key: "⌘C", kind: .done)
    }

    private func startDrag(_ index: Int) {
        guard !FileDrag.isDragging, session.photos.indices.contains(index) else { return }
        let url = session.photos[index]
        if !selection.contains(url) {
            selection = []
            session.select(index)
        }
        let urls = targets(for: index)
        FileDrag.begin(files: files(of: urls), preview: ThumbnailLoader.cached(url)?.image, count: urls.count)
    }

    @ViewBuilder
    private func contextMenu(_ index: Int) -> some View {
        let urls = targets(for: index)
        let count = files(of: urls).count
        Button(count > 1 ? "Скопировать \(count) \(PhotoSession.plural(count, "файл", "файла", "файлов"))" : "Скопировать файл") {
            copyFiles(urls)
        }
        Button("Показать в Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(files(of: urls))
        }
        Divider()
        Button("Открыть") {
            session.open(index)
        }
        Button("Выбрать все") {
            selectAll()
        }
        if !selection.isEmpty {
            Button("Снять выделение") {
                selection = []
            }
        }
    }

    // MARK: - Клавиатура

    private func handleEvent(_ event: NSEvent) -> Bool {
        // Коды клавиш не зависят от раскладки
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 0: // ⌘A — выбрать все
                selectAll()
                return true
            case 8: // ⌘C — скопировать файлы
                copyFiles(currentTargets)
                return true
            default:
                break
            }
        }

        switch event.keyCode {
        case 6: // Z (и ⌘Z)
            session.undo()
            return true
        case 24, 69: // + и numpad +
            session.setGridSize(session.gridThumbSize * 1.2)
            return true
        case 27, 78: // − и numpad −
            session.setGridSize(session.gridThumbSize / 1.2)
            return true
        case 29, 82: // 0 — размер по умолчанию
            session.setGridSize(defaultSize)
            return true
        default:
            break
        }

        if event.modifierFlags.contains(.command) {
            return false
        }

        let columns = columnCount
        let last = session.photos.count - 1
        switch event.keyCode {
        case 3, 36, 76: // F, Return, Enter — открыть фото
            session.open(session.index)
        case 8: // C — сравнение
            session.startCompare()
        case 34: // I — сведения
            withAnimation(.easeOut(duration: 0.2)) { session.showInfo.toggle() }
        case 123: // ←
            session.select(session.index - 1)
        case 124, 49: // →, пробел
            session.select(session.index + 1)
        case 126: // ↑
            session.select(session.index - columns)
        case 125: // ↓
            session.select(min(session.index + columns, last))
        case 115: // Home
            session.select(0)
        case 119: // End
            session.select(last)
        case 51, 117: // Delete
            session.trashCurrent()
        case 53: // Esc — сначала снять выделение, потом выйти
            if selection.isEmpty {
                session.stopReview()
            } else {
                selection = []
            }
        default:
            guard let first = event.charactersIgnoringModifiers?.first, first.isWholeNumber else {
                return false
            }
            session.handleShortcut(String(first))
        }
        return true
    }
}

// MARK: - Ячейка

private struct GridCell: View {
    let url: URL
    let number: Int
    let isSelected: Bool
    let compact: Bool
    let hasNotes: Bool
    /// Расширения остальных файлов кадра: ["NEF"] для пары JPG + NEF
    let extras: [String]

    @Environment(\.theme) private var theme
    @State private var thumbnail: Thumbnail?
    @State private var hovered = false

    var body: some View {
        let c = theme.c
        let thumb = thumbnail ?? ThumbnailLoader.cached(url)
        let shape = RoundedRectangle(cornerRadius: theme.rMd)

        VStack(alignment: .leading, spacing: 0) {
            if theme.isContact {
                // Номер кадра, как на контактном листе
                Text("\(number)")
                    .font(theme.edgeFont)
                    .foregroundStyle(c.text3)
                    .lineLimit(1)
                    .frame(height: 14)
            }

            thumbArea(thumb)

            caption(thumb?.info)
                .padding(.top, theme.isQuiet ? 6 : 8)
        }
        .padding(cellPadding)
        .background(cellFill, in: shape)
        .overlay { selectionMark(shape) }
        .shadow(color: glow, radius: isSelected && theme.isGlass ? 4 : 0)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .task(id: url) {
            guard thumbnail == nil else { return }
            if let loaded = await ThumbnailLoader.load(url), !Task.isCancelled {
                thumbnail = loaded
            }
        }
    }

    private var cellPadding: EdgeInsets {
        switch theme.direction {
        case .studio: EdgeInsets(top: 10, leading: 10, bottom: 8, trailing: 10)
        case .glass: EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12)
        case .quiet: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        case .contact: EdgeInsets(top: 4, leading: 6, bottom: 6, trailing: 6)
        }
    }

    private var cellFill: Color {
        let c = theme.c
        switch theme.direction {
        case .studio:
            return isSelected ? c.selectionFill : (hovered ? c.surface1 : .clear)
        case .glass:
            return isSelected ? c.selectionFill : (hovered ? c.surface2 : c.surface1)
        case .quiet:
            return hovered && !isSelected ? c.surface1 : .clear
        case .contact:
            return hovered && !isSelected ? c.surface1 : .clear
        }
    }

    private var glow: Color {
        guard isSelected, theme.isGlass else { return .clear }
        return theme.c.selection.opacity(0.35)
    }

    @ViewBuilder
    private func selectionMark(_ shape: RoundedRectangle) -> some View {
        if isSelected {
            let c = theme.c
            switch theme.direction {
            case .studio:
                shape.strokeBorder(c.selection, lineWidth: 2)
            case .glass:
                shape.strokeBorder(c.selection, lineWidth: 3)
            case .quiet:
                Rectangle().strokeBorder(c.selection, lineWidth: 1.5)
            case .contact:
                EmptyView() // у «Контакта» — уголки кадрирования вокруг миниатюры
            }
        }
    }

    private func thumbArea(_ thumb: Thumbnail?) -> some View {
        let c = theme.c
        let radius = theme.rSm
        return ZStack {
            if let image = thumb?.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: radius))
            } else if thumb == nil {
                // Загрузка: серая заглушка и индикатор
                RoundedRectangle(cornerRadius: radius)
                    .fill(c.surface2)
                    .aspectRatio(1.5, contentMode: .fit)
                    .padding(.horizontal, 20)
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(c.text3)
            }
        }
        .aspectRatio(theme.isContact ? 1.5 : 1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay {
            if isSelected && theme.isContact {
                CropCorners()
                    .stroke(c.selection, lineWidth: 2)
                    .padding(-6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hasNotes {
                noteBadge
                    .padding(6)
            }
        }
    }

    /// Значок «есть пометки» в правом верхнем углу миниатюры
    private var noteBadge: some View {
        let c = theme.c
        return Image(systemName: "pencil")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.isQuiet ? c.text1 : c.accent)
            .frame(width: 20, height: 20)
            .background {
                if !theme.isQuiet {
                    Circle().fill(c.overlay)
                    Circle().stroke(c.line, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(theme.isLight ? 0.15 : 0), radius: 1.5, y: 1)
            .help("Есть пометки")
    }

    @ViewBuilder
    private func caption(_ info: PhotoInfo?) -> some View {
        let c = theme.c
        if theme.isQuiet {
            HStack(spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? c.text1 : c.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !extras.isEmpty {
                    pairTag
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(url.lastPathComponent)
                        .font(.system(size: theme.isContact ? 11 : 12, weight: .medium))
                        .foregroundStyle(thumbnail == nil && ThumbnailLoader.cached(url) == nil ? c.text2 : c.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !extras.isEmpty {
                        pairTag
                    }
                }
                if !compact {
                    // Строки есть всегда, чтобы все ячейки были одной высоты
                    Text(details(info))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(c.text3)
                    Text(info?.camera ?? " ")
                        .font(.system(size: 11))
                        .foregroundStyle(c.text3)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Метка пары: «+NEF» — у кадра есть ещё и RAW
    private var pairTag: some View {
        Text("+" + extras.joined(separator: "+"))
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.c.text2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.c.lineStrong, lineWidth: 1))
            .fixedSize()
            .help("Кадр снят в нескольких форматах; переносится целиком")
    }

    private func details(_ info: PhotoInfo?) -> String {
        guard let info else { return " " }
        var parts: [String] = []
        if let size = info.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let w = info.pixelWidth, let h = info.pixelHeight {
            parts.append("\(w)×\(h)")
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}

/// Четыре уголка кадрирования («Контакт»: выделение кадра на контактном листе)
nonisolated struct CropCorners: Shape {
    var length: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let l = min(length, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        return path
    }
}

/// Перетаскивание файлов из сетки в Finder и другие приложения (копирование)
final class FileDrag: NSObject, NSDraggingSource {
    private static let shared = FileDrag()
    private(set) static var isDragging = false

    static func begin(files: [URL], preview: NSImage?, count: Int) {
        guard !files.isEmpty,
              let event = NSApp.currentEvent,
              let view = event.window?.contentView else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        let side: CGFloat = 72
        let items = files.enumerated().map { item -> NSDraggingItem in
            let dragItem = NSDraggingItem(pasteboardWriter: item.element as NSURL)
            // Первый файл — миниатюра кадра, остальные — стопкой за ним
            let image = (item.offset == 0 ? preview : nil) ?? NSWorkspace.shared.icon(forFile: item.element.path)
            let shift = CGFloat(min(item.offset, 4)) * 4
            dragItem.setDraggingFrame(
                NSRect(x: point.x - side / 2 + shift, y: point.y - side / 2 - shift, width: side, height: side),
                contents: image
            )
            return dragItem
        }
        isDragging = true
        let session = view.beginDraggingSession(with: items, event: event, source: shared)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        FileDrag.isDragging = false
    }
}
