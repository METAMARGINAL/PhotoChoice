import SwiftUI

/// Панель сведений о снимке (клавиша I)
struct InfoPanel: View {
    let url: URL
    /// Остальные файлы кадра (пара RAW + JPEG)
    var companions: [URL] = []
    /// «Нейтраль» в просмотре: выбор фона под фото
    var showsSurround = false
    /// `session.editRevision`: кадр сохранили в другой программе — перечитать
    var revision = 0

    @Environment(\.theme) private var theme
    @State private var details: PhotoDetails?
    /// Блок «Цвета» (палитра кадра) включён
    @AppStorage("paletteEnabled") private var paletteEnabled = true
    /// Подсветка на кадре в просмотре и сравнении, как в Lightroom: клик по треугольнику на гистограмме
    @AppStorage("clipShadows") private var clipShadows = false
    @AppStorage("clipHighlights") private var clipHighlights = false
    @AppStorage(Pref.surroundTone) private var surroundTone = 2

    /// Ширина по умолчанию (у каждой темы своя — `theme.panelWidth`)
    static let width: CGFloat = 300

    var body: some View {
        let c = theme.c
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if showsSurround && theme.isNeutral {
                    surroundPicker
                }
                histogram
                exposure
                if paletteEnabled {
                    PaletteSection(url: url)
                }
                if let defectSection {
                    sectionView(defectSection)
                }
                if !companions.isEmpty {
                    sectionView(filesSection)
                }
                #if DEBUG
                sectionView(analysisDebugSection)
                #endif
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
            .padding(.horizontal, theme.isGlass ? 22 : 18)
            .padding(.vertical, theme.isGlass ? 22 : 16)
        }
        .scrollIndicators(.visible)
        .frame(width: theme.panelWidth)
        .background { panelBackground }
        .task(id: "\(url.path)#\(revision)") {
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
            Color.clear.themedPanel(theme, cornerRadius: 32)
        case .film:
            Color(hex: 0x131313)
        case .neutral:
            c.surface1
        case .table:
            if theme.isLight {
                Color.white
                    .shadow(color: Color.black.opacity(0.12), radius: 16, x: -8)
            } else {
                c.surface1
            }
        }
    }

    // MARK: - Заголовок

    private var header: some View {
        let c = theme.c
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Сведения")
                    .font(headerFont)
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

    private var headerFont: Font {
        switch theme.direction {
        case .film: .system(size: 15, weight: .semibold)
        case .glass: .system(size: 17, weight: .bold)
        case .neutral: .system(size: 14, weight: .semibold)
        case .table: .system(size: 18, weight: .semibold)
        }
    }

    /// «Фон под фото»: пять серых без оттенка
    private var surroundPicker: some View {
        let c = theme.c
        return HStack(spacing: 8) {
            Text("Фон под фото")
                .font(.system(size: 12.5))
                .foregroundStyle(c.text2)
            Spacer(minLength: 4)
            ForEach(SurroundTone.tones.indices, id: \.self) { i in
                Button {
                    surroundTone = i
                } label: {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(SurroundTone.color(i))
                        .frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        .padding(2)
                        .overlay {
                            if surroundTone == i {
                                RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: 0xF0F0F0), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(SurroundTone.titles[i])
            }
        }
    }

    // MARK: - Гистограмма

    private var histogramRadius: CGFloat {
        switch theme.direction {
        case .glass: 16
        case .table: 8
        case .film, .neutral: 6
        }
    }

    private var histogramFill: Color {
        switch theme.direction {
        case .glass: return theme.isLight ? Color.black.opacity(0.05) : Color.black.opacity(0.28)
        case .film: return Color(hex: 0x0E0E0E)
        case .neutral: return Color(hex: 0x1B1B1B)
        case .table: return theme.isLight ? Color(hex: 0xF3F2EF) : Color(hex: 0x1B1B1B)
        }
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
            .overlay(alignment: .topLeading) {
                clipToggle($clipShadows, symbol: "arrowtriangle.down.fill", color: c.clipLow,
                           help: "Показать провалы на кадре синим")
            }
            .overlay(alignment: .topTrailing) {
                clipToggle($clipHighlights, symbol: "arrowtriangle.up.fill", color: c.clipHigh,
                           help: "Показать пересветы на кадре красным")
            }

            if let histogram = details?.histogram {
                HStack {
                    Button {
                        clipShadows.toggle()
                    } label: {
                        clipping("Провалы", histogram.shadowsClipped, symbol: "arrowtriangle.down.fill", color: c.clipLow)
                    }
                    .buttonStyle(.plain)
                    .help(clipShadows ? "Скрыть провалы на кадре" : "Показать провалы на кадре синим")
                    Spacer()
                    Button {
                        clipHighlights.toggle()
                    } label: {
                        clipping("Пересветы", histogram.highlightsClipped, symbol: "arrowtriangle.up.fill", color: c.clipHigh)
                    }
                    .buttonStyle(.plain)
                    .help(clipHighlights ? "Скрыть пересветы на кадре" : "Показать пересветы на кадре красным")
                }
            }
        }
    }

    /// Треугольник в углу гистограммы: включает подсветку на кадре; включённый — в рамке своего цвета
    private func clipToggle(_ isOn: Binding<Bool>, symbol: String, color: Color, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8))
                .foregroundStyle(color)
                .opacity(isOn.wrappedValue ? 1 : 0.55)
                .frame(width: 18, height: 18)
                .background {
                    if isOn.wrappedValue {
                        RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.22))
                        RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(4)
        .help(isOn.wrappedValue ? "Скрыть подсветку на кадре" : help)
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
                .opacity(1)
            Text("\(title) \(number) %")
                .font(.system(size: 11).monospacedDigit())
                .fontWeight(warn ? .semibold : .regular)
                .foregroundStyle(warn ? c.text1 : c.text2)
        }
    }

    // MARK: - Четыре главных параметра

    private var exposure: some View {
        let columns = theme.isNeutral ? 4 : 2
        let gap: CGFloat = theme.isGlass ? 10 : (theme.isNeutral ? 6 : 14)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columns), alignment: .leading, spacing: gap) {
            exposureCell(details?.shutter, "Выдержка")
            exposureCell(details?.aperture, "Диафрагма")
            exposureCell(details?.iso, "ISO")
            exposureCell(details?.focal, "Фокусное")
        }
    }

    private func exposureCell(_ value: String?, _ caption: String) -> some View {
        let c = theme.c
        let shape = RoundedRectangle(cornerRadius: 18)
        return VStack(alignment: .leading, spacing: theme.isFilm ? 5 : 2) {
            Text(value ?? "—")
                .font(theme.exifFont)
                .tracking(theme.isFilm ? 0.6 : 0)
                .foregroundStyle(value == nil ? c.text3 : (theme.isFilm ? c.edge : c.text1))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: theme.isNeutral ? 11 : 12))
                .foregroundStyle(c.text3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.isGlass ? 14 : 0)
        .padding(.vertical, theme.isGlass ? 12 : 0)
        .background(theme.isGlass ? Color.white.opacity(theme.isLight ? 0.5 : 0.08) : Color.clear, in: shape)
    }

    // MARK: - Секции

    #if DEBUG
    /// Сырые метрики анализа (только в отладочной сборке) — для подбора порогов брака
    private var analysisDebugSection: InfoSection {
        let store = AnalysisStore.shared
        guard let m = store.metrics(for: url) else {
            let state = store.isRunning ? "в очереди (\(store.done) из \(store.total))" : "нет данных"
            return InfoSection(title: "Анализ · отладка", rows: [InfoRow(label: "Статус", value: state)])
        }
        func f(_ value: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", value) }
        func pct(_ value: Double) -> String { f(value * 100) + " %" }
        var rows: [InfoRow] = [
            InfoRow(label: "Резкость объекта", value: f(m.sharpness, 0)),
            InfoRow(label: "Резкость кадра", value: f(m.sharpnessGlobal, 0)),
            InfoRow(label: "Объект", value: m.subjectRect.map { "x \(f($0.minX, 2)) y \(f($0.minY, 2)) · \(f($0.width, 2))×\(f($0.height, 2))" } ?? "—"),
            InfoRow(label: "Пересвет / провал", value: "\(pct(m.clipHigh)) / \(pct(m.clipLow))"),
            InfoRow(label: "Яркость", value: f(m.meanLuma, 2)),
            InfoRow(label: "Горизонт", value: m.horizonAngle.map { f($0) + "°" } ?? "не найден"),
            InfoRow(label: "Эстетика", value: m.aesthetics.map { f($0, 2) } ?? "—"),
            InfoRow(label: "Служебный", value: m.isUtility.map { $0 ? "да" : "нет" } ?? "—"),
            InfoRow(label: "Выдержка", value: m.exposureTime.map { f($0, 4) + " с" } ?? "—"),
            InfoRow(label: "Время съёмки", value: m.captureDate.map { $0.formatted(date: .numeric, time: .standard) } ?? "—"),
            InfoRow(label: "Отпечаток", value: m.featurePrintCount.map { "\($0) чисел" } ?? "—"),
            InfoRow(label: "Размер анализа", value: "\(m.analyzedWidth)×\(m.analyzedHeight)"),
            InfoRow(label: "Лиц", value: "\(m.faces.count)")
        ]
        for (i, face) in m.faces.enumerated() {
            let area = face.rect.width * face.rect.height
            let eyes = "\(face.leftEye.map { f($0, 2) } ?? "—")/\(face.rightEye.map { f($0, 2) } ?? "—")"
            let details = "глаза \(eyes) · кач. \(face.quality.map { f($0, 2) } ?? "—") · yaw \(face.yaw.map { f($0, 0) } ?? "—")° · \(pct(area))"
            rows.append(InfoRow(label: "Лицо \(i + 1)", value: details + " · ярк. \(face.luma.map { f($0, 2) } ?? "—")"))
        }
        rows.append(InfoRow(label: "Детали объекта", value: m.detailRatio.map { f($0, 3) } ?? "—"))
        rows.append(InfoRow(label: "Детали кадра", value: m.detailRatioGlobal.map { f($0, 3) } ?? "—"))
        rows.append(InfoRow(label: "Яркость объекта", value: m.subjectLuma.map { f($0, 2) } ?? "—"))
        rows.append(InfoRow(label: "Почти белые", value: m.clipWhite.map { pct($0) } ?? "—"))
        rows.append(InfoRow(label: "Белые на лицах / объекте", value: "\(m.faces.compactMap(\.white).max().map { pct($0) } ?? "—") / \(m.subjectWhite.map { pct($0) } ?? "—")"))
        rows.append(InfoRow(label: "Резкость 100 %", value: m.fullSharpness.map { f($0, 0) } ?? "—"))
        rows.append(InfoRow(label: "Детали 100 %", value: m.fullDetailRatio.map { f($0, 3) } ?? "—"))
        if let context = store.contexts[url] {
            rows.append(InfoRow(label: "Серия", value: "\((context.series ?? 0) + 1) · \(context.seriesSize) кадров"))
            rows.append(InfoRow(label: "К лучшему соседу", value: context.relSharpness.map { pct($0) } ?? "—"))
        }
        if let p = store.probabilities[url] {
            rows.append(InfoRow(label: "По разметке: брак", value: pct(p)))
        }
        if m.clipModel != nil {
            func has(_ data: Data?) -> String { data == nil ? "нет" : "да" }
            let faceVectors = m.faces.filter { $0.clip != nil }.count
            rows.append(InfoRow(label: "Векторы MobileCLIP", value: "кадр \(has(m.clipFrame)) · 100 % \(has(m.clipFocus)) · лиц \(faceVectors)"))
            if let s = store.signals[url] {
                func p(_ value: Double?) -> String { value.map { pct($0) } ?? "—" }
                let eyes = s.closed.sorted { $0.key < $1.key }.map { "лицо \($0.key + 1): \(pct($0.value))" }
                rows.append(InfoRow(label: "Модель: не в фокусе", value: p(s.blur)))
                rows.append(InfoRow(label: "Модель: смаз кадра", value: p(s.motion)))
                rows.append(InfoRow(label: "Модель: глаза закрыты", value: eyes.isEmpty ? "—" : eyes.joined(separator: " · ")))
                rows.append(InfoRow(label: "Модель: случайный", value: p(s.accidental)))
                rows.append(InfoRow(label: "Модель: пересвет", value: p(s.overexposed)))
            } else {
                rows.append(InfoRow(label: "Модель", value: "подсказки не посчитаны"))
            }
        }
        rows.append(InfoRow(label: "Медиана резкости", value: store.folderStats.medianSharpness.map { f($0, 0) } ?? "—"))
        rows.append(InfoRow(label: "Медиана 100 %", value: store.folderStats.medianFullSharpness.map { f($0, 0) } ?? "—"))
        for defect in store.candidates[url] ?? [] {
            rows.append(InfoRow(label: "? " + defect.reason.title, value: f(defect.confidence, 2)))
        }
        return InfoSection(title: "Анализ · отладка", rows: rows)
    }
    #endif

    /// «Брак»: причины пометок при текущей строгости (умный отбор)
    private var defectSection: InfoSection? {
        let defects = AnalysisStore.shared.defects(for: url)
        guard !defects.isEmpty else { return nil }
        return InfoSection(
            title: "Брак",
            rows: defects.map { InfoRow(label: $0.reason.title, value: $0.detail) }
        )
    }

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
                in: RoundedRectangle(cornerRadius: 16)
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .themeLabel(theme)
                    .padding(.top, 8)
                rows
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
        let opacity = theme.isLight ? 0.7 : 0.85
        Canvas { context, size in
            // Сетка по четвертям
            for quarter in 1..<4 {
                let x = size.width * CGFloat(quarter) / 4
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(theme.isLight ? .black.opacity(0.06) : .white.opacity(0.06)), lineWidth: 1)
            }

            // На светлом фоне каналы складываются как краски, на тёмном — как свет
            context.blendMode = theme.isLight ? .multiply : .screen
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
