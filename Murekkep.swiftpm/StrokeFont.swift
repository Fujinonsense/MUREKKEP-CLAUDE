import Foundation

/// A single-line technical lettering font (in the spirit of ISO 3098): every letter is a few pen
/// strokes, so typed or converted text can be written with any brush, 3D inks included.
///
/// Glyphs live on a grid where the cap height is 10 units, the x-height 7, descenders reach −3 and
/// y points up. A glyph is "advance; path | path | …". A path is a list of "x,y" points, arcs
/// "a(cx,cy,r,from,to)" and ellipse arcs "e(cx,cy,rx,ry,from,to)" with angles in degrees; the arc
/// runs counterclockwise when `to` > `from`, clockwise otherwise.
enum StrokeFont {
    struct Glyph {
        let advance: Float
        let paths: [[SIMD2<Float>]]
    }

    /// Units between neighbouring glyphs (0.28 × the cap height) and for a space (0.55 ×), so letters
    /// never run into each other, also in thick 3D inks.
    static let tracking: Float = 2.8
    static let spaceAdvance: Float = 5.5

    private static let source: [Character: String] = [
        // Capitals
        "A": "7; 0,0 3.5,10 7,0 | 1.4,3.8 5.6,3.8",
        "B": "6.2; 0,0 0,10 3.6,10 a(3.6,7.5,2.5,90,-90) 0,5 3.8,5 a(3.8,2.5,2.5,90,-90) 0,0",
        "C": "6.6; e(3.4,5,3.3,5,42,318)",
        "D": "6.4; 0,0 0,10 2.4,10 e(2.4,5,4,5,90,-90) 0,0",
        "E": "5.6; 5.6,10 0,10 0,0 5.6,0 | 0,5.1 4.6,5.1",
        "F": "5.6; 5.6,10 0,10 0,0 | 0,5.1 4.6,5.1",
        "G": "6.8; e(3.4,5,3.4,5,42,360) 3.9,5",
        "H": "6; 0,0 0,10 | 6,0 6,10 | 0,5.1 6,5.1",
        "I": "0; 0,0 0,10",
        "J": "5; 5,10 5,2.6 a(2.5,2.6,2.5,0,-180)",
        "K": "6; 0,0 0,10 | 6,10 0,3.8 | 2.1,5.6 6.2,0",
        "L": "5.2; 0,10 0,0 5.2,0",
        "M": "8; 0,0 0,10 4,2.6 8,10 8,0",
        "N": "6.4; 0,0 0,10 6.4,0 6.4,10",
        "O": "7; e(3.5,5,3.5,5,90,450)",
        "P": "6; 0,0 0,10 3.4,10 a(3.4,7.4,2.6,90,-90) 0,4.8",
        "Q": "7; e(3.5,5,3.5,5,90,450) | 4.4,2.2 7.2,-0.8",
        "R": "6.2; 0,0 0,10 3.4,10 a(3.4,7.4,2.6,90,-90) 0,4.8 | 2.8,4.8 6.2,0",
        "S": "6.2; e(3.1,7.5,2.9,2.5,20,270) e(3.1,2.5,3.1,2.5,90,-160)",
        "T": "6.4; 0,10 6.4,10 | 3.2,10 3.2,0",
        "U": "6.4; 0,10 0,3.2 a(3.2,3.2,3.2,180,360) 6.4,10",
        "V": "7; 0,10 3.5,0 7,10",
        "W": "9.6; 0,10 2.4,0 4.8,7.6 7.2,0 9.6,10",
        "X": "6.6; 0,10 6.6,0 | 0,0 6.6,10",
        "Y": "7; 0,10 3.5,5 7,10 | 3.5,5 3.5,0",
        "Z": "6.2; 0,10 6.2,10 0,0 6.2,0",
        "Ç": "6.6; e(3.4,5,3.3,5,42,318) | 3.6,0 3.9,-1.1 2.9,-2.2",
        "Ğ": "6.8; e(3.4,5,3.4,5,42,360) 3.9,5 | e(3.4,12.2,1.6,1.2,180,360)",
        "İ": "0; 0,0 0,10 | 0,11.6 0,12.1",
        "Ö": "7; e(3.5,5,3.5,5,90,450) | 2.2,11.4 2.2,11.9 | 4.8,11.4 4.8,11.9",
        "Ş": "6.2; e(3.1,7.5,2.9,2.5,20,270) e(3.1,2.5,3.1,2.5,90,-160) | 3.2,0 3.5,-1.1 2.5,-2.2",
        "Ü": "6.4; 0,10 0,3.2 a(3.2,3.2,3.2,180,360) 6.4,10 | 2,11.4 2,11.9 | 4.4,11.4 4.4,11.9",
        // Lowercase
        "a": "5.6; e(2.8,3.5,2.8,3.5,0,360) | 5.6,7 5.6,0",
        "b": "5.6; 0,10 0,0 | e(2.8,3.5,2.8,3.5,180,540)",
        "c": "5.4; e(2.9,3.5,2.9,3.5,40,320)",
        "d": "5.6; e(2.8,3.5,2.8,3.5,0,360) | 5.6,10 5.6,0",
        "e": "5.6; 0,3.5 5.6,3.5 e(2.8,3.5,2.8,3.5,0,315)",
        "f": "4.4; 4.4,9.7 a(3.1,8.5,1.5,60,180) 1.6,0 | 0,7 4,7",
        "g": "5.6; e(2.8,3.5,2.8,3.5,0,360) | 5.6,7 5.6,-1 a(3.4,-1,2.2,0,-150)",
        "h": "5.4; 0,10 0,0 | 0,4.3 a(2.7,4.3,2.7,180,0) 5.4,0",
        "i": "0; 0,0 0,7 | 0,9.2 0,9.7",
        "j": "2.4; 2.4,7 2.4,-1.4 a(1,-1.4,1.4,0,-160) | 2.4,9.2 2.4,9.7",
        "k": "5; 0,10 0,0 | 4.8,7 0,2.8 | 1.6,4 5,0",
        "l": "0; 0,10 0,0",
        "m": "8; 0,7 0,0 | 0,5 a(2,5,2,180,0) 4,0 | 4,5 a(6,5,2,180,0) 8,0",
        "n": "5.4; 0,7 0,0 | 0,4.3 a(2.7,4.3,2.7,180,0) 5.4,0",
        "o": "5.8; e(2.9,3.5,2.9,3.5,90,450)",
        "p": "5.6; 0,7 0,-3.2 | e(2.8,3.5,2.8,3.5,180,540)",
        "q": "5.6; e(2.8,3.5,2.8,3.5,0,360) | 5.6,7 5.6,-3.2",
        "r": "4.2; 0,7 0,0 | 0,4.2 a(2.8,4.2,2.8,180,70)",
        "s": "4.8; e(2.4,5.25,2.2,1.75,20,270) e(2.4,1.75,2.4,1.75,90,-160)",
        "t": "4; 1.5,10 1.5,1.4 a(2.9,1.4,1.4,180,270) 4,0.2 | 0,7 3.8,7",
        "u": "5.4; 0,7 0,2.7 a(2.7,2.7,2.7,180,360) | 5.4,7 5.4,0",
        "v": "5.6; 0,7 2.8,0 5.6,7",
        "w": "8; 0,7 2,0 4,5.6 6,0 8,7",
        "x": "5.4; 0,7 5.4,0 | 0,0 5.4,7",
        "y": "5.6; 0,7 2.9,0.2 | 5.6,7 1.8,-3.2",
        "z": "5.2; 0,7 5.2,7 0,0 5.2,0",
        "ç": "5.4; e(2.9,3.5,2.9,3.5,40,320) | 3,0 3.3,-1.1 2.3,-2.2",
        "ğ": "5.6; e(2.8,3.5,2.8,3.5,0,360) | 5.6,7 5.6,-1 a(3.4,-1,2.2,0,-150) | e(2.8,9.6,1.5,1.1,180,360)",
        "ı": "0; 0,0 0,7",
        "ö": "5.8; e(2.9,3.5,2.9,3.5,90,450) | 1.8,9 1.8,9.5 | 4,9 4,9.5",
        "ş": "4.8; e(2.4,5.25,2.2,1.75,20,270) e(2.4,1.75,2.4,1.75,90,-160) | 2.6,0 2.9,-1.1 1.9,-2.2",
        "ü": "5.4; 0,7 0,2.7 a(2.7,2.7,2.7,180,360) | 5.4,7 5.4,0 | 1.6,9 1.6,9.5 | 3.8,9 3.8,9.5",
        // Digits
        "0": "6; e(3,5,3,5,90,450)",
        "1": "3.4; 0.4,7.8 3.4,10 3.4,0",
        "2": "6; a(3,7.25,2.75,160,-30) 0,0 6,0",
        "3": "5.6; a(2.9,7.5,2.5,150,-90) a(2.9,2.6,2.6,90,-150)",
        "4": "6.2; 4.6,0 4.6,10 0,3 6.2,3",
        "5": "6; 5.6,10 1,10 0.7,5.7 a(3,3,3,135,-150)",
        "6": "6; e(5.6,3.2,5.6,6.6,100,180) e(3,3,3,3,180,540)",
        "7": "6; 0,10 6,10 1.8,0",
        "8": "6; e(3,7.6,2.5,2.4,270,630) e(3,2.6,3,2.6,90,450)",
        "9": "6; e(3,7,3,3,0,360) e(0.4,6.8,5.6,6.8,0,-80)",
        // Punctuation
        ".": "0; 0,0 0,0.35",
        ",": "0.8; 0.6,0.4 0.6,0 0,-1.8",
        ":": "0; 0,0 0,0.35 | 0,5.6 0,5.95",
        ";": "0.8; 0.6,5.6 0.6,5.95 | 0.6,0.4 0.6,0 0,-1.8",
        "!": "0; 0,10 0,3 | 0,0 0,0.35",
        "?": "5; e(2.5,7.5,2.5,2.5,170,-60) 2.5,3.6 2.5,2.4 | 2.5,0 2.5,0.35",
        "'": "0; 0,10 0,7.6",
        "\"": "1.6; 0,10 0,7.6 | 1.6,10 1.6,7.6",
        "-": "4; 0,4 4,4",
        "_": "6; 0,-1.2 6,-1.2",
        "+": "6; 3,1 3,7 | 0,4 6,4",
        "=": "6; 0,2.6 6,2.6 | 0,5.4 6,5.4",
        "*": "5; 2.5,8 2.5,2 | 0.1,6.4 4.9,3.6 | 0.1,3.6 4.9,6.4",
        "/": "5; 0,-0.5 5,10.5",
        "\\": "5; 0,10.5 5,-0.5",
        "(": "2.6; e(4.4,4,4.4,7.4,118,242)",
        ")": "2.6; e(-1.8,4,4.4,7.4,62,-62)",
        "[": "2; 2,11 0,11 0,-2 2,-2",
        "]": "2; 0,11 2,11 2,-2 0,-2",
        "{": "2.6; 2.6,11 1.6,10.4 1.4,5.4 0,4.5 1.4,3.6 1.6,-1.4 2.6,-2",
        "}": "2.6; 0,11 1,10.4 1.2,5.4 2.6,4.5 1.2,3.6 1,-1.4 0,-2",
        "<": "5; 5,7 0,4 5,1",
        ">": "5; 0,7 5,4 0,1",
        "%": "7; e(1.6,8.1,1.6,1.9,90,450) | 6.6,10 0.4,0 | e(5.4,1.9,1.6,1.9,90,450)",
        "#": "6.6; 1.8,0 2.8,10 | 4.2,0 5.2,10 | 0.3,3.3 6.6,3.3 | 0,6.7 6.3,6.7",
        "$": "6.2; e(3.1,7.5,2.9,2.5,20,270) e(3.1,2.5,3.1,2.5,90,-160) | 3.1,11 3.1,-1",
        "°": "2.4; e(1.2,8.8,1.2,1.2,90,450)",
        "^": "4; 0,7 2,10 4,7",
        "~": "6; e(1.5,4,1.5,1.2,180,0) e(4.5,4,1.5,1.2,180,360)",
        "|": "0; 0,-2 0,11",
        // Math
        "×": "5; 0.5,1.5 4.5,6.5 | 0.5,6.5 4.5,1.5",
        "÷": "6; 0,4 6,4 | 3,6.4 3,6.75 | 3,1.25 3,1.6",
        "±": "6; 3,2.4 3,8 | 0,5.2 6,5.2 | 0,0.6 6,0.6",
        "√": "8.4; 0,4.8 1.2,5.4 2.8,0 4.6,11 8.4,11",
        "π": "7; 0,7 7,7 | 2,7 1.6,0 | 5.2,7 5.3,1 6.3,0",
        "≈": "6; e(1.5,5.2,1.5,1,180,0) e(4.5,5.2,1.5,1,180,360) | e(1.5,2.6,1.5,1,180,0) e(4.5,2.6,1.5,1,180,360)",
        "≠": "6; 0,2.6 6,2.6 | 0,5.4 6,5.4 | 4.6,7.6 1.4,0.4",
        "≤": "5; 5,8 0,5 5,2 | 0,0 5,0",
        "≥": "5; 0,8 5,5 0,2 | 0,0 5,0",
        "∞": "9; e(2.25,4,2.25,2.2,0,360) e(6.75,4,2.25,2.2,180,540)",
        "→": "8; 0,4 8,4 | 5.6,6.2 8,4 5.6,1.8",
        "←": "8; 8,4 0,4 | 2.4,6.2 0,4 2.4,1.8",
        "∫": "4; a(3,10.4,1,40,180) 2,-1 a(1,-1,1,0,-140)",
        "α": "6; e(2.6,3.5,2.6,3.5,0,360) | 5,6 6,0",
        "β": "5.4; 0,-3 0,8 a(2.2,8,2.2,180,-90) a(2.4,2.9,2.9,90,-150)",
        "θ": "5.6; e(2.8,5,2.8,5,90,450) | 0,5 5.6,5",
        "λ": "5.6; 0.4,10 1.4,10 5.6,0 | 0,0 3.1,6",
        "μ": "5.4; 0,7 0,-3.2 | 0,2.7 a(2.7,2.7,2.7,180,360) | 5.4,7 5.4,0",
        "σ": "6; e(2.7,3.2,2.7,3.2,90,450) | 2.7,6.4 6,6.4",
        "Δ": "7; 0,0 3.5,10 7,0 0,0",
        "Σ": "6; 6,10 0,10 3.4,5 0,0 6,0",
        "Ω": "7; 0,0 2.2,0 1.45,2.45 e(3.5,5.8,3.4,4.2,233,-53) 4.8,0 7,0",
        "·": "0; 0,4 0,4.35",
        "•": "0; 0,4 0,4.45",
        "ρ": "5.6; e(2.8,3.5,2.8,3.5,180,540) | 0,3.5 0,-3.2",
        "ω": "8; 0.4,7 e(2,2.7,2,2.7,170,360) 4,4.6 | 4,2.7 e(6,2.7,2,2.7,180,370) 7.6,7",
        "τ": "5; 0,7 5,7 | 2.6,7 2.6,1 a(3.6,1,1,180,270)",
        "φ": "6; e(3,3.5,3,3.5,90,450) | 3,10 3,-3.2",
        "ε": "4.8; e(2.6,5.25,2.3,1.75,60,270) e(2.6,1.75,2.6,1.75,90,300)",
        "γ": "5.6; 0,7 2.8,0.5 5.6,7 | 2.8,0.5 2.8,-3.2",
        "δ": "5.6; e(2.8,2.9,2.8,2.9,90,450) | 2.8,5.8 0.8,9 4.6,10",
        "η": "5.4; 0,7 0,0 | 0,4.3 a(2.7,4.3,2.7,180,0) 5.4,-3.2",
        "€": "7; e(4,5,3.6,5,50,310) | 0,6 4.6,6 | 0,4 4.6,4",
        // More math (handwriting read as math comes back with these)
        "∂": "5.8; e(2.9,2.8,2.9,2.8,0,360) | 5.8,2.8 5.8,6.2 a(3.6,6.2,2.2,0,150)",
        "∑": "6; 6,10 0,10 3.4,5 0,0 6,0",
        "∏": "7; 0,10 7,10 | 1.2,10 1.2,0 | 5.8,10 5.8,0",
        "∈": "5; 5,7 2.9,7 e(2.9,3.5,2.9,3.5,90,270) 5,0 | 0,3.5 4.6,3.5",
        "∉": "5; 5,7 2.9,7 e(2.9,3.5,2.9,3.5,90,270) 5,0 | 0,3.5 4.6,3.5 | 4,8.8 1,-1.8",
        "∀": "7; 0,10 3.5,0 7,10 | 1.6,5.4 5.4,5.4",
        "∃": "5.6; 0,10 5.6,10 5.6,0 0,0 | 1.2,5 5.6,5",
        "⇒": "8; 0,5.2 6.6,5.2 | 0,2.8 6.6,2.8 | 5.2,7.2 8,4 5.2,0.8",
        "⇔": "9; 2.4,5.2 6.6,5.2 | 2.4,2.8 6.6,2.8 | 2.8,7.2 0,4 2.8,0.8 | 6.2,7.2 9,4 6.2,0.8",
        "↔": "9; 0,4 9,4 | 2.4,6.2 0,4 2.4,1.8 | 6.6,6.2 9,4 6.6,1.8",
        "↑": "5; 2.5,0 2.5,10 | 0.4,7.6 2.5,10 4.6,7.6",
        "↓": "5; 2.5,10 2.5,0 | 0.4,2.4 2.5,0 4.6,2.4",
        "∇": "7; 0,10 7,10 3.5,0 0,10",
        "′": "0.8; 0.8,10 0,7.6",
        "″": "2.2; 0.8,10 0,7.6 | 2.2,10 1.4,7.6",
        "∪": "6; 0,7 0,3 a(3,3,3,180,360) 6,7",
        "∩": "6; 0,0 0,4 a(3,4,3,180,0) 6,0",
        "⊂": "6; 6,7 3,7 e(3,3.5,3,3.5,90,270) 6,0",
        "∅": "7; e(3.5,4,3,3.8,90,450) | 6.4,9 0.6,-1",
        "⊥": "6; 3,8.4 3,0 | 0,0 6,0",
        "≡": "6; 0,1.6 6,1.6 | 0,4 6,4 | 0,6.4 6,6.4",
        "∮": "4; a(3,10.4,1,40,180) 2,-1 a(1,-1,1,0,-140) | e(2,4.5,1.6,1.6,0,360)",
        "ℝ": "6.2; 0,0 0,10 3.4,10 a(3.4,7.4,2.6,90,-90) 0,4.8 | 2.8,4.8 6.2,0 | 1.1,0 1.1,10",
        "ℕ": "6.4; 0,0 0,10 6.4,0 6.4,10 | 1.1,10 1.1,1.6",
        "ℤ": "6.2; 0,10 6.2,10 0,0 6.2,0 | 4.9,10 0,0.9",
        "ℚ": "7; e(3.5,5,3.5,5,90,450) | 4.4,2.2 7.2,-0.8 | 1.2,2.2 1.2,7.8",
        "ψ": "6; 0,7 0,3.6 a(3,3.6,3,180,360) 6,7 | 3,9.4 3,-3.2",
        "χ": "5.6; 0,7 5.6,-3.2 | 0,-3.2 5.6,7",
        "κ": "5; 0,7 0,0 | 4.8,7 0,2.8 | 1.6,4 5,0",
        "ν": "5.6; 0,7 2.8,0 5.6,7",
        "Φ": "7; e(3.5,5,3.5,3,90,450) | 3.5,10 3.5,0",
        "Ψ": "7; 0,10 0,6.4 a(3.5,6.4,3.5,180,360) 7,10 | 3.5,10 3.5,0",
        "Γ": "5.6; 0,0 0,10 5.6,10",
        "Λ": "7; 0,0 3.5,10 7,0",
        "Π": "7; 0,0 0,10 7,10 7,0",
        "Θ": "7; e(3.5,5,3.5,5,90,450) | 1.8,5 5.2,5",
        "⋅": "0; 0,4 0,4.35",
        "∙": "0; 0,4 0,4.35",
        "∆": "7; 0,0 3.5,10 7,0 0,0",
    ]

