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

    /// A typed word's span and the span of the handwriting it replaced (page x).
    struct Anchor: Equatable {
        var typedMin: CGFloat
        var typedMax: CGFloat
        var handMin: CGFloat
        var handMax: CGFloat
    }

    /// Where `x`, written along the typed text, falls in the handwriting that text replaced. The next
    /// word is written after the typed words, which are narrower or wider than the hand; read again
    /// next to the old handwriting as written, it would run into it ("restaurant" over "the") or
    /// leave a gap inside a word ("res taurant"). Between the anchors it is linear; past the ends it
    /// keeps its distance.
    static func handX(_ x: CGFloat, anchors: [Anchor]) -> CGFloat {
        guard let first = anchors.first, let last = anchors.last else { return x }
        var points: [(typed: CGFloat, hand: CGFloat)] = []
        for a in anchors {
            points.append((a.typedMin, a.handMin))
            points.append((a.typedMax, a.handMax))
        }
        if x <= first.typedMin { return first.handMin + (x - first.typedMin) }
        if x >= last.typedMax { return last.handMax + (x - last.typedMax) }
        for (a, b) in zip(points, points.dropFirst()) where x >= a.typed && x <= b.typed {
            guard b.typed > a.typed else { return a.hand }
            return a.hand + (x - a.typed) * (b.hand - a.hand) / (b.typed - a.typed)
        }
        return x
    }

    /// Anchors for words typed on one line from handwriting words, both left to right; one anchor
    /// for the whole line when the handwriting words do not go left to right (one box per line).
    static func anchors(typed: [(minX: CGFloat, maxX: CGFloat)], hand: [(minX: CGFloat, maxX: CGFloat)]) -> [Anchor] {
        guard let t0 = typed.first, let t1 = typed.last, let h0 = hand.first, let h1 = hand.last,
              typed.count == hand.count else { return [] }
        let ordered = zip(hand, hand.dropFirst()).allSatisfy { $1.minX >= $0.maxX - 0.5 } && hand.allSatisfy { $0.maxX > $0.minX }
        guard ordered else {
            return [Anchor(typedMin: t0.minX, typedMax: t1.maxX, handMin: h0.minX, handMax: max(hand.map(\.maxX).max() ?? h1.maxX, h0.minX + 1))]
        }
        return zip(typed, hand).map { Anchor(typedMin: $0.minX, typedMax: $0.maxX, handMin: $1.minX, handMax: $1.maxX) }
    }
}
