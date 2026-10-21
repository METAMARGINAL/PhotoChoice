import AppKit
import CoreGraphics
import Foundation
import Observation
import UniformTypeIdentifiers

struct Destination: Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: URL
    var shortcut: String

    init(id: UUID = UUID(), name: String, url: URL, shortcut: String) {
        self.id = id
        self.name = name
        self.url = url
        self.shortcut = shortcut
    }
}

struct HistoryEntry {
    let originalURL: URL
    let currentURL: URL
    /// Позиция кадра в полном списке папки (`allPhotos`) до переноса
    let allIndexBefore: Int
    /// Остальные файлы кадра (пара RAW + JPEG): откуда → куда
    var companionMoves: [(original: URL, current: URL)] = []
}

/// Шаг для Z / ⌘Z: перенос кадра или смена звёзд и цвета (что было у кадров до неё)
enum UndoStep {
    case move(HistoryEntry)
    case marks([URL: PhotoMark])
}

/// Вид подтверждения действия: влияет на цвет и значок
enum ToastKind {
    case info, move, trash, undo, done, error
}

/// Всплывающее подтверждение: нажатая клавиша и результат
struct Toast: Equatable {
    let id = UUID()
    var key: String?
    var text: String
    var kind: ToastKind
}

/// Раздел сетки (умный отбор, docs/SmartCulling.md). Раздел — только отфильтрованный список кадров:
/// действия внутри него те же, что везде (1–9, Delete, Z…)
enum PhotoSection: Equatable {
    case all
    case defects
    case series
    case people

    var title: String {
        switch self {
        case .all: "Все фото"
        case .defects: "Брак"
        case .series: "Серии"
        case .people: "Люди"
        }
    }
}

/// Человек в разделе «Люди»: его кадры по порядку съёмки и лицо для плитки
struct PersonGroup: Identifiable {
    /// Номер по числу кадров (с 1)
    let number: Int
    let photos: [URL]
    /// Кадр и прямоугольник лица (в долях кадра, сверху слева) для плитки
    let coverURL: URL
    let coverRect: CGRect
    /// Лица этого человека — по ним он узнаётся после перегруппировки (кадры у людей общие, лица — нет)
    let faces: Set<FaceRef>

    /// Не обложка: у двух людей она может быть из одного кадра, и плитки с одинаковым id пропадали
    var id: Int { number }
}

/// Серия в сетке: её кадры, лучший кадр и место в списке раздела
struct SeriesBlock: Identifiable {
    /// Номер серии по порядку съёмки (с 1)
    let number: Int
    let members: [URL]
    let best: URL?
    /// Почему выбран лучший — для подсказки
    let bestNote: String
    let start: Date?
    /// От первого до последнего кадра, секунды
    let duration: TimeInterval
    /// Позиции кадров в `PhotoSession.photos`
    var range: Range<Int>

    var id: URL { members[0] }
}

enum ViewMode {
    case grid
    case single
    case compare
}

enum CompareSide {
    case left, right

    var other: CompareSide { self == .left ? .right : .left }
}

@Observable
final class PhotoSession {
    static let gridSizeRange: ClosedRange<CGFloat> = 110...520

    var sourceURL: URL?
    var destinations: [Destination] = []
    /// Все кадры папки в исходном порядке. Меняют его только сканирование, перенос/корзина и отмена
    private(set) var allPhotos: [URL] = []
    /// Кадры текущего раздела — их показывают сетка, просмотр и сравнение; `index` указывает сюда.
    /// Пересобирается через `rebuildVisible`
    private(set) var photos: [URL] = []
    private(set) var section: PhotoSection = .all
    var index: Int = 0
    var includeSubfolders = false
    var isViewing = false
    var viewMode: ViewMode = .grid
    /// Панель сведений о снимке (клавиша I)
    var showInfo = false
    /// Панель «Калибровка брака» в сетке (⌥⌘K)
    var showCalibration = false

    // Сравнение (клавиша C): слева эталон (A), справа кандидат (B).
    // Активная сторона — та, к которой применяются стрелки, 1–9, Delete, Z; currentPhoto = её фото
    var compareLeft: URL?
    var compareRight: URL?
    var compareActive: CompareSide = .right
    /// Зум и перемещение одинаковые в обеих половинах
    var compareSync = true

    // Рисование (клавиша D). Пометки только в памяти, файл не меняется
    var isDrawing = false
    var drawTool: DrawTool = .pen
    var drawColor: DrawColor = .red
    var drawSize: DrawSize = .medium
    private(set) var annotations: [URL: [Stroke]] = [:]
    private var annotationHistory: [URL: [[Stroke]]] = [:]
    /// Ширина ячейки сетки в точках
    var gridThumbSize: CGFloat = 230

    func setGridSize(_ value: CGFloat) {
        gridThumbSize = min(max(value, Self.gridSizeRange.lowerBound), Self.gridSizeRange.upperBound)
    }
    var errorMessage: String?
    /// Текущее подтверждение действия (показывается ~0,7 с)
    var toast: Toast?
    var flashMessage: String? { toast?.text }
    /// «482 файла, из них 468 RAW» для стартового экрана
    var sourceSummary: String?
    var movedCount = 0
    var trashedCount = 0

    private var history: [UndoStep] = []
    /// Пары RAW + JPEG: показываемый файл → остальные файлы того же кадра
    private(set) var companions: [URL: [URL]] = [:]

