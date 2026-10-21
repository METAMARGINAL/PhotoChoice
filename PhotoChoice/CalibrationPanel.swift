import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Калибровка брака (⌥⌘K): по каждой причине — все кадры папки точками на шкале её метрики,
// порог — ползунком. Ручная разметка «брак / норма» (правая кнопка → «Калибровка») красит точки
// и считает ошибки текущих порогов. Экспорт CSV — чтобы подобрать пороги по реальной папке.

/// Точка на графике: кадр и значение метрики
private struct CalibrationPoint {
    let url: URL
    let value: Double
    let flagged: Bool
    let label: Bool?
    /// Разброс по вертикали, чтобы точки с близкими значениями не сливались
    let jitter: Double
}

struct CalibrationPanel: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme
    @Bindable private var store = AnalysisStore.shared

    static let width: CGFloat = 340

    /// Итог последнего обучения
    @State private var trainingMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                strictness
                summary
                training
                if store.modelActive {
                    Text("Сейчас брак определяет обученная модель. Правила ниже только поясняют причину у помеченных ею кадров.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.c.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(DefectReason.rules) { reason in
                    reasonCard(reason)
                }
                modelSection
                footer
            }
            // Содержимое строго по ширине панели: длинные подписи переносятся, а не раздвигают её
            .frame(width: Self.width - 32, alignment: .leading)
            .padding(16)
        }
        .scrollIndicators(.visible)
        .frame(width: Self.width)
        .background { panelBackground }
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

    // MARK: Шапка

    private var header: some View {
        let c = theme.c
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Калибровка брака")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.text1)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { session.showCalibration = false }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(PCIconButtonStyle())
                .focusable(false)
                .help("Закрыть (⌥⌘K)")
            }
            Text("Каждая точка — кадр папки, по горизонтали — значение метрики. Линия — граница: кадры в красной зоне попадают в брак по этой причине. Ползунок двигает линию. Клик по точке — выделить кадр в сетке.")
                .font(.system(size: 11))
                .foregroundStyle(c.text3)
                .fixedSize(horizontal: false, vertical: true)
            legend
        }
    }

    private var legend: some View {
        let c = theme.c
        func item(_ color: Color, _ size: CGFloat, _ text: String) -> some View {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: size, height: size)
                Text(text)
            }
        }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 12) {
                item(c.warning, 6, "в браке по этой причине")
                item(c.text3, 5, "не в браке")
            }
            HStack(spacing: 12) {
                item(c.danger, 8, "вы отметили «брак»")
                item(c.success, 8, "вы отметили «норма»")
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(c.text2)
    }

    private var strictness: some View {
        let c = theme.c
        return HStack(spacing: 10) {
            Text("Строгость")
                .font(.system(size: 12))
                .foregroundStyle(c.text2)
            Picker("Строгость", selection: $store.strictness) {
                ForEach(DefectStrictness.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .focusable(false)
            Spacer(minLength: 0)
        }
    }

    // MARK: Обучение

    private var training: some View {
        let c = theme.c
        let labeled = session.allPhotos.compactMap { store.label($0) }
        let bad = labeled.filter { $0 }.count
        let good = labeled.count - bad
        let minimum = DefectModel.minimumPerClass
        return VStack(alignment: .leading, spacing: 8) {
            Text("Обучение по разметке")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.text1)
            Text("Модель смотрит на все числа анализа сразу — резкость в 100 %, сравнение с соседями по серии, качество лица, яркость — и учится отличать ваш брак от нормы. Нужно хотя бы по \(minimum) размеченных кадров каждого вида, лучше 30+.")
                .font(.system(size: 11))
                .foregroundStyle(c.text3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(store.model == nil ? "Обучить" : "Переобучить") {
                    Task {
                        trainingMessage = await store.trainModel(photos: session.allPhotos)
                    }
                }
                .buttonStyle(PCButtonStyle())
                .disabled(store.isTraining || bad < minimum || good < minimum)
                if store.isTraining {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
                if store.model != nil {
                    Button("Забыть") {
                        store.forgetModel()
                        trainingMessage = nil
                    }
                    .buttonStyle(PCButtonStyle(kind: .ghost))
                    .help("Удалить обученную модель и вернуться к правилам")
                }
            }
            if let model = store.model {
                PCCheckbox(isOn: $store.useModel, title: "Брак определяет модель")
                Text(modelSummary(model))
                    .font(.system(size: 11))
                    .foregroundStyle(c.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let trainingMessage {
                Text(trainingMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(c.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func modelSummary(_ model: DefectModel) -> String {
        var text = "Обучена на \(model.badCount + model.goodCount) кадрах (брак \(model.badCount), норма \(model.goodCount))"
        if let accuracy = model.heldOutAccuracy {
            text += ", на отложенных угадывает \(Int((accuracy * 100).rounded())) %"
        }
        return text + ". Строгость задаёт, с какой вероятности кадр считается браком: Мягко 80 %, Обычно 60 %, Строго 40 %."
    }

    // MARK: Сводка по разметке

    private var summary: some View {
        let c = theme.c
        let photos = session.allPhotos
        var bad = 0, good = 0, falseAlarms = 0, missed = 0
        for url in photos {
            guard let label = store.label(url) else { continue }
            let flagged = store.isDefect(url)
            if label {
                bad += 1
                if !flagged { missed += 1 }
            } else {
                good += 1
                if flagged { falseAlarms += 1 }
            }
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("В браке сейчас")
                    .foregroundStyle(c.text2)
                Spacer()
                Text("\(session.defectPhotos.count) из \(photos.count)")
                    .foregroundStyle(c.text1)
            }
            HStack {
                Text("Размечено вручную")
                    .foregroundStyle(c.text2)
                Spacer()
                Text("брак \(bad) · норма \(good)")
                    .foregroundStyle(c.text1)
            }
            if bad + good > 0 {
                HStack {
                    Text("Ошибки порогов")
                        .foregroundStyle(c.text2)
                    Spacer()
                    Text("лишних \(falseAlarms) · пропущено \(missed)")
                        .foregroundStyle(falseAlarms + missed == 0 ? c.success : c.warning)
                }
            } else {
                Text("Разметьте кадры правой кнопкой → «Калибровка»: «Это брак» / «Это норма». На графиках они станут красными и зелёными, а здесь появится число ошибок.")
                    .foregroundStyle(c.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12).monospacedDigit())
        .padding(10)
        .background(c.surface2.opacity(theme.isQuiet ? 0 : 1), in: RoundedRectangle(cornerRadius: theme.rSm))
    }

    // MARK: Карточка причины

    private func points(_ reason: DefectReason) -> [CalibrationPoint] {
        session.allPhotos.compactMap { url in
            guard let m = store.metrics(for: url),
                  let value = DefectRules.value(reason, m, context: store.contexts[url], stats: store.folderStats) else { return nil }
            let flagged = store.defects(for: url).contains { $0.reason == reason }
            return CalibrationPoint(url: url, value: value, flagged: flagged, label: store.label(url),
                                    jitter: Self.jitter(url))
        }
    }

    /// Постоянный для кадра сдвиг по вертикали
    private static func jitter(_ url: URL) -> Double {
        let hash = url.lastPathComponent.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
        return Double(hash % 1000) / 1000
    }

    private func flaggedCount(_ reason: DefectReason) -> Int {
        session.allPhotos.filter { url in store.defects(for: url).contains { $0.reason == reason } }.count
    }

    private func reasonCard(_ reason: DefectReason) -> some View {
        let c = theme.c
        let isOn = Binding(
            get: { store.tuning.isOn(reason) },
            set: { store.tuning.set(reason, on: $0) }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(c.line).frame(height: 1)
            HStack {
                PCCheckbox(isOn: isOn, title: reason.title)
                Spacer()
                Text("в браке: \(flaggedCount(reason))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(c.text1)
                    .help("Кадров с этой причиной при текущей строгости")
            }
            if let scale = DefectScale.of(reason), let threshold = store.tuning.threshold(reason) {
                StripPlot(
                    points: points(reason),
                    scale: scale,
                    boundary: scale.effective(threshold, strictness: store.strictness),
                    current: session.currentPhoto
                ) { url in
                    session.reveal(url)
                }
                .frame(height: 54)
                .opacity(store.tuning.isOn(reason) ? 1 : 0.4)

                HStack(spacing: 8) {
                    Slider(
                        // Ползунок — сама граница при текущей строгости; в настройку пишем порог «Обычно»
                        value: Binding(
                            get: { scale.effective(store.tuning.threshold(reason) ?? threshold, strictness: store.strictness) },
                            set: { store.tuning.setThreshold(reason, scale.base(fromEffective: $0, strictness: store.strictness)) }
                        ),
                        in: scale.range
                    )
                    .controlSize(.small)
                    .focusable(false)
                    Text(scale.format(scale.effective(threshold, strictness: store.strictness)))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(c.text1)
                        .frame(width: 52, alignment: .trailing)
                    Button {
                        if let standard = DefectTuning.standard.threshold(reason) {
                            store.tuning.setThreshold(reason, standard)
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(PCIconButtonStyle())
                    .focusable(false)
                    .help("Вернуть порог по умолчанию")
                }
                .disabled(!store.tuning.isOn(reason))

                Text("\(scale.name.prefix(1).uppercased() + scale.name.dropFirst()); брак — \(scale.defectBelow ? "левее" : "правее") линии")
                    .font(.system(size: 10.5))
                    .foregroundStyle(c.text3)
            } else {
                Text("Служебные снимки, почти чёрные или белые кадры и кадры с очень низкой эстетической оценкой Vision (ниже −0,3; при «Мягко» — ниже −0,4)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(c.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Модель MobileCLIP

    private var modelSection: some View {
        let c = theme.c
        let photos = session.allPhotos
        let withVectors = photos.filter { store.metrics(for: $0)?.clipModel != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(c.line).frame(height: 1)
            Text("Модель MobileCLIP")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.text1)
            Text(modelStatus(withVectors: withVectors, total: photos.count))
                .font(.system(size: 11))
                .foregroundStyle(c.text3)
                .fixedSize(horizontal: false, vertical: true)
            if QualityModel.isBundled {
                HStack(spacing: 8) {
                    Button(store.hasTextModel ? "Пересчитать подсказки" : "Посчитать подсказки…") {
                        if store.hasTextModel {
                            Task { await store.recomputePrompts() }
                        } else {
                            pickTextModel()
                        }
                    }
                    .buttonStyle(PCButtonStyle())
                    .disabled(store.isComputingPrompts)
                    .help(store.hasTextModel
                          ? "Текстовая часть модели уже выбрана — пересчёт без вопросов"
                          : "Выбрать mobileclip_s2_text.mlpackage — текстовую часть модели")
                    if store.isComputingPrompts {
                        ProgressView().controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }
                if store.hasTextModel && PromptBank.bundledTextModel == nil {
                    Button("Другой файл модели…") { pickTextModel() }
                        .buttonStyle(PCButtonStyle(kind: .ghost))
                        .disabled(store.isComputingPrompts)
                }
                #if DEBUG
                if store.prompts?.source == .user {
                    Button("Сохранить prompts.json") { exportPrompts() }
                        .buttonStyle(PCButtonStyle(kind: .ghost))
                        .help("Положите файл в PhotoChoice/Models — подсказки войдут в приложение у всех")
                }
                #endif
                if let promptMessage = store.promptMessage {
                    Text(promptMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(c.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if store.prompts != nil, withVectors > 0 {
                    ForEach(ModelPlot.allCases) { plot in
                        modelPlot(plot)
                    }
                }
            }
        }
    }

    private func modelStatus(withVectors: Int, total: Int) -> String {
        guard QualityModel.isBundled else {
            return "Модель не добавлена в приложение — брак ищется без неё. Как добавить — README, раздел «Модель MobileCLIP»."
        }
        guard QualityModel.isEnabled else {
            return "Модель выключена в настройках."
        }
        var text = "Векторы модели есть у \(withVectors) из \(total) кадров. "
        if let prompts = store.prompts {
            if prompts.missing > 0 {
                text += "Подсказки устарели (\(prompts.missing) описаний без векторов) — пересчитайте."
            } else {
                text += prompts.source == .user ? "Подсказки посчитаны на этом Mac." : "Подсказки — из приложения."
            }
            text += " В брак входит только «не в фокусе»: ниже 85 % она снимает пометку «Размыто». Остальные оценки — для сверки с вашей разметкой (красные и зелёные точки)."
        } else {
            text += "Подсказки не посчитаны: нужна текстовая часть модели (mobileclip_s2_text.mlpackage), в приложение она не входит."
        }
        return text
    }

    private func modelPlot(_ plot: ModelPlot) -> some View {
        let c = theme.c
        let scale = DefectScale(range: 0...1, defectBelow: false, name: plot.title, isPercent: true, isDegrees: false, slope: 1)
        let points = session.allPhotos.compactMap { url -> CalibrationPoint? in
            guard let signal = store.signals[url], let value = plot.value(signal) else { return nil }
            let flagged = store.defects(for: url).contains { $0.reason == plot.reason }
            return CalibrationPoint(url: url, value: value, flagged: flagged, label: store.label(url),
                                    jitter: Self.jitter(url))
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(plot.title)
                    .foregroundStyle(c.text2)
                Spacer()
                Text("выше 50 %: \(points.filter { $0.value >= 0.5 }.count)")
                    .foregroundStyle(c.text1)
            }
            .font(.system(size: 11).monospacedDigit())
            StripPlot(points: points, scale: scale, boundary: nil, current: session.currentPhoto) { url in
                session.reveal(url)
            }
            .frame(height: 44)
        }
    }

    private func pickTextModel() {
        let panel = NSOpenPanel()
        panel.message = "Выберите mobileclip_s2_text.mlpackage или папку, где он лежит (Загрузки → mobileclip)"
        panel.prompt = "Посчитать"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if let type = UTType(filenameExtension: "mlpackage") {
            panel.allowedContentTypes = [type]
        }
        // Куда скачивает команда из README; домашняя папка настоящая, а не контейнер песочницы
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            panel.directoryURL = URL(fileURLWithPath: String(cString: home)).appendingPathComponent("Downloads/mobileclip")
        }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.computePrompts(textModel: url) }
    }

    #if DEBUG
    private func exportPrompts() {
        guard let source = PromptBank.userFile, let data = try? Data(contentsOf: source) else {
            session.flash("Не удалось прочитать prompts.json", kind: .error)
            return
        }
        export(data, name: "prompts", ext: "json")
    }
    #endif

    // MARK: Низ

    private var footer: some View {
        let c = theme.c
        return VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(c.line).frame(height: 1)
            HStack(spacing: 8) {
                #if DEBUG
                Button("Экспорт CSV") { exportCSV() }
                    .buttonStyle(PCButtonStyle())
                    .help("Метрики, разметка и вердикты по всем кадрам папки — в exports проекта")
                #endif
                Button("Сбросить пороги") { store.tuning = .standard }
                    .buttonStyle(PCButtonStyle(kind: .ghost))
                    .disabled(store.tuning == .standard)
            }
            Button("Снять разметку в этой папке") {
                store.setLabel(session.allPhotos, nil)
            }
            .buttonStyle(PCButtonStyle(kind: .ghost))
            .disabled(!session.allPhotos.contains { store.label($0) != nil })
        }
    }

    // Выгрузки CSV и prompts.json — только в отладочной сборке: для подбора порогов, пользователю не нужны
    #if DEBUG
    // MARK: CSV

    private func exportCSV() {
        export(Data(csv().utf8), name: session.sourceURL?.lastPathComponent ?? "калибровка", ext: "csv")
    }

    // MARK: Выгрузки

    /// Папка `exports` в корне проекта — путь известен при сборке; песочница пускает туда после одного выбора
    private static let projectExports = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("exports", isDirectory: true)

    /// Выбрана один раз, дальше — по закладке без вопросов
    private func exportFolder() -> URL? {
        if let data = UserDefaults.standard.data(forKey: "exportBookmark"),
           let url = FolderAccess.resolveBookmark(data) {
            return url
        }
        let panel = NSOpenPanel()
        panel.message = "Папка для выгрузок CSV и JSON — выберите exports в проекте, дальше вопросов не будет"
        panel.prompt = "Выбрать"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = Self.projectExports
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if let data = FolderAccess.bookmark(for: url) {
            UserDefaults.standard.set(data, forKey: "exportBookmark")
        }
        return url
    }

    /// Без окна сохранения: имя — папка и время выгрузки, старые файлы не перезаписываются
    private func export(_ data: Data, name: String, ext: String) {
        guard let folder = exportFolder() else { return }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let base = "\(name)_\(stamp.string(from: Date()))"
        var file = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = folder.appendingPathComponent("\(base)_\(n)").appendingPathExtension(ext)
            n += 1
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .withoutOverwriting)
            session.flash("Сохранено: \(file.lastPathComponent)", kind: .done)
        } catch {
            session.flash("Не удалось сохранить \(ext.uppercased())", kind: .error)
        }
    }

    private func csv() -> String {
        func number(_ value: Double?) -> String {
            value.map { String(format: "%.5f", $0) } ?? ""
        }
        let reasons = DefectReason.rules
        var header = ["file", "capture_time", "gap_prev_s", "print_dist_prev", "label", "flagged", "reasons"]
        header += reasons.map { "value_\($0.rawValue)" }
        header += reasons.map { "conf_\($0.rawValue)" }
        header += ["sharpness", "sharpness_global", "detail_ratio", "detail_ratio_global", "subject_luma",
                   "mean_luma", "clip_high", "clip_low", "clip_white", "horizon", "aesthetics", "utility",
                   "exposure", "faces", "face_luma_min", "eyes_min", "full_sharpness", "full_detail",
                   "series", "series_size", "rel_sharpness", "rel_detail", "face_quality", "rel_face_quality", "model_p",
                   "clip_dist_prev", "p_blur", "p_motion", "p_closed_max", "p_accidental", "p_over",
                   "face_white_max", "subject_white"]
        var lines = [header.joined(separator: ",")]
        for url in session.allPhotos {
            guard let m = store.metrics(for: url) else { continue }
            let label = store.label(url).map { $0 ? "bad" : "good" } ?? ""
            let flagged = store.defects(for: url)
            let candidates = store.candidates[url] ?? []
            let neighbor = store.neighbors[url]
            let time = m.captureDate.map { String(format: "%.2f", $0.timeIntervalSince1970) } ?? ""
            var row = ["\"\(url.lastPathComponent.replacingOccurrences(of: "\"", with: "\"\""))\"",
                       time, number(neighbor?.gap), number(neighbor?.distance), label,
                       flagged.isEmpty ? "0" : "1",
                       flagged.map(\.reason.rawValue).joined(separator: "+")]
            let context = store.contexts[url]
            row += reasons.map { number(DefectRules.value($0, m, context: context, stats: store.folderStats)) }
            row += reasons.map { reason in number(candidates.first { $0.reason == reason }?.confidence) }
            let eyes = m.faces.compactMap { face -> Double? in
                guard let l = face.leftEye, let r = face.rightEye else { return nil }
                return max(l, r)
            }.min()
            row += [number(m.sharpness), number(m.sharpnessGlobal), number(m.detailRatio), number(m.detailRatioGlobal),
                    number(m.subjectLuma), number(m.meanLuma), number(m.clipHigh), number(m.clipLow), number(m.clipWhite),
                    number(m.horizonAngle), number(m.aesthetics), m.isUtility.map { $0 ? "1" : "0" } ?? "",
                    number(m.exposureTime), "\(m.faces.count)", number(m.faces.compactMap(\.luma).min()), number(eyes),
                    number(m.fullSharpness), number(m.fullDetailRatio),
                    context?.series.map { "\($0)" } ?? "", "\(context?.seriesSize ?? 1)",
                    number(context?.relSharpness), number(context?.relDetail),
                    number(SeriesGrouping.faceQuality(m)), number(context?.relFaceQuality),
                    number(store.probabilities[url])]
            let signal = store.signals[url]
            row += [number(neighbor?.clip), number(signal?.blur), number(signal?.motion),
                    number(signal?.closedMax), number(signal?.accidental), number(signal?.overexposed),
                    number(m.faces.compactMap(\.white).max()), number(m.subjectWhite)]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
    #endif
}

// MARK: - Оценки модели

/// Оценка модели на графике и причина правил, с которой её сравниваем
private enum ModelPlot: String, CaseIterable, Identifiable {
    case blur
    case motion
    case closed
    case accidental
    case overexposed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blur: "Модель: не в фокусе"
        case .motion: "Модель: смаз кадра"
        case .closed: "Модель: закрыты глаза"
        case .accidental: "Модель: случайный кадр"
        case .overexposed: "Модель: пересвет"
        }
    }

    var reason: DefectReason {
        switch self {
        case .blur, .motion: .blur
        case .closed: .eyesClosed
        case .accidental: .accidental
        case .overexposed: .overexposed
        }
    }

    func value(_ signal: ModelSignals) -> Double? {
        switch self {
        case .blur: signal.blur
        case .motion: signal.motion
        case .closed: signal.closedMax
        case .accidental: signal.accidental
        case .overexposed: signal.overexposed
        }
    }
}

// MARK: - График-полоска

private struct StripPlot: View {
    let points: [CalibrationPoint]
    let scale: DefectScale
    /// Граница брака при текущей строгости; nil — без границы (оценки модели)
    let boundary: Double?
    let current: URL?
    let onPick: (URL) -> Void

    @Environment(\.theme) private var theme

    private func x(_ value: Double, _ width: CGFloat) -> CGFloat {
        let lo = scale.range.lowerBound
        let hi = scale.range.upperBound
        let t = min(1, max(0, (value - lo) / (hi - lo)))
        return 4 + CGFloat(t) * (width - 8)
    }

    private func y(_ jitter: Double, _ height: CGFloat) -> CGFloat {
        6 + CGFloat(jitter) * (height - 12)
    }

    var body: some View {
        let c = theme.c
        GeometryReader { geo in
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(c.surface2.opacity(0.6)))

                // Зона брака при текущей строгости и граница
                if let boundary {
                    let xe = x(boundary, size.width)
                    let zone = scale.defectBelow
                        ? CGRect(x: 0, y: 0, width: xe, height: size.height)
                        : CGRect(x: xe, y: 0, width: size.width - xe, height: size.height)
                    context.fill(Path(zone), with: .color(c.danger.opacity(0.12)))

                    var line = Path()
                    line.move(to: CGPoint(x: xe, y: 0))
                    line.addLine(to: CGPoint(x: xe, y: size.height))
                    context.stroke(line, with: .color(c.accent), lineWidth: 1.5)
                }

                // Сначала неразмеченные, сверху — размеченные
                for point in points where point.label == nil {
                    let center = CGPoint(x: x(point.value, size.width), y: y(point.jitter, size.height))
                    let dot = Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
                    context.fill(dot, with: .color(point.flagged ? c.warning.opacity(0.9) : c.text3.opacity(0.55)))
                }
                for point in points {
                    guard let label = point.label else { continue }
                    let center = CGPoint(x: x(point.value, size.width), y: y(point.jitter, size.height))
                    let dot = Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
                    context.fill(dot, with: .color(label ? c.danger : c.success))
                }
                if let current, let point = points.first(where: { $0.url == current }) {
                    let center = CGPoint(x: x(point.value, size.width), y: y(point.jitter, size.height))
                    let ring = Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
                    context.stroke(ring, with: .color(c.text1), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                pick(at: location, size: geo.size)
            }
        }
        .help(scale.name)
    }

    private func pick(at location: CGPoint, size: CGSize) {
        var best: (url: URL, distance: CGFloat)?
        for point in points {
            let dx = x(point.value, size.width) - location.x
            let dy = y(point.jitter, size.height) - location.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < 10, distance < (best?.distance ?? .infinity) {
                best = (point.url, distance)
            }
        }
        if let best { onPick(best.url) }
    }
}
