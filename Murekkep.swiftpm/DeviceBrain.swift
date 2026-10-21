import Combine
import Foundation
import UIKit
import os

/// The downloadable model of this iPad: which one fits, whether it is on disk, and its download.
/// Kept in Application Support/Murekkep/Brains/<model>/, out of the iCloud backup. State changes happen
/// on the main thread.
final class DeviceBrain: ObservableObject {
    static let shared = DeviceBrain()

    enum Phase: Equatable {
        case absent
        case downloading(done: Int64, total: Int64)
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .absent
    /// The model on disk, or the strongest one this iPad can run (nil when it has too little memory).
    @Published private(set) var model: BrainModel?

    private var download: Task<Void, Never>?

    private init() {
        let recommended = BrainModel.best(physicalMemory: ProcessInfo.processInfo.physicalMemory,
                                          available: Self.availableMemory())
        if let installed = BrainModel.all.first(where: { Self.isInstalled($0) }) {
            model = installed
            phase = .ready
        } else {
            model = recommended
        }
        let center = NotificationCenter.default
        // The GPU may not be used in the background: an answer in progress stops before the app goes.
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            BrainRuntime.pauseForBackground()
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            BrainRuntime.resume()
        }
        center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { await BrainRuntime.unloadIfIdle() }
        }
    }

    /// The model can answer now: on disk and the engine is in this build.
    var isReady: Bool { phase == .ready && BrainRuntime.isCompiledIn && directory != nil }

    var isDownloading: Bool {
        if case .downloading = phase { return true }
        return false
    }

    /// 0…1 while downloading.
    var fraction: Double? {
        guard case let .downloading(done, total) = phase, total > 0 else { return nil }
        return min(1, Double(done) / Double(total))
    }

    /// Where the model's files are, when they are all there.
    var directory: URL? {
        guard let model, Self.isInstalled(model) else { return nil }
        return Self.folder(model)
    }

    /// Why the model cannot answer, or nil.
    var unavailableReason: String? {
        if !BrainRuntime.isCompiledIn {
            return Loc.t("Bu derlemede indirilebilir model motoru (MLX) yok. Yeni derlemede gelir.")
        }
        guard let model else {
            return Loc.t("Bu iPad'in belleği indirilebilir model için yetmiyor (en az 6 GB gerekir).")
        }
        switch phase {
        case .ready: return nil
        case .downloading: return Loc.t("{0} indiriliyor…", model.title)
        case .absent, .failed: return Loc.t("{0} henüz indirilmedi (Ayarlar > Yapay zekâ beyni).", model.title)
        }
    }

    @MainActor
    func startDownload() {
        guard let model, download == nil, phase != .ready else { return }
        phase = .downloading(done: 0, total: model.bytes)
        UIApplication.shared.isIdleTimerDisabled = true
        let target = Self.folder(model)
        download = Task { @MainActor [weak self] in
            do {
                try await BrainFetcher.fetch(model, into: target) { done, total in
                    Task { @MainActor in
                        guard let self, self.isDownloading else { return }
                        self.phase = .downloading(done: done, total: total)
                    }
                }
                try Self.markInstalled(model)
                self?.phase = .ready
            } catch is CancellationError {
                self?.phase = .absent
            } catch let error as URLError where error.code == .cancelled {
                self?.phase = .absent
            } catch {
                self?.phase = .failed(BrainFetcher.friendly(error))
            }
            UIApplication.shared.isIdleTimerDisabled = false
            self?.download = nil
        }
    }

    /// Stops the download; what came is kept and the next download goes on from there.
    @MainActor
    func cancelDownload() {
        download?.cancel()
    }

    @MainActor
    func delete() {
        download?.cancel()
        guard let model else { return }
        Task {
            await BrainRuntime.unload()
            try? FileManager.default.removeItem(at: Self.folder(model))
        }
        phase = .absent
        self.model = BrainModel.best(physicalMemory: ProcessInfo.processInfo.physicalMemory,
                                     available: Self.availableMemory())
    }

    // MARK: Disk

    private static var root: URL? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true) else { return nil }
        var url = support.appendingPathComponent("Murekkep/Brains", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    static func folder(_ model: BrainModel) -> URL {
        (root ?? FileManager.default.temporaryDirectory).appendingPathComponent(model.folder, isDirectory: true)
    }

    private static func marker(_ model: BrainModel) -> URL {
        folder(model).appendingPathComponent("murekkep-complete.json")
    }

    static func isInstalled(_ model: BrainModel) -> Bool {
        FileManager.default.fileExists(atPath: marker(model).path)
    }

    private static func markInstalled(_ model: BrainModel) throws {
        let info = ["model": model.id, "date": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: info).write(to: marker(model), options: .atomic)
    }

    /// Bytes the app may still take before iOS stops it (nil when unknown).
    static func availableMemory() -> Int64? {
        let free = os_proc_available_memory()
        return free > 0 ? Int64(free) : nil
    }
}

/// Downloads a model's files from Hugging Face (public, no account). A file stops and goes on where
/// it stopped (HTTP Range), so a cut connection or a closed app never starts a 3 GB file over.
enum BrainFetcher {
    struct RemoteFile: Decodable {
        let type: String
        let path: String
        let size: Int64?
    }

