import Foundation
import UIKit
#if canImport(ImagePlayground) && !MUREKKEP_PLAIN
import ImagePlayground
#endif

/// Hand-drawn illustrations for a video overview's title, questions and section cards, made on the
/// iPad by Image Playground (Apple Intelligence, iPadOS 18.4+) in its sketch style. Without Apple
/// Intelligence nothing is drawn and the slides keep their symbols.
enum StudioIllustrator {
    static let maxPictures = 8

    static func illustrate(_ overview: inout Overview, folder: URL, progress: @MainActor (Double) -> Void) async {
        #if canImport(ImagePlayground) && !MUREKKEP_PLAIN
        if #available(iOS 18.4, *) {
            guard let creator = try? await ImageCreator() else { return }
            let styles = creator.availableStyles
            guard let style = [ImagePlaygroundStyle.sketch, .illustration, .animation].first(where: { styles.contains($0) }) else { return }
            let targets = Array(overview.scenes.indices.filter { i in
                let layout = overview.scenes[i].layout
                return layout == .title || layout == .question || layout == .section
            }.prefix(maxPictures))
            for (n, i) in targets.enumerated() {
                if Task.isCancelled { return }
                await progress(Double(n) / Double(max(targets.count, 1)))
                let scene = overview.scenes[i]
                let subject = VideoOutline.plain(scene.title)
                let about = String(VideoOutline.plain(scene.narration).prefix(600))
                var image = await firstImage(creator, [.extracted(from: about, title: subject)], style)
                if image == nil {
                    image = await firstImage(creator, [.text(subject)], style)
                }
                guard let image, let data = UIImage(cgImage: image).pngData() else { continue }
                let name = "art-\(scene.id.uuidString).png"
                if (try? data.write(to: folder.appendingPathComponent(name), options: .atomic)) != nil {
                    overview.scenes[i].art = "file:" + name
                }
            }
        }
        #endif
    }

    #if canImport(ImagePlayground) && !MUREKKEP_PLAIN
    @available(iOS 18.4, *)
    private static func firstImage(_ creator: ImageCreator, _ concepts: [ImagePlaygroundConcept],
                                   _ style: ImagePlaygroundStyle) async -> CGImage? {
        do {
            for try await created in creator.images(for: concepts, style: style, limit: 1) {
                return created.cgImage
            }
        } catch {
            return nil
        }
        return nil
    }
    #endif
}
