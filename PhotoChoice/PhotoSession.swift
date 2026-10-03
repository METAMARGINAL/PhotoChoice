import AppKit
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
    let indexBefore: Int
    /// Остальные файлы кадра (пара RAW + JPEG): откуда → куда
    var companionMoves: [(original: URL, current: URL)] = []
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
    var photos: [URL] = []
    var index: Int = 0
    var includeSubfolders = false
    var isViewing = false
    var viewMode: ViewMode = .grid
    /// Панель сведений о снимке (клавиша I)
    var showInfo = false

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

    private var history: [HistoryEntry] = []
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

    func startReview() {
        errorMessage = nil
        guard let sourceURL else {
            errorMessage = "Сначала выберите папку с фото."
            return
        }
        if destinations.isEmpty {
            ensureKeepFolder()
        }
        photos = scan(source: sourceURL)
        index = 0
        history.removeAll()
        movedCount = 0
        trashedCount = 0
        guard !photos.isEmpty else {
            errorMessage = "В этой папке нет фотографий."
            return
        }
        viewMode = .grid
        isViewing = true
        WindowChrome.enterFullScreen()
        prefetchAroundCurrent()
    }

    func stopReview() {
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
        do {
            try FileManager.default.createDirectory(at: destination.url, withIntermediateDirectories: true)
            // Имя по метаданным берём у показываемого файла — у всей пары оно общее
            let newBase = renamesOnMove ? MetadataNaming.baseName(for: photo, style: renameStyle) : nil
            let moved = try moveGroup([photo] + extras, to: destination.url, baseName: newBase)
            let text = extras.isEmpty ? destination.name : "\(destination.name) · \(extras.count + 1) файла"
            finishMove(
                original: photo,
                current: moved[0],
                companionMoves: zip(extras, moved.dropFirst()).map { (original: $0.0, current: $0.1) },
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
            for file in [photo] + companions(of: photo) {
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
        finishMove(
            original: photo,
            current: trashed[0].current,
            companionMoves: Array(trashed.dropFirst()),
            toast: Toast(key: "⌫", text: trashed.count > 1 ? "В корзину · \(trashed.count) файла" : "В корзину", kind: .trash)
        )
        trashedCount += 1
    }

    func undo() {
        // В режиме рисования Z/⌘Z отменяет штрих, а не перенос файла
        if isDrawing && viewMode == .single {
            undoDrawing()
            return
        }
        guard let entry = history.popLast() else { return }
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
            if restored.count > 1 {
                companions[restore] = Array(restored.dropFirst())
            }
            ImageLoader.evict(entry.currentURL)
            moveAnnotations(from: entry.currentURL, to: restore)
            let insertAt = min(entry.indexBefore, photos.count)
            photos.insert(restore, at: insertAt)
            index = insertAt
            if viewMode == .compare {
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
        history.append(HistoryEntry(
            originalURL: original,
            currentURL: current,
            indexBefore: removedIndex,
            companionMoves: companionMoves
        ))
        companions[original] = nil
        ImageLoader.evict(original)
        ThumbnailLoader.evict(original)
        moveAnnotations(from: original, to: current)
        photos.remove(at: removedIndex)
        if photos.isEmpty {
            flash(result.text, key: result.key, kind: result.kind)
            return
        }
        if index >= photos.count {
            index = photos.count - 1
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

    private func ensureKeepFolder() {
        guard let sourceURL else { return }
        let keep = sourceURL.appendingPathComponent("Отобранные", isDirectory: true)
        try? FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
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
