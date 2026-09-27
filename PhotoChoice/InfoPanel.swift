import SwiftUI

/// Панель сведений о снимке (клавиша I)
struct InfoPanel: View {
    let url: URL

    @State private var details: PhotoDetails?

    static let width: CGFloat = 300

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                histogram
                exposure
                if let details {
                    ForEach(details.sections) { section in
                        sectionView(section)
                    }
                    if let map = details.mapURL {
                        Link(destination: map) {
                            Label("Открыть на карте", systemImage: "map")
                                .font(.system(size: 12))
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.visible)
        .frame(width: Self.width)
        .background(Color(white: 0.1).opacity(0.94))
        .environment(\.colorScheme, .dark)
        .task(id: url) {
            details = PhotoDetailsLoader.cached(url)
            guard details == nil else { return }
            let loaded = await PhotoDetailsLoader.load(url)
            if !Task.isCancelled { details = loaded }
        }
    }

    // MARK: - Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(url.lastPathComponent)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(url.deletingLastPathComponent().lastPathComponent)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    private var histogram: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let histogram = details?.histogram {
                    HistogramView(histogram: histogram)
                } else {
                    Color(white: 0.14)
                    if details == nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Нет данных")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.08)))

            if let histogram = details?.histogram {
                HStack {
                    clipping("Провалы", histogram.shadowsClipped, icon: "square.fill", color: .blue)
                    Spacer()
                    clipping("Пересветы", histogram.highlightsClipped, icon: "square.fill", color: .red)
                }
            }
        }
    }

    private func clipping(_ title: String, _ share: Double, icon: String, color: Color) -> some View {
        let percent = share * 100
        let text = percent < 0.05 ? "0%" : String(format: percent < 10 ? "%.1f%%" : "%.0f%%", percent)
        let warn = percent >= 1
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 7))
                .foregroundStyle(warn ? color : .white.opacity(0.25))
            Text("\(title) \(text)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(warn ? 0.85 : 0.45))
        }
    }

    private var exposure: some View {
        HStack(spacing: 6) {
            exposureCell(details?.shutter, "выдержка")
            exposureCell(details?.aperture, "диафрагма")
            exposureCell(details?.iso, "ISO")
            exposureCell(details?.focal, "фокусное")
        }
    }

    private func exposureCell(_ value: String?, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value ?? "—")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(value == nil ? Color.white.opacity(0.3) : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func sectionView(_ section: InfoSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(.white.opacity(0.4))
            ForEach(section.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.label)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 104, alignment: .leading)
                    Text(row.value)
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .font(.system(size: 12))
            }
        }
    }
}

/// RGB‑гистограмма: каналы складываются (plusLighter), пересечения дают жёлтый/голубой/пурпурный/белый
struct HistogramView: View {
    let histogram: Histogram

    private static let red = Color(.sRGB, red: 1, green: 0.16, blue: 0.16)
    private static let green = Color(.sRGB, red: 0.16, green: 0.95, blue: 0.2)
    private static let blue = Color(.sRGB, red: 0.2, green: 0.35, blue: 1)

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.13)))

            // Сетка по четвертям
            for quarter in 1..<4 {
                let x = size.width * CGFloat(quarter) / 4
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.07)), lineWidth: 1)
            }

            context.blendMode = .plusLighter
            context.fill(area(histogram.red, size), with: .color(Self.red))
            context.fill(area(histogram.green, size), with: .color(Self.green))
            context.fill(area(histogram.blue, size), with: .color(Self.blue))

            context.blendMode = .normal
            context.stroke(outline(histogram.luminance, size), with: .color(.white.opacity(0.55)), lineWidth: 1)
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

    private func outline(_ bins: [Double], _ size: CGSize) -> Path {
        var path = Path()
        for (i, value) in bins.enumerated() {
            if i == 0 {
                path.move(to: point(i, value, size))
            } else {
                path.addLine(to: point(i, value, size))
            }
        }
        return path
    }
}
