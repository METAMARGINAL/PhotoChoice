import AppKit
import Foundation
import Observation

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
}

@Observable
final class PhotoSession {
    var sourceURL: URL?
    var destinations: [Destination] = []
    var photos: [URL] = []
    var index: Int = 0
    var includeSubfolders = false
    var isViewing = false
    var errorMessage: String?
    var flashMessage: String?
    var movedCount = 0
    var trashedCount = 0

    private var history: [HistoryEntry] = []
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
    }

    func addDestination() {
        guard let url = FolderAccess.pickFolder(message: "Папка, куда переносить отобранные фото") else { return }
        rememberAccess(url)
        let nextShortcut = String((destinations.count + 1).clamped(to: 1...9))
        let name = url.lastPathComponent
        destinations.append(Destination(name: name, url: url, shortcut: nextShortcut))
    }

    func removeDestination(_ destination: Destination) {
        destinations.removeAll { $0.id == destination.id }
        reassignShortcuts()
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
        isViewing = true
        WindowChrome.enterFullScreen()
        prefetchAroundCurrent()
    }

    func stopReview() {
        isViewing = false
        WindowChrome.exitFullScreen()
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
        do {
            let target = uniqueURL(in: destination.url, preferredName: photo.lastPathComponent)
            try FileManager.default.createDirectory(at: destination.url, withIntermediateDirectories: true)
            try moveFile(from: photo, to: target)
            finishMove(original: photo, current: target, flash: "→ \(destination.name)")
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
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: photo, resultingItemURL: &resulting)
            let current = (resulting as URL?) ?? photo
            finishMove(original: photo, current: current, flash: "В корзину")
            trashedCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undo() {
        guard let entry = history.popLast() else { return }
        do {
            let restore = uniqueURL(in: entry.originalURL.deletingLastPathComponent(), preferredName: entry.originalURL.lastPathComponent)
            try moveFile(from: entry.currentURL, to: restore)
            ImageLoader.evict(entry.currentURL)
            let insertAt = min(entry.indexBefore, photos.count)
            photos.insert(restore, at: insertAt)
            index = insertAt
            flash("Отмена")
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

    private func finishMove(original: URL, current: URL, flash text: String) {
        let removedIndex = index
        history.append(HistoryEntry(originalURL: original, currentURL: current, indexBefore: removedIndex))
        ImageLoader.evict(original)
        photos.remove(at: removedIndex)
        if photos.isEmpty {
            flash(text)
            return
        }
        if index >= photos.count {
            index = photos.count - 1
        }
        flash(text)
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

        return files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
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

    private func flash(_ text: String) {
        flashMessage = text
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if flashMessage == text {
                flashMessage = nil
            }
        }
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
