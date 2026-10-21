import AppKit
import Foundation
import Observation
import SwiftUI

// Звёзды и цветовые метки (настройка `marksEnabled`, по умолчанию выкл.).
// Хранятся у приложения (Application Support/PhotoChoice/marks.json) по пути файла и переезжают вместе с кадром.
// Рядом с фото пишутся только по команде «Записать в XMP»: `DSCF0001.xmp`, сами снимки не меняются.

/// Цветовая метка. Номер — клавиша ⌃1–⌃8
nonisolated enum ColorClass: Int, CaseIterable, Identifiable, Sendable {
    case red = 1, orange, yellow, green, blue, purple, cyan, gray

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .red: "Красный"
        case .orange: "Оранжевый"
        case .yellow: "Жёлтый"
        case .green: "Зелёный"
        case .blue: "Синий"
        case .purple: "Фиолетовый"
        case .cyan: "Голубой"
        case .gray: "Серый"
        }
    }

    /// xmp:Label: Lightroom и Bridge узнают Red, Yellow, Green, Blue, Purple, остальные показывают как свою метку
    var label: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .cyan: "Cyan"
        case .gray: "Gray"
        }
    }

    var color: Color { Color(hex: hex) }

    var hex: UInt32 {
        switch self {
        case .red: 0xE5484D
        case .orange: 0xF0883E
        case .yellow: 0xE8C547
        case .green: 0x46A758
        case .blue: 0x3E7BFA
        case .purple: 0x9B5DE5
        case .cyan: 0x3EC6D9
        case .gray: 0x8E8E93
        }
    }

    /// Кружок для меню: в NSMenu SF Symbols одноцветные
    @MainActor
    var menuDot: NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

nonisolated struct PhotoMark: Codable, Equatable, Sendable {
    /// 0 — без звёзд
    var rating = 0
    /// 0 — без цвета, иначе `ColorClass.rawValue`
    var color = 0

    var isEmpty: Bool { rating == 0 && color == 0 }
}

/// ⌥0–⌥5 — звёзды, ⌃0–⌃8 — цвет. 1–9 без модификаторов остаются за переносом в папки
enum MarkCommand {
    case rating(Int)
    case color(Int)

    /// Цифры по кодам клавиш — не зависят от раскладки; верхний ряд и цифровой блок
    private static let digits: [UInt16: Int] = [
        29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        82: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9
    ]

    init?(_ event: NSEvent) {
        guard MarkStore.isEnabled, let digit = Self.digits[event.keyCode] else { return nil }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .option, digit <= 5 {
            self = .rating(digit)
        } else if flags == .control, digit <= ColorClass.allCases.count {
            self = .color(digit)
        } else {
            return nil
        }
    }

    var key: String {
        switch self {
        case .rating(let n): "⌥\(n)"
        case .color(let n): "⌃\(n)"
        }
    }

    var text: String {
        switch self {
        case .rating(let n): n == 0 ? "Без звёзд" : String(repeating: "★", count: n)
        case .color(let n): ColorClass(rawValue: n)?.title ?? "Без цвета"
        }
    }
}

/// Фильтр сетки: число звёзд из `ratings` и цвет из `colors` (пусто — любые; 0 — без звёзд / без цвета)
struct MarkFilter: Equatable {
    var ratings: Set<Int> = []
    var colors: Set<Int> = []

    var isActive: Bool { !ratings.isEmpty || !colors.isEmpty }

    func matches(_ mark: PhotoMark) -> Bool {
        (ratings.isEmpty || ratings.contains(mark.rating)) && (colors.isEmpty || colors.contains(mark.color))
    }

    /// «★2», «★3+», «★2, 4» — выбранные звёзды для кнопки фильтра
    private var ratingSummary: String? {
        let sorted = ratings.sorted()
        guard let low = sorted.first else { return nil }
        if sorted.count == 1 {
            return low == 0 ? "Без звёзд" : "★\(low)"
        }
        if low > 0, sorted == Array(low...5) {
            return "★\(low)+"
        }
        return "★" + sorted.map(String.init).joined(separator: ", ")
    }

    /// «★3+ · 2 цвета» для кнопки фильтра
    var summary: String {
        var parts: [String] = []
        if let ratingSummary { parts.append(ratingSummary) }
        if colors.count == 1, let only = colors.first {
            parts.append(ColorClass(rawValue: only)?.title ?? "Без цвета")
        } else if colors.count > 1 {
            parts.append("\(colors.count) \(PhotoSession.plural(colors.count, "цвет", "цвета", "цветов"))")
        }
        return parts.isEmpty ? "Фильтр" : parts.joined(separator: " · ")
    }
}

// MARK: - Хранилище

@Observable
final class MarkStore {
    static let shared = MarkStore()

