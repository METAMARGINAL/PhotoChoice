import Foundation
import ImageIO

/// Шаблон имени при переименовании по метаданным
nonisolated enum RenameStyle: String, CaseIterable, Identifiable, Sendable {
    /// 2026-06-14_174212_DSC_0452
    case dateTimeOriginal
    /// 20260614-174212_DSC_0452
    case compactDateTimeOriginal
    /// 2026-06-14_174212 (серия в одну секунду — с долями секунды или суффиксом)
    case dateTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateTimeOriginal: "Дата, время и исходное имя"
        case .compactDateTimeOriginal: "Компактно: дата, время и исходное имя"
        case .dateTime: "Только дата и время"
        }
    }

    var example: String {
        switch self {
        case .dateTimeOriginal: "2026-06-14_174212_DSC_0452.JPG"
        case .compactDateTimeOriginal: "20260614-174212_DSC_0452.JPG"
        case .dateTime: "2026-06-14_174212.JPG"
        }
    }

    fileprivate var stampFormat: String {
        switch self {
        case .dateTimeOriginal, .dateTime: "yyyy-MM-dd_HHmmss"
        case .compactDateTimeOriginal: "yyyyMMdd-HHmmss"
        }
    }
}

/// Имя файла по метаданным: дата и время съёмки из EXIF, а если их нет — дата изменения файла
nonisolated enum MetadataNaming {
    /// Новое имя без расширения для кадра
    static func baseName(for url: URL, style: RenameStyle) -> String {
        let original = url.deletingPathExtension().lastPathComponent
        let capture = captureDate(url)
        guard let date = capture?.date ?? modificationDate(url) else { return original }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = style.stampFormat
        let stamp = formatter.string(from: date)

        // Файл уже назван по этой схеме (например, отбирают второй раз) — не добавляем дату повторно
        if original.hasPrefix(stamp) { return original }

        switch style {
        case .dateTimeOriginal, .compactDateTimeOriginal:
            return "\(stamp)_\(original)"
        case .dateTime:
            // Доли секунды разводят кадры серии; остальные совпадения решит суффикс _2, _3…
            if let subsec = capture?.subsec, !subsec.isEmpty {
                return "\(stamp)-\(subsec.prefix(2))"
            }
            return stamp
        }
    }

    /// Пример имени для настроек: на реальном кадре, если он есть
    static func preview(for url: URL?, style: RenameStyle) -> String {
        guard let url else { return style.example }
        return baseName(for: url, style: style) + "." + url.pathExtension
    }

    // MARK: - Порядок по времени съёмки

    /// Кадры по времени съёмки, а не по имени: снимки с разных камер встают вперемешку, как снимались.
    /// Без даты в EXIF — по дате изменения файла; при равенстве остаётся исходный порядок
    static func sortedByCaptureDate(_ urls: [URL]) -> [URL] {
        var dates = [Date?](repeating: nil, count: urls.count)
        // Читается только заголовок файла; потоков сколько ядер — тысяча кадров за доли секунды
        dates.withUnsafeMutableBufferPointer { buffer in
            let out = buffer
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                out[i] = sortDate(urls[i])
            }
        }
        return urls.indices.sorted { a, b in
            switch (dates[a], dates[b]) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a < b
            }
        }.map { urls[$0] }
    }

    /// Время съёмки с долями секунды (серия в одну секунду идёт по порядку), иначе дата изменения
    private static func sortDate(_ url: URL) -> Date? {
        guard let capture = captureDate(url) else { return modificationDate(url) }
        if let subsec = capture.subsec, !subsec.isEmpty, let fraction = Double("0." + subsec) {
            return capture.date.addingTimeInterval(fraction)
        }
        return capture.date
    }

    // MARK: - Чтение дат

    private static func captureDate(_ url: URL) -> (date: Date, subsec: String?)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        guard let raw = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
                ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String)
                ?? (tiff[kCGImagePropertyTIFFDateTime] as? String) else { return nil }

        guard let date = exifParser.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }

        let subsec = (exif[kCGImagePropertyExifSubsecTimeOriginal] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (date, subsec)
    }

    /// Время в EXIF записано по часам камеры, без часового пояса — читаем и пишем в одном поясе.
    /// Один на все вызовы: DateFormatter дорог в создании, а разбор потокобезопасен
    nonisolated(unsafe) private static let exifParser: DateFormatter = {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return parser
    }()

    private static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
