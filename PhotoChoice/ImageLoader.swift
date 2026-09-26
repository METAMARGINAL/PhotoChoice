import AppKit
import ImageIO
import Foundation

private struct ImageBox: @unchecked Sendable {
    let image: NSImage?
}

enum ImageLoader {
    nonisolated(unsafe) private static let cache = NSCache<NSURL, NSImage>()

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
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    static func imageAsync(at url: URL, maxPixelSize: CGFloat = 2400) async -> NSImage? {
        let box = await Task.detached(priority: .userInitiated) {
            ImageBox(image: ImageLoader.image(at: url, maxPixelSize: maxPixelSize))
        }.value
        return box.image
    }

    static func prefetch(_ urls: [URL]) {
        Task.detached(priority: .userInitiated) {  
            for url in urls where ImageLoader.cachedImage(at: url) == nil {
                _ = ImageLoader.image(at: url)
            }
        }
    }

    nonisolated static func evict(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    private nonisolated static func decode(_ url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return NSImage(contentsOf: url)
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
