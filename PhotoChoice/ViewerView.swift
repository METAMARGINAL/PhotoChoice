import AppKit
import SwiftUI

struct ViewerView: View {
    @Bindable var session: PhotoSession

    @State private var currentImage: NSImage?

    @State private var dragOffset: CGSize = .zero

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panAtDragStart: CGSize?
    @State private var containerSize: CGSize = .zero

    // Двухпальцевый свайп по трекпаду. Класс, чтобы накопление не перерисовывало вид
    @State private var trackpadSwipe = TrackpadSwipe()

    // «Улетающее» фото после решения
    @State private var ghost: Ghost?

    private let imagePadding: CGFloat = 20
    private let infoPanelInsets = EdgeInsets(top: 52, leading: 0, bottom: 56, trailing: 16)
    private let maxZoom: CGFloat = 10
    private let minZoom: CGFloat = 0.1
    /// Увеличено больше «вписанного» — перетаскивание двигает фото, а не свайпает
    private var isZoomed: Bool { zoom > 1.01 }
    /// Масштаб отличается от «вписанного» в любую сторону
    private var isScaled: Bool { abs(zoom - 1) > 0.01 }

    private struct Ghost: Identifiable {
        let id = UUID()
        let image: NSImage
        let start: CGSize
        let target: CGSize
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if session.photos.isEmpty {
                finishedState
            } else {
                photoLayer
                hud
                if session.showInfo, let url = session.currentPhoto {
                    HStack {
                        Spacer()
                        InfoPanel(url: url)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08)))
                            .padding(infoPanelInsets)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            if let flash = session.flashMessage {
                flashBadge(flash)
            }
        }
        .background(
            KeyCatcher(
                onKeyDown: { handleEvent($0) },
                onMagnify: { delta, phase, anchor in handleMagnify(delta, phase, anchor) },
                onSmartMagnify: { anchor in toggleZoom(at: anchor) },
                onScroll: { handleScroll($0) },
                onCopy: { session.copyAnnotated() }
            )
        )
        .onChange(of: session.currentPhoto, initial: true) { _, url in
            resetTransform()
            if let url, let cached = ImageLoader.cachedImage(at: url) {
                currentImage = cached
            }
        }
        .onDisappear { session.isDrawing = false }
        .task(id: session.currentPhoto) {
            await loadCurrentImage()
        }
    }

    // MARK: - Layers

    private var photoLayer: some View {
        GeometryReader { geo in
            ZStack {
                if let currentImage {
                    Image(nsImage: currentImage)
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            if let url = session.currentPhoto {
                                AnnotationLayer(session: session, url: url, zoom: zoom)
                            }
                        }
                        .padding(imagePadding)
                        .scaleEffect(zoom)
                        .offset(
                            x: pan.width + dragOffset.width,
                            y: pan.height + dragOffset.height
                        )
                        .rotationEffect(.degrees(Double(dragOffset.width / 40)))
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }

                if let ghost {
                    FlyAway(image: ghost.image, start: ghost.start, target: ghost.target, padding: imagePadding)
                        .id(ghost.id)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(alignment: .topLeading) {
                if dragOffset.width < -80 {
                    label("Корзина", color: .red)
                        .padding(40)
                }
            }
            .overlay(alignment: .topTrailing) {
                if dragOffset.width > 80 {
                    label(session.primaryDestination?.name ?? "Папка", color: .green)
                        .padding(40)
                }
            }
            .contentShape(Rectangle())
            .onAppear { containerSize = geo.size }
            .onChange(of: geo.size) { _, newSize in
                containerSize = newSize
                pan = clampedPan(pan)
            }
        }
        .gesture(dragGesture, including: session.isDrawing ? .subviews : .all)
        .onTapGesture(count: 2) { location in
            guard !session.isDrawing else { return }
            toggleZoom(at: CGPoint(
                x: location.x - containerSize.width / 2,
                y: location.y - containerSize.height / 2
            ))
        }
    }

    private var hud: some View {
        VStack {
            HStack {
                Button("Выйти") { session.stopReview() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(session.currentPhoto?.lastPathComponent ?? "")
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if isScaled {
                    Text("\(Int((zoom * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.trailing, 8)
                }
                Button {
                    session.toggleDrawing()
                } label: {
                    Image(systemName: session.isDrawing ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(session.isDrawing ? Color.accentColor : Color.white.opacity(0.8))
                .help("Рисовать (D)")
                .padding(.trailing, 10)
                Text(session.progressText)
                    .foregroundStyle(.white)
                    .font(.headline.monospacedDigit())
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            if session.isDrawing {
                DrawToolbar(session: session)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                hints
            }
        }
    }

    private var hints: some View {
        VStack {
            HStack(spacing: 16) {
                hint("← →", "листать")
                hint("1–\(min(max(session.destinations.count, 1), 9))", "в папку")
                hint("⌫", "корзина")
                hint("Z", "отмена")
                hint("+ −", "зум")
                hint("0", "сброс зума")
                hint("I", "инфо")
                hint("D", "рисовать")
                hint("F", "сетка")
                hint("Esc", "сетка")
            }
        }
        .padding(.bottom, 18)
    }

    private var finishedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Готово")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Отобрано: \(session.movedCount)   В корзине: \(session.trashedCount)")
                .foregroundStyle(.white.opacity(0.8))
            Button("К выбору папки") {
                session.stopReview()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Drag: свайп (zoom == 1) или перемещение (zoom > 1)

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if isZoomed {
                    let base = panAtDragStart ?? pan
                    panAtDragStart = base
                    pan = clampedPan(CGSize(
                        width: base.width + value.translation.width,
                        height: base.height + value.translation.height
                    ))
                } else {
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                if isZoomed {
                    panAtDragStart = nil
                    return
                }
                let width = value.predictedEndTranslation.width
                let height = value.predictedEndTranslation.height

                if width > 140 {
                    commit(flyTo: CGSize(width: 900, height: height)) { session.moveCurrentToPrimary() }
                } else if width < -140 {
                    commit(flyTo: CGSize(width: -900, height: height)) { session.trashCurrent() }
                } else if height < -160, session.destinations.count > 1 {
                    commit(flyTo: CGSize(width: 0, height: -800)) {
                        session.moveCurrent(to: session.destinations[1])
                    }
                } else {
                    withAnimation(.spring(duration: 0.28)) { dragOffset = .zero }
                }
            }
    }

    private func commit(flyTo target: CGSize, _ action: () -> Void) {
        let before = session.currentPhoto
        let image = currentImage
        let start = dragOffset

        action()

        if session.currentPhoto != before, let image {
            let newGhost = Ghost(image: image, start: start, target: target)
            ghost = newGhost
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                if ghost?.id == newGhost.id { ghost = nil }
            }
        } else if session.currentPhoto == before {
            withAnimation(.spring(duration: 0.28)) { dragOffset = .zero }
        }
    }

    // MARK: - Zoom (как в «Просмотре»: можно отдалить меньше экрана, зум к курсору)

    /// Меняет масштаб, удерживая на месте точку `anchor` (смещение от центра экрана)
    private func setZoom(_ newValue: CGFloat, anchor: CGPoint = .zero) {
        guard zoom > 0 else { return }
        let target = min(max(newValue, minZoom), maxZoom)
        let ratio = target / zoom
        let newPan = CGSize(
            width: anchor.x - (anchor.x - pan.width) * ratio,
            height: anchor.y - (anchor.y - pan.height) * ratio
        )
        zoom = target
        pan = clampedPan(newPan)
    }

    private func handleMagnify(_ delta: CGFloat, _ phase: NSEvent.Phase, _ anchor: CGPoint) {
        guard currentImage != nil else { return }
        setZoom(zoom * (1 + delta), anchor: anchor)
        if phase == .ended || phase == .cancelled {
            settleZoom()
        }
    }

    /// Рядом с «вписанным» размером слегка примагничиваем к нему
    private func settleZoom() {
        if abs(zoom - 1) < 0.04 {
            withAnimation(.spring(duration: 0.2)) {
                zoom = 1
                pan = .zero
            }
        }
    }

    /// Курсор над панелью сведений — её прокрутку не перехватываем
    private func isOverInfoPanel(_ anchor: CGPoint) -> Bool {
        guard session.showInfo, containerSize.width > 0 else { return false }
        let x = anchor.x + containerSize.width / 2
        let y = anchor.y + containerSize.height / 2
        return x >= containerSize.width - infoPanelInsets.trailing - InfoPanel.width
            && y >= infoPanelInsets.top
            && y <= containerSize.height - infoPanelInsets.bottom
    }

    private func handleScroll(_ scroll: ScrollInfo) -> Bool {
        if isOverInfoPanel(scroll.anchor) { return false }
        // ⌘ или ⌥ + колесо/скролл — зум к курсору (удобно с мышью)
        if scroll.modifiers.contains(.command) || scroll.modifiers.contains(.option) {
            guard currentImage != nil else { return true }
            setZoom(zoom * pow(1.01, scroll.dy), anchor: scroll.anchor)
            return true
        }
        // Увеличено — два пальца двигают фото
        if isZoomed {
            pan = clampedPan(CGSize(width: pan.width + scroll.dx, height: pan.height + scroll.dy))
            return true
        }
        // Иначе горизонтальный свайп двумя пальцами листает, как стрелки
        guard scroll.isPrecise else { return true }
        switch trackpadSwipe.feed(scroll) {
        case .next: session.goNext()
        case .previous: session.goPrevious()
        case nil: break
        }
        return true
    }

    private func toggleZoom(at anchor: CGPoint = .zero) {
        guard currentImage != nil else { return }
        withAnimation(.spring(duration: 0.3)) {
            if isScaled {
                zoom = 1
                pan = .zero
            } else {
                setZoom(2.5, anchor: anchor)
            }
        }
    }

    private func stepZoom(by factor: CGFloat) {
        guard currentImage != nil else { return }
        withAnimation(.spring(duration: 0.2)) {
            setZoom(zoom * factor)
            if abs(zoom - 1) < 0.04 {
                zoom = 1
                pan = .zero
            }
        }
    }

    private func resetZoom() {
        withAnimation(.spring(duration: 0.25)) {
            zoom = 1
            pan = .zero
        }
    }

    /// Не даём утащить фото за пределы экрана
    private func clampedPan(_ value: CGSize) -> CGSize {
        guard let image = currentImage,
              image.size.width > 0, image.size.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }

        let availW = max(containerSize.width - imagePadding * 2, 1)
        let availH = max(containerSize.height - imagePadding * 2, 1)
        let fit = min(availW / image.size.width, availH / image.size.height)
        let shownW = image.size.width * fit * zoom
        let shownH = image.size.height * fit * zoom

        let maxX = max(0, (shownW - containerSize.width) / 2 + imagePadding)
        let maxY = max(0, (shownH - containerSize.height) / 2 + imagePadding)
        return CGSize(
            width: min(max(value.width, -maxX), maxX),
            height: min(max(value.height, -maxY), maxY)
        )
    }

    private func resetTransform() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragOffset = .zero
            zoom = 1
            pan = .zero
            panAtDragStart = nil
        }
    }

    // MARK: - Image loading

    private func loadCurrentImage() async {
        guard let url = session.currentPhoto else {
            currentImage = nil
            return
        }
        if let cached = ImageLoader.cachedImage(at: url) {
            currentImage = cached
            return
        }
        currentImage = nil
        let image = await ImageLoader.imageAsync(at: url)
        guard !Task.isCancelled, url == session.currentPhoto else { return }
        currentImage = image
    }

    // MARK: - Keyboard

    private func handleEvent(_ event: NSEvent) -> Bool {
        // Коды клавиш не зависят от раскладки (работает и на русской)
        let command = event.modifierFlags.contains(.command)
        if !command && event.keyCode == 2 { // D — рисование
            withAnimation(.easeOut(duration: 0.2)) { session.toggleDrawing() }
            return true
        }
        if session.isDrawing && !command {
            let tools: [UInt16: DrawTool] = [35: .pen, 46: .marker, 0: .arrow, 15: .rectangle, 31: .ellipse, 14: .eraser]
            if let tool = tools[event.keyCode] {
                session.drawTool = tool
                return true
            }
            if event.keyCode == 53 { // Esc — выйти из рисования
                withAnimation(.easeOut(duration: 0.2)) { session.isDrawing = false }
                return true
            }
        }

        switch event.keyCode {
        case 6: // Z (и ⌘Z)
            session.undo()
            return true
        case 24, 69: // = / + и numpad +
            stepZoom(by: 1.25)
            return true
        case 27, 78: // − и numpad −
            stepZoom(by: 0.8)
            return true
        case 29, 82: // 0 и numpad 0
            resetZoom()
            return true
        default:
            break
        }

        if event.modifierFlags.contains(.command) {
            return false
        }

        switch event.keyCode {
        case 3: // F — к сетке
            session.toggleViewMode()
            return true
        case 34: // I — сведения
            withAnimation(.easeOut(duration: 0.2)) { session.showInfo.toggle() }
            return true
        case 123: // left
            session.goPrevious()
            return true
        case 124, 49: // right, space
            session.goNext()
            return true
        case 51, 117: // delete, forward delete
            commit(flyTo: CGSize(width: -900, height: 0)) { session.trashCurrent() }
            return true
        case 53: // escape
            if isScaled {
                resetZoom()
            } else {
                session.viewMode = .grid
            }
            return true
        default:
            guard let first = event.charactersIgnoringModifiers?.first, first.isWholeNumber else {
                return false
            }
            commit(flyTo: CGSize(width: 900, height: 0)) {
                session.handleShortcut(String(first))
            }
            return true
        }
    }

    // MARK: - Small views

    private func hint(_ keys: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.caption.bold().monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.12), in: Capsule())
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.title.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color, lineWidth: 4)
            )
            .foregroundStyle(color)
            .rotationEffect(.degrees(-12))
    }

    private func flashBadge(_ text: String) -> some View {
        Text(text)
            .font(.title2.bold())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .transition(.opacity)
    }
}

