import Foundation

/// Whether new text-pen writing goes on the line the pen has just turned into text (twin of
/// tests/ports/textpen_batch.py). Then the whole line is read again: words read one at a time lose
/// their context ("Aga" alone read "Asa") and the spaces between them.
enum TextPenBatch {
    /// Seconds after the last reading that more writing still joins it.
    static let window: TimeInterval = 15
    /// How far right of the last writing the next words may start, in its heights.
    static let reach: CGFloat = 4

    /// `last`: the handwriting just read; `next`: the new writing's bounds (page points, y down).
    static func continues(last: CGRect, next: CGRect, elapsed: TimeInterval) -> Bool {
        guard elapsed >= 0, elapsed < window, !last.isNull, !next.isNull else { return false }
        let h = max(last.height, 1)
        if max(next.width, next.height) < 0.5 * h {
            // A dot, an accent, a comma or a full stop: over the line or just after it.
            return next.midY >= last.minY - 0.6 * h && next.midY <= last.maxY + 0.3 * h
                && next.midX >= last.minX - 0.2 * h && next.midX <= last.maxX + reach * h
        }
        guard abs(next.midY - last.midY) <= 0.5 * h else { return false }
        return next.minX >= last.minX - 0.5 * h && next.minX <= last.maxX + reach * h
    }
}