    /// Объединять файлы одного кадра (настройка «Объединять RAW и JPEG»)
    var pairsRawAndJPEG: Bool {
        UserDefaults.standard.object(forKey: "pairRawJpeg") as? Bool ?? true
    }

    /// Переименовывать кадр по метаданным при переносе в папку назначения (настройка, по умолчанию выкл.)
    var renamesOnMove: Bool {
        UserDefaults.standard.bool(forKey: "renameOnMove")
    }

    var renameStyle: RenameStyle {
        UserDefaults.standard.string(forKey: "renameStyle").flatMap(RenameStyle.init(rawValue:)) ?? .dateTimeOriginal
    }

    func companions(of url: URL) -> [URL] {
        companions[url] ?? []
    }
    private var accessURLs: [URL] = []

    var currentPhoto: URL? {
        guard photos.indices.contains(index) else { return nil }
        return photos[index]
    }

    var progressText: String {
        guard !photos.isEmpty else { return "Нет фото" }
        return "\(index + 1) / \(photos.count)"
    }

    var primaryDestination: Destination? { destinations.first }

    func chooseSource() {
        guard let url = FolderAccess.pickFolder(message: "Папка с фотографиями для отбора") else { return }
        rememberAccess(url)
        sourceURL = url
        if destinations.isEmpty {
            ensureKeepFolder()
        }
        refreshSourceSummary()
    }

    func addDestination() {
        guard let url = FolderAccess.pickFolder(message: "Папка, куда переносить отобранные фото") else { return }
        rememberAccess(url)
        let nextShortcut = String((destinations.count + 1).clamped(to: 1...9))
        let name = url.lastPathComponent
        destinations.append(Destination(name: name, url: url, shortcut: nextShortcut))
        refreshSourceSummary()
    }

    func removeDestination(_ destination: Destination) {
        destinations.removeAll { $0.id == destination.id }
        reassignShortcuts()
        refreshSourceSummary()
    }

    // MARK: - Разделы

    /// Умный отбор: разделы показываются (этап 1 — есть анализ; правила брака и серии — этапы 2 и 3)
    static let smartCullingReady = true

    /// Анализировать фото при открытии папки (настройка «Умный отбор», по умолчанию вкл.)
    var analysisEnabled: Bool {
        UserDefaults.standard.object(forKey: "smartAnalysis") as? Bool ?? true
    }

    /// Показывать переключатель разделов (анализ включён в настройках и готов)
    var sectionsAvailable: Bool {
        Self.smartCullingReady && analysisEnabled
    }

    func showSection(_ newSection: PhotoSection) {
        guard newSection != section, newSection == .all || sectionsAvailable else { return }
        section = newSection
        openedSeries = nil
        openedPerson = nil
        // Текущим остаётся прежний кадр, если он есть в новом разделе, иначе — первый
        rebuildVisible(keeping: currentPhoto, fallbackIndex: 0)
        prefetchAroundCurrent()
    }

    /// Кадры раздела с фильтром по звёздам и цвету (серии не фильтруются: их кадры идут блоками)
    private func visiblePhotos(for section: PhotoSection) -> [URL] {
        let list = sectionPhotos(section)
        guard section != .series, MarkStore.isEnabled, markFilter.isActive else { return list }
        let marks = MarkStore.shared
        return list.filter { markFilter.matches(marks.mark($0)) }
    }

    /// Кадры раздела из полного списка
    private func sectionPhotos(_ section: PhotoSection) -> [URL] {
        switch section {
        case .all:
            return allPhotos
        case .defects:
            return defectPhotos
        case .series:
            if let opened = openedSeriesBlock {
                return opened.members
            }
            return seriesPhotos
        case .people:
            // Пока человек не выбран, сетка показывает плитки людей, а не кадры
            return openedPersonGroup?.photos ?? []
        }
    }

    // MARK: Звёзды и цвета

    /// Фильтр сетки по звёздам и цвету (виден, когда функция включена в настройках)
    var markFilter = MarkFilter() {
        didSet {
            guard markFilter != oldValue else { return }
            rebuildVisible(keeping: currentPhoto, fallbackIndex: 0)
        }
    }

    /// Звёзды или цвет для `urls` (по умолчанию — текущий кадр)
    func applyMark(_ command: MarkCommand, to urls: [URL]? = nil) {
        guard MarkStore.isEnabled else { return }
        let targets = urls ?? currentPhoto.map { [$0] } ?? []
        guard !targets.isEmpty else { return }
        let store = MarkStore.shared
        let before = Dictionary(targets.map { ($0, store.mark($0)) }, uniquingKeysWith: { first, _ in first })
        switch command {
        case .rating(let n): store.setRating(targets, n)
        case .color(let n): store.setColor(targets, n)
        }
        // В историю — только если что-то поменялось: повторное ⌥3 не должно съедать Z
        if before.contains(where: { store.mark($0.key) != $0.value }) {
            history.append(.marks(before))
        }
        let suffix = targets.count > 1 ? " · \(targets.count) \(Self.plural(targets.count, "кадр", "кадра", "кадров"))" : ""
        flash(command.text + suffix, key: command.key, kind: .done)
        // Кадр перестал подходить под фильтр — уходит из сетки, текущим становится следующий
        if markFilter.isActive {
            rebuildVisible(keeping: currentPhoto, fallbackIndex: index)
        }
    }

