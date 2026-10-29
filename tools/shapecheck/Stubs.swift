import Foundation

// The few app types the shape files refer to, reduced to what they use (the real ones live in files
// that import Apple-only frameworks), as tools/swiftcheck/Stubs.swift does for its files.

/// MathEngine.swift's language pick; the fixture is written in Turkish, the key language of `Loc.t`.
enum AnswerLanguage {
    case turkish
    case english

    var directive: String { "" }
    static var current: AnswerLanguage { .turkish }
}

/// AIEngine.swift's language pick; the checks read the Turkish side.
func L(_ turkish: String, _ english: String) -> String { turkish }

/// Darwin's constant, which Foundation on Windows does not have (MathEngine reads "e").
let M_E = 2.718281828459045

/// Localization.swift's `Loc.t`, which gives back its Turkish key: the fixture records the iPad's
/// Turkish titles and the Android tests look them up as `ShapeName.titleTr`.
enum Loc {
    static func t(_ turkish: String, _ args: String...) -> String { turkish }
}

/// Brushes.swift's palettes name colours; only their existence matters here.
struct InkColor: Equatable, Hashable {
    var hex: UInt32

    init(hex: UInt32) {
        self.hex = hex
    }
}

/// InkModel.swift's point and vector helpers, as StrokeBuilder and ShapeEditing use them.
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

/// StrokeFont.swift writes the labels of the `axes` and `dimension` shapes and of plots, none of
/// which this check runs (Android has no stroke font yet); the shapes it does run never call it.
enum StrokeFont {
    static func paths(_ text: String, origin: SIMD2<Float>, capHeight: Float) -> [[SIMD2<Float>]] { [] }
    static func width(_ text: String) -> Float { 0 }
}
