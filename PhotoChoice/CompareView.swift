import AppKit
import SwiftUI

struct PaneTransform: Equatable {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
}

/// Сравнение двух кадров: слева эталон (A), справа кандидат (B)
struct CompareView: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme

    @State private var leftImage: NSImage?
    @State private var rightImage: NSImage?
    @State private var left = PaneTransform()
    @State private var right = PaneTransform()
    @State private var containerSize: CGSize = .zero
    @State private var dragBase: CGSize?
    @State private var trackpadSwipe = TrackpadSwipe()

    private let padding: CGFloat = 16
    private let minZoom: CGFloat = 0.1
    private let maxZoom: CGFloat = 10

    var body: some View {
        let c = theme.c
        GeometryReader { geo in
            HStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 0) {
                        if !theme.isGlass {
                            topBar
                        }
                        HStack(spacing: 0) {
                            pane(.left)
                            if dividerWidth > 0 {
                                c.canvas.frame(width: dividerWidth)
                            }
                            pane(.right)
                        }
                        if !theme.isGlass {
                            hints
                        }
                    }
                    if theme.isGlass {
                        VStack(spacing: 0) {
                            topBar
                            Spacer(minLength: 0)
                            hints
                        }
                    }
                    ToastOverlay(toast: session.toast)
                }

                if session.showInfo, let url = session.currentPhoto {
                    InfoPanel(url: url, companions: session.companions(of: url))
                        .padding(theme.isGlass ? 12 : 0)
                        .transition(.move(edge: .trailing))
                }
            }
            .onAppear { containerSize = geo.size }
            .onChange(of: geo.size) { _, size in containerSize = size }
        }
        .background(c.canvas)
        .background(
            KeyCatcher(
                onKeyDown: { handleEvent($0) },
                onMagnify: { delta, phase, anchor in handleMagnify(delta, phase, anchor) },
                onSmartMagnify: { anchor in
                    let point = absolute(anchor)
                    if let side = paneSide(at: point) {
                        toggleZoom(side, anchor: paneAnchor(side, point))
                    }
                },
                onScroll: { handleScroll($0) },
                onCopy: { session.copyAnnotated() }
            )
        )
        .task(id: session.compareLeft) { await loadImage(.left) }
        .task(id: session.compareRight) { await loadImage(.right) }
    }

    // MARK: - Половина экрана

    /// Поля вокруг фото в половине: сверху место под подпись
    private var paneInsets: EdgeInsets {
        theme.isGlass
            ? EdgeInsets(top: 72, leading: 16, bottom: 80, trailing: 16)
            : EdgeInsets(top: theme.isQuiet ? 28 : 36, leading: theme.isQuiet ? 0 : 16, bottom: 16, trailing: theme.isQuiet ? 0 : 16)
    }

    private func pane(_ side: CompareSide) -> some View {
        let c = theme.c
        let url = session.compareURL(side)
        let image = side == .left ? leftImage : rightImage
        let t = transform(side)
        let isActive = session.compareActive == side

        return GeometryReader { geo in
            ZStack {
                c.canvas
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .overlay {
                            if let url {
                                AnnotationLayer(session: session, url: url, zoom: t.zoom)
                            }
                        }
                        .padding(paneInsets)
                        .scaleEffect(t.zoom)
                        .offset(t.pan)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(c.text1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: theme.isGlass ? .bottom : .topLeading) {
                if let url {
                    PaneHeader(url: url, side: side, position: position(of: url), isActive: isActive)
                        .padding(theme.isGlass ? EdgeInsets(top: 0, leading: 0, bottom: 84, trailing: 0)
                                              : EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12))
                }
            }
            .overlay(alignment: theme.isGlass ? .bottomTrailing : .topTrailing) {
                if abs(t.zoom - 1) > 0.01 {
                    Text("\(Int((t.zoom * 100).rounded()))%")
                        .font(theme.numFont)
                        .foregroundStyle(theme.isContact ? c.edge : c.text2)
                        .padding(theme.isGlass ? EdgeInsets(top: 0, leading: 0, bottom: 92, trailing: 24)
                                              : EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 12))
                }
            }
            .overlay { activeMark(isActive) }
            .gesture(panGesture(side))
            .onTapGesture(count: 2) { location in
                toggleZoom(side, anchor: CGPoint(
                    x: location.x - geo.size.width / 2,
                    y: location.y - geo.size.height / 2
                ))
            }
            .simultaneousGesture(TapGesture().onEnded { session.setCompareActive(side) })
        }
    }

    /// Рамка активной половины
    @ViewBuilder
    private func activeMark(_ isActive: Bool) -> some View {
        if isActive {
            let c = theme.c
            switch theme.direction {
            case .glass:
                RoundedRectangle(cornerRadius: theme.rLg)
                    .strokeBorder(c.selection, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            case .quiet:
                VStack {
                    Rectangle().fill(c.selection).frame(height: 1.5)
                    Spacer()
                }
                .allowsHitTesting(false)
            case .studio, .contact:
                Rectangle()
                    .strokeBorder(c.selection, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func position(of url: URL) -> String {
        guard let i = session.photos.firstIndex(of: url) else { return "" }
        return "\(i + 1) / \(session.photos.count)"
    }

    // MARK: - Панели

    private var topBar: some View {
        let c = theme.c
        return HStack(spacing: 12) {
            capsuleGroup {
                Button {
                    session.stopCompare()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Выйти")
                    }
                }
                .buttonStyle(PCButtonStyle(kind: .ghost))
                .help("Закончить сравнение (C или Esc)")
            }

            capsuleGroup(text: true) {
                Text("Сравнение")
                    .font(theme.isContact ? .system(size: 15, weight: .semibold, design: .serif) : .system(size: 13, weight: .semibold))
                    .foregroundStyle(c.text1)
            }

            Spacer(minLength: 12)

            capsuleGroup(text: true) {
                Toggle(isOn: Binding(
                    get: { session.compareSync },
                    set: { _ in toggleSync() }
                )) {
                    HStack(spacing: 6) {
                        Text("Синхронный зум")
                            .font(.system(size: 12))
                            .foregroundStyle(session.compareSync ? c.text1 : c.text2)
                        KeyCap("L", size: .small)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            if theme.isStudio {
                Rectangle().fill(c.line).frame(width: 1, height: 16)
            }

            capsuleGroup {
                HStack(spacing: 6) {
                    Button {
                        session.swapCompare()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Поменять местами")
                            KeyCap("X", size: .small)
                        }
                    }
                    .buttonStyle(PCButtonStyle())

                    Button {
                        session.promoteToReference()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up")
                            Text("Сделать эталоном")
                            KeyCap("↑", size: .small)
                        }
                    }
                    .buttonStyle(PCButtonStyle())
                }
            }
        }
        .padding(.horizontal, theme.isGlass ? 16 : 12)
        .padding(.top, theme.isGlass ? 12 : 0)
        .frame(height: topbarHeight)
        .background {
            if theme.isStudio || theme.isContact {
                c.surface1
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(c.line).frame(height: 1)
                    }
            }
        }
    }

    private var hints: some View {
        HintBar(groups: [
            HintGroup(title: "Кандидат", hints: [
                Hint("←", "→", label: "листать"),
                Hint("Tab", label: "сторона")
            ]),
            HintGroup(title: "Отбор", hints: [
                Hint("1–9", label: "в папку"),
                Hint("⌫", label: "корзина")
            ]),
            HintGroup(title: "Сравнение", hints: [
                Hint("L", label: "синхр. зум"),
                Hint("X", label: "поменять"),
                Hint("↑", label: "эталон"),
                Hint("C", label: "выйти")
            ])
        ])
    }

    /// У «Стекла» группы — стеклянные капсулы; у остальных — просто содержимое
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

    // MARK: - Геометрия

    private var topbarHeight: CGFloat {
        theme.topbarHeight + (theme.isGlass ? 8 : 0)
    }

    /// Отступ половин сверху и снизу (у «Стекла» панели лежат поверх)
    private var paneTop: CGFloat { theme.isGlass ? 0 : topbarHeight }
    private var paneBottom: CGFloat { theme.isGlass ? 0 : theme.hintbarReserve }

    private var dividerWidth: CGFloat {
        switch theme.direction {
        case .glass: 0
        case .quiet: 1
        case .studio, .contact: 2
        }
    }

    private var panelWidth: CGFloat {
        session.showInfo ? theme.panelReserve : 0
    }

    private var paneSize: CGSize {
        CGSize(
            width: max((containerSize.width - panelWidth - dividerWidth) / 2, 1),
            height: max(containerSize.height - paneTop - paneBottom, 1)
        )
    }

    /// Точка от KeyCatcher (смещение от центра всего вида) → координаты от левого верхнего угла
    private func absolute(_ anchor: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x + containerSize.width / 2, y: anchor.y + containerSize.height / 2)
    }

    /// Над какой половиной курсор; nil — над панелью сведений
    private func paneSide(at point: CGPoint) -> CompareSide? {
        let width = paneSize.width
        if point.x < width { return .left }
        if point.x < width * 2 + dividerWidth { return .right }
        return nil
    }

    /// Смещение точки от центра нужной половины
    private func paneAnchor(_ side: CompareSide, _ point: CGPoint) -> CGPoint {
        let w = paneSize.width
        let centerX = side == .left ? w / 2 : w * 1.5 + dividerWidth
        let centerY = paneTop + paneSize.height / 2
        return CGPoint(x: point.x - centerX, y: point.y - centerY)
    }

    // MARK: - Зум

    private func transform(_ side: CompareSide) -> PaneTransform {
        side == .left ? left : right
    }

    private func image(_ side: CompareSide) -> NSImage? {
        side == .left ? leftImage : rightImage
    }

    /// Применяет масштаб/сдвиг к половине (или к обеим при синхронизации)
    private func apply(zoom: CGFloat, pan: CGSize, from side: CompareSide) {
        let target = min(max(zoom, minZoom), maxZoom)
        let sides: [CompareSide] = session.compareSync ? [.left, .right] : [side]
        for s in sides {
            let value = PaneTransform(zoom: target, pan: clampedPan(pan, zoom: target, image: image(s)))
            if s == .left { left = value } else { right = value }
        }
    }

    /// Зум с сохранением точки под курсором
    private func zoom(on side: CompareSide, to newZoom: CGFloat, anchor: CGPoint) {
        let t = transform(side)
        guard t.zoom > 0 else { return }
        let target = min(max(newZoom, minZoom), maxZoom)
        let ratio = target / t.zoom
        let pan = CGSize(
            width: anchor.x - (anchor.x - t.pan.width) * ratio,
            height: anchor.y - (anchor.y - t.pan.height) * ratio
        )
        apply(zoom: target, pan: pan, from: side)
    }

    private func toggleZoom(_ side: CompareSide, anchor: CGPoint) {
        withAnimation(.spring(duration: 0.3)) {
            if abs(transform(side).zoom - 1) > 0.01 {
                apply(zoom: 1, pan: .zero, from: side)
            } else {
                zoom(on: side, to: 2.5, anchor: anchor)
            }
        }
    }

    private func stepZoom(by factor: CGFloat) {
        let side = session.compareActive
        withAnimation(.spring(duration: 0.2)) {
            zoom(on: side, to: transform(side).zoom * factor, anchor: .zero)
            if abs(transform(side).zoom - 1) < 0.04 {
                apply(zoom: 1, pan: .zero, from: side)
            }
        }
    }

    private var isAnyScaled: Bool {
        abs(left.zoom - 1) > 0.01 || abs(right.zoom - 1) > 0.01
    }

    private func resetAll() {
        withAnimation(.spring(duration: 0.25)) {
            left = PaneTransform()
            right = PaneTransform()
        }
    }

    private func toggleSync() {
        session.toggleCompareSync()
        if session.compareSync {
            // Выравниваем вторую половину по активной
            let t = transform(session.compareActive)
            withAnimation(.spring(duration: 0.25)) {
                apply(zoom: t.zoom, pan: t.pan, from: session.compareActive)
            }
        }
    }

    private func clampedPan(_ value: CGSize, zoom: CGFloat, image: NSImage?) -> CGSize {
        let size = paneSize
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let availW = max(size.width - padding * 2, 1)
        let availH = max(size.height - padding * 2, 1)
        let fit = min(availW / image.size.width, availH / image.size.height)
        let maxX = max(0, (image.size.width * fit * zoom - size.width) / 2 + padding)
        let maxY = max(0, (image.size.height * fit * zoom - size.height) / 2 + padding)
        return CGSize(
            width: min(max(value.width, -maxX), maxX),
            height: min(max(value.height, -maxY), maxY)
        )
    }

    // MARK: - Жесты

    private func panGesture(_ side: CompareSide) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let t = transform(side)
                guard t.zoom > 1.01 else { return }
                let base = dragBase ?? t.pan
                if dragBase == nil { dragBase = base }
                apply(
                    zoom: t.zoom,
                    pan: CGSize(width: base.width + value.translation.width, height: base.height + value.translation.height),
                    from: side
                )
            }
            .onEnded { _ in dragBase = nil }
    }

    private func handleMagnify(_ delta: CGFloat, _ phase: NSEvent.Phase, _ anchor: CGPoint) {
        let point = absolute(anchor)
        guard let side = paneSide(at: point) else { return }
        zoom(on: side, to: transform(side).zoom * (1 + delta), anchor: paneAnchor(side, point))
        if phase == .ended || phase == .cancelled, abs(transform(side).zoom - 1) < 0.04 {
            withAnimation(.spring(duration: 0.2)) {
                apply(zoom: 1, pan: .zero, from: side)
            }
        }
    }

    private func handleScroll(_ scroll: ScrollInfo) -> Bool {
        let point = absolute(scroll.anchor)
        // Над панелью сведений — пусть прокручивается она
        guard let side = paneSide(at: point) else { return false }
        let t = transform(side)

        if scroll.modifiers.contains(.command) || scroll.modifiers.contains(.option) {
            zoom(on: side, to: t.zoom * pow(1.01, scroll.dy), anchor: paneAnchor(side, point))
            return true
        }
        if t.zoom > 1.01 {
            apply(zoom: t.zoom, pan: CGSize(width: t.pan.width + scroll.dx, height: t.pan.height + scroll.dy), from: side)
            return true
        }
        // Горизонтальный свайп двумя пальцами листает ту половину, над которой курсор
        guard scroll.isPrecise else { return true }
        switch trackpadSwipe.feed(scroll) {
        case .next:
            session.setCompareActive(side)
            session.compareStep(1)
        case .previous:
            session.setCompareActive(side)
            session.compareStep(-1)
        case nil:
            break
        }
        return true
    }

    // MARK: - Клавиатура

    private func handleEvent(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 6: // Z / ⌘Z
            session.undo()
            return true
        case 24, 69:
            stepZoom(by: 1.25)
            return true
        case 27, 78:
            stepZoom(by: 0.8)
            return true
        case 29, 82:
            resetAll()
            return true
        default:
            break
        }

        if event.modifierFlags.contains(.command) {
            return false
        }

        switch event.keyCode {
        case 8: // C — выйти из сравнения
            session.stopCompare()
        case 53: // Esc
            if isAnyScaled {
                resetAll()
            } else {
                session.stopCompare()
            }
        case 3: // F — к сетке
            session.toggleViewMode()
        case 34: // I
            withAnimation(.easeOut(duration: 0.2)) { session.showInfo.toggle() }
        case 123: // ←
            session.compareStep(-1)
        case 124, 49: // →, пробел
            session.compareStep(1)
        case 126: // ↑ — в эталон
            session.promoteToReference()
        case 48: // Tab — другая сторона
            session.setCompareActive(session.compareActive.other)
        case 7: // X — поменять местами
            session.swapCompare()
        case 37: // L — синхронный зум
            toggleSync()
        case 51, 117: // Delete
            session.trashCurrent()
        default:
            guard let first = event.charactersIgnoringModifiers?.first, first.isWholeNumber else {
                return false
            }
            session.handleShortcut(String(first))
        }
        return true
    }

    // MARK: - Загрузка

    private func loadImage(_ side: CompareSide) async {
        guard let url = session.compareURL(side) else {
            setImage(nil, side)
            return
        }
        if let cached = ImageLoader.cachedImage(at: url) {
            setImage(cached, side)
            return
        }
        setImage(nil, side)
        let image = await ImageLoader.imageAsync(at: url)
        guard !Task.isCancelled, session.compareURL(side) == url else { return }
        setImage(image, side)
    }

    private func setImage(_ image: NSImage?, _ side: CompareSide) {
        if side == .left {
            leftImage = image
            left.pan = clampedPan(left.pan, zoom: left.zoom, image: image)
        } else {
            rightImage = image
            right.pan = clampedPan(right.pan, zoom: right.zoom, image: image)
        }
    }
}

