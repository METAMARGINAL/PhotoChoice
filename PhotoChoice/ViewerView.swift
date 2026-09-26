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

    // «Улетающее» фото после решения
    @State private var ghost: Ghost?

    private let imagePadding: CGFloat = 20
    private let maxZoom: CGFloat = 10
    private let minGestureZoom: CGFloat = 0.5
    private var isZoomed: Bool { zoom > 1.01 }

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
            }

            if let flash = session.flashMessage {
                flashBadge(flash)
            }
        }
        .background(
            KeyCatcher(
                onKeyDown: { handleEvent($0) },
                onMagnify: { delta, phase in handleMagnify(delta, phase) },
                onSmartMagnify: { toggleZoom() },
                onScroll: { dx, dy in handleScroll(dx, dy) }
            )
        )
        .onChange(of: session.currentPhoto, initial: true) { _, url in
            resetTransform()
            if let url, let cached = ImageLoader.cachedImage(at: url) {
                currentImage = cached
            }
        }
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
        .gesture(dragGesture)
        .onTapGesture(count: 2) { toggleZoom() }
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
                if isZoomed {
                    Text("\(Int((zoom * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.trailing, 8)
                }
                Text(session.progressText)
                    .foregroundStyle(.white)
                    .font(.headline.monospacedDigit())
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            HStack(spacing: 16) {
                hint("← →", "листать")
                hint("1–\(min(max(session.destinations.count, 1), 9))", "в папку")
                hint("⌫", "корзина")
                hint("Z", "отмена")
                hint("+ −", "зум")
                hint("0", "сброс зума")
                hint("F", "сетка")
                hint("Esc", "сетка")
            }
            .padding(.bottom, 18)
        }
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

    // MARK: - Zoom

    private func handleMagnify(_ delta: CGFloat, _ phase: NSEvent.Phase) {
        guard currentImage != nil else { return }
        zoom = min(max(zoom * (1 + delta), minGestureZoom), maxZoom)
        pan = clampedPan(pan)
        if phase == .ended || phase == .cancelled {
            settleZoom()
        }
    }

    /// Если отдалили меньше, чем «вписано», плавно возвращаем к 100% вписанного размера
    private func settleZoom() {
        if zoom < 1.05 {
            withAnimation(.spring(duration: 0.25)) {
                zoom = 1
                pan = .zero
            }
        }
    }

    private func handleScroll(_ dx: CGFloat, _ dy: CGFloat) {
        guard isZoomed else { return }
        pan = clampedPan(CGSize(width: pan.width + dx, height: pan.height + dy))
    }

    private func toggleZoom() {
        guard currentImage != nil else { return }
        withAnimation(.spring(duration: 0.3)) {
            if zoom > 1.05 {
                zoom = 1
                pan = .zero
            } else {
                zoom = 2.5
            }
        }
    }

    private func stepZoom(by factor: CGFloat) {
        guard currentImage != nil else { return }
        withAnimation(.spring(duration: 0.2)) {
            zoom = min(max(zoom * factor, 1), maxZoom)
            if zoom <= 1.05 {
                zoom = 1
                pan = .zero
            } else {
                pan = clampedPan(pan)
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
            if isZoomed {
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
