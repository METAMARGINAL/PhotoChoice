import AppKit
import SwiftUI

struct ViewerView: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme

    @State private var currentImage: NSImage?

    @State private var dragOffset: CGSize = .zero

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panAtDragStart: CGSize?
    /// Размер области под фото (без панели сведений)
    @State private var containerSize: CGSize = .zero

    // Двухпальцевый свайп по трекпаду. Класс, чтобы накопление не перерисовывало вид
    @State private var trackpadSwipe = TrackpadSwipe()

    // «Улетающее» фото после решения
    @State private var ghost: Ghost?

    // Автоскрытие интерфейса поверх фото («Стекло», «Тишина»)
    @State private var hudVisible = true
    @State private var hideTask: Task<Void, Never>?

    private let maxZoom: CGFloat = 10
    private let minZoom: CGFloat = 0.1
    /// Увеличено больше «вписанного» — перетаскивание двигает фото, а не свайпает
    private var isZoomed: Bool { zoom > 1.01 }
    /// Масштаб отличается от «вписанного» в любую сторону
    private var isScaled: Bool { abs(zoom - 1) > 0.01 }

    /// Поля вокруг фото по теме
    private var insets: EdgeInsets {
        let s = theme.stageInsets
        return EdgeInsets(top: s.v, leading: s.h, bottom: s.v, trailing: s.h)
    }

    /// Ширина, которую забирает панель сведений справа; фото сдвигается, а не лежит под ней
    private var panelReserve: CGFloat {
        session.showInfo && !session.photos.isEmpty ? theme.panelReserve : 0
    }

    private struct Ghost: Identifiable {
        let id = UUID()
        let image: NSImage
        let start: CGSize
        let target: CGSize
    }

    var body: some View {
        let c = theme.c
        ZStack(alignment: .trailing) {
            c.canvas.ignoresSafeArea()

            if session.photos.isEmpty {
                finishedState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    photoLayer
                    hud
                        .opacity(showsHUD ? 1 : 0)
                        .allowsHitTesting(showsHUD)
                    ToastOverlay(toast: session.toast)
                }
                .padding(.trailing, panelReserve)

                if session.showInfo, let url = session.currentPhoto {
                    InfoPanel(url: url, companions: session.companions(of: url))
                        .padding(theme.isGlass ? 12 : 0)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(
            KeyCatcher(
                onKeyDown: { handleEvent($0) },
                onMagnify: { delta, phase, anchor in handleMagnify(delta, phase, photoAnchor(anchor)) },
                onSmartMagnify: { anchor in toggleZoom(at: photoAnchor(anchor)) },
                onScroll: { handleScroll($0) },
                onCopy: { session.copyAnnotated() }
            )
        )
        .onContinuousHover { phase in
            if case .active = phase { pokeHUD() }
        }
        .onAppear { pokeHUD() }
        .onChange(of: session.currentPhoto, initial: true) { _, url in
            resetTransform()
            if let url, let cached = ImageLoader.cachedImage(at: url) {
                currentImage = cached
            }
        }
        .onChange(of: session.isDrawing) { _, _ in pokeHUD() }
        .onDisappear {
            session.isDrawing = false
            hideTask?.cancel()
        }
        .task(id: session.currentPhoto) {
            await loadCurrentImage()
        }
    }

    private var showsHUD: Bool {
        hudVisible || !theme.autoHidesHUD || session.isDrawing
    }

    /// Возвращает интерфейс и заново заводит таймер скрытия (2 с простоя)
    private func pokeHUD() {
        if !hudVisible {
            withAnimation(.easeOut(duration: 0.15)) { hudVisible = true }
        }
        hideTask?.cancel()
        guard theme.autoHidesHUD else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !session.isDrawing else { return }
            withAnimation(.easeOut(duration: 0.3)) { hudVisible = false }
        }
    }

    /// Точка от KeyCatcher (смещение от центра всего экрана) → смещение от центра области фото
    private func photoAnchor(_ anchor: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x + panelReserve / 2, y: anchor.y)
    }

    // MARK: - Фото

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
                        .padding(insets)
                        .scaleEffect(zoom)
                        .offset(
                            x: pan.width + dragOffset.width,
                            y: pan.height + dragOffset.height
                        )
                        .rotationEffect(.degrees(Double(dragOffset.width / 40)))
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(theme.c.text1)
                }

                if let ghost {
                    FlyAway(image: ghost.image, start: ghost.start, target: ghost.target, insets: insets)
                        .id(ghost.id)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(alignment: .topLeading) {
                if dragOffset.width < -80 {
                    swipeLabel("Корзина", color: theme.c.danger)
                        .padding(.top, insets.top)
                        .padding(.leading, 40)
                }
            }
            .overlay(alignment: .topTrailing) {
                if dragOffset.width > 80 {
                    swipeLabel(session.primaryDestination?.name ?? "Папка", color: theme.c.success)
                        .padding(.top, insets.top)
                        .padding(.trailing, 40)
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

    // MARK: - Интерфейс поверх фото

    private var hud: some View {
        VStack(spacing: 0) {
            topbar
            Spacer(minLength: 0)
            if session.isDrawing {
                DrawToolbar(session: session)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HintBar(groups: [
                    HintGroup(title: "Листать", hints: [
                        Hint("←", "→", label: "кадр")
                    ]),
                    HintGroup(title: "Отбор", hints: [
                        Hint("1–9", label: "в папку"),
                        Hint("⌫", label: "корзина"),
                        Hint("Z", label: "отмена")
                    ]),
                    HintGroup(title: "Вид", hints: [
                        Hint("I", label: "инфо"),
                        Hint("D", label: "рисовать"),
                        Hint("C", label: "сравнить"),
                        Hint("F", label: "сетка")
                    ])
                ])
            }
        }
    }

    private var topbar: some View {
        let c = theme.c
        return HStack(spacing: 12) {
            capsuleGroup {
                Button {
                    session.viewMode = .grid
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Сетка")
                    }
                }
                .buttonStyle(PCButtonStyle(kind: .ghost))
                .help("К сетке (F или Esc)")
            }

            capsuleGroup(text: true) {
                HStack(spacing: 12) {
                    counter
                    Text(session.currentPhoto?.lastPathComponent ?? "")
                        .font(.system(size: theme.isQuiet ? 12 : 13, weight: theme.isQuiet ? .regular : .medium))
                        .foregroundStyle(theme.isQuiet ? c.text2 : c.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let url = session.currentPhoto, !session.companions(of: url).isEmpty {
                        Text("+ " + session.companions(of: url).map { $0.pathExtension.uppercased() }.joined(separator: " + "))
                            .font(theme.numFont)
                            .foregroundStyle(c.text3)
                    }
                }
            }

            Spacer(minLength: 12)

            if isScaled {
                zoomBadge
            }

            capsuleGroup {
                HStack(spacing: 4) {
                    Button {
                        session.startCompare()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .buttonStyle(PCIconButtonStyle())
                    .help("Сравнить с соседним кадром (C)")

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { session.toggleDrawing() }
                    } label: {
                        Image(systemName: "pencil.tip.crop.circle")
                    }
                    .buttonStyle(PCIconButtonStyle(isOn: session.isDrawing))
                    .help("Рисовать (D)")

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { session.showInfo.toggle() }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(PCIconButtonStyle(isOn: session.showInfo))
                    .help("Сведения о снимке (I)")
                }
            }
        }
        .padding(.horizontal, theme.isGlass ? 16 : 12)
        .padding(.top, theme.isGlass ? 12 : 0)
        .frame(height: theme.topbarHeight + (theme.isGlass ? 8 : 0))
        .background {
            if theme.isStudio || theme.isContact {
                c.overlay
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(c.line).frame(height: 1)
                    }
            }
        }
        .overlay {
            if session.isDrawing {
                // Ярлык режима по центру панели
                HStack(spacing: 5) {
                    Image(systemName: "pencil.tip")
                    Text("Режим рисования")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(c.accent)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .overlay(RoundedRectangle(cornerRadius: theme.isGlass ? 12 : theme.rMd).stroke(c.accent, lineWidth: 1))
                .padding(.top, theme.isGlass ? 12 : 0)
            }
        }
    }

    /// «12 / 480»
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

    /// Процент масштаба
    private var zoomBadge: some View {
        let c = theme.c
        return Text("\(Int((zoom * 100).rounded()))%")
            .font(theme.numFont)
            .foregroundStyle(theme.isContact ? c.edge : (theme.isQuiet ? c.text2 : c.text1))
            .padding(.horizontal, theme.isQuiet ? 0 : 8)
            .padding(.vertical, 2)
            .background {
                if theme.isStudio {
                    RoundedRectangle(cornerRadius: theme.rSm).fill(c.surface2)
                } else if theme.isContact {
                    RoundedRectangle(cornerRadius: theme.rSm).stroke(c.lineStrong, lineWidth: 1)
                }
            }
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

    private var finishedState: some View {
        let c = theme.c
        return VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(c.success)
            Text("Готово")
                .font(theme.titleFont)
                .foregroundStyle(c.text1)
            Text("Отобрано: \(session.movedCount)   В корзине: \(session.trashedCount)")
                .font(theme.bodyFont)
                .foregroundStyle(c.text2)
            Button("К выбору папки") {
                session.stopReview()
            }
            .buttonStyle(PCButtonStyle(kind: .primary, big: true))
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

    /// Меняет масштаб, удерживая на месте точку `anchor` (смещение от центра области фото)
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
        guard panelReserve > 0, containerSize.width > 0 else { return false }
        let fullWidth = containerSize.width + panelReserve
        let x = anchor.x + fullWidth / 2
        return x >= containerSize.width
    }

    private func handleScroll(_ scroll: ScrollInfo) -> Bool {
        if isOverInfoPanel(scroll.anchor) { return false }
        pokeHUD()
        // ⌘ или ⌥ + колесо/скролл — зум к курсору (удобно с мышью)
        if scroll.modifiers.contains(.command) || scroll.modifiers.contains(.option) {
            guard currentImage != nil else { return true }
            setZoom(zoom * pow(1.01, scroll.dy), anchor: photoAnchor(scroll.anchor))
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

        let h = insets.leading
        let v = insets.top
        let availW = max(containerSize.width - h * 2, 1)
        let availH = max(containerSize.height - v * 2, 1)
        let fit = min(availW / image.size.width, availH / image.size.height)
        let shownW = image.size.width * fit * zoom
        let shownH = image.size.height * fit * zoom

        // Увеличенное фото можно довести до края экрана, но не дальше
        let maxX = max(0, (shownW - containerSize.width) / 2 + min(h, 20))
        let maxY = max(0, (shownH - containerSize.height) / 2 + min(v, 20))
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

    // MARK: - Загрузка

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

    // MARK: - Клавиатура

    private func handleEvent(_ event: NSEvent) -> Bool {
        // Коды клавиш не зависят от раскладки (работает и на русской)
        let command = event.modifierFlags.contains(.command)

        // Действия отбора и листание не будят интерфейс — он не мешает смотреть на кадр
        let silentKeys: Set<UInt16> = [51, 117, 123, 124, 49]
        let isDigit = event.charactersIgnoringModifiers?.first?.isWholeNumber ?? false
        if !silentKeys.contains(event.keyCode) && !(isDigit && !command) {
            pokeHUD()
        }

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

        if command {
            return false
        }

        switch event.keyCode {
        case 3: // F — к сетке
            session.toggleViewMode()
            return true
        case 8: // C — сравнение
            session.startCompare()
            return true
        case 34: // I — сведения
            withAnimation(.easeOut(duration: 0.2)) { session.showInfo.toggle() }
            return true
        case 4: // H — спрятать/показать интерфейс
            if theme.autoHidesHUD {
                hideTask?.cancel()
                withAnimation(.easeOut(duration: 0.2)) { hudVisible.toggle() }
            }
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

    // MARK: - Мелочи

    /// Штамп при свайпе мышью: «Корзина» или имя папки
    private func swipeLabel(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 26, weight: .bold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: theme.rLg)
                    .stroke(color, lineWidth: 4)
            )
            .foregroundStyle(color)
            .rotationEffect(.degrees(-12))
    }
}

private struct FlyAway: View {
    let image: NSImage
    let start: CGSize
    let target: CGSize
    let insets: EdgeInsets

    @State private var launched = false

    var body: some View {
        let current = launched ? target : start
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .padding(insets)
            .offset(current)
            .rotationEffect(.degrees(Double(current.width / 40)))
            .opacity(launched ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: 0.28)) { launched = true }
            }
    }
}

/// Распознаёт горизонтальный свайп двумя пальцами: одно листание на жест, инерция игнорируется
final class TrackpadSwipe {
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
