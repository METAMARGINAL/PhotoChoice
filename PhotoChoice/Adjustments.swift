import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Простая коррекция ползунками (клавиша E): свет и цвет, как в «Основных» у Lightroom, без кривых и масок.
// Живёт в `session.adjustments[url]`, оригинал не меняется никогда; результат — копия JPEG через «Сохранить копию».

nonisolated struct Adjustment: Hashable, Codable, Sendable {
    /// EV, −3…+3
    var exposure = 0.0
    // Остальные −100…+100
    var contrast = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var whites = 0.0
    var blacks = 0.0
    var temperature = 0.0
    var tint = 0.0
    var vibrance = 0.0
    var saturation = 0.0

    static let identity = Adjustment()

    var isIdentity: Bool { self == .identity }
}

/// Ползунки панели «Коррекция»
enum AdjustParam: CaseIterable, Identifiable {
    case exposure, contrast, highlights, shadows, whites, blacks, temperature, tint, vibrance, saturation

    var id: Self { self }

    static let light: [AdjustParam] = [.exposure, .contrast, .highlights, .shadows, .whites, .blacks]
    static let color: [AdjustParam] = [.temperature, .tint, .vibrance, .saturation]

    var title: String {
        switch self {
        case .exposure: "Экспозиция"
        case .contrast: "Контраст"
        case .highlights: "Светлые"
        case .shadows: "Тени"
        case .whites: "Белые"
        case .blacks: "Чёрные"
        case .temperature: "Температура"
        case .tint: "Оттенок"
        case .vibrance: "Красочность"
        case .saturation: "Насыщенность"
        }
    }

    var range: ClosedRange<Double> { self == .exposure ? -3...3 : -100...100 }

    var step: Double { self == .exposure ? 0.05 : 1 }

    var keyPath: WritableKeyPath<Adjustment, Double> {
        switch self {
        case .exposure: \.exposure
        case .contrast: \.contrast
        case .highlights: \.highlights
        case .shadows: \.shadows
        case .whites: \.whites
        case .blacks: \.blacks
        case .temperature: \.temperature
        case .tint: \.tint
        case .vibrance: \.vibrance
        case .saturation: \.saturation
        }
    }

    /// «+0,35», «−12», «0»
    func format(_ value: Double) -> String {
        guard value != 0 else { return "0" }
        let sign = value > 0 ? "+" : "−"
        let magnitude = abs(value)
        let text = self == .exposure
            ? String(format: "%.2f", magnitude).replacingOccurrences(of: ".", with: ",")
            : String(Int(magnitude.rounded()))
        return sign + text
    }

    /// Края шкалы — подсказка, куда тянуть
    var ends: (String, String)? {
        switch self {
        case .temperature: ("холоднее", "теплее")
        case .tint: ("зеленее", "пурпурнее")
        default: nil
        }
    }
}

/// Готовый кадр между очередью отрисовки и главным потоком
nonisolated final class CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

nonisolated enum AdjustRenderer {
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let queue = DispatchQueue(label: "PhotoChoice.adjust", qos: .userInitiated)
    private static let lock = NSLock()
    /// Номер последнего запроса: при перетаскивании ползунка устаревшие пропускаются
    nonisolated(unsafe) private static var latest = 0
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Кадр для экрана (превью или полное разрешение); nil — запрос устарел или не вышло
    @MainActor
    static func render(_ image: NSImage, _ adjustment: Adjustment) async -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let size = image.size
        let box = CGImageBox(cg)
        let ticket = lock.withLock { () -> Int in
            latest += 1
            return latest
        }
        let result: CGImageBox? = await withCheckedContinuation { continuation in
            queue.async {
                guard lock.withLock({ latest == ticket }) else {
                    continuation.resume(returning: nil)
                    return
                }
                let output = apply(CIImage(cgImage: box.image), adjustment)
                let rendered = context.createCGImage(output, from: output.extent, format: .RGBA8,
                                                     colorSpace: box.image.colorSpace ?? sRGB)
                continuation.resume(returning: rendered.map(CGImageBox.init))
            }
        }
        return result.map { NSImage(cgImage: $0.image, size: size) }
    }

    /// Цепочка фильтров; значения не зависят от размера кадра, поэтому превью и копия совпадают
    static func apply(_ input: CIImage, _ a: Adjustment) -> CIImage {
        var image = input

        if a.temperature != 0 || a.tint != 0 {
            // Чем «синее» считаем исходный свет, тем теплее становится кадр
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = image
            filter.neutral = CIVector(x: 6500 + a.temperature * 30, y: a.tint)
            filter.targetNeutral = CIVector(x: 6500, y: 0)
            image = filter.outputImage ?? image
        }

        if a.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(a.exposure)
            image = filter.outputImage ?? image
        }

        if a.highlights < 0 || a.shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = image
            filter.highlightAmount = Float(1 + min(a.highlights, 0) / 100 * 0.75)
            filter.shadowAmount = Float(a.shadows / 100)
            image = filter.outputImage ?? image
        }

        if a.whites != 0 || a.blacks != 0 || a.highlights > 0 {
            // Белые и чёрные двигают концы кривой, «светлые» вверх — её верхнюю четверть
            let filter = CIFilter.toneCurve()
            filter.inputImage = image
            filter.point0 = a.blacks >= 0 ? CGPoint(x: 0, y: a.blacks * 0.0015) : CGPoint(x: -a.blacks * 0.0015, y: 0)
            filter.point1 = CGPoint(x: 0.25, y: 0.25)
            filter.point2 = CGPoint(x: 0.5, y: 0.5)
            filter.point3 = CGPoint(x: 0.75, y: 0.75 + max(a.highlights, 0) * 0.0012)
            filter.point4 = a.whites >= 0 ? CGPoint(x: 1 - a.whites * 0.0015, y: 1) : CGPoint(x: 1, y: 1 + a.whites * 0.0015)
            image = filter.outputImage ?? image
        }

        if a.contrast != 0 || a.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.contrast = Float(1 + a.contrast / 100 * 0.35)
            filter.saturation = Float(1 + a.saturation / 100)
            filter.brightness = 0
            image = filter.outputImage ?? image
        }

        if a.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = image
            filter.amount = Float(a.vibrance / 100)
            image = filter.outputImage ?? image
        }

        return image.cropped(to: input.extent)
    }

    /// Копия в полном разрешении: JPEG с EXIF исходника (дата съёмки, камера), поворот уже применён.
    /// RAW проявляется заново через Core Image
    static func export(_ source: URL, _ adjustment: Adjustment, to target: URL, raw: Bool) -> Bool {
        let input: CIImage?
        if raw, let filter = CIRAWFilter(imageURL: source) {
            input = filter.outputImage
        } else {
            input = CIImage(contentsOf: source, options: [.applyOrientationProperty: true])
        }
        guard let input else { return false }
        let output = apply(input, adjustment)
        let space = input.colorSpace ?? sRGB
        guard let cg = context.createCGImage(output, from: output.extent, format: .RGBA8,
                                             colorSpace: space.model == .rgb ? space : sRGB),
              let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }

        var properties: [String: Any] = [:]
        if let src = CGImageSourceCreateWithURL(source as CFURL, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
                if let value = original[key as String] { properties[key as String] = value }
            }
            if var tiff = original[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                tiff[kCGImagePropertyTIFFOrientation as String] = 1
                properties[kCGImagePropertyTIFFDictionary as String] = tiff
            }
        }
        properties[kCGImagePropertyOrientation as String] = 1
        properties[kCGImageDestinationLossyCompressionQuality as String] = 0.92
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
