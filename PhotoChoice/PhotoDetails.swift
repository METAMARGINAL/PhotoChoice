import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Модель

nonisolated struct InfoRow: Sendable, Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

nonisolated struct InfoSection: Sendable, Identifiable {
    let title: String
    let rows: [InfoRow]
    var id: String { title }
}

nonisolated struct Histogram: Sendable {
    /// 256 значений на канал, нормированы в 0…1
    let red: [Double]
    let green: [Double]
    let blue: [Double]
    let luminance: [Double]
    /// Доля пикселей с выбитым хотя бы одним каналом
    let highlightsClipped: Double
    /// Доля почти чёрных пикселей
    let shadowsClipped: Double
}

nonisolated struct PhotoDetails: Sendable {
    var shutter: String?
    var aperture: String?
    var iso: String?
    var focal: String?
    var sections: [InfoSection] = []
    var histogram: Histogram?
    var mapURL: URL?
}

nonisolated final class PhotoDetailsBox: @unchecked Sendable {
    let details: PhotoDetails
    init(_ details: PhotoDetails) { self.details = details }
}

// MARK: - Загрузка

enum PhotoDetailsLoader {
    nonisolated(unsafe) private static let cache: NSCache<NSURL, PhotoDetailsBox> = {
        let cache = NSCache<NSURL, PhotoDetailsBox>()
        cache.countLimit = 400
        return cache
    }()

    nonisolated static func cached(_ url: URL) -> PhotoDetails? {
        cache.object(forKey: url as NSURL)?.details
    }

    static func load(_ url: URL) async -> PhotoDetails {
        if let cached = cached(url) { return cached }
        return await Task.detached(priority: .utility) {
            let details = PhotoDetailsLoader.read(url)
            PhotoDetailsLoader.cache.setObject(PhotoDetailsBox(details), forKey: url as NSURL)
            return details
        }.value
    }

    // MARK: Чтение метаданных

