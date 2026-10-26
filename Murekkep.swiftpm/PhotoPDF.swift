import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Photos become a PDF, one page per photo in the order given, so a photographed handout or a
/// whiteboard photo opens like any PDF: write on it, ask about it, make study sets from it.
enum PhotoPDF {
    /// A page's long side in points (A4's), whatever the photo's resolution.
    static let pageLong: CGFloat = 842
    /// A photo's long side in pixels after scaling down: sharp enough to zoom into, small enough
    /// that twenty phone photos stay a few megabytes.
    static let maxPixels: CGFloat = 2400

    /// The page for a photo of this (upright) size: the photo's own shape, as long as A4.
    static func pageSize(for photo: CGSize) -> CGSize {
        guard photo.width > 0, photo.height > 0 else { return CGSize(width: 595, height: 842) }
        let k = pageLong / max(photo.width, photo.height)
        return CGSize(width: (photo.width * k).rounded(), height: (photo.height * k).rounded())
    }

    /// The pixel size a photo is scaled down to (never up).
    static func scaledPixels(for pixels: CGSize) -> CGSize {
        let k = min(1, maxPixels / max(pixels.width, pixels.height, 1))
        return CGSize(width: (pixels.width * k).rounded(), height: (pixels.height * k).rounded())
    }

    /// A file name from a title: no characters that cannot be in one.
    static func fileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Photos" : cleaned
    }

    #if canImport(UIKit)
    /// Writes the photos (image file data, any format UIKit reads) as a PDF. Photos it cannot read
    /// are skipped; it returns how many pages it wrote. `progress` gets how many photos are done
    /// and how many there are, after each one. Decoding and scaling take a while, so this belongs
    /// on a background thread (the renderers are fine there).
    @discardableResult
    static func write(_ photos: [Data], to url: URL, progress: (Int, Int) -> Void = { _, _ in }) throws -> Int {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        var pages = 0
        try renderer.writePDF(to: url) { ctx in
            for (i, data) in photos.enumerated() {
                autoreleasepool {
                    guard let photo = UIImage(data: data), photo.size.width > 0, photo.size.height > 0 else { return }
                    let page = CGRect(origin: .zero, size: pageSize(for: photo.size))
                    ctx.beginPage(withBounds: page, pageInfo: [:])
                    scaled(photo).draw(in: page)
                    pages += 1
                }
                progress(i + 1, photos.count)
            }
        }
        return pages
    }

    /// The photo upright, scaled down and saved as JPEG, so the PDF keeps it compressed.
    private static func scaled(_ photo: UIImage) -> UIImage {
        let size = scaledPixels(for: CGSize(width: photo.size.width * photo.scale, height: photo.size.height * photo.scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            photo.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = upright.jpegData(compressionQuality: 0.85), let compressed = UIImage(data: jpeg) else { return upright }
        return compressed
    }
    #endif
}
