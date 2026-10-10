import AppKit
import CoreGraphics
import SwiftUI

/// Сетка всех фото. Вход/выход в полноэкранный просмотр — F, двойной клик или Return
struct GridView: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme
    @State private var gridWidth: CGFloat = 0
    /// Выделенные кадры (⌘A, ⌘‑клик, ⇧‑клик) — для копирования; текущий кадр — session.index
    @State private var selection: Set<URL> = []
    @AppStorage("marksEnabled") private var marksEnabled = false

    private let defaultSize: CGFloat = 230

    private var spacing: CGFloat { theme.gridGap }
    private var padding: CGFloat { max(theme.gridGap, 8) }

    /// Число колонок считаем сами, чтобы стрелки ↑↓ прыгали ровно на строку
    private var columnCount: Int {
        let usable = gridWidth - padding * 2
        guard usable > 0 else { return 1 }
        return max(1, Int((usable + spacing) / (session.gridThumbSize + spacing)))
    }

    var body: some View {
        let c = theme.c
        VStack(spacing: 0) {
            topbar
            HStack(spacing: 0) {
                grid
                if session.showCalibration && session.sectionsAvailable {
                    CalibrationPanel(session: session)
                        .padding(theme.isGlass ? 12 : 0)
                        .transition(.move(edge: .trailing))
                }
                if session.showInfo, let url = session.currentPhoto {
                    InfoPanel(url: url, companions: session.companions(of: url))
                        .padding(theme.isGlass ? 12 : 0)
                        .transition(.move(edge: .trailing))
                }
            }
            HintBar(groups: [
                HintGroup(title: "Выбор", hints: [
                    Hint("←", "→", "↑", "↓", label: "кадр"),
                    Hint("↩", label: "просмотр"),
                    Hint("⌘A", label: "все"),
                    Hint("⌘C", label: "копировать")
                ]),
                HintGroup(title: "Отбор", hints: [
                    Hint("1–9", label: "в папку"),
                    Hint("⌫", label: "корзина"),
                    Hint("Z", label: "отмена")
                ])
            ] + (marksEnabled ? [MarkHints.group] : []) + [
                HintGroup(title: "Вид", hints: [
                    Hint("I", label: "инфо"),
                    Hint("C", label: "сравнить"),
                    Hint("Esc", label: "выйти")
                ])
            ])
        }
        .background(theme.isContact ? c.canvas : c.app)
        .overlay { ToastOverlay(toast: session.toast) }
        .onChange(of: session.section) { _, _ in
            selection = []
        }
        .onChange(of: marksEnabled) { _, _ in
            // Функцию выключили — фильтр не должен прятать кадры без кнопки, которой его снять
            session.markFilter = MarkFilter()
        }
        .background(
            KeyCatcher(
                onKeyDown: { handleEvent($0) },
                onMagnify: { delta, _, _ in
                    session.setGridSize(session.gridThumbSize * (1 + delta))
                },
                onCopy: { copyFiles(currentTargets) },
                onSelectAll: { selectAll() }
            )
        )
    }

    // MARK: - Верхняя панель

    private var topbar: some View {
        let c = theme.c
        return HStack(spacing: 12) {
            capsuleGroup {
                Button {
                    session.stopReview()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Выйти")
                    }
                }
                .buttonStyle(PCButtonStyle(kind: .ghost))
                .help("К выбору папки (Esc)")
            }

            if theme.isStudio || theme.isContact {
                Rectangle().fill(c.line).frame(width: 1, height: 16)
            }

            capsuleGroup(text: true) {
                HStack(spacing: 12) {
                    Text(session.sourceURL?.lastPathComponent ?? "")
                        .font(folderFont)
                        .foregroundStyle(theme.isQuiet ? c.text2 : c.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    counter
                    if !selection.isEmpty {
                        Text("выбрано \(selection.count)")
                            .font(theme.numFont)
                            .foregroundStyle(c.accent)
                    }
                }
            }

            if session.sectionsAvailable {
                capsuleGroup {
                    sectionSwitcher
                }
            }

            if marksEnabled {
                capsuleGroup {
                    markFilterMenu
                }
            }

            Spacer(minLength: 12)

            capsuleGroup {
                HStack(spacing: 6) {
                    Button {
                        session.startCompare()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Сравнить")
                            KeyCap("C", size: .small)
                        }
                    }
                    .buttonStyle(PCButtonStyle(kind: .ghost))
                    .help("Сравнить выбранный кадр с соседним")

                    if session.sectionsAvailable {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { session.showCalibration.toggle() }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(PCIconButtonStyle(isOn: session.showCalibration))
                        .help("Калибровка брака (⌥⌘K)")
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { session.showInfo.toggle() }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(PCIconButtonStyle(isOn: session.showInfo))
                    .help("Сведения о снимке (I)")
                }
            }

            capsuleGroup(text: true) {
                HStack(spacing: 8) {
                    Button {
                        session.setGridSize(session.gridThumbSize / 1.2)
                    } label: {
                        Image(systemName: "photo").font(.system(size: 10))
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
                    .frame(width: 120)
                    .help("Размер миниатюр")

                    Button {
                        session.setGridSize(session.gridThumbSize * 1.2)
                    } label: {
                        Image(systemName: "photo").font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .help("Крупнее (+)")
                }
                .foregroundStyle(c.text2)
            }
        }
        .padding(.horizontal, theme.isGlass ? 16 : 12)
        .padding(.top, theme.isGlass ? 12 : 0)
        .frame(height: theme.topbarHeight + (theme.isGlass ? 8 : 0))
        .background(theme.isGlass || theme.isQuiet ? Color.clear : c.surface1)
        .overlay(alignment: .bottom) {
            if !theme.isGlass && !theme.isQuiet {
                Rectangle().fill(c.line).frame(height: 1)
            }
        }
    }

    private var folderFont: Font {
        switch theme.direction {
        case .contact: .system(size: 15, weight: .semibold, design: .serif)
        case .quiet: .system(size: 12)
        case .studio, .glass: .system(size: 13, weight: .semibold)
        }
    }

    /// «12 / 480» — текущий кадр ярче
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

    /// У «Стекла» группы — плавающие стеклянные капсулы; у остальных — просто содержимое
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

    // MARK: - Сетка

    // MARK: - Звёзды и цвета

    /// Фильтр по звёздам и цвету и запись в XMP
    private var markFilterMenu: some View {
        let filter = session.markFilter
        return Menu {
            Section("Звёзд не меньше") {
                ForEach(0...5, id: \.self) { n in
                    Toggle(n == 0 ? "Любые" : String(repeating: "★", count: n), isOn: Binding(
                        get: { filter.minRating == n },
                        set: { _ in session.markFilter.minRating = n }
                    ))
                }
            }
            Section("Цвет") {
                Toggle("Без цвета", isOn: colorBinding(0))
                ForEach(ColorClass.allCases) { color in
                    Toggle(isOn: colorBinding(color.rawValue)) {
                        Label { Text(color.title) } icon: { Image(nsImage: color.menuDot) }
                    }
                }
            }
            Divider()
            Button("Сбросить фильтр") {
                session.markFilter = MarkFilter()
            }
            .disabled(!filter.isActive)
            Divider()
            Button("Записать звёзды и цвета в XMP") {
                session.exportMarks()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filter.isActive
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                Text(filter.summary)
            }
            .foregroundStyle(filter.isActive ? theme.c.accent : theme.c.text2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(session.section == .series
              ? "Фильтр по звёздам и цвету — в «Все фото», «Браке» и «Людях»; серии показываются целиком"
              : "Фильтр по звёздам и цвету")
    }

    private func colorBinding(_ color: Int) -> Binding<Bool> {
        Binding(
            get: { session.markFilter.colors.contains(color) },
            set: { on in
                if on {
                    session.markFilter.colors.insert(color)
                } else {
                    session.markFilter.colors.remove(color)
                }
            }
        )
    }

    // MARK: - Разделы

    /// «Все фото 812 · Брак 37 · Серии 12»
    private var sectionSwitcher: some View {
        PCSegmented(
            items: [
                PCSegmentItem(id: 0, title: PhotoSection.all.title, detail: "\(session.allPhotos.count)", help: "Все фото (⌘1)"),
                PCSegmentItem(
                    id: 1,
                    title: PhotoSection.defects.title,
                    detail: "\(session.defectPhotos.count)",
                    // Пока брака не найдено и анализ идёт — крутилка; найденное показываем сразу
                    busy: analysis.isRunning && session.defectPhotos.isEmpty,
                    help: analysisHelp("Кадры с техническим браком (⌘2)")
                ),
                PCSegmentItem(
                    id: 2,
                    title: PhotoSection.series.title,
                    detail: "\(session.seriesCount)",
                    busy: analysis.isRunning && session.seriesCount == 0,
                    help: analysisHelp("Серии похожих кадров (⌘3)")
                )
            ] + (PhotoAnalyzer.peopleEnabled ? [
                PCSegmentItem(
                    id: 3,
                    title: PhotoSection.people.title,
                    detail: "\(session.peopleGroups.count)",
                    busy: (analysis.isRunning || analysis.isGroupingPeople) && session.peopleGroups.isEmpty,
                    help: analysisHelp("Люди, которые встречаются на нескольких кадрах (⌘4)")
                )
            ] : []),
            selected: sectionID(session.section)
        ) { id in
            session.showSection([PhotoSection.all, .defects, .series, .people][id])
        }
    }

    private var analysis: AnalysisStore { AnalysisStore.shared }

    /// Пока идёт анализ — «Анализ: 412 из 812»
    private func analysisHelp(_ base: String) -> String {
        analysis.isRunning ? "\(base). Анализ: \(analysis.done) из \(analysis.total)" : base
    }

        private func sectionID(_ section: PhotoSection) -> Int {
        switch section {
        case .all: 0
        case .defects: 1
        case .series: 2
        case .people: 3
        }
    }

    private var emptySectionNote: String {
        if analysis.isRunning {
            return "Анализ ещё идёт: \(analysis.done) из \(analysis.total)"
        }
        if session.section == .defects {
            return "При строгости «\(analysis.strictness.title)». Строгость меняется в Настройках (⌘,)"
        }
        if session.section == .people {
            if analysis.isGroupingPeople { return "Группирую лица…" }
            return "Человек — похожие лица, которые встречаются хотя бы на двух кадрах. Лица меньше 40 px не учитываются"
        }
        return "Серия — кадры, снятые подряд с интервалом до 3 секунд и похожие друг на друга"
    }

    /// Пустой раздел: не прячем, а объясняем
    private var emptySection: some View {
        let c = theme.c
        return VStack(spacing: 10) {
            Image(systemName: session.section == .defects ? "checkmark.seal"
                  : session.section == .people ? "person.2.slash" : "square.stack.3d.up.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(c.text3)
            Text(session.section == .defects ? "Брака не нашлось"
                 : session.section == .people ? "Людей не нашлось" : "Серий не нашлось")
                .font(theme.headingFont)
                .foregroundStyle(c.text1)
            Text(emptySectionNote)
                .font(.system(size: 12))
                .foregroundStyle(c.text3)
                .multilineTextAlignment(.center)
            Button("Все фото") {
                session.showSection(.all)
            }
            .buttonStyle(PCButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var grid: some View {
        if session.section == .people && !session.isPersonOpened {
            if session.peopleGroups.isEmpty {
                emptySection
            } else {
                peopleTiles
            }
        } else if session.photos.isEmpty {
            emptySection
        } else {
            gridContent
        }
    }

    // MARK: - Люди

    /// Плитки людей: лицо, номер, число кадров. Клик — кадры этого человека
    private var peopleTiles: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: max(130, session.gridThumbSize * 0.7)), spacing: spacing)],
                spacing: spacing
            ) {
                ForEach(session.peopleGroups) { person in
                    PersonTile(person: person)
                        .onTapGesture { session.openPerson(person) }
                }
            }
            .padding(padding)
        }
    }

    /// Над кадрами открытого человека: «‹ Все люди · Человек 3 · 12 кадров»
    private func personHeader(_ person: PersonGroup) -> some View {
        let c = theme.c
        return HStack(spacing: 10) {
            Button {
                session.closePerson()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Все люди")
                    KeyCap("Esc", size: .small)
                }
            }
            .buttonStyle(PCButtonStyle(kind: .ghost))
            .focusable(false)
            FaceThumb(url: person.coverURL, rect: person.coverRect)
                .frame(width: 28, height: 28)
                .clipShape(Circle())
            Text("Человек \(person.number)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.text1)
            Text("\(person.photos.count) \(PhotoSession.plural(person.photos.count, "кадр", "кадра", "кадров"))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(c.text3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, padding)
        .padding(.top, padding)
    }

    private var gridContent: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    if let person = session.currentPerson {
                        personHeader(person)
                    }
                    if session.section == .series {
                        seriesList
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: spacing) {
                            ForEach(Array(session.photos.enumerated()), id: \.element) { item in
                                cell(item.offset, item.element)
                            }
                        }
                        .padding(padding)
                    }
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

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columnCount)
    }

    /// Ячейка кадра `index` раздела
    private func cell(_ index: Int, _ url: URL) -> some View {
        let best = session.seriesBest(url)
        return GridCell(
            url: url,
            number: index + 1,
            isSelected: index == session.index || selection.contains(url),
            compact: session.gridThumbSize < 160 || theme.isQuiet,
            hasNotes: session.hasAnnotations(url),
            extras: session.companions(of: url).map { $0.pathExtension.uppercased() },
            // Значок брака — только в «Все фото»: в разделе «Брак» он у всех
            defects: session.section == .all ? analysis.defects(for: url) : [],
            label: session.showCalibration ? analysis.label(url) : nil,
            bestNote: best?.bestNote,
            // В «Браке» — причина вместо модели камеры
            reasons: session.section == .defects ? analysis.defects(for: url) : [],
            mark: marksEnabled ? MarkStore.shared.mark(url) : nil,
            onMark: { session.applyMark($0, to: [url]) }
        )
        .id(url)
        .onTapGesture(count: 2) {
            session.open(index)
        }
        .simultaneousGesture(
            TapGesture().onEnded { click(index) }
        )
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { _ in startDrag(index) }
        )
        .contextMenu { contextMenu(index) }
    }

    // MARK: - Серии

    /// Серии с заголовками; каждая начинается с новой строки
    private var seriesList: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(session.visibleSeries) { block in
                VStack(alignment: .leading, spacing: 10) {
                    seriesHeader(block)
                    LazyVGrid(columns: gridColumns, spacing: spacing) {
                        ForEach(block.range, id: \.self) { i in
                            if session.photos.indices.contains(i) {
                                cell(i, session.photos[i])
                            }
                        }
                    }
                }
                // Своя метка: без неё у серии тот же id, что у её первого кадра
                .id(seriesAnchor(block))
            }
        }
        .padding(padding)
    }

    private func seriesHeader(_ block: SeriesBlock) -> some View {
        let c = theme.c
        let opened = session.isSeriesOpened
        return HStack(spacing: 10) {
            if opened {
                Button {
                    session.closeSeries()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Все серии")
                        KeyCap("Esc", size: .small)
                    }
                }
                .buttonStyle(PCButtonStyle(kind: .ghost))
                .focusable(false)
            }
            Text("Серия \(block.number)")
                .font(theme.isContact ? .system(size: 14, weight: .semibold, design: .serif) : .system(size: 13, weight: .semibold))
                .foregroundStyle(c.text1)
            Text(seriesDetails(block))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(c.text3)
            Spacer(minLength: 8)
            if !opened {
                Button("Открыть") {
                    session.openSeries(block)
                }
                .buttonStyle(PCButtonStyle(kind: .ghost))
                .focusable(false)
                .help("Показать только эту серию")
            }
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            if !theme.isQuiet {
                Rectangle().fill(c.line).frame(height: 1).offset(y: 5)
            }
        }
    }

    /// «8 кадров · 14:32:05 · 2,4 с»
    private func seriesDetails(_ block: SeriesBlock) -> String {
        let count = block.members.count
        var parts = ["\(count) \(PhotoSession.plural(count, "кадр", "кадра", "кадров"))"]
        if let start = block.start {
            parts.append(start.formatted(date: .omitted, time: .standard))
        }
        if block.duration > 0 {
            parts.append(String(format: "%.1f с", block.duration).replacingOccurrences(of: ".", with: ","))
        }
        return parts.joined(separator: " · ")
    }

    private func seriesAnchor(_ block: SeriesBlock) -> String {
        "series-" + block.id.path
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, anchor: UnitPoint?, animated: Bool) {
        guard let url = session.currentPhoto else { return }
        // В «Сериях» кадры лежат в сетках внутри ленивого списка: до ещё не созданной ячейки scrollTo
        // не достаёт, и после просмотра сетка оставалась наверху. Сначала — к серии, потом к кадру
        if !animated, session.section == .series,
           let block = session.visibleSeries.first(where: { $0.range.contains(session.index) }) {
            proxy.scrollTo(seriesAnchor(block), anchor: .top)
            DispatchQueue.main.async {
                proxy.scrollTo(url, anchor: anchor)
            }
            return
        }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(url, anchor: anchor)
            }
        } else {
            proxy.scrollTo(url, anchor: anchor)
        }
    }

    // MARK: - Выбор и копирование

    /// Клик: просто — один кадр; ⌘ — добавить/убрать; ⇧ — диапазон от текущего
    private func click(_ index: Int) {
        guard session.photos.indices.contains(index) else { return }
        let url = session.photos[index]
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.isEmpty, let current = session.currentPhoto {
                selection.insert(current)
            }
            if selection.contains(url) {
                selection.remove(url)
            } else {
                selection.insert(url)
            }
        } else if flags.contains(.shift) {
            let range = min(session.index, index)...max(session.index, index)
            selection.formUnion(range.compactMap { session.photos.indices.contains($0) ? session.photos[$0] : nil })
        } else {
            selection = []
        }
        session.select(index)
    }

    private func selectAll() {
        selection = Set(session.photos)
        session.flash("Выбрано \(session.photos.count)", key: "⌘A")
    }

    /// Что копировать сейчас: выделение, а если его нет — текущий кадр
    private var currentTargets: [URL] {
        let alive = session.photos.filter { selection.contains($0) }
        if !alive.isEmpty { return alive }
        return session.currentPhoto.map { [$0] } ?? []
    }

    /// Для клика правой кнопкой или перетаскивания: выделение, если кадр в нём, иначе только этот кадр
    private func targets(for index: Int) -> [URL] {
        guard session.photos.indices.contains(index) else { return [] }
        let url = session.photos[index]
        if selection.contains(url) {
            return session.photos.filter { selection.contains($0) }
        }
        return [url]
    }

    /// Все файлы кадров, включая парные RAW
    private func files(of urls: [URL]) -> [URL] {
        urls.flatMap { [$0] + session.companions(of: $0) }
    }

    /// Кладёт файлы в буфер обмена — вставляются в Finder, почту, мессенджеры как файлы
    private func copyFiles(_ urls: [URL]) {
        let all = files(of: urls)
        guard !all.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(all.map { $0 as NSURL })
        let word = PhotoSession.plural(all.count, "файл", "файла", "файлов")
        session.flash("Скопировано · \(all.count) \(word)", key: "⌘C", kind: .done)
    }

    private func startDrag(_ index: Int) {
        guard !FileDrag.isDragging, session.photos.indices.contains(index) else { return }
        let url = session.photos[index]
        if !selection.contains(url) {
            selection = []
            session.select(index)
        }
        let urls = targets(for: index)
        FileDrag.begin(files: files(of: urls), preview: ThumbnailLoader.cached(url)?.image, count: urls.count)
    }

    @ViewBuilder
    private func contextMenu(_ index: Int) -> some View {
        let urls = targets(for: index)
        let count = files(of: urls).count
        Button(count > 1 ? "Скопировать \(count) \(PhotoSession.plural(count, "файл", "файла", "файлов"))" : "Скопировать файл") {
            copyFiles(urls)
        }
        Button("Показать в Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(files(of: urls))
        }
        Divider()
        Button("Открыть") {
            session.open(index)
        }
        Button("Выбрать все") {
            selectAll()
        }
        if marksEnabled {
            Divider()
            Menu("Звёзды") {
                ForEach(0...5, id: \.self) { n in
                    Button(n == 0 ? "Без звёзд (⌥0)" : "\(String(repeating: "★", count: n)) (⌥\(n))") {
                        session.applyMark(.rating(n), to: urls)
                    }
                }
            }
            Menu("Цвет") {
                Button("Без цвета (⌃0)") { session.applyMark(.color(0), to: urls) }
                ForEach(ColorClass.allCases) { color in
                    Button {
                        session.applyMark(.color(color.rawValue), to: urls)
                    } label: {
                        Label { Text("\(color.title) (⌃\(color.rawValue))") } icon: { Image(nsImage: color.menuDot) }
                    }
                }
            }
            Button("Записать в XMP") {
                session.exportMarks(urls)
            }
        }
        if session.sectionsAvailable {
            Divider()
            Menu("Калибровка брака") {
                Button("Это брак") { analysis.setLabel(urls, true) }
                Button("Это норма") { analysis.setLabel(urls, false) }
                Button("Снять разметку") { analysis.setLabel(urls, nil) }
                Divider()
                Button(session.showCalibration ? "Скрыть панель калибровки" : "Показать панель калибровки") {
                    withAnimation(.easeOut(duration: 0.2)) { session.showCalibration.toggle() }
                }
            }
        }
        if !selection.isEmpty {
            Button("Снять выделение") {
                selection = []
            }
        }
    }

    // MARK: - Клавиатура

    private func handleEvent(_ event: NSEvent) -> Bool {
        // ⌥0–⌥5 — звёзды, ⌃0–⌃8 — цвет: выделению, а без него — текущему кадру
        if let command = MarkCommand(event) {
            session.applyMark(command, to: currentTargets)
            return true
        }
        // Коды клавиш не зависят от раскладки
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 0: // ⌘A — выбрать все
                selectAll()
                return true
            case 8: // ⌘C — скопировать файлы
                copyFiles(currentTargets)
                return true
            default:
                break
            }
        }

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
        case 8: // C — сравнение
            session.startCompare()
        case 34: // I — сведения
            withAnimation(.easeOut(duration: 0.2)) { session.showInfo.toggle() }
        case 123: // ←
            session.select(session.index - 1)
        case 124, 49: // →, пробел
            session.select(session.index + 1)
        case 126: // ↑ (в списке серий — к предыдущей серии)
            if session.section == .series && !session.isSeriesOpened {
                session.jumpSeries(-1)
            } else {
                session.select(session.index - columns)
            }
        case 125: // ↓ (в списке серий — к следующей серии)
            if session.section == .series && !session.isSeriesOpened {
                session.jumpSeries(1)
            } else {
                session.select(min(session.index + columns, last))
            }
        case 115: // Home
            session.select(0)
        case 119: // End
            session.select(last)
        case 51, 117: // Delete
            session.trashCurrent()
        case 53: // Esc — сначала снять выделение, потом закрыть серию, потом выйти
            if !selection.isEmpty {
                selection = []
            } else if session.isSeriesOpened {
                session.closeSeries()
            } else if session.isPersonOpened {
                session.closePerson()
            } else {
                session.stopReview()
            }
        default:
            guard let first = event.charactersIgnoringModifiers?.first, first.isWholeNumber else {
                return false
            }
            session.handleShortcut(String(first))
        }
        return true
    }
}

