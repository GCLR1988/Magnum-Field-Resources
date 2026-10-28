import UIKit
import ImageIO

/// Reuses decoded artwork across tiles and rows. Revision keys refresh changed logos.
@MainActor
final class LogoImageCache {
    static let shared = LogoImageCache()
    private let images = NSCache<NSString, UIImage>()

    private init() {
        images.countLimit = 40
        images.totalCostLimit = 24 * 1024 * 1024
    }

    func image(for file: DropboxFileMetadata) -> UIImage? {
        guard MediaCache.shared.isCached(file) else { return nil }
        let key = "\(file.id):\(file.rev)" as NSString
        if let image = images.object(forKey: key) { return image }
        // Decode only the pixels a tile needs, even if the uploaded logo is enormous.
        let url = MediaCache.shared.localURL(for: file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: thumbnail)
        images.setObject(image, forKey: key, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }

    func invalidate(_ file: DropboxFileMetadata) {
        images.removeObject(forKey: "\(file.id):\(file.rev)" as NSString)
    }

    func clear() {
        images.removeAllObjects()
    }
}