    static func files(of id: String) async throws -> [RemoteFile] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(id)/tree/main") else {
            throw LocalAIError(Loc.t("Model adresi geçersiz."))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw LocalAIError(Loc.t("Model listesi alınamadı (HTTP {0}).", "\(status)"))
        }
        return try JSONDecoder().decode([RemoteFile].self, from: data)
            .filter { $0.type == "file" && BrainModel.wanted($0.path) }
    }

    static func fetch(_ model: BrainModel, into folder: URL,
                      progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let files = try await files(of: model.id)
        guard files.contains(where: { $0.path == "config.json" }),
              files.contains(where: { $0.path.hasSuffix(".safetensors") }) else {
            throw LocalAIError(Loc.t("Model dosyaları sunucuda bulunamadı."))
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let total = files.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        let have = files.reduce(Int64(0)) { sum, f in sum + min(f.size ?? 0, partialSize(folder, f.path)) }
        if let free = freeSpace(folder), free < total - have + 300_000_000 {
            throw LocalAIError(Loc.t("iPad'de yeterli yer yok: {0} gerekiyor.",
                                     BrainModel.sizeText(total - have + 300_000_000, english: Loc.isEnglish)))
        }
        var finished: Int64 = 0
        progress(have, total)
        for file in files {
            try Task.checkCancellation()
            let destination = folder.appendingPathComponent(file.path)
            if let size = file.size, fileSize(destination) == size {
                finished += size
                continue
            }
            guard let url = URL(string: "https://huggingface.co/\(model.id)/resolve/main/\(file.path)") else { continue }
            var attempt = 0
            while true {
                do {
                    let base = finished
                    try await RangeDownload.run(url: url, to: destination, expected: file.size) { got in
                        progress(base + got, total)
                    }
                    break
                } catch {
                    if error is CancellationError || Task.isCancelled { throw CancellationError() }
                    attempt += 1
                    if attempt > 5 { throw error }
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                }
            }
            finished += file.size ?? fileSize(destination)
            progress(finished, total)
        }
    }

    static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? -1
    }

    /// Bytes of a file already here, whole or partial.
    private static func partialSize(_ folder: URL, _ path: String) -> Int64 {
        let whole = fileSize(folder.appendingPathComponent(path))
        if whole >= 0 { return whole }
        return max(0, fileSize(folder.appendingPathComponent(path + ".part")))
    }

    private static func freeSpace(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func friendly(_ error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return Loc.t("İnternet bağlantısı yok. Wi-Fi'ye bağlanınca \"İndir\"e yeniden bas; kaldığı yerden devam eder.")
            case .timedOut:
                return Loc.t("Bağlantı zaman aşımına uğradı. \"İndir\"e yeniden bas; kaldığı yerden devam eder.")
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

/// One file over HTTP, appended to "<file>.part" as it arrives and moved into place when complete.
private final class RangeDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let destination: URL
    private let part: URL
    private let expected: Int64?
    private let onBytes: (Int64) -> Void
    private let lock = NSLock()
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var failure: Error?
    private var continuation: CheckedContinuation<Void, Error>?
    private var lastReport = Date.distantPast

    private init(destination: URL, expected: Int64?, onBytes: @escaping (Int64) -> Void) {
        self.destination = destination
        self.part = destination.appendingPathExtension("part")
        self.expected = expected
        self.onBytes = onBytes
    }

    static func run(url: URL, to destination: URL, expected: Int64?, onBytes: @escaping (Int64) -> Void) async throws {
        let download = RangeDownload(destination: destination, expected: expected, onBytes: onBytes)
        try await download.start(url)
    }

    private func start(_ url: URL) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: part.path) {
            fm.createFile(atPath: part.path, contents: nil)
        }
        received = max(0, BrainFetcher.fileSize(part))
        if let expected, received > expected {
            try Data().write(to: part)
            received = 0
        }
        if let expected, received == expected {
            try finish()
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if received > 0 {
            request.setValue("bytes=\(received)-", forHTTPHeaderField: "Range")
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.lock()
                continuation = c
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        try finish()
    }

    /// The whole file is in the part file: it becomes the file.
    private func finish() throws {
        if let expected, BrainFetcher.fileSize(part) != expected {
            throw LocalAIError(Loc.t("Dosya eksik indi; yeniden deneniyor."))
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: part, to: destination)
    }

    private func resume(_ error: Error?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        if let error { c?.resume(throwing: error) } else { c?.resume() }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            switch status {
            case 206:
                let h = try FileHandle(forWritingTo: part)
                try h.seekToEnd()
                handle = h
            case 200:
                // The server sent the whole file: start the part over.
                let h = try FileHandle(forWritingTo: part)
                try h.truncate(atOffset: 0)
                handle = h
                received = 0
            default:
                failure = LocalAIError(Loc.t("İndirme sunucusu yanıt vermedi (HTTP {0}).", "\(status)"))
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
            received += Int64(data.count)
            let now = Date()
            if now.timeIntervalSince(lastReport) > 0.25 {
                lastReport = now
                onBytes(received)
            }
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        onBytes(received)
        resume(failure ?? error)
    }
}