    /// Z после звёзд или цвета: кадрам возвращается прежняя оценка, текущим становится один из них
    private func undoMarks(_ previous: [URL: PhotoMark]) {
        MarkStore.shared.restore(previous)
        let keep = currentPhoto.flatMap { previous[$0] != nil ? $0 : nil } ?? previous.keys.first
        if markFilter.isActive {
            rebuildVisible(keeping: keep, fallbackIndex: index)
        } else if let keep, let i = photos.firstIndex(of: keep) {
            select(i)
        }
        flash("Отмена", key: "Z", kind: .undo)
    }

    /// Записать звёзды и цвета кадров папки в XMP рядом с ними
    func exportMarks(_ urls: [URL]? = nil) {
        let targets = urls ?? allPhotos
        flash("Записываю XMP…")
        Task {
            let result = await MarkStore.shared.exportXMP(targets)
            if result.failed > 0 {
                flash("Не удалось записать \(result.failed) XMP — эти файлы не тронуты", kind: .error)
            } else if result.written == 0 {
                flash("Нет звёзд и цветов для записи")
            } else {
                flash("XMP: \(result.written) \(Self.plural(result.written, "файл", "файла", "файлов"))", kind: .done)
            }
        }
    }

    /// XMP кадра (`DSCF0001.xmp`) едет вместе с ним. Если пары не объединяются и у RAW и JPEG он общий —
    /// остаётся, пока в папке есть второй файл
    private func sidecars(of photo: URL) -> [URL] {
        let sidecar = XMPSidecar.url(for: photo)
        guard FileManager.default.fileExists(atPath: sidecar.path) else { return [] }
        let base = photo.deletingPathExtension().path.lowercased()
        let shared = allPhotos.contains { $0 != photo && $0.deletingPathExtension().path.lowercased() == base }
        return shared ? [] : [sidecar]
    }

    // MARK: Люди

    /// Люди папки (кадры ещё в папке, ≥ 2 кадров)
    private(set) var peopleGroups: [PersonGroup] = []
    /// Открытый человек: хранятся его лица — номер меняется при перегруппировке.
    /// По кадрам искать нельзя: групповой кадр есть у нескольких людей, и открывался другой человек
    private(set) var openedPerson: Set<FaceRef>?

    private var openedPersonGroup: PersonGroup? {
        guard let openedPerson else { return nil }
        return peopleGroups.max { a, b in
            openedPerson.intersection(a.faces).count < openedPerson.intersection(b.faces).count
        }.flatMap { openedPerson.isDisjoint(with: $0.faces) ? nil : $0 }
    }

    var isPersonOpened: Bool { section == .people && openedPersonGroup != nil }

    /// Открытый человек — для заголовка над сеткой
    var currentPerson: PersonGroup? { section == .people ? openedPersonGroup : nil }

    func openPerson(_ person: PersonGroup) {
        guard section == .people else { return }
        openedPerson = person.faces
        rebuildVisible(keeping: nil, fallbackIndex: 0)
        prefetchAroundCurrent()
    }

    func closePerson() {
        guard openedPerson != nil else { return }
        openedPerson = nil
        rebuildVisible(keeping: nil, fallbackIndex: 0)
    }

    private func refreshPeople() {
        let store = AnalysisStore.shared
        let present = Set(allPhotos)
        var groups: [PersonGroup] = []
        for cluster in store.people {
            let photos = cluster.photos.filter { present.contains($0) }
            guard photos.count >= 2 else { continue }
            let ordered = photos.enumerated().sorted { a, b in
                let da = store.metrics(for: a.element)?.captureDate
                let db = store.metrics(for: b.element)?.captureDate
                if let da, let db, da != db { return da < db }
                return a.offset < b.offset
            }.map(\.element)
            // Лицо для плитки: обложка группы, если её кадр ещё в папке, иначе первое лицо из оставшихся
            let cover = cluster.faces.first { $0 == cluster.cover && present.contains($0.url) }
                ?? cluster.faces.first { present.contains($0.url) }
            guard let cover, let rect = store.metrics(for: cover.url)?.faces[safe: cover.index]?.rect else { continue }
            groups.append(PersonGroup(number: groups.count + 1, photos: ordered, coverURL: cover.url, coverRect: rect,
                                      faces: Set(cluster.faces.filter { present.contains($0.url) })))
        }
        peopleGroups = groups
        if openedPerson != nil && openedPersonGroup == nil {
            openedPerson = nil
        }
    }

    /// Кадры с пометками при текущей строгости — по порядку съёмки
    private(set) var defectPhotos: [URL] = []
    /// Кадры серий подряд, серия за серией (пока без заголовков в сетке)
    private(set) var seriesPhotos: [URL] = []
    private(set) var seriesCount = 0
    /// Все серии папки (кадры ещё в папке, ≥ 2), с лучшим кадром
    private(set) var allSeries: [SeriesBlock] = []
    /// Открытая серия: в сетке только её кадры. Хранятся кадры серии — номер меняется, когда кадры уходят
    private(set) var openedSeries: Set<URL>?

    private var openedSeriesBlock: SeriesBlock? {
        guard let openedSeries else { return nil }
        return allSeries.first { !openedSeries.isDisjoint(with: $0.members) }
    }

