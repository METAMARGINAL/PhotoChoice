import AppKit
import SwiftUI

struct ViewerView: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Feature.stars.key) private var starsOn = false
    @AppStorage(Feature.colors.key) private var colorsOn = false
    @AppStorage(Feature.flags.key) private var flagsOn = false
    @AppStorage(Feature.transfer.key) private var transferOn = true
    @AppStorage(Feature.compare.key) private var compareOn = true
    @AppStorage(Feature.drawing.key) private var drawingOn = true
    @AppStorage(Feature.adjust.key) private var adjustOn = true
    @AppStorage(Feature.info.key) private var infoOn = true
    /// Панели гаснут через 2 с покоя (настройка, по умолчанию выкл.)
    @AppStorage(Pref.autoHideHUD) private var autoHideHUD = false
    @AppStorage(Pref.surroundTone) private var surroundTone = 2
    /// Подсветка пересветов и провалов — треугольники на гистограмме в сведениях
    @AppStorage("clipHighlights") private var clipHighlights = false
    @AppStorage("clipShadows") private var clipShadows = false

    @State private var currentImage: NSImage?
    /// Тот же кадр в полном разрешении — подгружается, когда при зуме пикселей превью уже не хватает
    @State private var fullImage: NSImage?
    /// Кадр с коррекцией: сначала по превью, через 0,3 с покоя — в полном разрешении, если оно загружено
    @State private var adjustedImage: NSImage?
    @State private var loadingFullFor: URL?
    @State private var fullLoadTask: Task<Void, Never>?
    /// Кадр из «Брака», который уже открыли сразу на проблемном месте (второй раз не прыгаем)
    @State private var autoZoomedFor: URL?

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

    // Интерфейс поверх фото: H прячет вручную, с автоскрытием — ещё и 2 с покоя
    @State private var hudVisible = true
    @State private var hideTask: Task<Void, Never>?

    private let maxZoom: CGFloat = 10
    private let minZoom: CGFloat = 0.1
    /// Увеличено больше «вписанного» — перетаскивание двигает фото, а не свайпает
    private var isZoomed: Bool { zoom > 1.01 }
    /// Масштаб отличается от «вписанного» в любую сторону
    private var isScaled: Bool { abs(zoom - 1) > 0.01 }

    private var marksOn: Bool { starsOn || colorsOn || flagsOn }

    /// Поля вокруг фото по теме; у «Нейтрали» панели плотные — фото между ними
    private var insets: EdgeInsets {
        let s = theme.stageInsets
        if theme.isNeutral {
            return EdgeInsets(top: theme.topbarHeight + s.v, leading: s.h, bottom: theme.hintbarHeight + s.v, trailing: s.h)
        }
        return EdgeInsets(top: s.v, leading: s.h, bottom: s.v, trailing: s.h)
    }

    /// Ширина, которую забирает панель сведений справа; фото сдвигается, а не лежит под ней
    private var panelReserve: CGFloat {
        (infoOn && session.showInfo || session.isAdjusting) && !session.photos.isEmpty ? theme.panelReserve : 0
    }

    private var adjustment: Adjustment {
        session.currentPhoto.map { session.adjustment(for: $0) } ?? .identity
    }

    /// Что показывать: с коррекцией, пока она не готова или «до» — исходный кадр
    private var shownImage: NSImage? {
        guard let base = fullImage ?? currentImage else { return nil }
        if adjustment.isIdentity || session.showsOriginal { return base }
        return adjustedImage ?? base
    }

    private struct RenderKey: Hashable {
        let url: URL?
        let adjustment: Adjustment
        let hasPreview: Bool
        let hasFull: Bool
    }

    /// Поле под фото: у «Нейтрали» его выбирают в сведениях
    private var stageColor: Color {
        theme.isNeutral ? SurroundTone.color(surroundTone) : theme.c.canvas
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
            stageColor.ignoresSafeArea()

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

                if session.isAdjusting, let url = session.currentPhoto {
                    AdjustPanel(session: session, url: url)
                        .padding(theme.isGlass ? 12 : 0)
                        .transition(.move(edge: .trailing))
                } else if infoOn, session.showInfo, let url = session.currentPhoto {
                    InfoPanel(url: url, companions: session.companions(of: url), showsSurround: true, revision: session.editRevision)
                        .padding(theme.isGlass ? 12 : 0)
                        .transition(.move(edge: .trailing))
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
            fullLoadTask?.cancel()
            fullLoadTask = nil
            loadingFullFor = nil
            resetTransform()
            adjustedImage = nil
            fullImage = url.flatMap { ImageLoader.cachedFullImage(at: $0) }
            if let url, let cached = ImageLoader.cachedImage(at: url) {
                currentImage = cached
                applyAutoZoom()
            }
        }
        .onChange(of: zoom) { _, _ in
            upgradeResolutionIfNeeded()
        }
        .onChange(of: session.isDrawing) { _, _ in pokeHUD() }
        .onChange(of: autoHideHUD) { _, on in
            hideTask?.cancel()
            if on { pokeHUD() } else { hudVisible = true }
        }
        .task(id: RenderKey(url: session.currentPhoto, adjustment: adjustment,
                            hasPreview: currentImage != nil, hasFull: fullImage != nil)) {
            await renderAdjusted()
        }
        .onDisappear {
            fullLoadTask?.cancel()
            fullLoadTask = nil
            loadingFullFor = nil
            session.isDrawing = false
            session.isAdjusting = false
            hideTask?.cancel()
        }
        .task(id: "\(session.currentPhoto?.path ?? "")#\(session.editRevision)") {
            await loadCurrentImage()
        }
    }

    private var showsHUD: Bool {
        hudVisible || session.isDrawing
    }

    /// С автоскрытием: возвращает интерфейс (за 120 мс) и заново заводит таймер (2 с покоя, гаснет за 200 мс)
    private func pokeHUD() {
        guard autoHideHUD else { return }
        if !hudVisible {
            withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.12)) { hudVisible = true }
        }
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !session.isDrawing else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.2)) { hudVisible = false }
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
                    Image(nsImage: shownImage ?? currentImage)
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            if clipHighlights || clipShadows, let url = session.currentPhoto {
                                ClippingLayer(url: url, image: shownImage ?? currentImage,
                                              highlights: clipHighlights, shadows: clipShadows)
                            }
                        }
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
            .contextMenu {
                if !session.isDrawing, let url = session.currentPhoto {
                    FileActionsMenu(session: session, photos: [url])
                    Divider()
                    Button("Показать в Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url] + session.companions(of: url))
                    }
                }
            }
            .onAppear {
                containerSize = geo.size
                applyAutoZoom()
            }
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
            if session.section == .defects, let url = session.currentPhoto {
                let defects = AnalysisStore.shared.defects(for: url)
                if !defects.isEmpty {
                    defectLine(defects)
                        .padding(.top, 10)
                }
            }
            Spacer(minLength: 0)
            if session.isDrawing {
                DrawToolbar(session: session)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HintBar(groups: hintGroups)
            }
        }
    }

    private var hintGroups: [HintGroup] {
        if session.isAdjusting {
            return [HintGroup(title: "Коррекция", hints: [
                Hint("←", "→", label: "листать"),
                Hint("\\", label: "до / после"),
                Hint("Z", label: "отменить"),
                Hint("⌘S", label: "сохранить копию"),
                Hint("E", label: "готово")
            ])]
        }
        var view = [Hint("←", "→", label: "листать"), Hint("F", label: "сетка")]
        if infoOn { view.append(Hint("I", label: "сведения")) }
        if drawingOn { view.append(Hint("D", label: "рисовать")) }
        if adjustOn { view.append(Hint("E", label: "коррекция")) }
        if compareOn { view.append(Hint("C", label: "сравнить")) }
        view.append(Hint("Z", label: "отменить"))
        var groups = [HintGroup.targets(session), HintGroup(title: "Вид", hints: view)]
        if let marks = MarkHints.group {
            groups.append(marks)
        }
        return groups
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
                .buttonStyle(PCButtonStyle(kind: theme.isGlass ? .ghost : .secondary))
                .help("К сетке (F или Esc)")
            }

            capsuleGroup(text: true) {
                HStack(spacing: 12) {
                    Text(session.currentPhoto?.lastPathComponent ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    counter
                    if let url = session.currentPhoto, !session.companions(of: url).isEmpty {
                        Text("+ " + session.companions(of: url).map { $0.pathExtension.uppercased() }.joined(separator: " + "))
                            .font(theme.numFont)
                            .foregroundStyle(c.text3)
                    }
                    if marksOn, let url = session.currentPhoto {
                        MarkEditor(
                            mark: MarkStore.shared.mark(url),
                            size: 12,
                            onRating: { session.applyMark(.rating($0)) },
                            onColor: { session.applyMark(.color($0)) },
                            onFlag: { session.applyMark(.flag($0)) }
                        )
                    }
                }
            }

            Spacer(minLength: 12)

            if isScaled {
                zoomBadge
            }

            if compareOn || drawingOn || adjustOn || infoOn {
                capsuleGroup {
                    HStack(spacing: 4) {
                        if compareOn {
                            Button {
                                session.startCompare()
                            } label: {
                                Image(systemName: "arrow.left.arrow.right")
                            }
                            .buttonStyle(PCIconButtonStyle())
                            .help("Сравнить с соседним кадром (C)")
                        }

                        if drawingOn {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { session.toggleDrawing() }
                            } label: {
                                Image(systemName: "pencil.tip.crop.circle")
                            }
                            .buttonStyle(PCIconButtonStyle(isOn: session.isDrawing))
                            .help("Рисовать (D)")
                        }

                        if adjustOn {
                            Button {
                                withAnimation(.easeOut(duration: 0.22)) { session.toggleAdjusting() }
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                            }
                            .buttonStyle(PCIconButtonStyle(isOn: session.isAdjusting || adjustment != .identity))
                            .help("Коррекция: экспозиция, тени, цвет (E)")
                        }

                        if infoOn {
                            Button {
                                withAnimation(.easeOut(duration: 0.22)) { session.showInfo.toggle() }
                            } label: {
                                Image(systemName: "sidebar.right")
                            }
                            .buttonStyle(PCIconButtonStyle(isOn: session.showInfo))
                            .help("Сведения о снимке (I)")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, theme.isGlass ? 14 : (theme.isNeutral ? 14 : 20))
        .padding(.top, theme.isGlass ? 14 : 0)
        .frame(height: theme.topbarHeight + (theme.isGlass ? 14 : 0))
        .background(theme.isNeutral ? Color(hex: 0x222222) : Color.clear)
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

    /// Причина брака под верхней панелью: «Размыто — Мало мелких деталей…»
    private func defectLine(_ defects: [Defect]) -> some View {
        let c = theme.c
        let text = defects.prefix(2).map { defect in
            defect.detail.isEmpty ? defect.reason.title : "\(defect.reason.title) — \(defect.detail)"
        }.joined(separator: "  ·  ")
        let line = HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(c.warning)
            Text(text)
                .foregroundStyle(c.text1)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(height: 28)
        return Group {
            if theme.isGlass {
                line.pcGlass(in: .capsule)
            } else {
                line
                    .background(c.overlay, in: Capsule())
                    .overlay(Capsule().stroke(c.line, lineWidth: 1))
            }
        }
        .help("Двойной клик — вписать кадр в экран")
    }

    /// «12 / 480»; у «Плёнки» — янтарными цифрами, как на краю плёнки
    private var counter: some View {
        let c = theme.c
        let total = session.photos.count
        let current = total == 0 ? 0 : session.index + 1
        return HStack(spacing: 0) {
            if session.section != .all {
                Text("\(session.section.title) · ")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.text2)
            }
            Text("\(current)")
                .fontWeight(.semibold)
                .foregroundStyle(theme.isFilm ? c.edge : c.text1)
            Text(" / \(total)")
                .foregroundStyle(theme.isFilm ? c.text3 : c.text2)
        }
        .font(theme.numFont)
        .tracking(theme.isFilm ? 0.9 : 0)
    }

    /// Процент масштаба
    private var zoomBadge: some View {
        let c = theme.c
        return Text("\(Int((zoom * 100).rounded())) %")
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(c.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }

    /// У «Стекла» группы — стеклянные капсулы; у остальных — просто содержимое
    @ViewBuilder
    private func capsuleGroup<Content: View>(text: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        if theme.isGlass {
            content()
                .padding(.horizontal, text ? 16 : 6)
                .frame(height: 40)
                .pcGlass(in: .capsule)
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

                if width > 140, transferOn {
                    commit(flyTo: CGSize(width: 900, height: height)) { session.moveCurrentToPrimary() }
                } else if width < -140 {
                    commit(flyTo: CGSize(width: -900, height: height)) { session.trashCurrent() }
                } else if height < -160, transferOn, session.destinations.count > 1 {
                    commit(flyTo: CGSize(width: 0, height: -800)) {
                        session.moveCurrent(to: session.destinations[1])
                    }
                } else {
                    // Не дотянули — карточка возвращается с лёгким пружинением
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) { dragOffset = .zero }
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
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) { dragOffset = .zero }
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
        let availH = max(containerSize.height - insets.top - insets.bottom, 1)
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

    // MARK: - Коррекция

    private func renderAdjusted() async {
        let adjustment = self.adjustment
        guard let url = session.currentPhoto, !adjustment.isIdentity, let preview = currentImage else {
            adjustedImage = nil
            return
        }
        if let image = await AdjustRenderer.render(preview, adjustment), !Task.isCancelled, url == session.currentPhoto {
            adjustedImage = image
        }
        guard let full = fullImage else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        if let image = await AdjustRenderer.render(full, adjustment), !Task.isCancelled, url == session.currentPhoto {
            adjustedImage = image
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
            applyAutoZoom()
            return
        }
        currentImage = nil
        let image = await ImageLoader.imageAsync(at: url)
        guard !Task.isCancelled, url == session.currentPhoto else { return }
        currentImage = image
        applyAutoZoom()
    }

    // MARK: - Полное разрешение и проблемное место

    /// Размер фото на экране при «вписать», в точках
    private var fittedSize: CGSize? {
        guard let image = currentImage, image.size.width > 0, image.size.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return nil }
        let availW = max(containerSize.width - insets.leading * 2, 1)
        let availH = max(containerSize.height - insets.top - insets.bottom, 1)
        let fit = min(availW / image.size.width, availH / image.size.height)
        return CGSize(width: image.size.width * fit, height: image.size.height * fit)
    }

    private var backingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    /// При крупном зуме превью (2400 px) уже мыльное — подгружаем кадр в полном разрешении.
    /// Подмена незаметна: размер на экране тот же, становится только чётче
    private func upgradeResolutionIfNeeded() {
        guard fullImage == nil, let url = session.currentPhoto, loadingFullFor != url,
              let preview = currentImage, let fitted = fittedSize,
              fitted.width * zoom * backingScale > preview.size.width * 1.1 else { return }
        loadingFullFor = url
        fullLoadTask = Task {
            let image = await ImageLoader.fullImageAsync(at: url)
            guard !Task.isCancelled else { return }
            if loadingFullFor == url { loadingFullFor = nil }
            guard url == session.currentPhoto, let image, image.size.width > preview.size.width else { return }
            fullImage = image
        }
    }

    /// Открывать кадр из «Брака» сразу на проблемном месте (настройка, по умолчанию выкл.)
    private var autoZoomEnabled: Bool {
        UserDefaults.standard.bool(forKey: "defectAutoZoom")
    }

    /// Кадр из «Брака» с размытием или глазами: сразу 100 % (пиксель снимка = пиксель экрана)
    /// с центром на глазах крупного лица или на объекте — так фотограф и проверяет фокус. Двойной клик — «вписать»
    private func applyAutoZoom() {
        guard session.section == .defects, autoZoomEnabled, !session.isDrawing,
              let url = session.currentPhoto, autoZoomedFor != url,
              currentImage != nil, let fitted = fittedSize else { return }
        let focusReasons: Set<DefectReason> = [.blur, .softer, .eyesClosed, .learned]
        guard AnalysisStore.shared.defects(for: url).contains(where: { focusReasons.contains($0.reason) }),
              let point = AnalysisStore.shared.focusPoint(for: url),
              let pixels = ImageLoader.pixelSize(url) else { return }
        autoZoomedFor = url
        let target = min(maxZoom, max(1.5, pixels.width / (fitted.width * backingScale)))
        let offset = CGSize(
            width: -(point.x - 0.5) * fitted.width * target,
            height: -(point.y - 0.5) * fitted.height * target
        )
        zoom = target
        pan = clampedPan(offset)
    }

    // MARK: - Клавиатура

    private func handleEvent(_ event: NSEvent) -> Bool {
        if let mark = MarkCommand(event) {
            session.applyMark(mark)
            return true
        }
        // Коды клавиш не зависят от раскладки (работает и на русской)
        let command = event.modifierFlags.contains(.command)

        // Действия отбора и листание не будят интерфейс — он не мешает смотреть на кадр
        let silentKeys: Set<UInt16> = [51, 117, 123, 124, 49]
        let isDigit = event.charactersIgnoringModifiers?.first?.isWholeNumber ?? false
        if !silentKeys.contains(event.keyCode) && !(isDigit && !command) {
            pokeHUD()
        }

        if !command && event.keyCode == 2 && drawingOn { // D — рисование
            withAnimation(.easeOut(duration: 0.2)) { session.toggleDrawing() }
            return true
        }
        if !command && event.keyCode == 14 && adjustOn && !session.isDrawing { // E — коррекция
            withAnimation(.easeOut(duration: 0.22)) { session.toggleAdjusting() }
            return true
        }
        if session.isAdjusting && !command {
            if event.keyCode == 42 { // \ — до / после
                if !adjustment.isIdentity { session.showsOriginal.toggle() }
                return true
            }
            if event.keyCode == 53 { // Esc — закрыть коррекцию
                withAnimation(.easeOut(duration: 0.22)) { session.isAdjusting = false }
                return true
            }
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
            guard compareOn else { return false }
            session.startCompare()
            return true
        case 34: // I — сведения
            guard infoOn else { return false }
            withAnimation(.easeOut(duration: 0.22)) { session.showInfo.toggle() }
            return true
        case 4: // H — спрятать/показать интерфейс (в любой теме)
            hideTask?.cancel()
            withAnimation(.easeOut(duration: hudVisible ? 0.2 : 0.12)) { hudVisible.toggle() }
            return true
        case 123: // left
            session.goPrevious()
            return true
        case 124, 49: // right, space
            session.goNext()
            return true
        case 51, 117: // delete, forward delete — мгновенно: перенос идёт сотни раз за сеанс
            session.trashCurrent()
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
            session.handleShortcut(String(first))
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
