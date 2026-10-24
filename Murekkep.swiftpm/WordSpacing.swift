import Foundation

/// The space between typed words (text pen and Aa box), in font units. Thick inks spread their letters
/// (HandwritingConverter.letterTracking); with a fixed space the gap between words then shrank to
/// barely more than the gap between letters ("Ohalde sizibö yle"). The space grows two and a half
/// times as fast as the tracking, so a word gap keeps reading as a word gap on every ink, and the
/// font's own tracking keeps the font's own space.
enum WordSpacing {
    static func space(tracking: Float, fontTracking: Float, spaceAdvance: Float) -> Float {
        spaceAdvance + 2.5 * max(0, tracking - fontTracking)
    }
}