// MARK: - Ячейка

private struct GridCell: View {
    let url: URL
    let number: Int
    let isSelected: Bool
    let compact: Bool
    let hasNotes: Bool
    /// Расширения остальных файлов кадра: ["NEF"] для пары JPG + NEF
    let extras: [String]
    /// Пометки брака (пусто — значка нет)
    var defects: [Defect] = []
    /// Ручная разметка для калибровки: true — брак, false — норма (видна, пока открыта панель)
    var label: Bool? = nil
    /// Лучший кадр серии — почему (nil — не лучший)
    var bestNote: String? = nil
    /// Причины брака для подписи (только в разделе «Брак»)
    var reasons: [Defect] = []
    /// Звёзды и цвет; nil — функция выключена
    var mark: PhotoMark? = nil
    var onMark: (MarkCommand) -> Void = { _ in }

    @Environment(\.theme) private var theme
    @State private var thumbnail: Thumbnail?
    @State private var hovered = false

    var body: some View {
        let c = theme.c
        let thumb = thumbnail ?? ThumbnailLoader.cached(url)
        let shape = RoundedRectangle(cornerRadius: theme.rMd)

        VStack(alignment: .leading, spacing: 0) {
            if theme.isContact {
                // Номер кадра, как на контактном листе
                Text("\(number)")
                    .font(theme.edgeFont)
                    .foregroundStyle(c.text3)
                    .lineLimit(1)
                    .frame(height: 14)
            }

            thumbArea(thumb)

            caption(thumb?.info)
                .padding(.top, theme.isQuiet ? 6 : 8)
        }
        .padding(cellPadding)
        .background(cellFill, in: shape)
        .overlay { selectionMark(shape) }
        .shadow(color: glow, radius: isSelected && theme.isGlass ? 4 : 0)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .task(id: url) {
            guard thumbnail == nil else { return }
            if let loaded = await ThumbnailLoader.load(url), !Task.isCancelled {
                thumbnail = loaded
            }
        }
    }

