import SwiftUI

/// Панель сведений о снимке (клавиша I)
struct InfoPanel: View {
    let url: URL
    /// Остальные файлы кадра (пара RAW + JPEG)
    var companions: [URL] = []

    @Environment(\.theme) private var theme
    @State private var details: PhotoDetails?
    /// Блок «Цвета» (палитра кадра) включён
    @AppStorage("paletteEnabled") private var paletteEnabled = true

    /// Ширина по умолчанию (у каждой темы своя — `theme.panelWidth`)
    static let width: CGFloat = 300

    var body: some View {
        let c = theme.c
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                histogram
                exposure
                if paletteEnabled {
                    PaletteSection(url: url)
                }
                if !companions.isEmpty {
                    sectionView(filesSection)
                }
                if let details {
                    ForEach(details.sections) { section in
                        sectionView(section)
                    }
                    if let map = details.mapURL {
                        Link(destination: map) {
                            Label("Открыть на карте", systemImage: "map")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(c.accent)
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.visible)
        .frame(width: theme.panelWidth)
        .background { panelBackground }
        .task(id: url) {
            details = PhotoDetailsLoader.cached(url)
            guard details == nil else { return }
            let loaded = await PhotoDetailsLoader.load(url)
            if !Task.isCancelled { details = loaded }
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        let c = theme.c
        switch theme.direction {
        case .glass:
            Color.clear.themedPanel(theme)
        case .quiet:
            c.overlay
        case .studio, .contact:
            c.surface1
                .overlay(alignment: .leading) {
                    Rectangle().fill(c.line).frame(width: 1)
                }
        }
    }

    // MARK: - Заголовок

    private var header: some View {
        let c = theme.c
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Сведения")
                    .font(theme.isContact ? .system(size: 15, weight: .semibold, design: .serif) : .system(size: 13, weight: .semibold))
                    .foregroundStyle(c.text1)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { paletteEnabled.toggle() }
                } label: {
                    Image(systemName: "paintpalette")
                }
                .buttonStyle(PCIconButtonStyle(isOn: paletteEnabled))
                .focusable(false)
                .help(paletteEnabled ? "Скрыть цвета кадра" : "Показать цвета кадра")
                HStack(spacing: 4) {
                    KeyCap("I", size: .small)
                    Text("скрыть")
                        .font(.system(size: 12))
                        .foregroundStyle(c.text2)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.text1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(url.deletingLastPathComponent().lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(c.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Гистограмма

    private var histogramRadius: CGFloat {
        theme.isGlass ? 12 : theme.rSm
    }

    private var histogramFill: Color {
        if theme.isGlass && !theme.isLight { return Color.black.opacity(0.35) }
        if theme.isQuiet { return .clear }
        return theme.c.canvas
    }

    private var histogram: some View {
        let c = theme.c
        let shape = RoundedRectangle(cornerRadius: histogramRadius)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack {
                histogramFill
                if let histogram = details?.histogram {
                    HistogramView(histogram: histogram)
                } else if details == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Нет данных")
                        .font(.caption)
                        .foregroundStyle(c.text3)
                }
            }
            .frame(height: 96)
            .clipShape(shape)
            .overlay {
                if theme.isQuiet {
                    VStack {
                        Spacer()
                        Rectangle().fill(c.lineStrong).frame(height: 1)
                    }
                } else if !theme.isLight {
                    shape.stroke(c.line, lineWidth: 1)
                }
            }

            if let histogram = details?.histogram {
                HStack {
                    clipping("Провалы", histogram.shadowsClipped, symbol: "arrowtriangle.down.fill", color: c.clipLow)
                    Spacer()
                    clipping("Пересветы", histogram.highlightsClipped, symbol: "arrowtriangle.up.fill", color: c.clipHigh)
                }
            }
        }
    }

    private func clipping(_ title: String, _ share: Double, symbol: String, color: Color) -> some View {
        let c = theme.c
        let percent = share * 100
        let number: String
        if percent < 0.05 {
            number = "0"
        } else {
            number = String(format: percent < 10 ? "%.1f" : "%.0f", percent)
                .replacingOccurrences(of: ".", with: ",")
        }
        // От 1 % выбитой площади — заметно глазом, подсвечиваем
        let warn = percent >= 1
        return HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 7))
                .foregroundStyle(color)
                .opacity(warn || !theme.isQuiet ? 1 : 0.5)
            Text("\(title) \(number) %")
                .font(.system(size: 11).monospacedDigit())
                .fontWeight(warn ? .semibold : .regular)
                .foregroundStyle(warn ? c.text1 : c.text2)
        }
    }

    // MARK: - Четыре главных параметра

    private var exposure: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            exposureCell(details?.shutter, "Выдержка")
            exposureCell(details?.aperture, "Диафрагма")
            exposureCell(details?.iso, "ISO")
            exposureCell(details?.focal, "Фокусное")
        }
    }

    private func exposureCell(_ value: String?, _ caption: String) -> some View {
        let c = theme.c
        let radius = theme.isGlass ? 12 : theme.rSm
        let shape = RoundedRectangle(cornerRadius: radius)
        return VStack(alignment: .leading, spacing: 1) {
            Text(value ?? "—")
                .font(theme.exifFont)
                .foregroundStyle(value == nil ? c.text3 : c.text1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Group {
                if theme.isContact {
                    Text(caption.uppercased()).themeLabel(theme)
                } else {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(c.text3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.isQuiet ? 0 : 10)
        .padding(.vertical, theme.isQuiet ? 4 : 8)
        .background(exposureFill, in: shape)
        .overlay {
            if theme.isContact {
                shape.stroke(c.line, lineWidth: 1)
            }
        }
    }

    private var exposureFill: Color {
        let c = theme.c
        switch theme.direction {
        case .studio: return theme.isLight ? c.app : c.surface2
        case .glass: return theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08)
        case .quiet, .contact: return .clear
        }
    }

    // MARK: - Секции

    /// «Файлы кадра»: формат → имя и размер каждого файла пары
    private var filesSection: InfoSection {
        let rows = ([url] + companions).map { file -> InfoRow in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }
            let sizeText = size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            let value = [file.lastPathComponent, sizeText].compactMap { $0 }.joined(separator: " · ")
            return InfoRow(label: file.pathExtension.uppercased(), value: value)
        }
        return InfoSection(title: "Файлы кадра", rows: rows)
    }

    @ViewBuilder
    private func sectionView(_ section: InfoSection) -> some View {
        let c = theme.c
        let rows = VStack(alignment: .leading, spacing: 0) {
            ForEach(section.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label)
                        .foregroundStyle(c.text2)
                        .fixedSize()
                    Spacer(minLength: 0)
                    Text(row.value)
                        .foregroundStyle(c.text1)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .font(.system(size: 12))
                .padding(.vertical, 2)
            }
        }

        if theme.isGlass {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.text2)
                rows
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                theme.isLight ? Color.black.opacity(0.035) : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 12)
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title.uppercased())
                    .themeLabel(theme)
                    .padding(.top, 8)
                rows
            }
            .overlay(alignment: .top) {
                if !theme.isQuiet {
                    Rectangle().fill(c.line).frame(height: 1)
                }
            }
        }
    }
}

/// RGB‑гистограмма: каналы накладываются в режиме screen, пересечения дают жёлтый/голубой/пурпурный/белый
struct HistogramView: View {
    let histogram: Histogram

    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.c
        let opacity = theme.isQuiet ? 0.7 : 0.85
        Canvas { context, size in
            // Сетка по четвертям
            for quarter in 1..<4 {
                let x = size.width * CGFloat(quarter) / 4
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 1)
            }

            context.blendMode = .screen
            context.fill(area(histogram.red, size), with: .color(c.histR.opacity(opacity)))
            context.fill(area(histogram.green, size), with: .color(c.histG.opacity(opacity)))
            context.fill(area(histogram.blue, size), with: .color(c.histB.opacity(opacity)))
        }
    }

    private func point(_ i: Int, _ value: Double, _ size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * CGFloat(i) / 255,
            y: size.height - size.height * CGFloat(value) * 0.96
        )
    }

    private func area(_ bins: [Double], _ size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, value) in bins.enumerated() {
            path.addLine(to: point(i, value, size))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}
