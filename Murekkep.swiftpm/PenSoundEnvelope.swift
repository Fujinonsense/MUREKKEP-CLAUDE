import Foundation

/// How loud the pen sound should be, from the pencil's samples (twin of tests/ports/pen_sound.py).
///
/// Three parts. Motion: the hand's speed, smoothed over 15 ms, silent below 20 pt/s, square-rooted so
/// slow writing is still heard, full at 700 pt/s. Texture: how fast the line turns, smoothed over 30 ms;
/// a straight line sits at 60 %, the loops and corners of letters lift it to 100 %, so the sound moves
/// with the shape of the writing instead of droning along a long line. Pressure adds up to a quarter.
/// The audio thread glides to the result sample by sample: quickly up, a little slower down.
struct PenSoundEnvelope {
    /// Per-sample glide factors at 44.1 kHz: 90 % of a rise in 12 ms, 90 % of a fall in 17 ms.
    static let attack = 0.005
    static let release = 0.003

    private static let speedGate = 20.0
    private static let speedFull = 700.0
    private static let turnFull = 25.0
    private static let speedTau = 0.015
    private static let turnTau = 0.03
    private static let minStep = 0.25

    private var last: (x: Double, y: Double, time: Double)?
    private var heading: Double?
    private var speed = 0.0
    private var turn = 0.0

    /// Target loudness 0…1 for a pencil sample (view points, seconds, force 0…~4).
    mutating func update(x: Double, y: Double, time: Double, force: Double) -> Double {
        guard let l = last else {
            last = (x, y, time)
            return 0
        }
        last = (x, y, time)
        let dt = max(time - l.time, 1.0 / 480)
        let dx = x - l.x
        let dy = y - l.y
        let dist = (dx * dx + dy * dy).squareRoot()
        speed += (dist / dt - speed) * (1 - exp(-dt / Self.speedTau))
        let turnK = 1 - exp(-dt / Self.turnTau)
        if dist > Self.minStep {
            let h = atan2(dy, dx)
            if let previous = heading {
                // The turn folded into -π…π.
                var d = (h - previous + Double.pi).truncatingRemainder(dividingBy: 2 * Double.pi)
                if d < 0 { d += 2 * Double.pi }
                d -= Double.pi
                turn += (abs(d) / dt - turn) * turnK
            }
            heading = h
        } else {
            turn -= turn * turnK
        }
        let motion = min(max(speed - Self.speedGate, 0) / (Self.speedFull - Self.speedGate), 1).squareRoot()
        let texture = min(turn / Self.turnFull, 1)
        let press = 0.75 + 0.25 * min(max(force, 0), 2) / 2
        return motion * (0.6 + 0.4 * texture) * press
    }

    /// The pencil lifted: the next sample starts a new line.
    mutating func reset() {
        last = nil
        heading = nil
        speed = 0
        turn = 0
    }
}
