import Foundation

/// The app went to the background around an answer of the downloaded model: iOS lets no app use the
/// GPU there, so the answer stopped at a token (or could not start). Studio and the study tools do
/// the step again once the app is back on screen (BackgroundWork); the assistant says so and the
/// user asks again. Checked in tools/braincheck.
struct BrainInterrupted: LocalizedError, Equatable {
    /// The answer had started when the app went away (else the app was already away).
    let started: Bool

    var errorDescription: String? {
        started
            ? Loc.t("Uygulama arka plana geçtiği için yanıt durdu. Tekrar sor.")
            : Loc.t("Uygulama arka plandayken model çalışmaz. Tekrar sor.")
    }
}

/// Keeps the GPU out of the background: an answer may not start while the app is away, and going
/// away waits (briefly) for the running one to stop.
final class BrainGate: @unchecked Sendable {
    /// How long going to the background waits for a running answer to see the stop.
    static let stopWait: TimeInterval = 0.8

    private let lock = NSLock()
    private var paused = false
    private var running = 0

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    /// Answers running right now.
    var runningCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func enter() throws {
        lock.lock()
        defer { lock.unlock() }
        if paused {
            throw BrainInterrupted(started: false)
        }
        running += 1
    }

    func leave() {
        lock.lock()
        running -= 1
        lock.unlock()
    }

    func pause() {
        lock.lock()
        paused = true
        lock.unlock()
        let deadline = Date().addingTimeInterval(Self.stopWait)
        while Date() < deadline {
            lock.lock()
            let busy = running > 0
            lock.unlock()
            if !busy { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    func resume() {
        lock.lock()
        paused = false
        lock.unlock()
    }
}