    /// Raised small characters (exponents) and the full-size glyph they are drawn with.
    private static let superscripts: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
        "⁻": "-", "⁺": "+", "ⁿ": "n", "⁼": "=", "⁽": "(", "⁾": ")",
        "ᵃ": "a", "ᵇ": "b", "ᶜ": "c", "ᵈ": "d", "ᵉ": "e", "ᶠ": "f", "ᵍ": "g", "ʰ": "h", "ⁱ": "i", "ʲ": "j",
        "ᵏ": "k", "ˡ": "l", "ᵐ": "m", "ᵒ": "o", "ᵖ": "p", "ʳ": "r", "ˢ": "s", "ᵗ": "t", "ᵘ": "u", "ᵛ": "v",
        "ʷ": "w", "ˣ": "x", "ʸ": "y", "ᶻ": "z", "ᵅ": "α", "ᵝ": "β", "ᶿ": "θ",
    ]

    /// The raised (exponent) form of a character, when the font has one ("2" → "²").
    static func raised(_ base: Character) -> Character? {
        raisedForms[base]
    }

    private static let raisedForms: [Character: Character] =
        Dictionary(superscripts.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })

    /// Lowered small characters (indices, the lower limit of a sum or an integral).
    private static let subscripts: [Character: Character] = [
        "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
        "₊": "+", "₋": "-", "₌": "=", "₍": "(", "₎": ")",
        "ₐ": "a", "ₑ": "e", "ₒ": "o", "ₓ": "x", "ₕ": "h", "ₖ": "k", "ₗ": "l", "ₘ": "m", "ₙ": "n", "ₚ": "p",
        "ₛ": "s", "ₜ": "t", "ᵢ": "i", "ⱼ": "j", "ᵣ": "r", "ᵤ": "u", "ᵥ": "v",
    ]

    private static let glyphs: [Character: Glyph] = {
        var out: [Character: Glyph] = [:]
        for (ch, spec) in source {
            if let g = parse(spec) { out[ch] = g }
        }
        return out
    }()

    private static func parse(_ spec: String) -> Glyph? {
        let halves = spec.components(separatedBy: ";")
        guard halves.count == 2, let advance = Float(halves[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        var paths: [[SIMD2<Float>]] = []
        for segment in halves[1].components(separatedBy: "|") {
            var pts: [SIMD2<Float>] = []
            for token in segment.split(separator: " ") where !token.isEmpty {
                if token.hasPrefix("a(") || token.hasPrefix("e(") {
                    let inner = token.dropFirst(2).dropLast()
                    let v = inner.split(separator: ",").compactMap { Float($0) }
                    if token.hasPrefix("a("), v.count == 5 {
                        pts.append(contentsOf: arc(cx: v[0], cy: v[1], rx: v[2], ry: v[2], from: v[3], to: v[4]))
                    } else if v.count == 6 {
                        pts.append(contentsOf: arc(cx: v[0], cy: v[1], rx: v[2], ry: v[3], from: v[4], to: v[5]))
                    }
                } else {
                    let v = token.split(separator: ",").compactMap { Float($0) }
                    if v.count == 2 { pts.append(SIMD2<Float>(v[0], v[1])) }
                }
            }
            if !pts.isEmpty { paths.append(pts) }
        }
        return Glyph(advance: advance, paths: paths)
    }

    private static func arc(cx: Float, cy: Float, rx: Float, ry: Float, from a0: Float, to a1: Float) -> [SIMD2<Float>] {
        let sweep = a1 - a0
        let steps = max(2, Int((abs(sweep) / 12).rounded(.up)))
        return (0...steps).map { i in
            let a = (a0 + sweep * Float(i) / Float(steps)) * .pi / 180
            return SIMD2<Float>(cx + rx * cos(a), cy + ry * sin(a))
        }
    }

    /// True when every character of `text` has its own pen glyph (no "?" fallback needed).
    static func canDraw(_ text: String) -> Bool {
        let tr = Locale(identifier: "tr_TR")
        for ch in prepared(text) where !ch.isWhitespace {
            if glyphs[ch] != nil || superscripts[ch] != nil || subscripts[ch] != nil { continue }
            let lower = String(ch).lowercased(with: tr)
            let upper = String(ch).uppercased(with: tr)
            let other = [lower, upper].first { $0.count == 1 && glyphs[$0.first!] != nil }
            if other == nil { return false }
        }
        return true
    }

    /// The glyph for `ch`, falling back to the other case and finally to "?".
    static func glyph(_ ch: Character) -> Glyph? {
        if let g = glyphs[ch] { return g }
        let tr = Locale(identifier: "tr_TR")
        for variant in [String(ch).lowercased(with: tr), String(ch).uppercased(with: tr)] {
            if variant.count == 1, let c = variant.first, let g = glyphs[c] { return g }
        }
        return glyphs["?"]
    }

    /// Characters the font draws differently from how they are typed.
    private static func prepared(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: Loc.isEnglish ? "and" : "ve")
            .replacingOccurrences(of: "\t", with: "    ")
            .replacingOccurrences(of: "…", with: "...")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "∗", with: "*")
            .replacingOccurrences(of: "⋯", with: "...")
            .replacingOccurrences(of: "ℓ", with: "l")
    }

    /// Width of `text` in font units (multiply by capHeight / 10 for points).
    static func width(_ text: String, tracking: Float = StrokeFont.tracking) -> Float {
        var w: Float = 0
        var first = true
        for ch in prepared(text) {
            if ch == " " {
                w += spaceAdvance
                first = true
                continue
            }
            let small = superscripts[ch] ?? subscripts[ch]
            guard let g = glyph(small ?? ch) else { continue }
            if !first { w += tracking * (small == nil ? 1 : 0.6) }
            w += g.advance * (small == nil ? 1 : 0.6)
            first = false
        }
        return w
    }

    /// Pen paths of `text` in page space (y down): the baseline starts at `origin`.
    static func paths(_ text: String, origin: SIMD2<Float>, capHeight: Float,
                      tracking: Float = StrokeFont.tracking) -> [[SIMD2<Float>]] {
        let s = capHeight / 10
        var out: [[SIMD2<Float>]] = []
        var pen: Float = 0
        var first = true
        for ch in prepared(text) {
            if ch == " " {
                pen += spaceAdvance
                first = true
                continue
            }
            let raised = superscripts[ch]
            let lowered = subscripts[ch]
            let small = raised ?? lowered
            guard let g = glyph(small ?? ch) else { continue }
            let k: Float = small == nil ? 1 : 0.6
            let rise: Float = raised != nil ? 5.2 : (lowered != nil ? -2.2 : 0)
            if !first { pen += tracking * k }
            for path in g.paths {
                out.append(path.map { p in
                    SIMD2<Float>(origin.x + (pen + p.x * k) * s, origin.y - (rise + p.y * k) * s)
                })
            }
            pen += g.advance * k
            first = false
        }
        return out
    }
}

