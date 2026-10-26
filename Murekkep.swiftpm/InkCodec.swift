import Foundation

/// Compact little-endian binary format for all strokes of a document.
enum InkCodec {
    enum CodecError: Error {
        case badMagic
        case unsupportedVersion
        case truncated
        case tooLarge
    }

    private static let magic: UInt32 = 0x314B_524D // "MRK1"
    private static let version: UInt32 = 1

    static func encode(_ pages: [[Stroke]]) -> Data {
        var w = ByteWriter()
        let pointTotal = pages.reduce(0) { $0 + $1.reduce(0) { $0 + $1.points.count } }
        w.reserve(16 + pointTotal * 16 + pages.count * 8)
        w.u32(magic)
        w.u32(version)
        w.u32(UInt32(pages.count))
        for strokes in pages {
            w.u32(UInt32(strokes.count))
            for s in strokes {
                w.u8(s.brush.rawValue)
                w.u8(0)
                w.u8(0)
                w.u8(0)
                w.f32(s.color.r)
                w.f32(s.color.g)
                w.f32(s.color.b)
                w.f32(s.color.a)
                w.f32(s.width)
                w.f64(s.birth)
                w.f32(s.seed)
                w.u32(UInt32(s.points.count))
                for p in s.points {
                    w.f32(p.x)
                    w.f32(p.y)
                    w.f32(p.r)
                    w.f32(p.ink)
                }
            }
        }
        return w.data
    }

    static func decode(_ data: Data) throws -> [[Stroke]] {
        var r = ByteReader(data)
        guard try r.u32() == magic else { throw CodecError.badMagic }
        guard try r.u32() == version else { throw CodecError.unsupportedVersion }
        let pageCount = Int(try r.u32())
        guard pageCount <= 100_000 else { throw CodecError.tooLarge }
        var pages: [[Stroke]] = []
        pages.reserveCapacity(pageCount)
        for _ in 0..<pageCount {
            let strokeCount = Int(try r.u32())
            guard strokeCount <= 2_000_000 else { throw CodecError.tooLarge }
            var strokes: [Stroke] = []
            strokes.reserveCapacity(strokeCount)
            for _ in 0..<strokeCount {
                let brush = Brush(rawValue: try r.u8()) ?? .pen
                _ = try r.u8()
                _ = try r.u8()
                _ = try r.u8()
                let color = InkColor(try r.f32(), try r.f32(), try r.f32(), try r.f32())
                let width = try r.f32()
                let birth = try r.f64()
                let seed = try r.f32()
                let n = Int(try r.u32())
                guard n <= 5_000_000, r.remaining >= n * 16 else { throw CodecError.truncated }
                var pts: [InkPoint] = []
                pts.reserveCapacity(n)
                for _ in 0..<n {
                    let p = InkPoint(x: try r.f32(), y: try r.f32(), r: try r.f32(), ink: try r.f32())
                    if p.x.isFinite && p.y.isFinite && p.r.isFinite && p.r > 0 {
                        pts.append(p)
                    }
                }
                if !pts.isEmpty {
                    strokes.append(Stroke(brush: brush, color: color, width: width, birth: birth, seed: seed, points: pts))
                }
            }
            pages.append(strokes)
        }
        return pages
    }

    /// The format version `data` was written with; nil when it is not an ink file at all.
    static func formatVersion(of data: Data) -> UInt32? {
        var r = ByteReader(data.prefix(8))
        guard let m = try? r.u32(), m == magic, let v = try? r.u32() else { return nil }
        return v
    }

    /// True for a file a newer Mürekkep wrote: the ink in it is fine, this build just cannot read
    /// it (and must not write over it).
    static func isNewerFormat(_ data: Data) -> Bool {
        (formatVersion(of: data) ?? 0) > version
    }
}

struct ByteWriter {
    private(set) var data = Data()

    mutating func reserve(_ n: Int) {
        data.reserveCapacity(n)
    }

    mutating func u8(_ v: UInt8) {
        data.append(v)
    }

    mutating func u32(_ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    mutating func f32(_ v: Float) {
        u32(v.bitPattern)
    }

    mutating func f64(_ v: Double) {
        var le = v.bitPattern.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}

struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    var remaining: Int { bytes.count - offset }

    mutating func u8() throws -> UInt8 {
        guard offset + 1 <= bytes.count else { throw InkCodec.CodecError.truncated }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func u32() throws -> UInt32 {
        guard offset + 4 <= bytes.count else { throw InkCodec.CodecError.truncated }
        let o = offset
        offset += 4
        return UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
    }

    mutating func f32() throws -> Float {
        Float(bitPattern: try u32())
    }

    mutating func f64() throws -> Double {
        let lo = UInt64(try u32())
        let hi = UInt64(try u32())
        return Double(bitPattern: lo | (hi << 32))
    }
}