/// Подпись половины: A/B, «Эталон», имя файла, позиция и параметры съёмки
private struct PaneHeader: View {
    let url: URL
    let side: CompareSide
    let position: String
    let isActive: Bool

    @Environment(\.theme) private var theme
    @State private var details: PhotoDetails?

    var body: some View {
        let c = theme.c
        let content = HStack(spacing: 8) {
            badge
            if side == .left {
                Text(theme.isGlass ? "Эталон" : "ЭТАЛОН")
                    .font(theme.isContact ? theme.edgeFont : .system(size: 10.5, weight: .semibold))
                    .tracking(theme.isGlass ? 0 : 0.6)
                    .foregroundStyle(theme.isContact ? c.edge : c.text3)
            }
            Text("\(url.lastPathComponent) · \(position)")
                .font(theme.isContact ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .foregroundStyle(isActive ? c.text1 : c.text2)
                .lineLimit(1)
                .truncationMode(.middle)
            if !exposure.isEmpty {
                Text(exposure)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(c.text3)
                    .lineLimit(1)
            }
        }

        Group {
            if theme.isGlass {
                content
                    .padding(.leading, 6)
                    .padding(.trailing, 14)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
            } else {
                content
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(c.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: theme.rSm))
            }
        }
        .task(id: url) {
            details = PhotoDetailsLoader.cached(url)
            guard details == nil else { return }
            let loaded = await PhotoDetailsLoader.load(url)
            if !Task.isCancelled { details = loaded }
        }
    }

    /// Плашка A / B: у активной половины — акцентная
    private var badge: some View {
        let c = theme.c
        let letter = side == .left ? "A" : "B"
        let shape = RoundedRectangle(cornerRadius: theme.isGlass ? 11 : theme.rSm)
        let fill: Color = isActive ? (theme.isQuiet ? .clear : c.accentFill) : (theme.isQuiet || theme.isContact ? .clear : c.surface2)
        let stroke: Color = isActive ? (theme.isQuiet ? .clear : c.accentFill) : (theme.isQuiet ? .clear : (theme.isContact ? c.edge : c.lineStrong))
        let text: Color = isActive ? (theme.isQuiet ? c.text1 : c.onAccent) : (theme.isContact ? c.edge : c.text1)
        return Text(letter)
            .font(theme.isGlass ? .system(size: 12, weight: .bold, design: .rounded) : .system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(text)
            .frame(width: 22, height: 22)
            .background(fill, in: shape)
            .overlay(shape.stroke(stroke, lineWidth: 1))
    }

    private var exposure: String {
        [
            details?.shutter,
            details?.aperture,
            (details?.iso).map { "ISO \($0)" },
            details?.focal
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