/// Turns font paths into strokes of a brush.
enum StrokeText {
    struct Style: Equatable {
        var brush: Brush
        var color: InkColor
        var width: Float
    }

    /// One stroke per pen path. Grass keeps its flower setting through `flowerLevel`.
    /// Straight pieces are filled in with points: the renderer draws a smooth curve through the
    /// points, and between far-apart corners that curve would bulge (an octagon became a circle).
    static func strokes(_ paths: [[SIMD2<Float>]], style: Style, flowerLevel: Int, birth: Double) -> [Stroke] {
        let r = max(style.width * 0.5, 0.35)
        let spacing = max(0.6, r * 0.5)
        return paths.compactMap { path -> Stroke? in
            guard !path.isEmpty else { return nil }
            var pts: [InkPoint] = []
            pts.reserveCapacity(path.count * 4)
            for i in path.indices {
                let a = path[i]
                pts.append(InkPoint(x: a.x, y: a.y, r: r, ink: 0.55))
                guard i + 1 < path.count else { continue }
                let b = path[i + 1]
                let n = Int(vlength(b - a) / spacing)
                if n > 1 {
                    for k in 1..<n {
                        let p = a + (b - a) * (Float(k) / Float(n))
                        pts.append(InkPoint(x: p.x, y: p.y, r: r, ink: 0.55))
                    }
                }
            }
            let random = Float.random(in: 0..<1)
            let seed = style.brush == .grass ? GrassGenerator.seed(level: flowerLevel, random: random) : random
            return Stroke(brush: style.brush, color: style.color, width: style.width, birth: birth, seed: seed, points: pts)
        }
    }
}
