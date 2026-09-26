import AppKit
import SwiftUI

/// Сетка всех фото. Вход/выход в полноэкранный просмотр — F, двойной клик или Return
struct GridView: View {
    @Bindable var session: PhotoSession

    @State private var gridWidth: CGFloat = 0

    private let spacing: CGFloat = 10
    private let padding: CGFloat = 16
    private let defaultSize: CGFloat = 230

    /// Число колонок считаем сами, чтобы стрелки ↑↓ прыгали ровно на строку
    private var columnCount: Int {
        let usable = gridWidth - padding * 2
        guard usable > 0 else { return 1 }
        return max(1, Int((usable + spacing) / (session.gridThumbSize + spacing)))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(height: 1)
            grid
        }
        .background(Color(white: 0.16))
        .overlay {
            if let flash = session.flashMessage {
                Text(flash)
                    .font(.title2.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
        }
        .background(
            KeyCatcher(
                onKeyDown: { handleEvent($0) },
                onMagnify: { delta, _ in
                    session.setGridSize(session.gridThumbSize * (1 + delta))
                }
            )
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button("Выйти") { session.stopReview() }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))

            Text(session.sourceURL?.lastPathComponent ?? "")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(session.progressText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))

            Spacer(minLength: 20)

            Text("F / ↩ — открыть · 1–9 в папку · ⌫ корзина · Z отмена")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

            HStack(spacing: 8) {
                Button {
                    session.setGridSize(session.gridThumbSize / 1.2)
                } label: {
                    Image(systemName: "square.grid.3x3")
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
                .frame(width: 160)
                .help("Размер миниатюр")

                Button {
                    session.setGridSize(session.gridThumbSize * 1.2)
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .buttonStyle(.plain)
                .help("Крупнее (+)")
            }
            .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(white: 0.22))
    }

    // MARK: - Grid

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
                                isSelected: item.offset == session.index,
                                compact: session.gridThumbSize < 160
                            )
                            .id(item.element)
                            .onTapGesture(count: 2) {
                                session.open(item.offset)
                            }
                            .simultaneousGesture(
                                TapGesture().onEnded { session.select(item.offset) }
                            )
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

    // MARK: - Keyboard

    private func handleEvent(_ event: NSEvent) -> Bool {
        // Коды клавиш не зависят от раскладки
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
        case 53: // Esc
            session.stopReview()
        default:
            guard let first = event.charactersIgnoringModifiers?.first, first.isWholeNumber else {
                return false
            }
            session.handleShortcut(String(first))
        }
        return true
    }
}

// MARK: - Cell

private struct GridCell: View {
    let url: URL
    let isSelected: Bool
    let compact: Bool

    @State private var thumbnail: Thumbnail?

    private static let selectionColor = Color(red: 0.94, green: 0.96, blue: 0.62)

    var body: some View {
        let thumb = thumbnail ?? ThumbnailLoader.cached(url)

        VStack(spacing: 0) {
            ZStack {
                isSelected ? Self.selectionColor : Color(white: 0.3)

                if let image = thumb?.image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(8)
                } else if thumb == nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .aspectRatio(1, contentMode: .fit)

            caption(thumb?.info)
        }
        .background(Color(white: 0.25))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Self.selectionColor : Color.black.opacity(0.35), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .task(id: url) {
            guard thumbnail == nil else { return }
            if let loaded = await ThumbnailLoader.load(url), !Task.isCancelled {
                thumbnail = loaded
            }
        }
    }

    private func caption(_ info: PhotoInfo?) -> some View {
        VStack(spacing: 2) {
            Text(url.lastPathComponent)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            if !compact {
                // Строки есть всегда, чтобы все ячейки были одной высоты
                Text(details(info))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                Text(info?.camera ?? " ")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private func details(_ info: PhotoInfo?) -> String {
        guard let info else { return " " }
        var parts: [String] = []
        if let size = info.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let w = info.pixelWidth, let h = info.pixelHeight {
            parts.append("\(w) × \(h)")
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}
