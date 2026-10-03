//
//  PaletteExtractor.swift
//  Основные цвета изображения: k-means в цветовом пространстве OKLab.
//

import Foundation
import CoreGraphics
import ImageIO
import SwiftUI

// MARK: - Модель цвета

nonisolated struct PaletteColor: Identifiable, Hashable, Sendable {
    let id: Int
    let red: Double        // sRGB, 0…1
    let green: Double
    let blue: Double
    let lightness: Double  // OKLab L, 0…1
    let hue: Double        // угол оттенка в OKLab, радианы
    let chroma: Double     // насыщенность в OKLab
    let share: Double      // доля пикселей кадра, 0…1

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    var hex: String {
        String(format: "#%02X%02X%02X",
               Int((red * 255).rounded()),
               Int((green * 255).rounded()),
               Int((blue * 255).rounded()))
    }

    var isLight: Bool { lightness > 0.65 }
}

nonisolated enum PaletteSort: String, CaseIterable, Identifiable, Sendable {
    case lightness = "Светлота"
    case hue = "Оттенок"
    case share = "Доля"

    var id: Self { self }
}

nonisolated extension Array where Element == PaletteColor {
    func ordered(by mode: PaletteSort) -> [PaletteColor] {
        switch mode {
        case .lightness:
            return sorted { $0.lightness < $1.lightness }
        case .hue:
            // Хроматические — по кругу оттенков, нейтральные — в конце по светлоте.
            let chromatic = filter { $0.chroma >= 0.03 }.sorted { $0.hue < $1.hue }
            let neutral = filter { $0.chroma < 0.03 }.sorted { $0.lightness < $1.lightness }
            return chromatic + neutral
        case .share:
            return sorted { $0.share > $1.share }
        }
    }
}

// MARK: - Извлечение

nonisolated enum PaletteExtractor {

    /// Запасной путь: миниатюра с диска через ImageIO.
    /// `IfAbsent` — для RAW/JPEG берётся встроенное превью, если есть (быстро, без полного проявления RAW).
    static func thumbnail(at url: URL, maxPixelSize: Int = 256) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Основные цвета. Принимает изображение любого размера — внутри оно рисуется в ≤ `analysisSize` px.
    /// Поддерживает отмену: если текущая Task отменена, возвращает [].
    static func extract(from image: CGImage,
                        count: Int = 10,
                        analysisSize: Int = 256,
                        iterations: Int = 20) -> [PaletteColor] {
        let samples = labPixels(of: image, maxPixelSize: analysisSize)
        guard !samples.isEmpty, count > 0 else { return [] }

        var centers = seedCenters(samples, k: min(count, samples.count))
        var assignment = [Int](repeating: 0, count: samples.count)

        for _ in 0..<iterations {
            if Task.isCancelled { return [] }

            var changed = false
            for i in samples.indices {
                let nearest = nearestCenter(to: samples[i], in: centers)
                if nearest != assignment[i] {
                    assignment[i] = nearest
                    changed = true
                }
            }

            var sums = [SIMD3<Float>](repeating: .zero, count: centers.count)
            var counts = [Int](repeating: 0, count: centers.count)
            for i in samples.indices {
                sums[assignment[i]] += samples[i]
                counts[assignment[i]] += 1
            }
            for j in centers.indices where counts[j] > 0 {
                centers[j] = sums[j] / Float(counts[j])
            }

            if !changed { break }
        }

        var counts = [Int](repeating: 0, count: centers.count)
        for a in assignment { counts[a] += 1 }
        let total = Double(samples.count)

        return centers.indices.compactMap { j -> PaletteColor? in
            guard counts[j] > 0 else { return nil }
            let lab = centers[j]
            let rgb = OKLab.toSRGB(lab)
            return PaletteColor(
                id: j,
                red: Double(rgb.x),
                green: Double(rgb.y),
                blue: Double(rgb.z),
                lightness: Double(lab.x),
                hue: Double(atan2(lab.z, lab.y)),
                chroma: Double((lab.y * lab.y + lab.z * lab.z).squareRoot()),
                share: Double(counts[j]) / total
            )
        }
    }

    // MARK: Пиксели → OKLab

    private static func labPixels(of image: CGImage, maxPixelSize: Int) -> [SIMD3<Float>] {
        let scale = min(1, Double(maxPixelSize) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return [] }

        // Отрисовка в sRGB-контекст приводит любой профиль (P3, AdobeRGB, Gray) к sRGB и заодно уменьшает.
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return [] }

        let pixelCount = width * height
        let px = data.bindMemory(to: UInt8.self, capacity: pixelCount * 4)

        var result: [SIMD3<Float>] = []
        result.reserveCapacity(pixelCount)

        for i in 0..<pixelCount {
            let alpha = Float(px[i * 4 + 3])
            guard alpha > 127 else { continue }
            let rgb = SIMD3<Float>(Float(px[i * 4]) / alpha,
                                   Float(px[i * 4 + 1]) / alpha,
                                   Float(px[i * 4 + 2]) / alpha)
            result.append(OKLab.fromSRGB(rgb))
        }
        return result
    }

    // MARK: k-means++

    private static func seedCenters(_ samples: [SIMD3<Float>], k: Int) -> [SIMD3<Float>] {
        var rng = SplitMix64(seed: 42)
        var centers = [samples[Int.random(in: samples.indices, using: &rng)]]
        var distances = samples.map { distanceSquared($0, centers[0]) }

        while centers.count < k {
            let total = distances.reduce(0, +)
            guard total > 0 else { break }

            var target = Float.random(in: 0..<total, using: &rng)
            var chosen = samples.count - 1
            for (i, d) in distances.enumerated() {
                target -= d
                if target <= 0 { chosen = i; break }
            }

            let center = samples[chosen]
            centers.append(center)
            for i in samples.indices {
                distances[i] = Swift.min(distances[i], distanceSquared(samples[i], center))
            }
        }
        return centers
    }

    private static func nearestCenter(to point: SIMD3<Float>, in centers: [SIMD3<Float>]) -> Int {
        var best = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for (j, center) in centers.enumerated() {
            let d = distanceSquared(point, center)
            if d < bestDistance {
                bestDistance = d
                best = j
            }
        }
        return best
    }

    @inline(__always)
    private static func distanceSquared(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return (d * d).sum()
    }
}

// MARK: - OKLab (Björn Ottosson, 2020)

nonisolated enum OKLab {
    static func fromSRGB(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let r = toLinear(c.x), g = toLinear(c.y), b = toLinear(c.z)

        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

        let L: Float = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A: Float = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let B: Float = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return SIMD3(L, A, B)
    }

    static func toSRGB(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        let l_: Float = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
        let m_: Float = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
        let s_: Float = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z

        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_

        let r: Float =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g: Float = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b: Float = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return SIMD3(toGamma(r), toGamma(g), toGamma(b))
    }

    private static func toLinear(_ v: Float) -> Float {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func toGamma(_ v: Float) -> Float {
        let v = Swift.min(Swift.max(v, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}

// MARK: - Детерминированный ГСЧ

nonisolated private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
