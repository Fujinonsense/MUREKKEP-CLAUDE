import SwiftUI
import UIKit

@main
struct MurekkepApp: App {
    /// iOS's background download events (the AI model comes down while the app is closed).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LibraryStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var studio = StudioStore()
    @StateObject private var study = StudyStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(studio)
                .environmentObject(study)
                .tint(Color(red: 0.10, green: 0.33, blue: 0.80))
                // Another language rebuilds every screen in it (dates and numbers follow too).
                .environment(\.locale, Locale(identifier: settings.language == .english ? "en_US" : "tr_TR"))
                .id(settings.language)
                // Qwen3.5 is the app's brain: it starts coming down by itself (Wi-Fi, in the background).
                .task { DeviceBrain.shared.startIfNeeded(automatic: settings.autoBrainDownload) }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    DeviceBrain.shared.startIfNeeded(automatic: settings.autoBrainDownload)
                }
        }
    }
}

extension InkColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    init(_ color: Color) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Float { Float(min(max(v, 0), 1)) }
        self.init(c(r), c(g), c(b), c(a))
    }
}