    var isSeriesOpened: Bool { section == .series && openedSeriesBlock != nil }

    /// Серии, как они видны в сетке сейчас: все или одна открытая; `range` — позиции в `photos`
    var visibleSeries: [SeriesBlock] {
        guard section == .series else { return [] }
        if var opened = openedSeriesBlock {
            opened.range = 0..<opened.members.count
            return [opened]
        }
        return allSeries
    }

    /// Лучший кадр серии (для отметки в сетке)
    func seriesBest(_ url: URL) -> SeriesBlock? {
        guard section == .series else { return nil }
        return allSeries.first { $0.best == url }
    }

    /// Открыть серию: в сетке только её кадры (Esc — назад к списку серий)
    func openSeries(_ block: SeriesBlock) {
        guard section == .series else { return }
        openedSeries = Set(block.members)
        rebuildVisible(keeping: currentPhoto.flatMap { block.members.contains($0) ? $0 : nil } ?? block.best ?? block.members[0],
                       fallbackIndex: 0)
    }

    func closeSeries() {
        guard openedSeries != nil else { return }
        openedSeries = nil
        rebuildVisible(keeping: currentPhoto, fallbackIndex: 0)
    }

    /// ↑/↓ в разделе «Серии»: к предыдущей/следующей серии, на ту же позицию в ней (или на последний кадр)
    func jumpSeries(_ delta: Int) {
        let blocks = visibleSeries
        guard let current = blocks.firstIndex(where: { $0.range.contains(index) }) else { return }
        let target = current + delta
        guard blocks.indices.contains(target) else { return }
        let offset = index - blocks[current].range.lowerBound
        let destination = blocks[target].range
        select(min(destination.lowerBound + offset, destination.upperBound - 1))
    }

    /// Пересобирает список брака; без даты съёмки кадр остаётся на своём месте в общем порядке
    private func refreshDefects() {
        let store = AnalysisStore.shared
        let flagged = allPhotos.enumerated().filter { store.isDefect($0.element) }
        defectPhotos = flagged.sorted { a, b in
            let da = store.metrics(for: a.element)?.captureDate
            let db = store.metrics(for: b.element)?.captureDate
            if let da, let db, da != db { return da < db }
            return a.offset < b.offset
        }.map(\.element)

        // Серии — только из кадров, которые ещё в папке; от серии в 1 кадр ничего не осталось.
        // Лучший выбирается среди оставшихся: перенесли лучший — лучшим станет следующий
        let present = Set(allPhotos)
        let groups = store.series.map { $0.filter { present.contains($0) } }.filter { $0.count >= 2 }
        var blocks: [SeriesBlock] = []
        var position = 0
        for (i, members) in groups.enumerated() {
            let pick = SeriesGrouping.best(of: members) { store.metrics(for: $0) }
            let dates = members.compactMap { store.metrics(for: $0)?.captureDate }
            let start = dates.min()
            let duration = start.map { (dates.max() ?? $0).timeIntervalSince($0) } ?? 0
            blocks.append(SeriesBlock(number: i + 1, members: members, best: pick?.url, bestNote: pick?.note ?? "",
                                      start: start, duration: duration, range: position..<(position + members.count)))
            position += members.count
        }
        allSeries = blocks
        seriesPhotos = groups.flatMap { $0 }
        seriesCount = groups.count
        refreshPeople()
        // Открытая серия исчезла (в ней остался 1 кадр) — назад к списку
        if openedSeries != nil && openedSeriesBlock == nil {
            openedSeries = nil
        }
    }

    /// Анализ дописал кадры или сменилась строгость
    private func analysisChanged() {
        refreshDefects()
        if section != .all {
            rebuildVisible(keeping: currentPhoto, fallbackIndex: index)
        }
    }

    /// Пересобирает список раздела. Текущим становится `url`, если он виден, иначе кадр на месте `fallbackIndex`
    private func rebuildVisible(keeping url: URL?, fallbackIndex: Int) {
        refreshDefects()
        photos = visiblePhotos(for: section)
        if let url, let i = photos.firstIndex(of: url) {
            index = i
        } else {
            index = photos.isEmpty ? 0 : min(max(fallbackIndex, 0), photos.count - 1)
        }
        // Раздел опустел, а в папке кадры ещё есть — возвращаемся к сетке (а не к экрану «Готово»)
        if photos.isEmpty && !allPhotos.isEmpty && viewMode != .grid {
            isDrawing = false
            viewMode = .grid
        }
    }

