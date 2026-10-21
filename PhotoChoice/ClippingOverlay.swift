import AppKit
import CoreGraphics
import SwiftUI

// Подсветка пересветов и провалов поверх кадра — включается треугольниками на гистограмме в сведениях (настройки
// `clipHighlights`, `clipShadows`). Считается по той картинке, что на экране: превью 2400 px, а при зуме — полное
// разрешение. Определения те же, что у гистограммы

nonisolated enum ClippingMask {
    /// Красный — выбит хотя бы один канал (= 255), синий — почти чёрное (все каналы ≤ 2). Остальное прозрачно.
    /// Больше `maxSide` не считаем: маска растягивается без сглаживания, и на экране этого хватает
    static func make(_ image: CGImage, highlights: Bool, shadows: Bool, maxSide: Int = 4000) -> CGImage? {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale))
        let h = max(1, Int(Double(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        // Цвета непрозрачные, поэтому premultiplied не мешает
        var mask = [UInt8](repeating: 0, count: w * h * 4)
        var found = false
        pixels.withUnsafeBufferPointer { p in
            mask.withUnsafeMutableBufferPointer { m in
                var i = 0
                let end = w * h * 4
                while i < end {
                    let r = p[i], g = p[i + 1], b = p[i + 2]
                    if highlights && (r == 255 || g == 255 || b == 255) {
                        m[i] = 255; m[i + 1] = 40; m[i + 2] = 40; m[i + 3] = 255
                        found = true
                    } else if shadows && max(r, g, b) <= 2 {
                        m[i] = 40; m[i + 1] = 110; m[i + 2] = 255; m[i + 3] = 255
                        found = true
                    }
                    i += 4
                }
            }
        }
        guard found else { return nil }

        guard let provider = CGDataProvider(data: Data(mask) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

private struct MaskBox: @unchecked Sendable {
    let image: CGImage?
}

/// Слой поверх `Image(nsImage:)…scaledToFit()` — в его рамке; маска считается в фоне для каждой новой картинки
struct ClippingLayer: View {
    let url: URL
    let image: NSImage
    let highlights: Bool
    let shadows: Bool

    @State private var mask: CGImage?
    @State private var maskURL: URL?

    private struct Key: Hashable {
        let image: ObjectIdentifier
        let highlights: Bool
        let shadows: Bool
    }

    var body: some View {
        ZStack {
            // Пока считается маска для полного разрешения, видна прежняя — того же кадра
            if let mask, maskURL == url {
                Image(decorative: mask, scale: 1)
                    .resizable()
                    .interpolation(.none)
            }
        }
        .allowsHitTesting(false)
        .task(id: Key(image: ObjectIdentifier(image), highlights: highlights, shadows: shadows)) {
            let source = MaskBox(image: image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let target = url
            let (high, low) = (highlights, shadows)
            let result = await Task.detached(priority: .userInitiated) {
                MaskBox(image: source.image.flatMap { ClippingMask.make($0, highlights: high, shadows: low) })
            }.value
            guard !Task.isCancelled else { return }
            mask = result.image
            maskURL = target
        }
    }
}