    /// Настройка «Звёзды и цветовые метки»
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "marksEnabled")
    }

    /// Путь файла → оценка; кадров без оценки здесь нет
    private(set) var marks: [String: PhotoMark] = MarkStore.load()
    @ObservationIgnored private var saveScheduled = false

    func mark(_ url: URL) -> PhotoMark {
        marks[Self.key(url)] ?? PhotoMark()
    }

    func setRating(_ urls: [URL], _ rating: Int) {
        update(urls) { $0.rating = rating }
    }

    func setColor(_ urls: [URL], _ color: Int) {
        update(urls) { $0.color = color }
    }

    /// Отмена: кадрам возвращаются прежние звёзды и цвет
    func restore(_ previous: [URL: PhotoMark]) {
        for (url, mark) in previous {
            marks[Self.key(url)] = mark.isEmpty ? nil : mark
        }
        scheduleSave()
    }

    /// Кадр перенесли, отправили в корзину или вернули: оценка следует за файлом
    func move(from old: URL, to new: URL) {
        guard let mark = marks.removeValue(forKey: Self.key(old)) else { return }
        marks[Self.key(new)] = mark
        scheduleSave()
    }

    private func update(_ urls: [URL], _ change: (inout PhotoMark) -> Void) {
        for url in urls {
            var mark = self.mark(url)
            change(&mark)
            marks[Self.key(url)] = mark.isEmpty ? nil : mark
        }
        scheduleSave()
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    // MARK: Диск

    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PhotoChoice/marks.json")
    }

    private static func load() -> [String: PhotoMark] {
        guard let file, let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: PhotoMark].self, from: data)) ?? [:]
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            saveNow()
        }
    }

    /// Оценку поставили и сразу закрыли приложение — отложенная запись не успела бы
    @ObservationIgnored private var quitObserver: NSObjectProtocol?

    private init() {
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { MarkStore.shared.saveNow() }
        }
    }

    private func saveNow() {
        guard saveScheduled else { return }
        saveScheduled = false
        guard let file = Self.file, let data = try? JSONEncoder().encode(marks) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    // MARK: XMP

    /// Записывает оценки кадров в XMP рядом с ними. Кадры без оценки и без XMP не трогаются;
    /// у кадра без оценки, но с XMP звёзды и цвет из XMP убираются
    func exportXMP(_ photos: [URL]) async -> (written: Int, failed: Int) {
        let items = photos.map { (url: $0, mark: mark($0)) }
        return await Task.detached(priority: .userInitiated) {
            var written = 0
            var failed = 0
            for item in items {
                switch XMPSidecar.write(item.mark, for: item.url) {
                case .written: written += 1
                case .failed: failed += 1
                case .skipped: break
                }
            }
            return (written, failed)
        }.value
    }
}

// MARK: - XMP рядом с фото

nonisolated enum XMPSidecar {
    static let xmpNS = "http://ns.adobe.com/xap/1.0/"

    nonisolated enum Outcome: Sendable {
        case written, skipped, failed
    }

    /// `DSCF0001.RAF` → `DSCF0001.xmp`: у пары RAW + JPEG файл общий
    static func url(for photo: URL) -> URL {
        photo.deletingPathExtension().appendingPathExtension("xmp")
    }

    static func isSidecar(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "xmp"
    }

    private static let template = """
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="PhotoChoice">
     <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about=""/>
     </rdf:RDF>
    </x:xmpmeta>
    """

    /// Меняет только звёзды и цвет, остальное в существующем файле остаётся.
    /// Файл, который не удалось разобрать, не перезаписывается
    static func write(_ mark: PhotoMark, for photo: URL) -> Outcome {
        let file = url(for: photo)
        let document: XMLDocument
        if FileManager.default.fileExists(atPath: file.path) {
            guard let parsed = try? XMLDocument(contentsOf: file, options: [.nodePreserveAll]) else { return .failed }
            document = parsed
        } else {
            guard !mark.isEmpty else { return .skipped }
            guard let fresh = try? XMLDocument(xmlString: template, options: [.nodePreserveAll]) else { return .failed }
            document = fresh
        }
        let descriptions = ((try? document.nodes(forXPath: "//*[local-name()='RDF']/*[local-name()='Description']")) ?? [])
            .compactMap { $0 as? XMLElement }
        guard let first = descriptions.first else { return .failed }
        let color = ColorClass(rawValue: mark.color)
        set(first, in: descriptions, name: "Rating", uri: xmpNS, prefix: "xmp", value: mark.rating > 0 ? "\(mark.rating)" : nil)
        set(first, in: descriptions, name: "Label", uri: xmpNS, prefix: "xmp", value: color?.label)
        do {
            try document.xmlData(options: [.nodePrettyPrint]).write(to: file, options: .atomic)
            return .written
        } catch {
            return .failed
        }
    }

    /// Убирает свойство из всех rdf:Description (атрибутом или элементом, под любым префиксом) и пишет атрибутом в первый
    private static func set(_ target: XMLElement, in all: [XMLElement], name: String, uri: String, prefix: String, value: String?) {
        for element in all {
            for attribute in element.attributes ?? [] where matches(attribute, in: element, name: name, uri: uri) {
                if let qualified = attribute.name { element.removeAttribute(forName: qualified) }
            }
            for child in element.children ?? [] {
                if let child = child as? XMLElement, matches(child, in: child, name: name, uri: uri) {
                    child.detach()
                }
            }
        }
        guard let value else { return }
        var used = target.resolvePrefix(forNamespaceURI: uri)
        if used == nil || used?.isEmpty == true {
            if let namespace = XMLNode.namespace(withName: prefix, stringValue: uri) as? XMLNode {
                target.addNamespace(namespace)
            }
            used = prefix
        }
        if let attribute = XMLNode.attribute(withName: "\(used ?? prefix):\(name)", uri: uri, stringValue: value) as? XMLNode {
            target.addAttribute(attribute)
        }
    }

    private static func matches(_ node: XMLNode, in scope: XMLElement, name: String, uri: String) -> Bool {
        guard node.localName == name, let qualified = node.name else { return false }
        let resolved = node.uri ?? scope.resolveNamespace(forName: qualified)?.stringValue
        return resolved == uri
    }
}