    func startReview() {
        errorMessage = nil
        guard let sourceURL else {
            errorMessage = "Сначала выберите папку с фото."
            return
        }
        // Галочку «Отобранные по умолчанию» выключили после выбора папки — убираем её из списка
        if !Self.autoKeepFolder {
            let keep = sourceURL.appendingPathComponent("Отобранные", isDirectory: true).standardizedFileURL
            let before = destinations.count
            destinations.removeAll { $0.name == "Отобранные" && $0.url.standardizedFileURL == keep }
            if destinations.count != before { reassignShortcuts() }
        }
        if destinations.isEmpty {
            ensureKeepFolder()
        }
        ImageLoader.removeAll()
        ThumbnailLoader.removeAll()
        markFilter = MarkFilter()
        allPhotos = scan(source: sourceURL)
        section = .all
        openedSeries = nil
        openedPerson = nil
        rebuildVisible(keeping: nil, fallbackIndex: 0)
        history.removeAll()
        movedCount = 0
        trashedCount = 0
        guard !allPhotos.isEmpty else {
            errorMessage = "В этой папке нет фотографий."
            return
        }
        viewMode = .grid
        isViewing = true
        WindowChrome.enterFullScreen()
        // Анализ в фоне, ниже миниатюр по приоритету; готовое берётся из кэша
        if analysisEnabled {
            AnalysisStore.shared.onDefectsChanged = { [weak self] in self?.analysisChanged() }
            AnalysisStore.shared.onFinished = { [weak self] summary in self?.flash(summary, kind: .done) }
            AnalysisStore.shared.start(photos: allPhotos, source: sourceURL)
        }
    }

    func stopReview() {
        AnalysisStore.shared.close()
        ImageLoader.removeAll()
        ThumbnailLoader.removeAll()
        isDrawing = false
        isViewing = false
        WindowChrome.exitFullScreen()
    }

    func toggleViewMode() {
        viewMode = viewMode == .grid ? .single : .grid
        if viewMode == .grid { isDrawing = false }
        prefetchAroundCurrent()
    }

    func select(_ newIndex: Int) {
        guard photos.indices.contains(newIndex), newIndex != index else { return }
        index = newIndex
        prefetchAroundCurrent()
    }

    /// Сделать кадр текущим (клик по точке на графике калибровки). Нет в разделе — переходим во «Все фото»
    func reveal(_ url: URL) {
        if let i = photos.firstIndex(of: url) {
            select(i)
        } else if allPhotos.contains(url) {
            showSection(.all)
            if let i = photos.firstIndex(of: url) { select(i) }
        }
    }

    func open(_ newIndex: Int) {
        guard photos.indices.contains(newIndex) else { return }
        index = newIndex
        viewMode = .single
        prefetchAroundCurrent()
    }

    func goNext() {
        guard index < photos.count - 1 else { return }
        index += 1
        prefetchAroundCurrent()
    }

    func goPrevious() {
        guard index > 0 else { return }
        index -= 1
        prefetchAroundCurrent()
    }