private struct FlyAway: View {
    let image: NSImage
    let start: CGSize
    let target: CGSize
    let padding: CGFloat

    @State private var launched = false

    var body: some View {
        let current = launched ? target : start
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .padding(padding)
            .offset(current)
            .rotationEffect(.degrees(Double(current.width / 40)))
            .opacity(launched ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: 0.28)) { launched = true }
            }
    }
}

/// Распознаёт горизонтальный свайп двумя пальцами: одно листание на жест, инерция игнорируется
private final class TrackpadSwipe {
    enum Direction { case next, previous }

    private var accumX: CGFloat = 0
    private var accumY: CGFloat = 0
    private var fired = false
    private let threshold: CGFloat = 50

    func feed(_ scroll: ScrollInfo) -> Direction? {
        // Инерция после отпускания пальцев — не листаем
        if !scroll.momentumPhase.isEmpty { return nil }
        if scroll.phase.contains(.began) || scroll.phase.contains(.mayBegin) {
            reset()
        }
        if scroll.phase.contains(.ended) || scroll.phase.contains(.cancelled) {
            reset()
            return nil
        }
        guard !fired else { return nil }

        // Приводим к направлению движения пальцев независимо от настройки прокрутки
        let fingerX = scroll.isNatural ? scroll.dx : -scroll.dx
        accumX += fingerX
        accumY += abs(scroll.dy)

        guard abs(accumX) > threshold, abs(accumX) > accumY * 1.5 else { return nil }
        fired = true
        // Пальцы влево — следующее фото, вправо — предыдущее (как листать страницы)
        return accumX < 0 ? .next : .previous
    }

    private func reset() {
        accumX = 0
        accumY = 0
        fired = false
    }
}
