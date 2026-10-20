import AVFoundation
import UIKit

enum OverviewExportError: LocalizedError {
    case writer(String)

    var errorDescription: String? {
        switch self {
        case let .writer(message): return message
        }
    }
}

/// Saves overviews as files to share: MP4 (Full HD slides with the narration) or M4A.
enum OverviewExporter {
    static let fps: Int32 = 30
    static let size = CGSize(width: 1920, height: 1080)

    @MainActor
    static func video(_ overview: Overview, folder: URL, assets: SlideAssets?,
                      progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let frames = folder.appendingPathComponent("export-frames.mp4")
        let output = folder.appendingPathComponent(OverviewFormatting.fileName(overview.title) + ".mp4")
        try? FileManager.default.removeItem(at: frames)
        try? FileManager.default.removeItem(at: output)
        // Not detached: "Vazgeç" cancels this task, and with it the frame loop. The loop itself runs
        // off the main thread (a nonisolated async function).
        try await renderFrames(overview, timeline: overview.timeline, assets: assets, to: frames) { value in
            Task { @MainActor in progress(0.92 * value) }
        }
        try Task.checkCancellation()
        progress(0.93)

        let comp = AVMutableComposition()
        let framesAsset = AVURLAsset(url: frames)
        guard let source = try await framesAsset.loadTracks(withMediaType: .video).first,
              let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw OverviewExportError.writer(Loc.t("Video kareleri okunamadı."))
        }
        let duration = try await framesAsset.load(.duration)
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
        try await OverviewAudio.addNarration(overview, folder: folder, to: comp)
        try await export(comp, preset: AVAssetExportPresetHighestQuality, type: .mp4, to: output)
        try? FileManager.default.removeItem(at: frames)
        progress(1)
        return output
    }

    static func audio(_ overview: Overview, folder: URL) async throws -> URL {
        let output = folder.appendingPathComponent(OverviewFormatting.fileName(overview.title) + ".m4a")
        try? FileManager.default.removeItem(at: output)
        let comp = try await OverviewAudio.composition(overview, folder: folder)
        try await export(comp, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: output)
        return output
    }

    private static func export(_ asset: AVAsset, preset: String, type: AVFileType, to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw OverviewExportError.writer(Loc.t("Dışa aktarma başlatılamadı."))
        }
        session.outputURL = url
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                cont.resume()
            }
        }
        guard session.status == .completed else {
            throw session.error ?? OverviewExportError.writer(Loc.t("Dışa aktarma tamamlanamadı."))
        }
    }

    /// Draws every frame of the slides into an H.264 file (no sound yet).
    private static func renderFrames(_ o: Overview, timeline: OverviewTimeline, assets: SlideAssets?, to url: URL,
                                     progress: @escaping (Double) -> Void) async throws {
        let width = Int(size.width)
        let height = Int(size.height)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw OverviewExportError.writer(Loc.t("Video kodlayıcı eklenemedi.")) }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? OverviewExportError.writer(Loc.t("Video yazılamadı."))
        }
        writer.startSession(atSourceTime: .zero)
        let count = max(1, Int((timeline.total * Double(fps)).rounded(.up)))
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        for n in 0..<count {
            if Task.isCancelled {
                writer.cancelWriting()
                throw CancellationError()
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 3_000_000)
            }
            // Each frame's text and images are released right away (thousands of frames).
            try autoreleasepool {
                guard let pool = adaptor.pixelBufferPool else { throw OverviewExportError.writer(Loc.t("Görüntü belleği ayrılamadı.")) }
                var made: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
                guard let buffer = made else { throw OverviewExportError.writer(Loc.t("Görüntü belleği ayrılamadı.")) }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space, bitmapInfo: info) {
                    // y down, like UIKit.
                    ctx.translateBy(x: 0, y: CGFloat(height))
                    ctx.scaleBy(x: 1, y: -1)
                    SlideRenderer.drawFrame(o, timeline: timeline, time: Double(n) / Double(fps), assets: assets, captions: true,
                                            size: size, staticBackground: true, in: ctx)
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                if !adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(n), timescale: fps)) {
                    throw writer.error ?? OverviewExportError.writer(Loc.t("Kare yazılamadı."))
                }
            }
            if n % 20 == 0 { progress(Double(n) / Double(count)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? OverviewExportError.writer(Loc.t("Video tamamlanamadı."))
        }
    }
}
