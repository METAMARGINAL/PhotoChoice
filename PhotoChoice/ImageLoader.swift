import AppKit
import CoreGraphics
import ImageIO
import Foundation
import os

private struct ImageBox: @unchecked Sendable {
    let image: NSImage?
}

enum ImageLoader {
    /// Превью 2400 px — до ~15 МБ каждое; держим соседей текущего кадра, а не всё просмотренное
    nonisolated(unsafe) private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 12
        cache.totalCostLimit = 200 * 1024 * 1024
        return cache
    }()

    /// Номер последнего запроса предзагрузки: старые при быстром листании не декодируются
    nonisolated private static let prefetchRun = OSAllocatedUnfairLock(initialState: 0)

    nonisolated static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff",
        "webp", "gif", "bmp", "dng", "raf", "cr2", "cr3",
        "nef", "arw", "orf", "rw2"
    ]

    nonisolated static func isPhoto(_ url: URL) -> Bool {
        photoExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static func cachedImage(at url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    nonisolated static func image(at url: URL, maxPixelSize: CGFloat = 2400) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let image = decode(url, maxPixelSize: maxPixelSize) else { return nil }
        cache.setObject(image, forKey: url as NSURL, cost: cost(image))
        return image
    }

    static func imageAsync(at url: URL, maxPixelSize: CGFloat = 2400) async -> NSImage? {
        let box = await Task.detached(priority: .userInitiated) {
            ImageBox(image: ImageLoader.image(at: url, maxPixelSize: maxPixelSize))
        }.value
        return box.image
    }

    static func prefetch(_ urls: [URL]) {
        let run = prefetchRun.withLock { value -> Int in
            value += 1
            return value
        }
        Task.detached(priority: .userInitiated) {
            for url in urls where ImageLoader.cachedImage(at: url) == nil {
                guard ImageLoader.prefetchRun.withLock({ $0 }) == run else { return }
                _ = ImageLoader.image(at: url)
            }
        }
    }

    nonisolated static func evict(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
        fullCache.removeObject(forKey: url as NSURL)
    }

    /// Смена папки: картинки прошлой больше не нужны
    nonisolated static func removeAll() {
        cache.removeAllObjects()
        fullCache.removeAllObjects()
    }

    nonisolated private static func cost(_ image: NSImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }

    // MARK: Полное разрешение (для крупного зума в просмотре)

    /// Пара последних кадров в полном разрешении: ~100 МБ каждый, больше не держим
    nonisolated(unsafe) private static let fullCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 2
        return cache
    }()

    nonisolated static func cachedFullImage(at url: URL) -> NSImage? {
        fullCache.object(forKey: url as NSURL)
    }

    /// Больше 16384 px не создаётся IOSurface (IOSurface creation failed) — панорамы уменьшаем
    nonisolated static let maxFullSide: CGFloat = 16000

    /// Снимок в полном разрешении (с учётом поворота). Для RAW — самое крупное встроенное превью
    static func fullImageAsync(at url: URL) async -> NSImage? {
        if let cached = cachedFullImage(at: url) { return cached }
        let box = await Task.detached(priority: .userInitiated) {
            ImageBox(image: ImageLoader.decode(url, maxPixelSize: ImageLoader.maxFullSide))
        }.value
        if let image = box.image {
            fullCache.setObject(image, forKey: url as NSURL)
        }
        return box.image
    }

    /// Размер снимка в пикселях с учётом поворота (без декодирования)
    nonisolated static func pixelSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    private nonisolated static func decode(_ url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        // Битый файл с нулевым размером — не декодируем
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
           width == 0 || height == 0 {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return NSImage(contentsOf: url)
    }
}
