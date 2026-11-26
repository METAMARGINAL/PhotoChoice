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
    @AppStorage(Pref.smartAnalysis) private var smartAnalysis = true
    @AppStorage(Feature.stars.key) private var starsOn = false
    @AppStorage(Feature.colors.key) private var colorsOn = false
    @AppStorage(Feature.flags.key) private var flagsOn = false
    @AppStorage(Feature.transfer.key) private var transferOn = true
    @AppStorage(Feature.compare.key) private var compareOn = true
    @AppStorage(Feature.info.key) private var infoOn = true
    @AppStorage(Pref.sortByCaptureDate) private var sortByCaptureDate = false
    @State private var showMarkFilter = false
    @FocusState private var searchFocused: Bool

    private let defaultSize: CGFloat = 230

    private var marksOn: Bool { starsOn || colorsOn || flagsOn }

    private var spacing: CGFloat { theme.gridGap }
    private var padding: CGFloat { theme.gridPadding }
    /// У «Стекла» сетка уходит под капсулы: первому ряду нужен отступ сверху
    private var topInset: CGFloat { theme.isGlass ? 70 : (theme.isFilm ? 10 : 0) }
    private var bottomInset: CGFloat { theme.isGlass ? theme.hintbarReserve + 8 : 0 }

    /// Число колонок считаем сами, чтобы стрелки ↑↓ прыгали ровно на строку
    private var columnCount: Int {
        let usable = gridWidth - padding * 2
        guard usable > 0 else { return 1 }
        return max(1, Int((usable + spacing) / (session.gridThumbSize + spacing)))
    }

    var body: some View {
        Group {
            if theme.isGlass {
                glassLayout
            } else {
                stackLayout
            }
        }
        .background { gridBackground }
        .overlay { ToastOverlay(toast: session.toast) }
        .onChange(of: session.section) { _, _ in
            selection = []
        }
        .onChange(of: searchFocused) { _, focused in
            session.isEditingText = focused
        }
        .onDisappear {
            session.isEditingText = false
        }
        .onChange(of: sortByCaptureDate) { _, _ in
            session.applySortOrder()
        }
        .onChange(of: [starsOn, colorsOn, flagsOn]) { _, _ in
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

    @ViewBuilder
    private var gridBackground: some View {
        if theme.isTable && theme.isLight {
            RadialGradient(
                colors: [Color(hex: 0xFBFBFA), Color(hex: 0xECEBE8)],
                center: .top, startRadius: 0, endRadius: 1400
            )
        } else {
            theme.c.app
        }
    }

    /// Панель, сетка, подсказки одна под другой
    private var stackLayout: some View {
        VStack(spacing: 0) {
            topbar
            HStack(spacing: 0) {
                if theme.isNeutral {
                    NeutralRail(session: session)
                }
                grid
                    .padding(.trailing, sideReserve)
                    .transaction(value: sideReserve) { $0.animation = nil }
            }
            .overlay(alignment: .trailing) { sidePanels }
            HintBar(groups: hintGroups)
        }
    }

    private var showsCalibration: Bool {
        session.showCalibration && session.sectionsAvailable
    }

    private var showsInfoPanel: Bool {
        infoOn && session.showInfo && session.currentPhoto != nil
    }

    /// Место под панели справа. Сетка перестраивается один раз и без анимации: панель выезжает поверх,
    /// а не сдвигает сотни ячеек на каждом кадре движения
    private var sideReserve: CGFloat {
        let glassPad: CGFloat = theme.isGlass ? 24 : 0
        return (showsCalibration ? CalibrationPanel.width + glassPad : 0) + (showsInfoPanel ? theme.panelWidth + glassPad : 0)
    }

    /// «Стекло»: кадры на весь экран, управление в капсулах поверх
    private var glassLayout: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                grid
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.black.opacity(0.62), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 96)
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                }
                .opacity(theme.isLight ? 0.25 : 1)
                .allowsHitTesting(false)
                VStack(spacing: 0) {
                    topbar
                    Spacer(minLength: 0)
                    HintBar(groups: hintGroups)
                }
            }
            .padding(.trailing, sideReserve)
            .transaction(value: sideReserve) { $0.animation = nil }
        }
        .overlay(alignment: .trailing) { sidePanels }
    }

    private var sidePanels: some View {
        HStack(spacing: 0) {
            if showsCalibration {
                CalibrationPanel(session: session)
                    .padding(theme.isGlass ? 12 : 0)
                    .transition(.move(edge: .trailing))
            }
            if showsInfoPanel, let url = session.currentPhoto {
                InfoPanel(url: url, companions: session.companions(of: url), revision: session.editRevision)
                    .padding(theme.isGlass ? 12 : 0)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var hintGroups: [HintGroup] {
        var view = [Hint("←", "→", "↑", "↓", label: "выбрать"), Hint("F", label: "открыть")]
        if infoOn { view.append(Hint("I", label: "сведения")) }
        if compareOn { view.append(Hint("C", label: "сравнить")) }
        view.append(Hint("Z", label: "отменить"))
        view.append(Hint("⌘C", label: "копировать"))
        view.append(Hint("⌘F", label: "поиск"))
        var groups = [HintGroup.targets(session), HintGroup(title: "Вид", hints: view)]
        if let marks = MarkHints.group {
            groups.append(marks)
        }
        return groups
    }

    // MARK: - Верхняя панель

    private var topbar: some View {
        let c = theme.c
        return HStack(spacing: theme.isGlass ? 10 : 14) {
            capsuleGroup {
                Button {
                    session.stopReview()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Выйти")
                    }
                }
                .buttonStyle(PCButtonStyle(kind: theme.isGlass ? .ghost : .secondary))
                .help("К выбору папки (Esc)")
            }

            capsuleGroup(text: true) {
                VStack(alignment: .leading, spacing: 1) {
                    titleBlock
                    if smartAnalysis && analysis.isRunning && session.section == .all {
                        Text(analysis.progressText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(c.text2)
                    }
                }
            }

            if session.sectionsAvailable && !theme.isNeutral {
                capsuleGroup {
                    sectionSwitcher
                }
            }

            if marksOn {
                capsuleGroup(text: true) {
                    markFilterMenu
                }
            }

            capsuleGroup(text: true) {
                searchField
            }

            Spacer(minLength: 12)

            capsuleGroup {
                HStack(spacing: 6) {
                    if compareOn {
                        Button {
                            session.startCompare()
                        } label: {
                            Image(systemName: "arrow.left.arrow.right")
                        }
                        .buttonStyle(PCIconButtonStyle())
                        .help("Сравнить выбранный кадр с соседним (C)")
                    }

                    if session.sectionsAvailable {
                        Button {
                            withAnimation(.easeOut(duration: 0.22)) { session.showCalibration.toggle() }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(PCIconButtonStyle(isOn: session.showCalibration))
                        .help("Калибровка брака (⌥⌘K)")
                    }
                }
            }

            capsuleGroup(text: true) {
                zoomSlider
            }

            if infoOn {
                capsuleGroup {
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
        .padding(.horizontal, theme.isGlass ? 14 : (theme.isNeutral ? 14 : (theme.isTable ? 32 : 24)))
        .padding(.top, theme.isGlass ? 14 : 0)
        .frame(height: theme.topbarHeight + (theme.isGlass ? 14 : 0))
        .background(theme.isNeutral ? Color(hex: 0x222222) : Color.clear)
        .foregroundStyle(c.text1)
    }

    /// Поиск по имени файла (⌘F): Return или клик по кадру — обратно к сетке, Esc — очистить
    private var searchField: some View {
        let c = theme.c
        let wide = searchFocused || !session.nameQuery.isEmpty
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(session.isSearching ? c.text1 : c.text3)
            TextField("Поиск по имени", text: $session.nameQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(c.text1)
                .focused($searchFocused)
                .frame(width: wide ? 170 : 110)
                .onSubmit { searchFocused = false }
                .onExitCommand {
                    session.nameQuery = ""
                    searchFocused = false
                }
            if !session.nameQuery.isEmpty {
                Button {
                    session.nameQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(c.text3)
                }
                .buttonStyle(.plain)
                .help("Очистить поиск")
            }
        }
        .padding(.horizontal, theme.isGlass ? 0 : 9)
        .frame(height: theme.isGlass ? 44 : (theme.isTable ? 32 : 28))
        .background {
            if !theme.isGlass {
                RoundedRectangle(cornerRadius: min(theme.rControl, 14))
                    .fill(theme.isTable && theme.isLight ? Color.white : c.surface2)
                    .overlay {
                        RoundedRectangle(cornerRadius: min(theme.rControl, 14))
                            .strokeBorder(searchFocused ? c.lineStrong : (theme.isLight ? c.line : Color.clear), lineWidth: 1)
                    }
            }
        }
        .contentShape(Rectangle())
        // Клик мимо текста (по лупе, по краю) — тоже в поле; самому полю клик не мешает
        .simultaneousGesture(TapGesture().onEnded { searchFocused = true })
        .help("Поиск по имени файла (⌘F). Любой кусок имени: «6481» найдёт DSCF6481.JPG. Несколько слов — все должны быть в имени, «4810-4830» — номера кадров")
    }

    /// Название папки и «Кадр 12 из 480»
    @ViewBuilder
    private var titleBlock: some View {
        let c = theme.c
        let name = session.sourceURL?.lastPathComponent ?? ""
        if theme.isTable {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(c.text1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    counter
                    selectionCount
                }
            }
        } else {
            HStack(spacing: 12) {
                Text(name)
                    .font(.system(size: theme.isFilm ? 15 : 14, weight: .semibold))
                    .foregroundStyle(c.text1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                counter
                selectionCount
            }
        }
    }

    @ViewBuilder
    private var selectionCount: some View {
        if !selection.isEmpty {
            Text("выбрано \(selection.count)")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(theme.isFilm ? theme.c.edge : theme.c.text1)
        }
    }

    /// «Кадр 12 из 480» — номер ярче
    private var counter: some View {
        let c = theme.c
        let total = session.photos.count
        let current = total == 0 ? 0 : session.index + 1
        return HStack(spacing: 0) {
            Text("Кадр ")
            Text("\(current)")
                .fontWeight(.semibold)
                .foregroundStyle(c.text1)
            Text(" из \(total)")
        }
        .font(.system(size: theme.isTable ? 13.5 : 13).monospacedDigit())
        .foregroundStyle(c.text2)
        .lineLimit(1)
    }

    private var zoomSlider: some View {
        HStack(spacing: 10) {
            Button {
                session.setGridSize(session.gridThumbSize / 1.2)
            } label: {
                Image(systemName: "rectangle").font(.system(size: 10))
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
            .frame(width: theme.isNeutral ? 110 : 120)
            .help("Размер миниатюр")

            Button {
                session.setGridSize(session.gridThumbSize * 1.2)
            } label: {
                Image(systemName: "rectangle").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Крупнее (+)")
        }
        .foregroundStyle(theme.c.text3)
    }

    /// У «Стекла» группы — плавающие стеклянные капсулы; у остальных — просто содержимое
    @ViewBuilder
    private func capsuleGroup<Content: View>(text: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        if theme.isGlass {
            content()
                .padding(.horizontal, text ? 18 : 5)
                .frame(height: 44)
                .pcGlass(in: .capsule)
        } else {
            content()
        }
    }

    // MARK: - Сетка

    // MARK: - Звёзды и цвета

    /// Кнопка фильтра; панель не закрывается после каждого выбора — можно отметить несколько звёзд и цветов
    private var markFilterMenu: some View {
        let filter = session.markFilter
        return Button {
            showMarkFilter.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filter.isActive
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                Text(filter.summary)
            }
            .foregroundStyle(filter.isActive ? theme.c.accent : theme.c.text2)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(session.section == .series
              ? "Фильтр по звёздам и цвету — в «Все фото», «Браке» и «Людях»; серии показываются целиком"
              : "Фильтр по звёздам и цвету")
        .popover(isPresented: $showMarkFilter, arrowEdge: .bottom) {
            MarkFilterPanel(session: session)
        }
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
            return analysis.progressText
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
    @ViewBuilder
    private var emptySection: some View {
        let filtered = session.isSearching || session.markFilter.isActive
        // Серии и плитки людей поиском не фильтруются
        if filtered && session.section != .series && !(session.section == .people && !session.isPersonOpened) {
            nothingFound
        } else {
            emptySectionContent
        }
    }

    /// Поиск или фильтр ничего не оставили
    private var nothingFound: some View {
        let c = theme.c
        let query = session.nameQuery.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(c.text3)
            Text("Ничего не нашлось")
                .font(theme.headingFont)
                .foregroundStyle(c.text1)
            Text(query.isEmpty ? "Ни один кадр не подходит под фильтр" : "Нет кадров с «\(query)» в имени" + (session.markFilter.isActive ? " и под фильтром" : ""))
                .font(.system(size: 12))
                .foregroundStyle(c.text3)
                .multilineTextAlignment(.center)
            Button(session.markFilter.isActive && session.isSearching ? "Сбросить поиск и фильтр" : (session.isSearching ? "Сбросить поиск" : "Сбросить фильтр")) {
                session.nameQuery = ""
                session.markFilter = MarkFilter()
            }
            .buttonStyle(PCButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySectionContent: some View {
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
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
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
        .padding(.top, padding + topInset)
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
                        LazyVGrid(columns: gridColumns, spacing: theme.gridRowGap) {
                            ForEach(Array(session.photos.enumerated()), id: \.element) { item in
                                cell(item.offset, item.element)
                            }
                        }
                        .padding(padding)
                        .padding(.top, topInset)
                        .padding(.bottom, bottomInset)
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
        let selected = index == session.index || selection.contains(url)
        return GridCell(
            url: url,
            number: index + 1,
            isSelected: selected,
            compact: session.gridThumbSize < 160,
            hasNotes: session.hasAnnotations(url),
            extras: session.companions(of: url).map { $0.pathExtension.uppercased() },
            // Значок брака — только в «Все фото»: в разделе «Брак» он у всех
            defects: smartAnalysis && session.section == .all ? analysis.defects(for: url) : [],
            label: session.showCalibration ? analysis.label(url) : nil,
            bestNote: best?.bestNote,
            // В «Браке» — причина вместо модели камеры
            reasons: session.section == .defects ? analysis.defects(for: url) : [],
            mark: marksOn ? MarkStore.shared.mark(url) : nil,
            revision: session.editRevision,
            adjusted: session.hasAdjustment(url),
            onMark: { session.applyMark($0, to: [url]) }
        )
        .zIndex(selected ? 1 : 0)
        .id(url)
        .onTapGesture(count: 2) {
            searchFocused = false
            session.open(index)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                searchFocused = false
                click(index)
            }
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
                    LazyVGrid(columns: gridColumns, spacing: theme.gridRowGap) {
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
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
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
                .font(theme.isFilm ? Theme.condensed(17) : .system(size: 13, weight: .semibold))
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
            Rectangle().fill(c.line).frame(height: 1).offset(y: 5)
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
        // Без анимации: при отборе ноутбук декодирует кадры, а не рисует переходы
        proxy.scrollTo(url, anchor: anchor)
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
        FileActionsMenu(session: session, photos: urls)
        Divider()
        Button("Открыть") {
            session.open(index)
        }
        Button("Выбрать все") {
            selectAll()
        }
        if marksOn {
            Divider()
            if starsOn {
                Menu("Звёзды") {
                    ForEach(0...5, id: \.self) { n in
                        Button(n == 0 ? "Без звёзд (⌥0)" : "\(String(repeating: "★", count: n)) (⌥\(n))") {
                            session.applyMark(.rating(n), to: urls)
                        }
                    }
                }
            }
            if colorsOn {
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
            }
            if flagsOn {
                Menu("Флаг") {
                    ForEach([PhotoFlag.pick, .reject, .off], id: \.rawValue) { flag in
                        Button("\(flag.title) (\(flag.key))") {
                            session.applyMark(.flag(flag.rawValue), to: urls)
                        }
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
            case 3: // ⌘F — поиск по имени
                searchFocused = true
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
            guard compareOn else { return false }
            session.startCompare()
        case 34: // I — сведения
            guard infoOn else { return false }
            withAnimation(.easeOut(duration: 0.22)) { session.showInfo.toggle() }
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
        case 53: // Esc — сначала снять выделение и поиск, потом закрыть серию, потом выйти
            if !selection.isEmpty {
                selection = []
            } else if session.isSearching {
                session.nameQuery = ""
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
    /// Звёзды, цвет и флаг; nil — функции выключены
    var mark: PhotoMark? = nil
    /// `session.editRevision`: кадр сохранили в другой программе — перечитать миниатюру
    var revision = 0
    /// Есть коррекция ползунками (миниатюра — без неё)
    var adjusted = false
    var onMark: (MarkCommand) -> Void = { _ in }

    @Environment(\.theme) private var theme
    @State private var thumbnail: Thumbnail?
    @State private var hovered = false

    /// Отклонённый флагом кадр приглушён
    private var rejected: Bool { mark?.flag == PhotoFlag.reject.rawValue }

    var body: some View {
        let thumb = thumbnail ?? ThumbnailLoader.cached(url)
        Group {
            switch theme.direction {
            case .film: filmCell(thumb)
            case .glass: glassCell(thumb)
            case .neutral: neutralCell(thumb)
            case .table: tableCell(thumb)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .task(id: "\(url.path)#\(revision)") {
            guard thumbnail == nil || ThumbnailLoader.cached(url) == nil else { return }
            if let loaded = await ThumbnailLoader.load(url), !Task.isCancelled {
                thumbnail = loaded
            }
        }
    }

    // MARK: Темы

    /// «Плёнка»: кадр на ленте, снизу край плёнки — номер и имя файла; выбранный обведён карандашом
    private func filmCell(_ thumb: Thumbnail?) -> some View {
        let c = theme.c
        return VStack(alignment: .leading, spacing: 0) {
            picture(thumb)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            HStack(spacing: 7) {
                Text("\(number)")
                    .font(theme.edgeFont)
                    .tracking(0.75)
                    .foregroundStyle(hovered ? Color(hex: 0xF6BB61) : c.edge)
                Spacer(minLength: 4)
                if let mark {
                    markEditor(mark)
                }
                if hasNotes {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(c.text3)
                        .help("Есть пометки")
                }
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(Theme.condensed(14, .medium))
                    .tracking(0.4)
                    .foregroundStyle(isSelected ? c.text1 : c.text3)
                    .truncationMode(.middle)
                if !extras.isEmpty {
                    Text("+" + extras.joined(separator: "+"))
                        .font(Theme.condensed(12, .medium))
                        .foregroundStyle(c.text3)
                        .help("Кадр снят в нескольких форматах; переносится целиком")
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 30)
            if !reasons.isEmpty {
                reasonLine
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
        .background(c.surface1, in: RoundedRectangle(cornerRadius: 2))
        .overlay {
            if isSelected {
                ZStack {
                    PencilLoop()
                        .stroke(theme.pen.opacity(0.95), style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
                    PencilLoop()
                        .stroke(theme.pen.opacity(0.5), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .padding(3)
                }
                .padding(-9)
                .allowsHitTesting(false)
            }
        }
    }

    /// «Жидкое стекло»: кадр — плитка со скруглением, имя в стеклянной капсуле поверх
    private func glassCell(_ thumb: Thumbnail?) -> some View {
        let c = theme.c
        let shape = RoundedRectangle(cornerRadius: 18)
        return ZStack {
            shape.fill(c.surface1)
            picture(thumb, radius: 0)
        }
        .aspectRatio(1.5, contentMode: .fit)
        .clipShape(shape)
        .brightness(hovered && !isSelected ? 0.05 : 0)
        .overlay(alignment: .bottomLeading) {
            if !compact {
                HStack(spacing: 6) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !extras.isEmpty {
                        Text("+" + extras.joined(separator: "+"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(c.text2)
                    }
                }
                .foregroundStyle(c.text1)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .pcGlass(in: .capsule)
                .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let mark, !mark.isEmpty || hovered || isSelected {
                markEditor(mark)
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .pcGlass(in: .capsule)
                    .padding(8)
            }
        }
        .overlay {
            if isSelected {
                shape.strokeBorder(Color.white, lineWidth: 2)
                RoundedRectangle(cornerRadius: 21)
                    .stroke(c.selection.opacity(0.88), lineWidth: 3)
                    .padding(-3.5)
            }
        }
        .overlay(alignment: .bottom) {
            if !reasons.isEmpty {
                reasonLine
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .pcGlass(in: .capsule)
                    .padding(.bottom, compact ? 8 : 42)
            }
        }
    }

    /// «Нейтраль»: кадр без подложки, под ним имя и размер; выбранный — белая рамка
    private func neutralCell(_ thumb: Thumbnail?) -> some View {
        let c = theme.c
        return VStack(alignment: .leading, spacing: 0) {
            picture(thumb)
            HStack(spacing: 5) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.white : c.text1)
                    .truncationMode(.middle)
                if !extras.isEmpty {
                    pairTag
                }
                if let mark, !mark.isEmpty || hovered || isSelected {
                    Spacer(minLength: 4)
                    markEditor(mark)
                }
            }
            .lineLimit(1)
            .padding(.top, 7)
            if !compact {
                if reasons.isEmpty {
                    Text(details(thumb?.info))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(c.text3)
                        .lineLimit(1)
                        .padding(.top, 1)
                } else {
                    reasonLine
                        .padding(.top, 1)
                }
            } else if !reasons.isEmpty {
                reasonLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «Световой стол»: отпечаток с белыми полями, подпись на нижнем поле
    private func tableCell(_ thumb: Thumbnail?) -> some View {
        let c = theme.c
        let shape = RoundedRectangle(cornerRadius: 2)
        return VStack(alignment: .leading, spacing: 0) {
            picture(thumb)
            HStack(spacing: 6) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? c.text1 : c.text2)
                    .truncationMode(.middle)
                if !extras.isEmpty {
                    pairTag
                }
                Spacer(minLength: 4)
                if let mark, !mark.isEmpty || hovered || isSelected {
                    markEditor(mark)
                }
                Text("\(number)")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(c.text3)
            }
            .lineLimit(1)
            .frame(height: 22)
            if !reasons.isEmpty {
                reasonLine
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 7)
        .padding(.bottom, 3)
        .background(Color.white, in: shape)
        .shadow(color: Color(hex: 0x141419).opacity(0.1), radius: 0.5, y: 1)
        .shadow(color: Color(hex: 0x141419).opacity(isSelected ? 0.42 : (hovered ? 0.34 : 0.26)),
                radius: isSelected ? 14 : (hovered ? 11 : 8), y: isSelected ? 14 : (hovered ? 10 : 6))
        .overlay {
            if isSelected {
                shape.stroke(c.text1, lineWidth: 2.5).padding(-1.25)
            }
        }
    }

    // MARK: Кадр и значки

    /// Миниатюра в рамке 3 : 2 целиком, со значками; у «Нейтрали» рамка выбора — по краю самого кадра
    private func picture(_ thumb: Thumbnail?, radius: CGFloat? = nil) -> some View {
        let c = theme.c
        let r = radius ?? (theme.isNeutral ? 4 : (theme.isGlass ? 0 : 1))
        return ZStack {
            if let image = thumb?.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: r))
                    .brightness(hovered && !theme.isGlass ? 0.05 : 0)
                    .opacity(rejected ? 0.4 : 1)
                    .overlay {
                        if isSelected && theme.isNeutral {
                            RoundedRectangle(cornerRadius: r + 1)
                                .stroke(Color.black, lineWidth: 1)
                                .padding(-2.5)
                            RoundedRectangle(cornerRadius: r + 1)
                                .stroke(Color.white, lineWidth: 2)
                                .padding(-1)
                        }
                    }
            } else if thumb == nil {
                // Загрузка: заглушка и индикатор
                RoundedRectangle(cornerRadius: r)
                    .fill(theme.isTable && theme.isLight ? c.surface3 : c.surface2)
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(c.text3)
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                if !defects.isEmpty {
                    defectBadge
                }
                if mark?.flag == PhotoFlag.pick.rawValue {
                    cornerBadge("flag.fill", color: Color.white, help: "Оставлен")
                }
                if rejected {
                    cornerBadge("flag.slash.fill", color: Color(hex: 0xFF6B61), help: "Отклонён (⌥U — снять флаг)")
                }
                if hasNotes && !theme.isFilm {
                    cornerBadge("pencil", color: Color.white, help: "Есть пометки")
                }
                if adjusted {
                    cornerBadge("slider.horizontal.3", color: Color.white, help: "Есть коррекция (E в просмотре)")
                }
            }
            .padding(theme.isGlass ? 10 : 6)
        }
        .overlay(alignment: .bottomTrailing) {
            if let bestNote {
                bestBadge(bestNote)
                    .padding(theme.isGlass ? 10 : 6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let label {
                Image(systemName: label ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white, label ? c.danger : c.success)
                    .padding(theme.isGlass ? 44 : 6)
                    .help(label ? "Размечено: брак" : "Размечено: норма")
            }
        }
    }

    /// Круглый значок на тёмной подложке поверх кадра
    private func cornerBadge(_ symbol: String, color: Color, help: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(Color.black.opacity(0.62), in: Circle())
            .help(help)
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
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.c.warning)
            .frame(width: 22, height: 22)
            .background(Color.black.opacity(0.62), in: Circle())
            .help(defects.map { "\($0.reason.title): \($0.detail)" }.joined(separator: "\n"))
    }

    /// Флаг, звёзды и цвет: пустые видны при наведении и у выбранного кадра
    private func markEditor(_ mark: PhotoMark) -> some View {
        MarkEditor(
            mark: mark,
            size: 10,
            showsEmpty: hovered || isSelected,
            onRating: { onMark(.rating($0)) },
            onColor: { onMark(.color($0)) },
            onFlag: { onMark(.flag($0)) }
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

    /// «47,3 МБ · 8256×5504»
    private func details(_ info: PhotoInfo?) -> String {
        guard let info else { return " " }
        var parts: [String] = []
        if let size = info.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let w = info.pixelWidth, let h = info.pixelHeight {
            parts.append("\(w)×\(h)")
        }
        if let camera = info.camera, !compact {
            parts.append(camera)
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}

// MARK: - Колонка папок «Нейтрали»

/// Слева всегда видно, куда ведут клавиши и сколько там кадров; ниже — разделы умного отбора
private struct NeutralRail: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme
    @AppStorage(Feature.transfer.key) private var transferOn = true

    var body: some View {
        let c = theme.c
        VStack(alignment: .leading, spacing: 2) {
            if transferOn {
                header("Папки")
                if session.destinations.isEmpty {
                    Text("Папок назначения нет")
                        .font(.system(size: 12))
                        .foregroundStyle(c.text3)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }
                ForEach(session.destinations) { destination in
                    row(key: destination.shortcut, title: destination.name, count: session.movedCount(to: destination))
                        .help(PathDisplay.short(destination.url))
                }
            }
            row(key: "⌫", title: "Корзина", count: session.trashedInSession)

            if session.sectionsAvailable {
                Spacer().frame(height: 18)
                header("Разделы")
                section(.all, "Все кадры", session.allPhotos.count, key: "⌘1")
                section(.defects, "Возможный брак", session.defectPhotos.count, key: "⌘2")
                section(.series, "Серии", session.seriesCount, key: "⌘3")
                if PhotoAnalyzer.peopleEnabled {
                    section(.people, "Люди", session.peopleGroups.count, key: "⌘4")
                }
                if AnalysisStore.shared.isRunning {
                    Text(AnalysisStore.shared.progressText)
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(c.text3)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 12)
            progress
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(c.surface1)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.c.text3)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
    }

    private func row(key: String, title: String, count: Int, isOn: Bool = false) -> some View {
        let c = theme.c
        return HStack(spacing: 10) {
            KeyCap(key)
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(c.text1)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(c.text2)
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(isOn ? c.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private func section(_ value: PhotoSection, _ title: String, _ count: Int, key: String) -> some View {
        let c = theme.c
        let isOn = session.section == value
        return Button {
            session.showSection(value)
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13.5, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(c.text1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(c.text2)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(isOn ? c.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("\(title) (\(key))")
    }

    /// «Разобрано 42 из 480»
    private var progress: some View {
        let c = theme.c
        let done = session.sortedInSession
        let total = done + session.allPhotos.count
        let share = total > 0 ? Double(done) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Разобрано")
                Spacer()
                Text("\(done) из \(total)").monospacedDigit()
            }
            .font(.system(size: 12.5))
            .foregroundStyle(c.text2)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(c.surface3)
                    Capsule().fill(Color(hex: 0xD8D8D8)).frame(width: max(geo.size.width * share, share > 0 ? 4 : 0))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
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

// MARK: - Фильтр по звёздам и цвету

/// Тот же список, что был в меню, но не закрывается после выбора: звёзды, цвета и флаги отмечаются по несколько.
/// «★★» — только две звезды, «★★★ ★★★★ ★★★★★» — от трёх; ничего не отмечено — фильтра нет
private struct MarkFilterPanel: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme
    @AppStorage(Feature.stars.key) private var starsOn = false
    @AppStorage(Feature.colors.key) private var colorsOn = false
    @AppStorage(Feature.flags.key) private var flagsOn = false

    var body: some View {
        let filter = session.markFilter
        VStack(alignment: .leading, spacing: 0) {
            if flagsOn {
                header("Флаг")
                MenuRow(title: "Оставлено", checked: filter.flags.contains(1)) { toggleFlag(1) }
                MenuRow(title: "Отклонено", checked: filter.flags.contains(2)) { toggleFlag(2) }
                MenuRow(title: "Без флага", checked: filter.flags.contains(0)) { toggleFlag(0) }
            }
            if starsOn {
                header("Звёзды")
                MenuRow(title: "Без звёзд", checked: filter.ratings.contains(0)) { toggleRating(0) }
                ForEach(1...5, id: \.self) { n in
                    MenuRow(title: String(repeating: "★", count: n), checked: filter.ratings.contains(n)) { toggleRating(n) }
                }
            }
            if colorsOn {
                header("Цвет")
                MenuRow(title: "Без цвета", checked: filter.colors.contains(0)) { toggleColor(0) }
                ForEach(ColorClass.allCases) { color in
                    MenuRow(title: color.title, checked: filter.colors.contains(color.rawValue), dot: color.color) {
                        toggleColor(color.rawValue)
                    }
                }
            }
            Divider().padding(.vertical, 5)
            MenuRow(title: "Сбросить фильтр", enabled: filter.isActive) {
                session.markFilter = MarkFilter()
            }
            Divider().padding(.vertical, 5)
            MenuRow(title: "Записать в XMP") {
                session.exportMarks()
            }
        }
        .padding(5)
        .frame(minWidth: 220)
        .fixedSize()
        // Как у меню: оформление окна, а не системы (окно бывает тёмным при светлой macOS)
        .preferredColorScheme(theme.isLight ? .light : .dark)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func toggleRating(_ n: Int) {
        if session.markFilter.ratings.contains(n) {
            session.markFilter.ratings.remove(n)
        } else {
            session.markFilter.ratings.insert(n)
        }
    }

    private func toggleFlag(_ n: Int) {
        if session.markFilter.flags.contains(n) {
            session.markFilter.flags.remove(n)
        } else {
            session.markFilter.flags.insert(n)
        }
    }

    private func toggleColor(_ n: Int) {
        if session.markFilter.colors.contains(n) {
            session.markFilter.colors.remove(n)
        } else {
            session.markFilter.colors.insert(n)
        }
    }
}

/// Строка в стиле системного меню: галочка, кружок цвета, подсветка при наведении
private struct MenuRow: View {
    let title: String
    var checked: Bool? = nil
    var dot: Color? = nil
    var enabled = true
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        let lit = hovered && enabled
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(checked == true ? 1 : 0)
                    .frame(width: 12)
                if let dot {
                    Circle()
                        .fill(dot)
                        .frame(width: 10, height: 10)
                }
                Text(title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(lit ? Color.white : (enabled ? Color.primary : Color.secondary))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(lit ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
    }
}
