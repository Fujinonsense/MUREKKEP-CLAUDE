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

    /// The file list is being fetched before the background download starts.
    private var preparing = false

    private init() {
        let recommended = BrainModel.best(physicalMemory: ProcessInfo.processInfo.physicalMemory,
                                          available: Self.availableMemory())
        if let installed = BrainModel.all.first(where: { Self.isInstalled($0) }) {
            model = installed
            phase = .ready
        } else {
            model = recommended
            // A download started earlier goes on (iOS may have been running it while the app was closed).
            if let recommended, BrainBackground.hasJob(for: recommended) {
                phase = .downloading(done: 0, total: recommended.bytes)
                BrainBackground.shared.resume(recommended)
            }
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

    /// Starts the download by itself when the app opens (and again after a failed try): Qwen is the
    /// app's brain, and it comes down in the background on Wi-Fi. Not after the user stopped it.
    @MainActor
    func startIfNeeded(automatic: Bool) {
        guard automatic, BrainRuntime.isCompiledIn, let model, !BrainBackground.isPaused(model) else { return }
        switch phase {
        case .absent, .failed: startDownload()
        case .downloading, .ready: break
        }
    }

    @MainActor
    func startDownload() {
        guard let model, !preparing, !isDownloading, phase != .ready else { return }
        preparing = true
        phase = .downloading(done: 0, total: model.bytes)
        BrainBackground.setPaused(false, model)
        Task { @MainActor [weak self] in
            defer { self?.preparing = false }
            do {
                let files = try await BrainFetcher.files(of: model.id)
                guard files.contains(where: { $0.path == "config.json" }),
                      files.contains(where: { $0.path.hasSuffix(".safetensors") }) else {
                    throw LocalAIError(Loc.t("Model dosyaları sunucuda bulunamadı."))
                }
                let plan = files.map { BrainDownloadPlan.File(path: $0.path, size: $0.size) }
                let folder = Self.folder(model)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let (have, total) = BrainDownloadPlan.progress(plan, disk: { BrainBackground.disk(folder, $0) }, inFlight: [:])
                if let free = BrainFetcher.freeSpace(folder), free < total - have + 300_000_000 {
                    throw LocalAIError(Loc.t("iPad'de yeterli yer yok: {0} gerekiyor.",
                                             BrainModel.sizeText(total - have + 300_000_000, english: Loc.isEnglish)))
                }
                self?.phase = .downloading(done: have, total: total)
                try BrainBackground.shared.start(model, files: plan)
            } catch {
                self?.phase = .failed(BrainFetcher.friendly(error))
            }
        }
    }

    /// Stops the download; what came is kept and the next download goes on from there.
    @MainActor
    func cancelDownload() {
        guard let model else { return }
        BrainBackground.setPaused(true, model)
        BrainBackground.shared.stop()
        phase = .absent
    }

    @MainActor
    func delete() {
        BrainBackground.shared.stop()
        guard let model else { return }
        Task {
            await BrainRuntime.unload()
            try? FileManager.default.removeItem(at: Self.folder(model))
        }
        phase = .absent
        self.model = BrainModel.best(physicalMemory: ProcessInfo.processInfo.physicalMemory,
                                     available: Self.availableMemory())
    }

    // MARK: Reports from the background download (main thread)

    @MainActor
    func downloadProgress(done: Int64, total: Int64) {
        guard phase != .ready, !BrainBackground.isPaused(model) else { return }
        phase = .downloading(done: done, total: total)
    }

    @MainActor
    func downloadFinished(_ finished: BrainModel) {
        guard finished == model else { return }
        phase = .ready
    }

    @MainActor
    func downloadFailed(_ message: String) {
        guard phase != .ready else { return }
        phase = .failed(message)
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

    static func markInstalled(_ model: BrainModel) throws {
        let info = ["model": model.id, "date": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: info).write(to: marker(model), options: .atomic)
    }

    /// Bytes the app may still take before iOS stops it (nil when unknown).
    static func availableMemory() -> Int64? {
        let free = os_proc_available_memory()
        return free > 0 ? Int64(free) : nil
    }
}

/// The list of a model's files on Hugging Face (public, no account).
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

    static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? -1
    }

    static func freeSpace(_ url: URL) -> Int64? {
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

/// The model's files come down in iOS's background download session: on Wi-Fi (not on mobile data
/// or in Low Data Mode), while the app is closed or another app is in front, and each file goes on
/// where it stopped (BrainDownloadPlan). iOS opens the app in the background to hand over files that
/// finished while it was closed (AppDelegate).
final class BrainBackground: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = BrainBackground()
    static let identifier = "com.murekkep.brain-download"

    /// iOS's completion handler for events of downloads that ended while the app was not running.
    var eventsDone: (() -> Void)?

    private struct Job: Codable {
        var modelID: String
        var files: [BrainDownloadPlan.File]
    }

    private let lock = NSLock()
    private var job: Job?
    private var inFlight: [String: Int64] = [:]
    private var attempts: [String: Int] = [:]
    private var stopped = false
    private var lastReport = Date.distantPast

    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    // MARK: State on disk

    private static func manifest(_ model: BrainModel) -> URL {
        DeviceBrain.folder(model).appendingPathComponent("murekkep-download.json")
    }

    private static func pausedMarker(_ model: BrainModel) -> URL {
        DeviceBrain.folder(model).appendingPathComponent("murekkep-paused")
    }

    static func hasJob(for model: BrainModel) -> Bool {
        FileManager.default.fileExists(atPath: manifest(model).path) && !isPaused(model)
    }

    static func isPaused(_ model: BrainModel?) -> Bool {
        guard let model else { return false }
        return FileManager.default.fileExists(atPath: pausedMarker(model).path)
    }

    static func setPaused(_ paused: Bool, _ model: BrainModel) {
        let url = pausedMarker(model)
        if paused {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func disk(_ folder: URL, _ path: String) -> BrainDownloadPlan.OnDisk {
        let file = folder.appendingPathComponent(path)
        return .init(whole: BrainFetcher.fileSize(file), part: BrainFetcher.fileSize(file.appendingPathExtension("part")))
    }

    // MARK: Starting and stopping

    func start(_ model: BrainModel, files: [BrainDownloadPlan.File]) throws {
        let job = Job(modelID: model.id, files: files)
        try JSONEncoder().encode(job).write(to: Self.manifest(model), options: .atomic)
        lock.lock()
        self.job = job
        stopped = false
        attempts = [:]
        lock.unlock()
        resume(model)
    }

    /// Picks up a download started earlier: the tasks iOS still runs stay, files with nothing running
    /// get a task from where their part file ends.
    func resume(_ model: BrainModel) {
        guard let data = try? Data(contentsOf: Self.manifest(model)),
              let saved = try? JSONDecoder().decode(Job.self, from: data) else { return }
        lock.lock()
        job = saved
        stopped = false
        lock.unlock()
        let folder = DeviceBrain.folder(model)
        session.getAllTasks { tasks in
            let running = Set(tasks.filter { $0.state == .running || $0.state == .suspended }.compactMap(\.taskDescription))
            for file in saved.files where !running.contains(file.path) {
                self.next(file, model: model, folder: folder)
            }
            self.checkComplete(model)
            self.report(model, force: true)
        }
    }

    /// Stops every download; what came stays on disk (and as resume data) for the next start.
    func stop() {
        let current = currentJob()
        lock.lock()
        stopped = true
        lock.unlock()
        session.getAllTasks { tasks in
            for task in tasks {
                guard let download = task as? URLSessionDownloadTask, let path = task.taskDescription,
                      let current, let model = BrainModel.all.first(where: { $0.id == current.modelID }) else {
                    task.cancel()
                    continue
                }
                let folder = DeviceBrain.folder(model)
                download.cancel(byProducingResumeData: { data in
                    if let data { try? data.write(to: folder.appendingPathComponent(path + ".resume")) }
                })
            }
        }
    }

    // MARK: One file

    /// The next thing a file needs: nothing, a move into place, or a download task.
    private func next(_ file: BrainDownloadPlan.File, model: BrainModel, folder: URL) {
        switch BrainDownloadPlan.step(file, Self.disk(folder, file.path)) {
        case .done:
            return
        case .finish:
            finish(file.path, folder: folder)
        case let .fetch(from):
            let resumeURL = folder.appendingPathComponent(file.path + ".resume")
            let task: URLSessionDownloadTask
            if let data = try? Data(contentsOf: resumeURL) {
                try? FileManager.default.removeItem(at: resumeURL)
                task = session.downloadTask(withResumeData: data)
            } else {
                guard let url = URL(string: "https://huggingface.co/\(model.id)/resolve/main/\(file.path)") else { return }
                var request = URLRequest(url: url)
                if from > 0 {
                    request.setValue("bytes=\(from)-", forHTTPHeaderField: "Range")
                }
                task = session.downloadTask(with: request)
            }
            task.taskDescription = file.path
            task.resume()
        }
    }

    /// The part file is whole: it becomes the file.
    private func finish(_ path: String, folder: URL) {
        let file = folder.appendingPathComponent(path)
        let fm = FileManager.default
        try? fm.removeItem(at: file)
        try? fm.moveItem(at: file.appendingPathExtension("part"), to: file)
    }

    /// The download in hand; after iOS opened the app in the background for finished files, it is
    /// read from the manifest first.
    private func currentJob() -> Job? {
        lock.lock()
        defer { lock.unlock() }
        if job == nil {
            for model in BrainModel.all {
                if let data = try? Data(contentsOf: Self.manifest(model)), let saved = try? JSONDecoder().decode(Job.self, from: data) {
                    job = saved
                    break
                }
            }
        }
        return job
    }

    /// The model and file a task belongs to.
    private func lookup(_ path: String) -> (BrainModel, URL, BrainDownloadPlan.File)? {
        guard let current = currentJob(), let model = BrainModel.all.first(where: { $0.id == current.modelID }),
              let file = current.files.first(where: { $0.path == path }) else { return nil }
        return (model, DeviceBrain.folder(model), file)
    }

    private func checkComplete(_ model: BrainModel) {
        guard let current = currentJob() else { return }
        let folder = DeviceBrain.folder(model)
        guard current.files.allSatisfy({ BrainDownloadPlan.step($0, Self.disk(folder, $0.path)) == .done }) else { return }
        try? DeviceBrain.markInstalled(model)
        try? FileManager.default.removeItem(at: Self.manifest(model))
        lock.lock()
        job = nil
        lock.unlock()
        Task { @MainActor in DeviceBrain.shared.downloadFinished(model) }
    }

    private func report(_ model: BrainModel, force: Bool = false) {
        guard let current = currentJob() else { return }
        lock.lock()
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) > 0.5 else {
            lock.unlock()
            return
        }
        lastReport = now
        let flying = inFlight
        lock.unlock()
        let folder = DeviceBrain.folder(model)
        let (done, total) = BrainDownloadPlan.progress(current.files, disk: { Self.disk(folder, $0) }, inFlight: flying)
        Task { @MainActor in DeviceBrain.shared.downloadProgress(done: done, total: total) }
    }

    // MARK: URLSession

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let path = downloadTask.taskDescription, let (model, _, _) = lookup(path) else { return }
        lock.lock()
        inFlight[path] = totalBytesWritten
        lock.unlock()
        report(model)
    }

    /// The downloaded bytes (the whole file, or the rest of it) go into the part file at once: iOS
    /// removes `location` when this returns.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let path = downloadTask.taskDescription, let (_, folder, file) = lookup(path) else { return }
        let response = downloadTask.response as? HTTPURLResponse
        let part = folder.appendingPathComponent(path + ".part")
        let fm = FileManager.default
        try? fm.createDirectory(at: part.deletingLastPathComponent(), withIntermediateDirectories: true)
        let merge = BrainDownloadPlan.merge(status: response?.statusCode ?? 0,
                                            rangeStart: BrainDownloadPlan.rangeStart(response?.value(forHTTPHeaderField: "Content-Range")),
                                            partSize: BrainFetcher.fileSize(part),
                                            received: BrainFetcher.fileSize(location), expected: file.size)
        switch merge {
        case .replace:
            try? fm.removeItem(at: part)
            try? fm.moveItem(at: location, to: part)
        case .append:
            guard let input = try? FileHandle(forReadingFrom: location),
                  let output = try? FileHandle(forWritingTo: part) else { return }
            defer {
                try? input.close()
                try? output.close()
            }
            _ = try? output.seekToEnd()
            while let chunk = try? input.read(upToCount: 8 << 20), !chunk.isEmpty {
                try? output.write(contentsOf: chunk)
            }
        case .discard:
            break
        }
        if BrainDownloadPlan.step(file, Self.disk(folder, path)) == .finish {
            finish(path, folder: folder)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let path = task.taskDescription, let (model, folder, file) = lookup(path) else { return }
        lock.lock()
        inFlight[path] = nil
        let halted = stopped
        lock.unlock()
        if let error, let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? data.write(to: folder.appendingPathComponent(path + ".resume"))
        }
        if !halted, BrainDownloadPlan.step(file, Self.disk(folder, path)) != .done {
            // Not whole yet (a failure, or bytes that did not fit): again, a few times, a little later.
            lock.lock()
            let tries = (attempts[path] ?? 0) + 1
            attempts[path] = tries
            lock.unlock()
            if tries <= 5 {
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(tries) * 3) {
                    self.next(file, model: model, folder: folder)
                }
            } else {
                let message = error.map(BrainFetcher.friendly) ?? Loc.t("İndirme sunucusu yanıt vermedi.")
                Task { @MainActor in DeviceBrain.shared.downloadFailed(message) }
            }
        }
        checkComplete(model)
        report(model, force: true)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.eventsDone?()
            self.eventsDone = nil
        }
    }
}

/// Hands iOS's background download events to the model's download.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == BrainBackground.identifier else {
            completionHandler()
            return
        }
        BrainBackground.shared.eventsDone = completionHandler
        _ = BrainBackground.shared.session
    }
}