    private var cellPadding: EdgeInsets {
        switch theme.direction {
        case .studio: EdgeInsets(top: 10, leading: 10, bottom: 8, trailing: 10)
        case .glass: EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12)
        case .quiet: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        case .contact: EdgeInsets(top: 4, leading: 6, bottom: 6, trailing: 6)
        }
    }

    private var cellFill: Color {
        let c = theme.c
        // Цветовая метка — подложка ячейки; выделение важнее
        if !isSelected, let color = mark.flatMap({ ColorClass(rawValue: $0.color) }) {
            return color.color.opacity(hovered ? 0.3 : 0.22)
        }
        switch theme.direction {
        case .studio:
            return isSelected ? c.selectionFill : (hovered ? c.surface1 : .clear)
        case .glass:
            return isSelected ? c.selectionFill : (hovered ? c.surface2 : c.surface1)
        case .quiet:
            return hovered && !isSelected ? c.surface1 : .clear
        case .contact:
            return hovered && !isSelected ? c.surface1 : .clear
        }
    }

    private var glow: Color {
        guard isSelected, theme.isGlass else { return .clear }
        return theme.c.selection.opacity(0.35)
    }

    @ViewBuilder
    private func selectionMark(_ shape: RoundedRectangle) -> some View {
        if isSelected {
            let c = theme.c
            switch theme.direction {
            case .studio:
                shape.strokeBorder(c.selection, lineWidth: 2)
            case .glass:
                shape.strokeBorder(c.selection, lineWidth: 3)
            case .quiet:
                Rectangle().strokeBorder(c.selection, lineWidth: 1.5)
            case .contact:
                EmptyView() // у «Контакта» — уголки кадрирования вокруг миниатюры
            }
        }
    }

    private func thumbArea(_ thumb: Thumbnail?) -> some View {
        let c = theme.c
        let radius = theme.rSm
        return ZStack {
            if let image = thumb?.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: radius))
            } else if thumb == nil {
                // Загрузка: серая заглушка и индикатор
                RoundedRectangle(cornerRadius: radius)
                    .fill(c.surface2)
                    .aspectRatio(1.5, contentMode: .fit)
                    .padding(.horizontal, 20)
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(c.text3)
            }
        }
        .aspectRatio(theme.isContact ? 1.5 : 1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay {
            if isSelected && theme.isContact {
                CropCorners()
                    .stroke(c.selection, lineWidth: 2)
                    .padding(-6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hasNotes {
                noteBadge
                    .padding(6)
            }
        }
        .overlay(alignment: .topLeading) {
            if !defects.isEmpty {
                defectBadge
                    .padding(6)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let bestNote {
                bestBadge(bestNote)
                    .padding(6)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let label {
                Image(systemName: label ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white, label ? theme.c.danger : theme.c.success)
                    .padding(6)
                    .help(label ? "Размечено: брак" : "Размечено: норма")
            }
        }
    }

    /// «⚠︎ Размыто, Темно» — причины брака; подробности в подсказке
    private var reasonLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(theme.c.warning)
            Text(reasons.map(\.reason.title).joined(separator: ", "))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.c.text2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(reasons.map { $0.detail.isEmpty ? $0.reason.title : "\($0.reason.title): \($0.detail)" }.joined(separator: "\n"))
    }

    /// «★ Лучший» на лучшем кадре серии
    private func bestBadge(_ note: String) -> some View {
        let c = theme.c
        return HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
            Text("Лучший")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(c.onAccent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(c.accentFill, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .help(note)
    }

    /// Маленький значок брака; причины — в подсказке
    private var defectBadge: some View {
        let c = theme.c
        return Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(c.warning)
            .frame(width: 18, height: 18)
            .background {
                if !theme.isQuiet {
                    Circle().fill(c.overlay)
                    Circle().stroke(c.line, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(theme.isLight ? 0.15 : 0), radius: 1.5, y: 1)
            .help(defects.map { "\($0.reason.title): \($0.detail)" }.joined(separator: "\n"))
    }

    /// Значок «есть пометки» в правом верхнем углу миниатюры
    private var noteBadge: some View {
        let c = theme.c
        return Image(systemName: "pencil")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.isQuiet ? c.text1 : c.accent)
            .frame(width: 20, height: 20)
            .background {
                if !theme.isQuiet {
                    Circle().fill(c.overlay)
                    Circle().stroke(c.line, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(theme.isLight ? 0.15 : 0), radius: 1.5, y: 1)
            .help("Есть пометки")
    }

    @ViewBuilder
    private func caption(_ info: PhotoInfo?) -> some View {
        let c = theme.c
        if theme.isQuiet {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? c.text1 : c.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !extras.isEmpty {
                        pairTag
                    }
                    if let mark {
                        markEditor(mark)
                    }
                }
                if !reasons.isEmpty {
                    reasonLine
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(url.lastPathComponent)
                        .font(.system(size: theme.isContact ? 11 : 12, weight: .medium))
                        .foregroundStyle(thumbnail == nil && ThumbnailLoader.cached(url) == nil ? c.text2 : c.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !extras.isEmpty {
                        pairTag
                    }
                    if let mark, !mark.isEmpty || hovered || isSelected {
                        Spacer(minLength: 4)
                        markEditor(mark)
                    }
                }
                if !compact {
                    // Строки есть всегда, чтобы все ячейки были одной высоты
                    Text(details(info))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(c.text3)
                    if reasons.isEmpty {
                        Text(info?.camera ?? " ")
                            .font(.system(size: 11))
                            .foregroundStyle(c.text3)
                    } else {
                        reasonLine
                    }
                } else if !reasons.isEmpty {
                    reasonLine
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Звёзды и цвет: пустые видны при наведении и у выбранного кадра
    private func markEditor(_ mark: PhotoMark) -> some View {
        MarkEditor(
            mark: mark,
            size: 10,
            showsEmpty: hovered || isSelected,
            onRating: { onMark(.rating($0)) },
            onColor: { onMark(.color($0)) }
        )
    }

    /// Метка пары: «+NEF» — у кадра есть ещё и RAW
    private var pairTag: some View {
        Text("+" + extras.joined(separator: "+"))
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.c.text2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.c.lineStrong, lineWidth: 1))
            .fixedSize()
            .help("Кадр снят в нескольких форматах; переносится целиком")
    }

    private func details(_ info: PhotoInfo?) -> String {
        guard let info else { return " " }
        var parts: [String] = []
        if let size = info.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let w = info.pixelWidth, let h = info.pixelHeight {
            parts.append("\(w)×\(h)")
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}

/// Четыре уголка кадрирования («Контакт»: выделение кадра на контактном листе)
nonisolated struct CropCorners: Shape {
    var length: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let l = min(length, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        return path
    }
}

/// Перетаскивание файлов из сетки в Finder и другие приложения (копирование)
final class FileDrag: NSObject, NSDraggingSource {
    private static let shared = FileDrag()
    private(set) static var isDragging = false

    static func begin(files: [URL], preview: NSImage?, count: Int) {
        guard !files.isEmpty,
              let event = NSApp.currentEvent,
              let view = event.window?.contentView else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        let side: CGFloat = 72
        let items = files.enumerated().map { item -> NSDraggingItem in
            let dragItem = NSDraggingItem(pasteboardWriter: item.element as NSURL)
            // Первый файл — миниатюра кадра, остальные — стопкой за ним
            let image = (item.offset == 0 ? preview : nil) ?? NSWorkspace.shared.icon(forFile: item.element.path)
            let shift = CGFloat(min(item.offset, 4)) * 4
            dragItem.setDraggingFrame(
                NSRect(x: point.x - side / 2 + shift, y: point.y - side / 2 - shift, width: side, height: side),
                contents: image
            )
            return dragItem
        }
        isDragging = true
        let session = view.beginDraggingSession(with: items, event: event, source: shared)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        FileDrag.isDragging = false
    }
}

// MARK: - Плитка человека

/// Плитка в разделе «Люди»: лицо крупно, номер и число кадров
private struct PersonTile: View {
    let person: PersonGroup

    @Environment(\.theme) private var theme
    @State private var hovered = false

    var body: some View {
        let c = theme.c
        let shape = RoundedRectangle(cornerRadius: theme.rMd)
        VStack(spacing: 8) {
            FaceThumb(url: person.coverURL, rect: person.coverRect)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .overlay(Circle().stroke(c.line, lineWidth: 1))
                .padding(.horizontal, 12)
            VStack(spacing: 1) {
                Text("Человек \(person.number)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.text1)
                Text("\(person.photos.count) \(PhotoSession.plural(person.photos.count, "кадр", "кадра", "кадров"))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(c.text3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(hovered ? c.surface2 : c.surface1, in: shape)
        .contentShape(shape)
        .onHover { hovered = $0 }
        .help("Показать кадры с этим человеком")
    }
}

/// Лицо, вырезанное из миниатюры кадра (с полями, квадратом)
struct FaceThumb: View {
    let url: URL
    /// Лицо в долях кадра, начало сверху слева
    let rect: CGRect

    @Environment(\.theme) private var theme
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            theme.c.surface2
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .foregroundStyle(theme.c.text3)
            }
        }
        .task(id: "\(url.path)|\(rect.minX)|\(rect.minY)") {
            let thumb: Thumbnail?
            if let cached = ThumbnailLoader.cached(url) {
                thumb = cached
            } else {
                thumb = await ThumbnailLoader.load(url)
            }
            guard !Task.isCancelled, let source = thumb?.image,
                  let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            image = Self.crop(cg, rect: rect)
        }
    }

    /// Квадрат вокруг лица в 1,6 раза больше лица. У края кадра квадрат сдвигается внутрь, а не обрезается —
    /// иначе выходил прямоугольник и лицо уезжало из центра круга
    private static func crop(_ image: CGImage, rect: CGRect) -> NSImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let side = min(max(rect.width * w, rect.height * h) * 1.6, w, h)
        let x = min(max(0, rect.midX * w - side / 2), w - side)
        let y = min(max(0, rect.midY * h - side / 2), h - side)
        let square = CGRect(x: x, y: y, width: side, height: side).integral
        guard square.width >= 4, square.height >= 4, let cropped = image.cropping(to: square) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}
