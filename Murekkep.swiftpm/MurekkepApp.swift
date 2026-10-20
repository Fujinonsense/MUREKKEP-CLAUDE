import SwiftUI
import UIKit

@main
struct MurekkepApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var studio = StudioStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(studio)
                .tint(Color(red: 0.10, green: 0.33, blue: 0.80))
                // Another language rebuilds every screen in it (dates and numbers follow too).
                .environment(\.locale, Locale(identifier: settings.language == .english ? "en_US" : "tr_TR"))
                .id(settings.language)
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
