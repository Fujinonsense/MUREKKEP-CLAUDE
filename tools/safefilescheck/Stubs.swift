import Foundation

// The ink types InkCodec.swift stores, reduced to what it reads and writes (the real ones live in
// InkModel.swift and Brushes.swift, which bring the app's palettes and texts with them).

enum Brush: UInt8 {
    case pen = 0
    case pencil = 4
}

struct InkColor: Equatable {
    var r: Float
    var g: Float
    var b: Float
    var a: Float

    init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

struct InkPoint: Equatable {
    var x: Float
    var y: Float
    var r: Float
    var ink: Float
}

struct Stroke: Equatable {
    var brush: Brush
    var color: InkColor
    var width: Float
    var birth: Double
    var seed: Float
    var points: [InkPoint]

    init(brush: Brush, color: InkColor, width: Float, birth: Double, seed: Float, points: [InkPoint]) {
        self.brush = brush
        self.color = color
        self.width = width
        self.birth = birth
        self.seed = seed
        self.points = points
    }
}