    nonisolated static func read(_ url: URL) -> PhotoDetails {
        var details = PhotoDetails()
        let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        let props = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        // Главные параметры
        if let t = number(exif[kCGImagePropertyExifExposureTime]), t > 0 {
            details.shutter = t < 1 ? "1/\(Int((1 / t).rounded()))" : "\(trim(t))″"
        }
        if let f = number(exif[kCGImagePropertyExifFNumber]), f > 0 {
            details.aperture = "ƒ/\(trim(f))"
        }
        if let isoList = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let iso = isoList.first {
            details.iso = "\(iso.intValue)"
        }
        let focal = number(exif[kCGImagePropertyExifFocalLength])
        let focal35 = number(exif[kCGImagePropertyExifFocalLenIn35mmFilm])
        if let focal, focal > 0 {
            details.focal = "\(trim(focal)) мм"
        }

        // Съёмка
        var shot: [InfoRow] = []
        if let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff[kCGImagePropertyTIFFDateTime] as? String {
            shot.append(InfoRow(label: "Дата", value: formatExifDate(raw)))
        }
        if let camera = cameraName(make: tiff[kCGImagePropertyTIFFMake] as? String, model: tiff[kCGImagePropertyTIFFModel] as? String) {
            shot.append(InfoRow(label: "Камера", value: camera))
        }
        if let lens = clean(exif[kCGImagePropertyExifLensModel] as? String) ?? clean(aux[kCGImagePropertyExifAuxLensModel] as? String) {
            shot.append(InfoRow(label: "Объектив", value: lens))
        }
        if let focal, focal > 0 {
            var value = "\(trim(focal)) мм"
            if let focal35, focal35 > 0, abs(focal35 - focal) >= 1 {
                value += " (экв. \(Int(focal35)) мм)"
            }
            shot.append(InfoRow(label: "Фокусное", value: value))
        }
        if let bias = number(exif[kCGImagePropertyExifExposureBiasValue]) {
            let sign = bias > 0.01 ? "+" : (bias < -0.01 ? "−" : "")
            shot.append(InfoRow(label: "Экспокоррекция", value: "\(sign)\(trim(abs(bias), digits: 2)) EV"))
        }
        if let program = number(exif[kCGImagePropertyExifExposureProgram]).flatMap({ exposurePrograms[Int($0)] }) {
            shot.append(InfoRow(label: "Режим", value: program))
        }
        if let metering = number(exif[kCGImagePropertyExifMeteringMode]).flatMap({ meteringModes[Int($0)] }) {
            shot.append(InfoRow(label: "Замер", value: metering))
        }
        if let flash = number(exif[kCGImagePropertyExifFlash]) {
            shot.append(InfoRow(label: "Вспышка", value: Int(flash) & 1 == 1 ? "Сработала" : "Не сработала"))
        }
        if let wb = number(exif[kCGImagePropertyExifWhiteBalance]) {
            shot.append(InfoRow(label: "Баланс белого", value: Int(wb) == 0 ? "Авто" : "Ручной"))
        }
        if !shot.isEmpty { details.sections.append(InfoSection(title: "Съёмка", rows: shot)) }

        // Изображение
        var image: [InfoRow] = []
        if var w = number(props[kCGImagePropertyPixelWidth]).map({ Int($0) }),
           var h = number(props[kCGImagePropertyPixelHeight]).map({ Int($0) }) {
            if let o = number(props[kCGImagePropertyOrientation]), Int(o) >= 5 { swap(&w, &h) }
            let mp = Double(w * h) / 1_000_000
            image.append(InfoRow(label: "Разрешение", value: "\(w) × \(h) · \(trim(mp)) Мп"))
            let shape = w == h ? "Квадрат" : (w > h ? "Горизонтальная" : "Вертикальная")
            image.append(InfoRow(label: "Ориентация", value: shape))
        }
        if let profile = clean(props[kCGImagePropertyProfileName] as? String) {
            image.append(InfoRow(label: "Профиль", value: profile))
        }
        if let depth = number(props[kCGImagePropertyDepth]) {
            image.append(InfoRow(label: "Глубина цвета", value: "\(Int(depth)) бит"))
        }
        if !image.isEmpty { details.sections.append(InfoSection(title: "Изображение", rows: image)) }

        // Устройство
        var device: [InfoRow] = []
        if let serial = clean(exif[kCGImagePropertyExifBodySerialNumber] as? String) ?? clean(aux[kCGImagePropertyExifAuxSerialNumber] as? String) {
            device.append(InfoRow(label: "Серийный №", value: serial))
        }
        if let firmware = clean(tiff[kCGImagePropertyTIFFSoftware] as? String) {
            device.append(InfoRow(label: "Прошивка / ПО", value: firmware))
        }
        if let frame = number(aux[kCGImagePropertyExifAuxImageNumber]) {
            device.append(InfoRow(label: "Номер кадра", value: "\(Int(frame))"))
        }
        if let artist = clean(tiff[kCGImagePropertyTIFFArtist] as? String) {
            device.append(InfoRow(label: "Автор", value: artist))
        }
        if let copyright = clean(tiff[kCGImagePropertyTIFFCopyright] as? String) {
            device.append(InfoRow(label: "Copyright", value: copyright))
        }
        if !device.isEmpty { details.sections.append(InfoSection(title: "Устройство", rows: device)) }

        // Место
        if let lat = number(gps[kCGImagePropertyGPSLatitude]), let lon = number(gps[kCGImagePropertyGPSLongitude]) {
            let latSigned = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -lat : lat
            let lonSigned = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -lon : lon
            var rows = [InfoRow(label: "Координаты", value: String(format: "%.5f, %.5f", latSigned, lonSigned))]
            if let alt = number(gps[kCGImagePropertyGPSAltitude]) {
                rows.append(InfoRow(label: "Высота", value: "\(Int(alt.rounded())) м"))
            }
            details.sections.append(InfoSection(title: "Место", rows: rows))
            details.mapURL = URL(string: String(format: "https://maps.apple.com/?ll=%.6f,%.6f&q=%.6f,%.6f", latSigned, lonSigned, latSigned, lonSigned))
        }

        // Файл
        var file: [InfoRow] = []
        let ext = url.pathExtension.uppercased()
        let typeName = UTType(filenameExtension: url.pathExtension)?.localizedDescription
        file.append(InfoRow(label: "Формат", value: typeName.map { "\(ext) · \($0)" } ?? ext))
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        if let size = values?.fileSize {
            file.append(InfoRow(label: "Размер", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        let fileDate = DateFormatter()
        fileDate.locale = Locale(identifier: "ru_RU")
        fileDate.dateFormat = "d MMM yyyy, HH:mm"
        if let created = values?.creationDate {
            file.append(InfoRow(label: "Создан", value: fileDate.string(from: created)))
        }
        if let modified = values?.contentModificationDate {
            file.append(InfoRow(label: "Изменён", value: fileDate.string(from: modified)))
        }
        file.append(InfoRow(label: "Папка", value: url.deletingLastPathComponent().path))
        details.sections.append(InfoSection(title: "Файл", rows: file))

        // Гистограмма по встроенному превью (быстро даже для RAW)
        if let source {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                details.histogram = histogram(from: cg)
            }
        }
        return details
    }

    // MARK: Гистограмма

    nonisolated static func histogram(from image: CGImage) -> Histogram? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var r = [Int](repeating: 0, count: 256)
        var g = [Int](repeating: 0, count: 256)
        var b = [Int](repeating: 0, count: 256)
        var l = [Int](repeating: 0, count: 256)
        var highs = 0
        var lows = 0
        let total = width * height

        pixels.withUnsafeBufferPointer { p in
            var i = 0
            for _ in 0..<total {
                let rv = Int(p[i]), gv = Int(p[i + 1]), bv = Int(p[i + 2])
                r[rv] += 1
                g[gv] += 1
                b[bv] += 1
                // Яркость по Rec.709, коэффициенты в сумме 256
                l[(rv * 54 + gv * 183 + bv * 19) >> 8] += 1
                if rv == 255 || gv == 255 || bv == 255 { highs += 1 }
                if max(rv, gv, bv) <= 2 { lows += 1 }
                i += 4
            }
        }

        let channels = [r, g, b, l].map(smooth)
        // Пик ищем без крайних значений, иначе пересвет сплющит весь график
        let peak = channels.map { Array($0[1...254]).max() ?? 0 }.max() ?? 0
        let norm = peak > 0 ? peak : 1
        let normalized = channels.map { $0.map { min(1, $0 / norm) } }

        return Histogram(
            red: normalized[0],
            green: normalized[1],
            blue: normalized[2],
            luminance: normalized[3],
            highlightsClipped: Double(highs) / Double(total),
            shadowsClipped: Double(lows) / Double(total)
        )
    }

    /// Лёгкое сглаживание: у 8‑битных превью гистограмма «гребёнкой»
    private nonisolated static func smooth(_ bins: [Int]) -> [Double] {
        (0..<256).map { i in
            let a = Double(bins[max(i - 1, 0)])
            let c = Double(bins[i])
            let d = Double(bins[min(i + 1, 255)])
            return (a + 2 * c + d) / 4
        }
    }

    // MARK: Хелперы

    private nonisolated static let exposurePrograms: [Int: String] = [
        1: "Ручной (M)",
        2: "Программа (P)",
        3: "Приоритет диафрагмы (A)",
        4: "Приоритет выдержки (S)",
        5: "Творческий",
        6: "Спорт",
        7: "Портрет",
        8: "Пейзаж"
    ]

    private nonisolated static let meteringModes: [Int: String] = [
        1: "Средний",
        2: "Центровзвешенный",
        3: "Точечный",
        4: "Мультиточечный",
        5: "Матричный",
        6: "Частичный"
    ]

    private nonisolated static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private nonisolated static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// 1.70 → «1.7», 8.0 → «8»
    private nonisolated static func trim(_ value: Double, digits: Int = 1) -> String {
        var text = String(format: "%.\(digits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// «NIKON CORPORATION» + «NIKON D850» → «NIKON D850»
    private nonisolated static func cameraName(make: String?, model: String?) -> String? {
        let make = clean(make)
        let model = clean(model)
        guard let model else { return make }
        guard let make, let brand = make.split(separator: " ").first else { return model }
        return model.lowercased().contains(brand.lowercased()) ? model : "\(make) \(model)"
    }

    private nonisolated static func formatExifDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = parser.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.locale = Locale(identifier: "ru_RU")
        out.dateFormat = "d MMMM yyyy, HH:mm:ss"
        return out.string(from: date)
    }
}