    func moveCurrent(to destination: Destination) {
        guard let photo = currentPhoto else { return }
        let extras = companions(of: photo)
        let others = extras + sidecars(of: photo)
        do {
            try FileManager.default.createDirectory(at: destination.url, withIntermediateDirectories: true)
            // Имя по метаданным берём у показываемого файла — у всей пары оно общее
            let newBase = renamesOnMove ? MetadataNaming.baseName(for: photo, style: renameStyle) : nil
            let moved = try moveGroup([photo] + others, to: destination.url, baseName: newBase)
            let text = extras.isEmpty ? destination.name : "\(destination.name) · \(extras.count + 1) файла"
            finishMove(
                original: photo,
                current: moved[0],
                companionMoves: zip(others, moved.dropFirst()).map { (original: $0.0, current: $0.1) },
                toast: Toast(key: destination.shortcut, text: text, kind: .move)
            )
            movedCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveCurrentToPrimary() {
        guard let destination = primaryDestination else {
            errorMessage = "Добавьте папку назначения."
            return
        }
        moveCurrent(to: destination)
    }

    func trashCurrent() {
        guard let photo = currentPhoto else { return }
        var trashed: [(original: URL, current: URL)] = []
        do {
            for file in [photo] + companions(of: photo) + sidecars(of: photo) {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: file, resultingItemURL: &resulting)
                trashed.append((original: file, current: (resulting as URL?) ?? file))
            }
        } catch {
            // Кадр не должен остаться разорванным: возвращаем то, что уже ушло в корзину
            for item in trashed.reversed() {
                try? moveFile(from: item.current, to: item.original)
            }
            errorMessage = error.localizedDescription
            return
        }
        let photoCount = trashed.filter { !XMPSidecar.isSidecar($0.original) }.count
        finishMove(
            original: photo,
            current: trashed[0].current,
            companionMoves: Array(trashed.dropFirst()),
            toast: Toast(key: "⌫", text: photoCount > 1 ? "В корзину · \(photoCount) файла" : "В корзину", kind: .trash)
        )
        trashedCount += 1
    }

    func undo() {
        // В режиме рисования Z/⌘Z отменяет штрих, а не перенос файла
        if isDrawing && viewMode == .single {
            undoDrawing()
            return
        }
        guard let step = history.popLast() else { return }
        let entry: HistoryEntry
        switch step {
        case .move(let move):
            entry = move
        case .marks(let previous):
            undoMarks(previous)
            return
        }
        do {
            // Все файлы кадра возвращаются под общим именем (если прежнее успели занять — с суффиксом)
            let moves = [(original: entry.originalURL, current: entry.currentURL)] + entry.companionMoves
            let directory = entry.originalURL.deletingLastPathComponent()
            let base = uniqueBase(in: directory, for: moves.map { $0.original })
            var restored: [URL] = []
            for move in moves {
                let target = directory.appendingPathComponent(base).appendingPathExtension(move.original.pathExtension)
                try moveFile(from: move.current, to: target)
                restored.append(target)
            }
            let restore = restored[0]
            let pair = restored.dropFirst().filter { !XMPSidecar.isSidecar($0) }
            if !pair.isEmpty {
                companions[restore] = Array(pair)
            }
            ImageLoader.evict(entry.currentURL)
            moveAnnotations(from: entry.currentURL, to: restore)
            AnalysisStore.shared.moveRecord(from: entry.currentURL, to: restore)
            MarkStore.shared.move(from: entry.currentURL, to: restore)
            let insertAt = min(entry.allIndexBefore, allPhotos.count)
            allPhotos.insert(restore, at: insertAt)
            // Кадр возвращается в общий список; в разделе он виден, только если по-прежнему ему подходит
            rebuildVisible(keeping: restore, fallbackIndex: index)
            if viewMode == .compare, photos.contains(restore) {
                // Возвращённый кадр показываем в активной половине
                setCompareURL(restore, compareActive)
            }
            flash("Отмена", key: "Z", kind: .undo)
            prefetchAroundCurrent()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleShortcut(_ key: String) {
        let lowered = key.lowercased()
        if lowered == "z" {
            undo()
            return
        }
        if let destination = destinations.first(where: { $0.shortcut == key }) {
            moveCurrent(to: destination)
        }
    }

    // MARK: - Сравнение

    func compareURL(_ side: CompareSide) -> URL? {
        side == .left ? compareLeft : compareRight
    }

    func startCompare() {
        guard isViewing, photos.count >= 2, let current = currentPhoto else {
            flash("Для сравнения нужно минимум 2 фото")
            return
        }
        isDrawing = false
        compareLeft = current
        compareRight = photos[index + 1 < photos.count ? index + 1 : index - 1]
        compareActive = .right
        syncIndexToCompare()
        viewMode = .compare
    }

    func stopCompare() {
        guard viewMode == .compare else { return }
        syncIndexToCompare()
        viewMode = .single
    }

    func toggleCompare() {
        if viewMode == .compare {
            stopCompare()
        } else {
            startCompare()
        }
    }

    func setCompareActive(_ side: CompareSide) {
        guard compareActive != side else { return }
        compareActive = side
        syncIndexToCompare()
    }

    /// Листает активную половину, перескакивая кадр из соседней
    func compareStep(_ delta: Int) {
        guard let active = compareURL(compareActive), let i = photos.firstIndex(of: active) else { return }
        let other = compareURL(compareActive.other)
        var j = i + delta
        if photos.indices.contains(j), photos[j] == other {
            j += delta
        }
        guard photos.indices.contains(j) else { return }
        setCompareURL(photos[j], compareActive)
        index = j
        prefetchAroundCurrent()
    }

    /// Поменять половины местами
    func swapCompare() {
        let left = compareLeft
        compareLeft = compareRight
        compareRight = left
        compareActive = compareActive.other
    }

    /// Активный кадр становится эталоном слева, справа — соседний
    func promoteToReference() {
        guard let chosen = compareURL(compareActive), let i = photos.firstIndex(of: chosen) else { return }
        guard let j = [i + 1, i - 1].first(where: { photos.indices.contains($0) }) else { return }
        compareLeft = chosen
        compareRight = photos[j]
        compareActive = .right
        syncIndexToCompare()
        flash("Новый эталон")
    }

    func toggleCompareSync() {
        compareSync.toggle()
        flash(compareSync ? "Зум синхронно" : "Зум раздельно")
    }

    private func setCompareURL(_ url: URL?, _ side: CompareSide) {
        if side == .left {
            compareLeft = url
        } else {
            compareRight = url
        }
    }

    private func syncIndexToCompare() {
        guard let url = compareURL(compareActive), let i = photos.firstIndex(of: url) else { return }
        index = i
        prefetchAroundCurrent()
    }

    /// Кадр ушёл в папку/корзину — освободившуюся половину занимает соседний
    private func repairCompare(removed: URL, at removedIndex: Int) {
        guard viewMode == .compare else { return }
        guard photos.count >= 2 else {
            viewMode = .single
            return
        }
        if compareLeft == removed { compareLeft = nil }
        if compareRight == removed { compareRight = nil }
        for side in [CompareSide.left, .right] where compareURL(side) == nil {
            let other = compareURL(side.other)
            var j = min(removedIndex, photos.count - 1)
            if photos[j] == other {
                j = j + 1 < photos.count ? j + 1 : j - 1
            }
            setCompareURL(photos[j], side)
        }
        syncIndexToCompare()
    }

    // MARK: - Пометки

    func strokes(for url: URL) -> [Stroke] {
        annotations[url] ?? []
    }

    func hasAnnotations(_ url: URL) -> Bool {
        !(annotations[url]?.isEmpty ?? true)
    }

    func addStroke(_ stroke: Stroke, to url: URL) {
        setStrokes(strokes(for: url) + [stroke], for: url)
    }

    func removeStroke(_ id: UUID, from url: URL) {
        setStrokes(strokes(for: url).filter { $0.id != id }, for: url)
    }

    func clearDrawing() {
        guard let url = currentPhoto, hasAnnotations(url) else { return }
        setStrokes([], for: url)
        flash("Пометки очищены")
    }

    func undoDrawing() {
        guard let url = currentPhoto, let previous = annotationHistory[url]?.popLast() else { return }
        annotations[url] = previous
    }

    func toggleDrawing() {
        guard isViewing, viewMode == .single else { return }
        isDrawing.toggle()
    }

    /// Копия снимка с пометками в буфер обмена (до 4000 px, чтобы вставлялось быстро)
    func copyAnnotated() {
        guard let url = currentPhoto else { return }
        let strokes = self.strokes(for: url)
        flash("Копирую…")
        Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                AnnotationExporter.render(url, strokes: strokes, maxPixelSize: 4000)
            }.value
            guard let rendered else {
                flash("Не удалось скопировать", kind: .error)
                return
            }
            let image = NSImage(
                cgImage: rendered.image,
                size: NSSize(width: rendered.image.width, height: rendered.image.height)
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            flash("Скопировано", key: "⌘C", kind: .done)
        }
    }

    /// Сохраняет копию снимка с пометками в полном разрешении. Оригинал не трогаем
    func saveAnnotated() {
        guard let url = currentPhoto else { return }
        let strokes = self.strokes(for: url)
        let panel = NSSavePanel()
        panel.title = "Сохранить копию с пометками"
        panel.allowedContentTypes = [.jpeg, .png]
        panel.canCreateDirectories = true
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "_пометки.jpg"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        guard target.standardizedFileURL != url.standardizedFileURL else {
            flash("Нельзя перезаписать оригинал", kind: .error)
            return
        }
        flash("Сохраняю…")
        Task {
            let ok = await Task.detached(priority: .userInitiated) {
                AnnotationExporter.write(url, strokes: strokes, to: target)
            }.value
            if ok {
                flash("Сохранено", key: "⌘S", kind: .done)
            } else {
                flash("Не удалось сохранить", kind: .error)
            }
        }
    }

    private func setStrokes(_ strokes: [Stroke], for url: URL) {
        annotationHistory[url, default: []].append(self.strokes(for: url))
        annotations[url] = strokes
    }

    private func moveAnnotations(from old: URL, to new: URL) {
        if let strokes = annotations.removeValue(forKey: old) {
            annotations[new] = strokes
        }
        if let history = annotationHistory.removeValue(forKey: old) {
            annotationHistory[new] = history
        }
    }

    private func finishMove(
        original: URL,
        current: URL,
        companionMoves: [(original: URL, current: URL)] = [],
        toast result: Toast
    ) {
        let removedIndex = index
        let allIndex = allPhotos.firstIndex(of: original) ?? allPhotos.count
        history.append(.move(HistoryEntry(
            originalURL: original,
            currentURL: current,
            allIndexBefore: allIndex,
            companionMoves: companionMoves
        )))
        companions[original] = nil
        ImageLoader.evict(original)
        ThumbnailLoader.evict(original)
        moveAnnotations(from: original, to: current)
        AnalysisStore.shared.moveRecord(from: original, to: current)
        MarkStore.shared.move(from: original, to: current)
        // Кадр исчезает из всех разделов; текущим становится следующий в разделе
        if allPhotos.indices.contains(allIndex) {
            allPhotos.remove(at: allIndex)
        }
        rebuildVisible(keeping: nil, fallbackIndex: removedIndex)
        if photos.isEmpty {
            flash(result.text, key: result.key, kind: result.kind)
            return
        }
        repairCompare(removed: original, at: removedIndex)
        flash(result.text, key: result.key, kind: result.kind)
        prefetchAroundCurrent()
    }

    private func scan(source: URL) -> [URL] {
        let destinationPaths = Set(destinations.map { $0.url.standardizedFileURL.path })
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        var files: [URL] = []

        if includeSubfolders, let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                if destinationPaths.contains(where: { url.path.hasPrefix($0 + "/") || url.path == $0 }) {
                    continue
                }
                if ImageLoader.isPhoto(url) {
                    files.append(url)
                }
            }
        } else {
            let listed = (try? FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )) ?? []
            files = listed.filter { ImageLoader.isPhoto($0) }
        }

