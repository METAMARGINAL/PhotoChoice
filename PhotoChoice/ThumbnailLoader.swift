import AppKit
import Foundation
import ImageIO
import os

/// Сведения о снимке для подписи в сетке
nonisolated struct PhotoInfo: Sendable {
    var fileSize: Int64?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var camera: String?
}

/// Миниатюра + сведения. Класс, чтобы класть в NSCache
nonisolated final class Thumbnail: @unchecked Sendable {
    let image: NSImage?
    let info: PhotoInfo

    init(image: NSImage?, info: PhotoInfo) {
        self.image = image
        self.info = info
    }
}

enum ThumbnailLoader {
    /// Размер миниатюры по длинной стороне. Один на все масштабы сетки, чтобы не перечитывать файлы при смене масштаба
    nonisolated static let maxPixelSize: CGFloat = 900

    nonisolated(unsafe) private static let cache: NSCache<NSURL, Thumbnail> = {
        let cache = NSCache<NSURL, Thumbnail>()
        cache.totalCostLimit = 600 * 1024 * 1024
        return cache
    }()

    /// Ограничиваем число одновременных декодов, иначе RAW‑файлы кладут диск и CPU
    nonisolated(unsafe) private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        return queue
    }()

    nonisolated static func cached(_ url: URL) -> Thumbnail? {
        cache.object(forKey: url as NSURL)
    }

    nonisolated static func evict(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    static func load(_ url: URL) async -> Thumbnail? {
        if let cached = cached(url) {
            return cached
        }
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Thumbnail?, Never>) in
                enqueue(url, cancelled: cancelled, continuation: continuation)
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    /// nonisolated, чтобы замыкание операции не унаследовало MainActor
    private nonisolated static func enqueue(
        _ url: URL,
        cancelled: OSAllocatedUnfairLock<Bool>,
        continuation: CheckedContinuation<Thumbnail?, Never>
    ) {
        queue.addOperation {
            // Ячейку уже прокрутили — не тратим время на декод
            if cancelled.withLock({ $0 }) {
                continuation.resume(returning: nil)
                return
            }
            continuation.resume(returning: makeThumbnail(url))
        }
    }

    private nonisolated static func makeThumbnail(_ url: URL) -> Thumbnail? {
        if let cached = cached(url) {
            return cached
        }
        var info = PhotoInfo()
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            info.fileSize = Int64(size)
        }

        var image: NSImage?
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                info.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int
                info.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
                if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
                   let model = tiff[kCGImagePropertyTIFFModel] as? String {
                    info.camera = model.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // Для повёрнутых кадров меняем стороны местами
                if let orientation = props[kCGImagePropertyOrientation] as? Int, orientation >= 5,
                   let w = info.pixelWidth, let h = info.pixelHeight {
                    info.pixelWidth = h
                    info.pixelHeight = w
                }
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }

        let thumbnail = Thumbnail(image: image, info: info)
        let cost = image.map { Int($0.size.width * $0.size.height * 4) } ?? 1
        cache.setObject(thumbnail, forKey: url as NSURL, cost: cost)
        return thumbnail
    }
}
