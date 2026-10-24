import Foundation

// The few app types the checked files refer to, reduced to what they use (the real ones live in
// files that import Apple-only frameworks).

enum AnswerLanguage {
    case turkish
    case english

    var directive: String { "" }
    static var current: AnswerLanguage { .turkish }
}

enum SpeechText {}

/// AIEngine.swift's language pick; the checks read the Turkish side.
func L(_ turkish: String, _ english: String) -> String { turkish }

/// Darwin's constant, which Foundation on Windows does not have (MathEngine reads "e").
let M_E = 2.718281828459045

/// Brushes.swift's palettes name colours; only their existence matters here.
struct InkColor: Equatable, Hashable {
    var hex: UInt32

    init(hex: UInt32) {
        self.hex = hex
    }

    // GrassGenerator reads the channels.
    var r: Float { Float((hex >> 16) & 0xFF) / 255 }
    var g: Float { Float((hex >> 8) & 0xFF) / 255 }
    var b: Float { Float(hex & 0xFF) / 255 }
}

/// InkModel.swift's point and vector helpers, as GrassGenerator uses them.
struct InkPoint: Equatable {
    var x: Float
    var y: Float
    var r: Float
    var ink: Float

    var position: SIMD2<Float> { SIMD2<Float>(x, y) }
}

func vdot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { (a * b).sum() }
func vlength(_ v: SIMD2<Float>) -> Float { vdot(v, v).squareRoot() }
func clampf(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(max(v, lo), hi) }
