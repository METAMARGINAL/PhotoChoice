import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Отправка по AirDrop и открытие кадра в другой программе (меню по правому клику в сетке и просмотре)

enum FileActions {
    /// Окно AirDrop с выбором получателя
    static func airDrop(_ files: [URL]) -> Bool {
        guard !files.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: files) else { return false }
        service.perform(withItems: files)
        return true
    }

    /// Один раз: меню собирается на каждую видимую ячейку
    static let preview: URL? = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview")

    /// Списки программ по расширению: меню строится на каждую ячейку сетки, а запрос к Launch Services не бесплатный
    private static var editorsByExtension: [String: [URL]] = [:]
    private static var icons: [String: NSImage] = [:]

    /// Программы, которые открывают такой файл: сначала программа по умолчанию, потом по алфавиту, без «Просмотра»
    static func editors(for file: URL) -> [URL] {
        let ext = file.pathExtension.lowercased()
        if let cached = editorsByExtension[ext] { return cached }
        let workspace = NSWorkspace.shared
        let fallback = workspace.urlForApplication(toOpen: file)
        let previewPath = preview?.standardizedFileURL.path
        var seen = Set<String>()
        var apps: [URL] = []
        for app in workspace.urlsForApplications(toOpen: file) {
            let path = app.standardizedFileURL.path
            guard path != previewPath, seen.insert(path).inserted else { continue }
            apps.append(app)
        }
        apps.sort { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
        if let fallback, let i = apps.firstIndex(where: { $0.standardizedFileURL == fallback.standardizedFileURL }) {
            apps.insert(apps.remove(at: i), at: 0)
        }
        editorsByExtension[ext] = apps
        return apps
    }

    static func name(of app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(of app: URL) -> NSImage {
        if let cached = icons[app.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.path)
        image.size = NSSize(width: 16, height: 16)
        icons[app.path] = image
        return image
    }

    static func open(_ files: [URL], with app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(files, withApplicationAt: app, configuration: configuration)
    }

    /// Выбор программы вручную, если нужной нет в списке
    static func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Открыть в программе"
        panel.prompt = "Открыть"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Пункты меню: «Открыть в Просмотре», «Открыть в» и «Отправить по AirDrop».
/// `photos` — кадры без парных RAW: обычно правят и отправляют их, RAW — отдельными пунктами
struct FileActionsMenu: View {
    let session: PhotoSession
    let photos: [URL]

    private var withPairs: [URL] {
        photos.flatMap { [$0] + session.companions(of: $0) }
    }

    private var raws: [URL] {
        photos.flatMap { session.companions(of: $0) }
    }

    var body: some View {
        if let preview = FileActions.preview {
            Button("Открыть в Просмотре") {
                openExternally(photos, with: preview)
            }
        }
        if let first = photos.first {
            Menu("Открыть в") {
                ForEach(FileActions.editors(for: first), id: \.self) { app in
                    Button {
                        openExternally(photos, with: app)
                    } label: {
                        Label { Text(FileActions.name(of: app)) } icon: { Image(nsImage: FileActions.icon(of: app)) }
                    }
                }
                if !raws.isEmpty, let rawApp = FileActions.editors(for: raws[0]).first {
                    Divider()
                    Button("RAW — в \(FileActions.name(of: rawApp))") {
                        openExternally(raws, with: rawApp)
                    }
                }
                Divider()
                Button("Другая программа…") {
                    if let app = FileActions.chooseApp() {
                        openExternally(photos, with: app)
                    }
                }
            }
        }
        Button("Отправить по AirDrop") {
            send(photos)
        }
        if !raws.isEmpty {
            Button("Отправить по AirDrop вместе с RAW") {
                send(withPairs)
            }
        }
    }

    private func openExternally(_ files: [URL], with app: URL) {
        session.markEditedExternally(files)
        FileActions.open(files, with: app)
    }

    private func send(_ files: [URL]) {
        if !FileActions.airDrop(files) {
            session.flash("AirDrop недоступен", kind: .error)
        }
    }
}
