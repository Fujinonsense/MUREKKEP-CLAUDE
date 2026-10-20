import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Tracks a single drawing touch and forwards every event (with coalesced and predicted touches).
final class InkGestureRecognizer: UIGestureRecognizer {
    var onBegan: ((UITouch, UIEvent) -> Void)?
    var onMoved: ((UITouch, UIEvent) -> Void)?
    var onEnded: ((UITouch, UIEvent) -> Void)?
    var onCancelled: (() -> Void)?
    /// Apple Pencil refined force/tilt values it had only estimated before.
    var onEstimatesUpdated: ((Set<UITouch>) -> Void)?

    private var tracked: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    convenience init() {
        self.init(target: nil, action: nil)
    }

    var isTracking: Bool { tracked != nil }
    var trackedType: UITouch.TouchType? { tracked?.type }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // The pencil always wins: a resting palm or finger that started a stroke is dropped.
        if let current = tracked, current.type != .pencil, let pencil = touches.first(where: { $0.type == .pencil }) {
            onCancelled?()
            ignore(current, for: event)
            tracked = pencil
            onBegan?(pencil, event)
            for other in touches where other !== pencil {
                ignore(other, for: event)
            }
            return
        }
        if tracked == nil, let touch = touches.first(where: { $0.type == .pencil }) ?? touches.first {
            tracked = touch
            state = .began
            onBegan?(touch, event)
            for other in touches where other !== touch {
                ignore(other, for: event)
            }
            return
        }
        // A second finger while drawing with a finger means the user wants to scroll or zoom.
        if let current = tracked, current.type == .direct {
            onCancelled?()
            tracked = nil
            state = .cancelled
        }
        for t in touches where t !== tracked {
            ignore(t, for: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        onMoved?(t, event)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        onEnded?(t, event)
        tracked = nil
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        onCancelled?()
        tracked = nil
        state = .cancelled
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        onEstimatesUpdated?(touches)
    }

    /// Called by the canvas when a touch should not draw (for example it started outside every page).
    func abandon() {
        guard tracked != nil else { return }
        tracked = nil
        if state == .began || state == .changed {
            state = .cancelled
        } else {
            state = .failed
        }
    }

    override func reset() {
        super.reset()
        tracked = nil
    }
}

/// Scroll view that refuses to pan while the pencil is writing (simple palm rejection) and leaves
/// touches on a drafting instrument to the instrument.
final class PageScrollView: UIScrollView {
    var isInking: (() -> Bool)?
    /// True when the gesture starts on something that handles its own fingers (a ruler, a protractor).
    var startsOnInstrument: ((UIGestureRecognizer) -> Bool)?

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer, isInking?() == true {
            return false
        }
        if gestureRecognizer === panGestureRecognizer || gestureRecognizer === pinchGestureRecognizer,
           startsOnInstrument?(gestureRecognizer) == true {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