// MARK: - Вид

/// Цвет и звёзды кадра, по ним можно кликнуть. Клик по уже поставленной звезде снимает звёзды
struct MarkEditor: View {
    let mark: PhotoMark
    var size: CGFloat = 10
    /// Пустые звёзды и кружок цвета видны (наведение, выбранный кадр, просмотр); иначе — только поставленное
    var showsEmpty = true
    let onRating: (Int) -> Void
    let onColor: (Int) -> Void

    @Environment(\.theme) private var theme
    @State private var hoverStar: Int?
    @State private var picking = false

    var body: some View {
        HStack(spacing: size * 0.4) {
            if showsEmpty || mark.color > 0 {
                colorButton
            }
            if showsEmpty || mark.rating > 0 {
                stars
            }
        }
        .fixedSize()
    }

    private var stars: some View {
        let shown = showsEmpty ? 5 : mark.rating
        let lit = hoverStar ?? mark.rating
        return HStack(spacing: 0) {
            ForEach(1...max(shown, 1), id: \.self) { n in
                Button {
                    onRating(n == mark.rating ? 0 : n)
                } label: {
                    Image(systemName: n <= lit ? "star.fill" : "star")
                        .font(.system(size: size, weight: .semibold))
                        .foregroundStyle(n <= lit ? (hoverStar == nil ? theme.c.text1 : theme.c.accent) : theme.c.text3)
                        .frame(width: size + 5, height: size + 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        hoverStar = n
                    } else if hoverStar == n {
                        hoverStar = nil
                    }
                }
                .help(n == mark.rating ? "Снять звёзды (⌥0)" : "\(n) \(PhotoSession.plural(n, "звезда", "звезды", "звёзд")) (⌥\(n))")
            }
        }
    }

    private var colorButton: some View {
        let current = ColorClass(rawValue: mark.color)
        return Button {
            picking.toggle()
        } label: {
            dot(current, diameter: size + 2)
                .frame(width: size + 6, height: size + 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(current.map { "Цвет: \($0.title)" } ?? "Цветовая метка")
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            palette
        }
    }

    /// Выбор цвета: «без цвета» и восемь меток
    private var palette: some View {
        HStack(spacing: 4) {
            swatch(0)
            ForEach(ColorClass.allCases) { color in
                swatch(color.rawValue)
            }
        }
        .padding(8)
    }

    private func swatch(_ value: Int) -> some View {
        let color = ColorClass(rawValue: value)
        return Button {
            onColor(value)
            picking = false
        } label: {
            dot(color, diameter: 16)
                .padding(3)
                .overlay {
                    if value == mark.color {
                        Circle().strokeBorder(theme.c.text1, lineWidth: 1.5)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.map { "\($0.title) (⌃\(value))" } ?? "Без цвета (⌃0)")
    }

    @ViewBuilder
    private func dot(_ color: ColorClass?, diameter: CGFloat) -> some View {
        if let color {
            Circle()
                .fill(color.color)
                .frame(width: diameter, height: diameter)
        } else {
            Circle()
                .strokeBorder(theme.c.text3, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                .frame(width: diameter, height: diameter)
        }
    }
}

/// Подсказка клавиш в нижней строке
enum MarkHints {
    static var group: HintGroup {
        HintGroup(title: "Оценка", hints: [
            Hint("⌥1–5", label: "звёзды"),
            Hint("⌃1–8", label: "цвет")
        ])
    }
}
