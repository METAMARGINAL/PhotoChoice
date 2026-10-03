import AppKit
import SwiftUI

// Цветовой анализ кадра в панели сведений (клавиша I): ~10 основных цветов полоской плашек.
// Ядро — PaletteExtractor.swift (k-means в OKLab). Здесь — кэш и отображение.

// MARK: - Кэш

/// Палитры уже посчитанных кадров, ~500 последних. Ключ — URL + дата изменения + размер файла:
/// если файл перенесли и вернули через Z без изменений, палитра снова найдётся
final class PaletteCache {
    static let shared = PaletteCache()

    struct Key: Hashable {
        let url: URL
        let modified: Date?
        let size: Int?
    }

    private var store: [Key: [PaletteColor]] = [:]
    private var order: [Key] = []
    private let limit = 500

    static func key(for url: URL) -> Key {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return Key(url: url, modified: values?.contentModificationDate, size: values?.fileSize)
    }

    func colors(for key: Key) -> [PaletteColor]? {
        store[key]
    }

    func save(_ colors: [PaletteColor], for key: Key) {
        if store[key] == nil { order.append(key) }
        store[key] = colors
        if order.count > limit {
            store[order.removeFirst()] = nil
        }
    }
}

// MARK: - Блок «Цвета»

struct PaletteSection: View {
    let url: URL

    @Environment(\.theme) private var theme
    @AppStorage("paletteSort") private var sortMode: PaletteSort = .lightness

    @State private var colors: [PaletteColor]?
    @State private var failed = false
    @State private var showSpinner = false
    @State private var hovered: PaletteColor?
    @State private var copiedHex: String?

    var body: some View {
        let c = theme.c
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(theme.isGlass ? "Цвета" : "ЦВЕТА")
                    .themeLabel(theme)
                Spacer()
                Picker("Сортировка", selection: $sortMode) {
                    ForEach(PaletteSort.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                .focusable(false)
                .help("Порядок цветов: по светлоте, по оттенку или по доле в кадре")
            }

            strip

            caption
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(height: 14, alignment: .leading)
        }
        .foregroundStyle(c.text1)
        .task(id: url) { await load() }
    }

    // MARK: Полоска

    @ViewBuilder
    private var strip: some View {
        let c = theme.c
        let shape = RoundedRectangle(cornerRadius: theme.isGlass ? 8 : theme.rSm)
        if let colors {
            HStack(spacing: 0) {
                ForEach(colors.ordered(by: sortMode)) { swatch in
                    swatchView(swatch)
                }
            }
            .frame(height: 44)
            .clipShape(shape)
            .overlay(shape.stroke(c.line, lineWidth: 1))
            .animation(.easeInOut(duration: 0.2), value: sortMode)
        } else if failed {
            Text("Не удалось определить цвета")
                .font(.system(size: 11))
                .foregroundStyle(c.text3)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            shape
                .fill(c.surface2)
                .frame(height: 44)
                .overlay {
                    if showSpinner {
                        ProgressView().controlSize(.small)
                    }
                }
        }
    }

    private func swatchView(_ swatch: PaletteColor) -> some View {
        let isHovered = hovered?.id == swatch.id
        return Rectangle()
            .fill(swatch.color)
            .overlay {
                if isHovered {
                    Rectangle()
                        .strokeBorder(swatch.isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.85), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    hovered = swatch
                } else if hovered?.id == swatch.id {
                    hovered = nil
                }
            }
            .onTapGesture { copy(swatch) }
            .help("\(swatch.hex) — \(percent(swatch)) кадра")
    }

    // MARK: Подпись под полоской

    @ViewBuilder
    private var caption: some View {
        let c = theme.c
        if let copiedHex {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                Text("Скопировано \(copiedHex)")
            }
            .foregroundStyle(c.success)
        } else if let hovered {
            HStack(spacing: 6) {
                Text(hovered.hex)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(c.text1)
                Text("\(percent(hovered)) кадра · клик — скопировать")
                    .foregroundStyle(c.text3)
            }
        } else if colors != nil {
            Text("Наведите на цвет — HEX и доля кадра, клик — скопировать")
                .foregroundStyle(c.text3)
        } else {
            Text(" ")
        }
    }

    private func percent(_ swatch: PaletteColor) -> String {
        let value = swatch.share * 100
        return value < 1 ? "<1 %" : "\(Int(value.rounded())) %"
    }

    private func copy(_ swatch: PaletteColor) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(swatch.hex, forType: .string)
        copiedHex = swatch.hex
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedHex == swatch.hex { copiedHex = nil }
        }
    }

    // MARK: Расчёт

    private func load() async {
        hovered = nil
        let key = PaletteCache.key(for: url)
        if let cached = PaletteCache.shared.colors(for: key) {
            colors = cached
            failed = false
            showSpinner = false
            return
        }
        colors = nil
        failed = false
        showSpinner = false

        // Источник №1 — уже декодированная картинка с экрана или миниатюра из сетки: с диска не читаем
        let shown = ImageLoader.cachedImage(at: url) ?? ThumbnailLoader.cached(url)?.image
        let decoded = shown?.cgImage(forProposedRect: nil, context: nil, hints: nil).map(RenderedImage.init)
        let target = url

        // Индикатор — только если расчёт затянулся, чтобы не мелькал при листании
        let spinner = Task {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled && colors == nil && !failed {
                showSpinner = true
            }
        }
        defer { spinner.cancel() }

        // Источник №2 — встроенное превью через ImageIO (для RAW без полного проявления).
        // Отмена задачи вида (смена кадра) передаётся в расчёт — k-means прерывается
        let job = Task.detached(priority: .userInitiated) { () -> [PaletteColor] in
            guard let image = decoded?.image ?? PaletteExtractor.thumbnail(at: target) else { return [] }
            return PaletteExtractor.extract(from: image)
        }
        let result = await withTaskCancellationHandler {
            await job.value
        } onCancel: {
            job.cancel()
        }

        guard !Task.isCancelled else { return }
        showSpinner = false
        if result.isEmpty {
            failed = true
        } else {
            PaletteCache.shared.save(result, for: key)
            colors = result
        }
    }
}
