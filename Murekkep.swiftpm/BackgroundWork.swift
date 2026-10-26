import UIKit

/// iOS's background time for a job in hand (a script or a study set being written, an overview
/// being voiced): the app goes on for a while (about half a minute) after it leaves the screen, so
/// what Apple's model, Claude or the voices are doing can end instead of freezing where it was.
/// The GPU is not part of it: iOS refuses GPU work from an app in the background, so the downloaded
/// model stops at a token (BrainGate) and the job does that step again on screen (`retrying`).
@MainActor
final class BackgroundWork {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Time is up: the task ends here, or iOS ends the app.
            Task { @MainActor in self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }

    /// Runs an AI step of a job. When the app goes to the background in the middle of it, the
    /// downloaded model stops (`BrainInterrupted`): the step is not handed to a lesser writer; it
    /// waits for the app to be back on screen, says so through `paused`, and starts over.
    static func retrying<T>(paused: (String) -> Void, _ step: () async throws -> T) async throws -> T {
        while true {
            do {
                return try await step()
            } catch is BrainInterrupted {
                paused(Loc.t("Uygulama arka plana geçince durdu; geri dönünce yeniden başlar."))
                await waitUntilActive()
                try Task.checkCancellation()
            }
        }
    }

    /// Returns when the app is on screen (at once when it already is).
    static func waitUntilActive() async {
        while UIApplication.shared.applicationState != .active {
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
                break
            }
        }
    }
}