        let grouped = groupPairs(files)
        companions = grouped.companions
        return grouped.primaries.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - Пары RAW + JPEG

    /// Какой файл кадра показывать: сначала JPEG/HEIC (открываются быстро), RAW — последним
    private static let displayPriority = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "webp", "gif", "bmp"]

    private func displayRank(_ url: URL) -> Int {
        let ext = url.pathExtension.lowercased()
        if let i = Self.displayPriority.firstIndex(of: ext) { return i }
        return Self.rawExtensions.contains(ext) ? 100 : 200
    }

    /// Файлы с одинаковым именем в одной папке — один кадр
    private func groupPairs(_ files: [URL]) -> (primaries: [URL], companions: [URL: [URL]]) {
        guard pairsRawAndJPEG else { return (files, [:]) }
        var groups: [String: [URL]] = [:]
        var order: [String] = []
        for url in files {
            let key = url.deletingPathExtension().path.lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(url)
        }
        var primaries: [URL] = []
        var map: [URL: [URL]] = [:]
        for key in order {
            guard let members = groups[key] else { continue }
            let sorted = members.sorted { displayRank($0) < displayRank($1) }
            primaries.append(sorted[0])
            if sorted.count > 1 {
                map[sorted[0]] = Array(sorted.dropFirst())
            }
        }
        return (primaries, map)
    }

    /// Имя без расширения, свободное сразу для всех файлов кадра: «DSC_0452», иначе «DSC_0452_2»…
    private func uniqueBase(in directory: URL, for files: [URL], preferred: String? = nil) -> String {
        let base = preferred ?? files[0].deletingPathExtension().lastPathComponent
        func isTaken(_ candidate: String) -> Bool {
            files.contains { file in
                let target = directory.appendingPathComponent(candidate).appendingPathExtension(file.pathExtension)
                return FileManager.default.fileExists(atPath: target.path)
            }
        }
        var candidate = base
        var i = 2
        while isTaken(candidate) {
            candidate = "\(base)_\(i)"
            i += 1
        }
        return candidate
    }

    /// Переносит все файлы кадра под общим именем; при сбое возвращает уже перенесённые
    private func moveGroup(_ files: [URL], to directory: URL, baseName: String? = nil) throws -> [URL] {
        let base = uniqueBase(in: directory, for: files, preferred: baseName)
        var done: [(from: URL, to: URL)] = []
        do {
            for file in files {
                let target = directory.appendingPathComponent(base).appendingPathExtension(file.pathExtension)
                try moveFile(from: file, to: target)
                done.append((from: file, to: target))
            }
        } catch {
            for item in done.reversed() {
                try? moveFile(from: item.to, to: item.from)
            }
            throw error
        }
        return done.map { $0.to }
    }

    /// Папка «Отобранные» по умолчанию (настройка `autoKeepFolder`, по умолчанию вкл.)
    static var autoKeepFolder: Bool {
        UserDefaults.standard.object(forKey: "autoKeepFolder") as? Bool ?? true
    }

    /// Назначает «Отобранные» внутри исходной папки клавишей 1. На диске папка НЕ создаётся:
    /// это делает `moveCurrent` при первом переносе, так что без переносов пустой папки не будет
    private func ensureKeepFolder() {
        guard Self.autoKeepFolder, let sourceURL else { return }
        let keep = sourceURL.appendingPathComponent("Отобранные", isDirectory: true)
        rememberAccess(keep)
        destinations = [Destination(name: "Отобранные", url: keep, shortcut: "1")]
    }

    private func uniqueURL(in directory: URL, preferredName: String) -> URL {
        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(preferredName)
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)_\(i)" : "\(base)_\(i).\(ext)"
            candidate = directory.appendingPathComponent(name)
            i += 1
        }
        return candidate
    }

    private func moveFile(from: URL, to: URL) throws {
        if FileManager.default.fileExists(atPath: to.path) {
            throw CocoaError(.fileWriteFileExists)
        }
        do {
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            try FileManager.default.copyItem(at: from, to: to)
            try FileManager.default.removeItem(at: from)
        }
    }

    private func prefetchAroundCurrent() {
        let urls = (-1...2).compactMap { offset -> URL? in
            let i = index + offset
            guard photos.indices.contains(i) else { return nil }
            return photos[i]
        }
        ImageLoader.prefetch(urls)
    }

    func flash(_ text: String, key: String? = nil, kind: ToastKind = .info) {
        let value = Toast(key: key, text: text, kind: kind)
        toast = value
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if toast?.id == value.id {
                toast = nil
            }
        }
    }

    // MARK: - Сводка по исходной папке

    func refreshSourceSummary() {
        guard let source = sourceURL else {
            sourceSummary = nil
            return
        }
        let recursive = includeSubfolders
        let excluded = Set(destinations.map { $0.url.standardizedFileURL.path })
        let pairing = pairsRawAndJPEG
        Task {
            let summary = await Task.detached(priority: .utility) {
                PhotoSession.summarize(source, recursive: recursive, excluded: excluded, pairing: pairing)
            }.value
            if sourceURL == source {
                sourceSummary = summary
            }
        }
    }

    private nonisolated static let rawExtensions: Set<String> = ["dng", "raf", "cr2", "cr3", "nef", "arw", "orf", "rw2"]

    private nonisolated static func summarize(_ source: URL, recursive: Bool, excluded: Set<String>, pairing: Bool) -> String {
        var total = 0
        var raw = 0
        var shots = Set<String>()
        func count(_ url: URL) {
            guard ImageLoader.isPhoto(url) else { return }
            total += 1
            if rawExtensions.contains(url.pathExtension.lowercased()) { raw += 1 }
            shots.insert(url.deletingPathExtension().path.lowercased())
        }
        if recursive, let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                let path = url.standardizedFileURL.path
                if excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { continue }
                count(url)
            }
        } else {
            let listed = (try? FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            listed.forEach(count)
        }
        guard total > 0 else { return "фото не найдено" }
        let files = "\(total) \(plural(total, "файл", "файла", "файлов"))"
        var summary = raw > 0 ? "\(files), из них \(raw) RAW" : files
        if pairing && shots.count < total {
            summary += " · \(shots.count) \(plural(shots.count, "кадр", "кадра", "кадров"))"
        }
        return summary
    }

    nonisolated static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10
        let n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }

    private func rememberAccess(_ url: URL) {
        if !accessURLs.contains(url) {
            accessURLs.append(url)
        }
    }

    private func reassignShortcuts() {
        for i in destinations.indices {
            destinations[i].shortcut = String((i + 1).clamped(to: 1...9))
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

enum WindowChrome {
    static func enterFullScreen() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }

    static func exitFullScreen() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }
}

extension Array {
    /// Элемент по индексу или nil, если индекса нет
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
