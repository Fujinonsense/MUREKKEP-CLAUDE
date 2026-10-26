import Foundation

// The exact half of the math engine: the equations and inequalities of a school page solved the
// way a textbook prints the answer (x = −7/4, x = ±3√2/2, −4 < x < 8, (−∞, −3] ∪ [9, ∞)), never a
// decimal. Linear and quadratic equations and inequalities, absolute values (|A| = |B|, |A| = c,
// |A| < c, a quadratic in |A|), rewriting a ≤ x ≤ b as |x − a| ≤ b and back, and a simple rational
// inequality. Anything else returns nil and stays the language model's.

// MARK: - Exact numbers

/// A reduced fraction. `ok` turns false when an operation overflowed and stays false from then on,
/// so a result is either exact or marked unusable.
struct Fraction: Equatable, Hashable {
    private(set) var num: Int
    private(set) var den: Int
    private(set) var ok: Bool

    static let zero = Fraction(0)
    static let one = Fraction(1)
    static let invalid = Fraction(raw: 0, 1, ok: false)

    private init(raw num: Int, _ den: Int, ok: Bool) {
        self.num = num
        self.den = den
        self.ok = ok
    }

    init(_ n: Int) {
        self.init(raw: n, 1, ok: true)
    }

    init(_ n: Int, _ d: Int) {
        guard d != 0, n != Int.min, d != Int.min else {
            self = .invalid
            return
        }
        var p = n
        var q = d
        if q < 0 {
            p = -p
            q = -q
        }
        let g = Fraction.gcd(abs(p), q)
        self.init(raw: p / g, q / g, ok: true)
    }

    /// An integer or a short decimal (2.5 → 5/2, up to six decimals); nil for π and friends.
    init?(_ v: Double) {
        guard v.isFinite, abs(v) < 1e12 else { return nil }
        for digits in 0...6 {
            let m = pow(10, Double(digits))
            let r = (v * m).rounded() / m
            if abs(r - v) <= 1e-9 * max(1, abs(v)) {
                self.init(Int((v * m).rounded()), Int(m))
                return
            }
        }
        return nil
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a
        var b = b
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return max(a, 1)
    }

    static func lcm(_ a: Int, _ b: Int) -> Int {
        let (m, overflow) = (a / gcd(a, b)).multipliedReportingOverflow(by: b)
        return overflow ? a : m
    }

    var isZero: Bool { ok && num == 0 }
    var sign: Int { num > 0 ? 1 : (num < 0 ? -1 : 0) }
    var isInteger: Bool { den == 1 }
    var double: Double { Double(num) / Double(den) }

    static func + (a: Fraction, b: Fraction) -> Fraction {
        guard a.ok, b.ok else { return .invalid }
        let (x, o1) = a.num.multipliedReportingOverflow(by: b.den)
        let (y, o2) = b.num.multipliedReportingOverflow(by: a.den)
        let (s, o3) = x.addingReportingOverflow(y)
        let (d, o4) = a.den.multipliedReportingOverflow(by: b.den)
        guard !o1, !o2, !o3, !o4 else { return .invalid }
        return Fraction(s, d)
    }

    static prefix func - (a: Fraction) -> Fraction {
        guard a.ok else { return .invalid }
        return Fraction(raw: -a.num, a.den, ok: true)
    }

    static func - (a: Fraction, b: Fraction) -> Fraction { a + (-b) }

    static func * (a: Fraction, b: Fraction) -> Fraction {
        guard a.ok, b.ok else { return .invalid }
        let (n, o1) = a.num.multipliedReportingOverflow(by: b.num)
        let (d, o2) = a.den.multipliedReportingOverflow(by: b.den)
        guard !o1, !o2 else { return .invalid }
        return Fraction(n, d)
    }

    var reciprocal: Fraction {
        guard ok, num != 0 else { return .invalid }
        return Fraction(den, num)
    }

    static func / (a: Fraction, b: Fraction) -> Fraction { a * b.reciprocal }

    /// "−7/4", "3", "0".
    var text: String {
        guard ok else { return "?" }
        let n = num < 0 ? "−\(-num)" : "\(num)"
        return den == 1 ? n : "\(n)/\(den)"
    }
}

/// r + s·√n with r, s rational and n square-free: every root of a quadratic with rational
/// coefficients, written the way a textbook prints it ("−7/4", "3√2/2", "(1 + √5)/2").
struct ExactNumber: Equatable, Hashable {
    private(set) var r: Fraction
    private(set) var s: Fraction
    private(set) var n: Int

    init(_ r: Fraction) {
        self.r = r
        s = .zero
        n = 1
    }

    init(r: Fraction, s: Fraction, n: Int) {
        if n == 1 {
            self.r = r + s
            self.s = .zero
            self.n = 1
        } else if s.isZero {
            self.r = r
            self.s = .zero
            self.n = 1
        } else {
            self.r = r
            self.s = s
            self.n = n
        }
    }

    var ok: Bool { r.ok && s.ok }
    var isRational: Bool { s.isZero }
    var isZero: Bool { r.isZero && s.isZero }
    var double: Double { r.double + s.double * Double(n).squareRoot() }

    /// m = k²·n with n square-free; nil when m is too large to factor quickly.
    static func squareFree(_ m: Int) -> (k: Int, n: Int)? {
        guard m > 0, m <= 10_000_000_000 else { return nil }
        var rest = m
        var k = 1
        var i = 2
        while i * i <= rest {
            while rest % (i * i) == 0 {
                rest /= i * i
                k *= i
            }
            i += 1
        }
        return (k, rest)
    }

    /// √(p/q) as (k/q)·√n; nil for a negative number or one too large to factor.
    static func sqrt(_ f: Fraction) -> ExactNumber? {
        guard f.ok, f.sign >= 0 else { return nil }
        if f.isZero { return ExactNumber(.zero) }
        let (m, overflow) = f.num.multipliedReportingOverflow(by: f.den)
        guard !overflow, let (k, n) = squareFree(m) else { return nil }
        return ExactNumber(r: .zero, s: Fraction(k, f.den), n: n)
    }

    static func + (a: ExactNumber, b: Fraction) -> ExactNumber { ExactNumber(r: a.r + b, s: a.s, n: a.n) }
    static func * (a: ExactNumber, b: Fraction) -> ExactNumber { ExactNumber(r: a.r * b, s: a.s * b, n: a.n) }
    static prefix func - (a: ExactNumber) -> ExactNumber { ExactNumber(r: -a.r, s: -a.s, n: a.n) }

    /// nil when the two surds differ (√2 + √3 has no place here).
    static func + (a: ExactNumber, b: ExactNumber) -> ExactNumber? {
        if b.isRational { return a + b.r }
        if a.isRational { return b + a.r }
        guard a.n == b.n else { return nil }
        return ExactNumber(r: a.r + b.r, s: a.s + b.s, n: a.n)
    }

    static func * (a: ExactNumber, b: ExactNumber) -> ExactNumber? {
        if b.isRational { return a * b.r }
        if a.isRational { return b * a.r }
        guard a.n == b.n else { return nil }
        // (r + s√n)(u + v√n) = ru + sv·n + (rv + su)√n
        let nn = Fraction(a.n)
        return ExactNumber(r: a.r * b.r + a.s * b.s * nn, s: a.r * b.s + a.s * b.r, n: a.n)
    }

    /// −1, 0 or 1, worked out exactly.
    var sign: Int {
        if isRational { return r.sign }
        if r.isZero { return s.sign }
        if r.sign == s.sign { return r.sign }
        // |r| against |s|√n: compare the squares.
        let d = r * r - s * s * Fraction(n)
        return d.sign > 0 ? r.sign : s.sign
    }

    var text: String {
        guard ok else { return "?" }
        if isRational { return r.text }
        if r.isZero { return ExactNumber.surdText(s, n) }
        let (g, og) = r.den.multipliedReportingOverflow(by: s.den)
        guard !og else { return MathFormat.decimal(double) }
        let q = g / Fraction.gcd(r.den, s.den)
        let (p, o1) = r.num.multipliedReportingOverflow(by: q / r.den)
        let (t, o2) = s.num.multipliedReportingOverflow(by: q / s.den)
        guard !o1, !o2 else { return MathFormat.decimal(double) }
        var inner = p < 0 ? "−\(-p)" : "\(p)"
        inner += t < 0 ? " − " : " + "
        inner += abs(t) == 1 ? "√\(n)" : "\(abs(t))√\(n)"
        return q == 1 ? inner : "(\(inner))/\(q)"
    }

    /// "√7", "−3√2/2", "2√3".
    private static func surdText(_ s: Fraction, _ n: Int) -> String {
        var out = s.num < 0 ? "−" : ""
        if abs(s.num) != 1 { out += "\(abs(s.num))" }
        out += "√\(n)"
        if s.den != 1 { out += "/\(s.den)" }
        return out
    }
}

// MARK: - Polynomials

/// A polynomial in one unknown with rational coefficients, constant term first.
struct RPoly: Equatable {
    private(set) var c: [Fraction]

    static let zero = RPoly([])
    static let one = RPoly([.one])
    static let x = RPoly([.zero, .one])

    init(_ coefficients: [Fraction]) {
        var cs = coefficients
        while let last = cs.last, last.isZero {
            cs.removeLast()
        }
        c = cs
    }

    init(constant: Fraction) {
        self.init([constant])
    }

    var ok: Bool { c.allSatisfy(\.ok) }
    var degree: Int { c.count - 1 }
    var isZero: Bool { c.isEmpty }
    var isConstant: Bool { c.count <= 1 }
    var constant: Fraction { c.first ?? .zero }
    var lead: Fraction { c.last ?? .zero }

    func coefficient(_ k: Int) -> Fraction {
        k < c.count ? c[k] : .zero
    }

    static func + (a: RPoly, b: RPoly) -> RPoly {
        let n = max(a.c.count, b.c.count)
        return RPoly((0..<n).map { a.coefficient($0) + b.coefficient($0) })
    }

    static prefix func - (a: RPoly) -> RPoly { RPoly(a.c.map { -$0 }) }
    static func - (a: RPoly, b: RPoly) -> RPoly { a + (-b) }

    func scaled(_ f: Fraction) -> RPoly {
        RPoly(c.map { $0 * f })
    }

    /// nil above degree 4: nothing on a school page needs more.
    static func * (a: RPoly, b: RPoly) -> RPoly? {
        if a.isZero || b.isZero { return .zero }
        guard a.degree + b.degree <= 4 else { return nil }
        var out = [Fraction](repeating: .zero, count: a.c.count + b.c.count - 1)
        for (i, x) in a.c.enumerated() {
            for (j, y) in b.c.enumerated() {
                out[i + j] = out[i + j] + x * y
            }
        }
        return RPoly(out)
    }

    /// The same polynomial up to sign, its leading coefficient positive (|−A| = |A|).
    var signNormalized: RPoly { lead.sign < 0 ? -self : self }

    func evaluate(_ v: ExactNumber) -> ExactNumber? {
        var acc = ExactNumber(.zero)
        for k in c.reversed() {
            guard let p = acc * v, let s = p + ExactNumber(k) else { return nil }
            acc = s
        }
        return acc
    }

    /// "4x + 23", "x² − 9", "(2x² − 3)/14", for the working shown under the answer.
    func text(_ variable: String) -> String {
        var q = 1
        for f in c {
            q = Fraction.lcm(q, f.den)
        }
        if q > 1 {
            let inner = scaled(Fraction(q)).text(variable)
            let terms = c.filter { !$0.isZero }.count
            return terms == 1 ? "\(inner)/\(q)" : "(\(inner))/\(q)"
        }
        var parts: [String] = []
        for k in stride(from: degree, through: 0, by: -1) {
            let f = coefficient(k)
            guard !f.isZero else { continue }
            let negative = f.sign < 0
            let mag = Fraction(abs(f.num), f.den)
            var term: String
            if k == 0 {
                term = mag.text
            } else {
                let v = k == 1 ? variable : variable + MathFormat.superscript(k)
                term = mag.num == 1 ? v : "\(mag.num)\(v)"
                if mag.den != 1 { term += "/\(mag.den)" }
            }
            parts.append((parts.isEmpty ? (negative ? "−" : "") : (negative ? " − " : " + ")) + term)
        }
        return parts.isEmpty ? "0" : parts.joined()
    }
}

/// A polynomial in x and t = |A(x)|: `terms[k]` is the coefficient (a polynomial in x) of t^k.
struct AbsPoly: Equatable {
    private(set) var terms: [RPoly]
    /// A, its leading coefficient positive; nil while no absolute value is in play.
    private(set) var inner: RPoly?

    static let zero = AbsPoly([], inner: nil)

    init(_ terms: [RPoly], inner: RPoly?) {
        var t = terms
        while let last = t.last, last.isZero {
            t.removeLast()
        }
        self.terms = t
        self.inner = t.count <= 1 ? nil : inner
    }

    init(poly: RPoly) {
        self.init([poly], inner: nil)
    }

    var ok: Bool { terms.allSatisfy(\.ok) && (inner?.ok ?? true) }
    var tDegree: Int { terms.count - 1 }
    var isPoly: Bool { terms.count <= 1 }
    var poly: RPoly { terms.first ?? .zero }

    func term(_ k: Int) -> RPoly {
        k < terms.count ? terms[k] : .zero
    }

    /// The inside the bars share; `ok` false when two expressions disagree about it.
    private static func merge(_ a: RPoly?, _ b: RPoly?) -> (ok: Bool, inner: RPoly?) {
        switch (a, b) {
        case (nil, nil): return (true, nil)
        case let (x?, nil), let (nil, x?): return (true, x)
        case let (x?, y?): return (x == y, x)
        }
    }

    static func + (a: AbsPoly, b: AbsPoly) -> AbsPoly? {
        let (ok, inner) = merge(a.inner, b.inner)
        guard ok else { return nil }
        let n = max(a.terms.count, b.terms.count)
        return AbsPoly((0..<n).map { a.term($0) + b.term($0) }, inner: inner)
    }

    static prefix func - (a: AbsPoly) -> AbsPoly { AbsPoly(a.terms.map { -$0 }, inner: a.inner) }

    func scaled(_ f: Fraction) -> AbsPoly {
        AbsPoly(terms.map { $0.scaled(f) }, inner: inner)
    }

    static func * (a: AbsPoly, b: AbsPoly) -> AbsPoly? {
        let (ok, inner) = merge(a.inner, b.inner)
        guard ok else { return nil }
        if a.terms.isEmpty || b.terms.isEmpty { return .zero }
        guard a.tDegree + b.tDegree <= 2 else { return nil }
        var out = [RPoly](repeating: .zero, count: a.terms.count + b.terms.count - 1)
        for (i, x) in a.terms.enumerated() {
            for (j, y) in b.terms.enumerated() {
                guard let p = x * y else { return nil }
                out[i + j] = out[i + j] + p
            }
        }
        return AbsPoly(out, inner: inner)
    }

    /// k when the expression is k·|A| and nothing else.
    var pureAbs: Fraction? {
        guard terms.count == 2, terms[0].isZero, terms[1].isConstant, inner != nil else { return nil }
        return terms[1].constant
    }
}

/// num / den; den is 1 unless the unknown is in a denominator, and then num has no absolute value.
struct RExpr {
    private(set) var num: AbsPoly
    private(set) var den: RPoly

    init(num: AbsPoly, den: RPoly) {
        if den.isConstant, !den.constant.isZero, den != .one {
            self.num = num.scaled(den.constant.reciprocal)
            self.den = .one
        } else {
            self.num = num
            self.den = den
        }
    }

    init(constant f: Fraction) {
        self.init(num: AbsPoly(poly: RPoly(constant: f)), den: .one)
    }

    static let x = RExpr(num: AbsPoly(poly: .x), den: .one)

    var ok: Bool { num.ok && den.ok && !den.isZero }

    static func + (a: RExpr, b: RExpr) -> RExpr? {
        if a.den == .one, b.den == .one {
            guard let n = a.num + b.num else { return nil }
            return RExpr(num: n, den: .one)
        }
        guard a.num.isPoly, b.num.isPoly, let x = a.num.poly * b.den, let y = b.num.poly * a.den,
              let d = a.den * b.den else { return nil }
        return RExpr(num: AbsPoly(poly: x + y), den: d)
    }

    static prefix func - (a: RExpr) -> RExpr { RExpr(num: -a.num, den: a.den) }
    static func - (a: RExpr, b: RExpr) -> RExpr? { a + (-b) }

    static func * (a: RExpr, b: RExpr) -> RExpr? {
        guard let n = a.num * b.num, let d = a.den * b.den, d.isConstant || n.isPoly else { return nil }
        return RExpr(num: n, den: d)
    }

    static func / (a: RExpr, b: RExpr) -> RExpr? {
        guard b.num.isPoly, !b.num.poly.isZero, let n = a.num * AbsPoly(poly: b.den), let d = a.den * b.num.poly,
              d.isConstant || n.isPoly else { return nil }
        return RExpr(num: n, den: d)
    }
}

// MARK: - Relations and solution sets

enum Relation: Equatable {
    case eq, lt, le, gt, ge

    init?(symbol: Character) {
        switch symbol {
        case "=": self = .eq
        case "<": self = .lt
        case "≤": self = .le
        case ">": self = .gt
        case "≥": self = .ge
        default: return nil
        }
    }

    var isStrict: Bool { self == .lt || self == .gt }

    /// The relation after both sides are multiplied by a negative number.
    var flipped: Relation {
        switch self {
        case .lt: return .gt
        case .le: return .ge
        case .gt: return .lt
        case .ge: return .le
        case .eq: return .eq
        }
    }

    var text: String {
        switch self {
        case .eq: return "="
        case .lt: return "<"
        case .le: return "≤"
        case .gt: return ">"
        case .ge: return "≥"
        }
    }

    /// Whether a number of this sign satisfies "number rel 0".
    func holds(sign: Int) -> Bool {
        switch self {
        case .eq: return sign == 0
        case .lt: return sign < 0
        case .le: return sign <= 0
        case .gt: return sign > 0
        case .ge: return sign >= 0
        }
    }
}

enum Bound: Equatable {
    case negInf
    case posInf
    case value(ExactNumber)

    var exact: ExactNumber? {
        if case let .value(v) = self { return v }
        return nil
    }

    var negated: Bound {
        switch self {
        case .negInf: return .posInf
        case .posInf: return .negInf
        case let .value(v): return .value(-v)
        }
    }

    var text: String {
        switch self {
        case .negInf: return "−∞"
        case .posInf: return "∞"
        case let .value(v): return v.text
        }
    }

    static func compare(_ a: Bound, _ b: Bound) -> Int {
        if a == b { return 0 }
        switch (a, b) {
        case (.negInf, _), (_, .posInf): return -1
        case (.posInf, _), (_, .negInf): return 1
        case let (.value(x), .value(y)): return x.double < y.double ? -1 : (x.double > y.double ? 1 : 0)
        }
    }
}

struct Interval: Equatable {
    var lo: Bound
    var hi: Bound
    var loClosed: Bool
    var hiClosed: Bool

    static let all = Interval(lo: .negInf, hi: .posInf, loClosed: false, hiClosed: false)

    static func point(_ v: ExactNumber) -> Interval {
        Interval(lo: .value(v), hi: .value(v), loClosed: true, hiClosed: true)
    }

    var isPoint: Bool { lo == hi }
    var isBounded: Bool { lo.exact != nil && hi.exact != nil }

    var isValid: Bool {
        let c = Bound.compare(lo, hi)
        return c < 0 || (c == 0 && loClosed && hiClosed && lo.exact != nil)
    }

    /// The interval of −x for x in this one.
    var mirrored: Interval {
        Interval(lo: hi.negated, hi: lo.negated, loClosed: hiClosed, hiClosed: loClosed)
    }

    /// "[−3, 9)", "{2}".
    var notation: String {
        if isPoint { return "{\(lo.text)}" }
        return (loClosed ? "[" : "(") + lo.text + ", " + hi.text + (hiClosed ? "]" : ")")
    }
}

/// A union of intervals, kept sorted, disjoint and merged.
struct IntervalSet: Equatable {
    private(set) var intervals: [Interval]

    static let empty = IntervalSet([])
    static let all = IntervalSet([.all])

    init(_ list: [Interval]) {
        intervals = IntervalSet.normalized(list)
    }

    var isEmpty: Bool { intervals.isEmpty }
    var isAll: Bool { intervals == [.all] }

    private static func normalized(_ list: [Interval]) -> [Interval] {
        let valid = list.filter(\.isValid).sorted { a, b in
            let c = Bound.compare(a.lo, b.lo)
            return c != 0 ? c < 0 : (a.loClosed && !b.loClosed)
        }
        var out: [Interval] = []
        for i in valid {
            guard var last = out.last else {
                out.append(i)
                continue
            }
            let c = Bound.compare(i.lo, last.hi)
            if c < 0 || (c == 0 && (i.loClosed || last.hiClosed)) {
                let h = Bound.compare(i.hi, last.hi)
                if h > 0 {
                    last.hi = i.hi
                    last.hiClosed = i.hiClosed
                } else if h == 0 {
                    last.hiClosed = last.hiClosed || i.hiClosed
                }
                out[out.count - 1] = last
            } else {
                out.append(i)
            }
        }
        return out
    }

    func union(_ o: IntervalSet) -> IntervalSet {
        IntervalSet(intervals + o.intervals)
    }

    func intersection(_ o: IntervalSet) -> IntervalSet {
        var out: [Interval] = []
        for a in intervals {
            for b in o.intervals {
                let cl = Bound.compare(a.lo, b.lo)
                let lo = cl >= 0 ? a.lo : b.lo
                let loClosed = cl == 0 ? (a.loClosed && b.loClosed) : (cl > 0 ? a.loClosed : b.loClosed)
                let ch = Bound.compare(a.hi, b.hi)
                let hi = ch <= 0 ? a.hi : b.hi
                let hiClosed = ch == 0 ? (a.hiClosed && b.hiClosed) : (ch < 0 ? a.hiClosed : b.hiClosed)
                out.append(Interval(lo: lo, hi: hi, loClosed: loClosed, hiClosed: hiClosed))
            }
        }
        return IntervalSet(out)
    }

    /// The set without one point (a value the unknown may not take).
    func excluding(_ p: ExactNumber) -> IntervalSet {
        let b = Bound.value(p)
        var out: [Interval] = []
        for i in intervals {
            let cl = Bound.compare(b, i.lo)
            let ch = Bound.compare(b, i.hi)
            if cl < 0 || ch > 0 {
                out.append(i)
            } else if cl == 0 && ch == 0 {
                continue
            } else if cl == 0 {
                out.append(Interval(lo: i.lo, hi: i.hi, loClosed: false, hiClosed: i.hiClosed))
            } else if ch == 0 {
                out.append(Interval(lo: i.lo, hi: i.hi, loClosed: i.loClosed, hiClosed: false))
            } else {
                out.append(Interval(lo: i.lo, hi: b, loClosed: i.loClosed, hiClosed: false))
                out.append(Interval(lo: b, hi: i.hi, loClosed: false, hiClosed: i.hiClosed))
            }
        }
        return IntervalSet(out)
    }

    /// "(−∞, −3] ∪ [9, ∞)".
    var notation: String {
        isEmpty ? "∅" : intervals.map(\.notation).joined(separator: " ∪ ")
    }
}

// MARK: - The solver

enum ExactMath {
    /// The engine's answer to one question: the line a textbook prints, and the working it rests on.
    struct Answer: Equatable {
        var answer: String
        var working: [String]
        var variable: String
        /// The relation the question gave ("|4x + 23| = |4x − 9|").
        var given: String
    }

    enum Solution: Equatable {
        /// The roots of an equation, sorted; none means no solution.
        case roots([ExactNumber])
        /// True for every value of the unknown.
        case identity
        /// The solution set of an inequality.
        case set(IntervalSet)
    }

    enum Roots: Equatable {
        case list([ExactNumber])
        /// The zero polynomial: every number.
        case every
    }

    /// Words of a question that asks for something other than the solution; the model's.
    private static let notSolving = ["show", "prove", "verify", "check", "explain", "why", "göster", "ispat", "kanıtla",
                                     "açıkla", "neden", "doğrula"]

    /// Signs that make a run an expression, not a lone "x = 5".
    private static let operators: Set<Character> = ["+", "-", "−", "*", "/", "×", "÷", "^", "²", "³", "√", "|"]

    // MARK: Reading the question

    /// "<=" and the like as one sign.
    static func normalizedRelations(_ s: String) -> String {
        s.replacingOccurrences(of: "<=", with: "≤").replacingOccurrences(of: "=<", with: "≤")
            .replacingOccurrences(of: ">=", with: "≥").replacingOccurrences(of: "=>", with: "≥")
            .replacingOccurrences(of: "==", with: "=")
    }

    private static func hasRelation(_ s: String) -> Bool {
        s.contains(where: { Relation(symbol: $0) != nil }) && !s.contains("≠")
    }

    /// "a = ____" (or a bare "a =", a blank the page's text layer lost) → "a".
    private static func blankLetter(_ run: String) -> String? {
        guard run.range(of: "^[A-Za-z]\\s*=\\s*(?:_{2,}|…+)?$", options: .regularExpression) != nil else { return nil }
        return String(run.first!)
    }

    private static func letters(_ s: String) -> Set<String> {
        Set(s.filter(\.isLetter).map { String($0) })
    }

    /// The sides and the signs of "L rel R" or "L rel M rel R".
    static func splitRelation(_ run: String) -> (parts: [String], rels: [Relation])? {
        var parts: [String] = []
        var rels: [Relation] = []
        var current = ""
        for ch in run {
            if let r = Relation(symbol: ch) {
                parts.append(current)
                current = ""
                rels.append(r)
            } else {
                current.append(ch)
            }
        }
        parts.append(current)
        let trimmed = parts.map { $0.trimmingCharacters(in: .whitespaces) }
        guard !rels.isEmpty, rels.count <= 2, trimmed.allSatisfy({ !$0.isEmpty }) else { return nil }
        return (trimmed, rels)
    }

    /// The question's math: the given relation (an equation, an inequality or a chain), the form it
    /// is to be rewritten in, and the blanks to fill, when the question is one the engine solves.
    struct Reading {
        var given: String
        var variable: String
        var form: String?
        var blanks: [String]
    }

    static func read(_ raw: String) -> Reading? {
        let stem = MathText.unifiedMath(raw)
        let lower = stem.lowercased()
        guard !notSolving.contains(where: { lower.contains($0) }) else { return nil }
        let runs = MathText.mathRuns(in: stem).map(normalizedRelations).filter(hasRelation)
        var blanks: [String] = []
        var others: [String] = []
        for run in runs {
            if let b = blankLetter(run) {
                if !blanks.contains(b) { blanks.append(b) }
            } else {
                others.append(run)
            }
        }
        var form: String?
        var given: String?
        for run in others {
            let ls = letters(run)
            if !blanks.isEmpty, form == nil, !run.contains(where: \.isNumber), ls.isSuperset(of: blanks), ls.count >= 2 {
                form = run
            } else if given == nil {
                given = run
            }
        }
        guard let given, !given.contains("_") else { return nil }
        let vars = letters(given).subtracting(blanks)
        guard vars.count == 1, let variable = vars.first, variable.unicodeScalars.first!.isASCII else { return nil }
        // "x = 5" alone is a statement, not an equation to solve.
        let coefficient = given.range(of: "[0-9][a-zA-Z]", options: .regularExpression) != nil
        let inequality = given.contains(where: { "<>≤≥".contains($0) })
        guard coefficient || inequality || given.contains(where: { operators.contains($0) }) else { return nil }
        return Reading(given: given, variable: variable, form: form, blanks: blanks)
    }

    // MARK: Expressions

    static func convert(_ e: MathExpr, variable: String) -> RExpr? {
        switch e {
        case let .number(v):
            guard let f = Fraction(v) else { return nil }
            return RExpr(constant: f)
        case let .variable(name):
            return name == variable ? .x : nil
        case let .negate(a):
            return convert(a, variable: variable).map { -$0 }
        case let .add(a, b):
            guard let x = convert(a, variable: variable), let y = convert(b, variable: variable) else { return nil }
            return x + y
        case let .subtract(a, b):
            guard let x = convert(a, variable: variable), let y = convert(b, variable: variable) else { return nil }
            return x - y
        case let .multiply(a, b):
            guard let x = convert(a, variable: variable), let y = convert(b, variable: variable) else { return nil }
            return x * y
        case let .divide(a, b):
            guard let x = convert(a, variable: variable), let y = convert(b, variable: variable) else { return nil }
            return x / y
        case let .power(a, b):
            guard case let .number(k) = b, k.rounded() == k, k >= 0, k <= 4, let x = convert(a, variable: variable) else { return nil }
            var out = RExpr(constant: .one)
            for _ in 0..<Int(k) {
                guard let p = out * x else { return nil }
                out = p
            }
            return out
        case let .call(name, a):
            guard let x = convert(a, variable: variable), x.den == .one, x.num.isPoly else { return nil }
            let inside = x.num.poly
            if name == "abs" {
                if inside.isConstant {
                    return RExpr(constant: inside.constant.sign < 0 ? -inside.constant : inside.constant)
                }
                return RExpr(num: AbsPoly([.zero, .one], inner: inside.signNormalized), den: .one)
            }
            if name == "sqrt", inside.isConstant, let root = ExactNumber.sqrt(inside.constant), root.isRational {
                return RExpr(constant: root.r)
            }
            return nil
        case .factorial, .degrees:
            return nil
        }
    }

    static func expression(_ text: String, variable: String) -> RExpr? {
        guard let e = MathParser.parse(text), let x = convert(e, variable: variable), x.ok else { return nil }
        return x
    }

    // MARK: Roots and signs

    static func roots(_ p: RPoly) -> Roots? {
        switch p.degree {
        case -1:
            return .every
        case 0:
            return .list([])
        case 1:
            return .list([ExactNumber(-p.coefficient(0) / p.coefficient(1))])
        case 2:
            let a = p.coefficient(2)
            let b = p.coefficient(1)
            let c = p.coefficient(0)
            let d = b * b - Fraction(4) * a * c
            guard d.ok else { return nil }
            if d.sign < 0 { return .list([]) }
            guard let sd = ExactNumber.sqrt(d) else { return nil }
            let twoA = Fraction(2) * a
            let base = ExactNumber(-b / twoA)
            if sd.isZero { return .list([base]) }
            let half = sd * twoA.reciprocal
            guard let r1 = base + half, let r2 = base + (-half) else { return nil }
            return .list(sorted([r1, r2]))
        default:
            return nil
        }
    }

    static func sorted(_ list: [ExactNumber]) -> [ExactNumber] {
        var out: [ExactNumber] = []
        for v in list.sorted(by: { $0.double < $1.double }) where !out.contains(v) {
            out.append(v)
        }
        return out
    }

    /// x rel r.
    private static func halfLine(_ r: ExactNumber, _ rel: Relation) -> Interval {
        switch rel {
        case .eq: return .point(r)
        case .lt: return Interval(lo: .negInf, hi: .value(r), loClosed: false, hiClosed: false)
        case .le: return Interval(lo: .negInf, hi: .value(r), loClosed: false, hiClosed: true)
        case .gt: return Interval(lo: .value(r), hi: .posInf, loClosed: false, hiClosed: false)
        case .ge: return Interval(lo: .value(r), hi: .posInf, loClosed: true, hiClosed: false)
        }
    }

    /// Every x with p(x) rel 0, for p of degree two or less.
    static func solvePoly(_ p: RPoly, _ rel: Relation) -> IntervalSet? {
        guard p.ok else { return nil }
        switch p.degree {
        case -1, 0:
            return rel.holds(sign: p.constant.sign) ? .all : .empty
        case 1:
            let r = ExactNumber(-p.coefficient(0) / p.coefficient(1))
            return IntervalSet([halfLine(r, p.coefficient(1).sign < 0 ? rel.flipped : rel)])
        case 2:
            guard let rs = roots(p), case let .list(list) = rs else { return nil }
            let positive = p.lead.sign > 0
            if list.isEmpty {
                // No real root: the sign of the leading coefficient everywhere.
                return rel.holds(sign: positive ? 1 : -1) ? .all : .empty
            }
            if list.count == 1 {
                // A double root r: p = a(x − r)².
                let r = list[0]
                switch rel {
                case .eq: return IntervalSet([.point(r)])
                case .lt: return positive ? .empty : IntervalSet.all.excluding(r)
                case .le: return positive ? IntervalSet([.point(r)]) : .all
                case .gt: return positive ? IntervalSet.all.excluding(r) : .empty
                case .ge: return positive ? .all : IntervalSet([.point(r)])
                }
            }
            let r1 = list[0]
            let r2 = list[1]
            let closed = !rel.isStrict
            let inside = IntervalSet([Interval(lo: .value(r1), hi: .value(r2), loClosed: closed, hiClosed: closed)])
            let outside = IntervalSet([Interval(lo: .negInf, hi: .value(r1), loClosed: false, hiClosed: closed),
                                       Interval(lo: .value(r2), hi: .posInf, loClosed: closed, hiClosed: false)])
            switch rel {
            case .eq: return IntervalSet([.point(r1), .point(r2)])
            case .lt, .le: return positive ? inside : outside
            case .gt, .ge: return positive ? outside : inside
            }
        default:
            return nil
        }
    }

    /// Every x with p(x)·q(x) rel 0, from the signs of the two factors.
    static func solveProduct(_ p: RPoly, _ q: RPoly, _ rel: Relation) -> IntervalSet? {
        let (same, opposite): (Relation, Relation)
        switch rel {
        case .eq:
            guard let a = solvePoly(p, .eq), let b = solvePoly(q, .eq) else { return nil }
            return a.union(b)
        case .lt: (same, opposite) = (.lt, .gt)
        case .le: (same, opposite) = (.le, .ge)
        case .gt: (same, opposite) = (.gt, .lt)
        case .ge: (same, opposite) = (.ge, .le)
        }
        // p·q rel 0 holds where p rel 0 and q has the matching sign, or both the other way round.
        guard let p1 = solvePoly(p, same), let q1 = solvePoly(q, rel == .lt || rel == .le ? opposite : same),
              let p2 = solvePoly(p, opposite), let q2 = solvePoly(q, rel == .lt || rel == .le ? same : opposite) else { return nil }
        return p1.intersection(q1).union(p2.intersection(q2))
    }

    // MARK: Steps

    /// p with integer coefficients and a positive leading one (and, `reduced`, no common factor);
    /// the relation follows a sign flip. The steps keep the common factor: "8x = −14", as written.
    static func integerized(_ p: RPoly, _ rel: Relation, reduced: Bool = true) -> (RPoly, Relation) {
        guard !p.isZero, p.ok else { return (p, rel) }
        var q = 1
        for f in p.c {
            q = Fraction.lcm(q, f.den)
        }
        var scaled = p.scaled(Fraction(q))
        if reduced {
            var g = 0
            for f in scaled.c {
                g = Fraction.gcd(g, abs(f.num))
            }
            if g > 1 { scaled = scaled.scaled(Fraction(1, g)) }
        }
        return scaled.lead.sign < 0 ? (-scaled, rel.flipped) : (scaled, rel)
    }

    /// "− 2" or "+ 5", for a factor (x − 2).
    private static func signed(_ v: ExactNumber) -> String {
        v.sign < 0 ? "− \((-v).text)" : "+ \(v.text)"
    }

    private static func caseLabel(_ k: Int) -> String {
        L("Durum \(k): ", "Case \(k): ")
    }

    /// How p = 0 is solved, as a teacher writes it: "8x = −14 ⇒ x = −7/4", "x² = 9/2 ⇒ x = ±3√2/2",
    /// "(x − 2)(x − 3) = 0 ⇒ x = 2 veya x = 3", "Δ = 20 ⇒ x = (2 ± √20)/2 = 1 ± √5".
    static func equationSteps(_ p: RPoly, variable v: String) -> String {
        let (q, _) = integerized(p, .eq, reduced: false)
        switch q.degree {
        case -1:
            return L("her \(v) için doğru", "true for every \(v)")
        case 0:
            return L("çözüm yok", "no solution")
        case 1:
            let a = q.coefficient(1)
            let c = q.coefficient(0)
            let root = ExactNumber(-c / a)
            if a == .one { return "\(v) = \(root.text)" }
            return "\(a.text)\(v) = \((-c).text) ⇒ \(v) = \(root.text)"
        case 2:
            let a = q.coefficient(2)
            let b = q.coefficient(1)
            let c = q.coefficient(0)
            guard let rs = roots(q), case let .list(list) = rs else { return q.text(v) + " = 0" }
            let result = text(.roots(list), variable: v)
            if b.isZero {
                let lead = a == .one ? "" : "\(a.text)\(v)² = \((-c).text) ⇒ "
                return lead + "\(v)² = \((-c / a).text) ⇒ " + result
            }
            if a == .one, list.count == 2, list.allSatisfy(\.isRational) {
                return "(\(v) \(signed(-list[0])))(\(v) \(signed(-list[1]))) = 0 ⇒ " + result
            }
            let d = b * b - Fraction(4) * a * c
            let twoA = Fraction(2) * a
            if d.sign < 0 { return "Δ = \(d.text) < 0 ⇒ " + result }
            if d.isZero { return "Δ = 0 ⇒ \(v) = \((-b).text)/\(twoA.text) = \(list[0].text)" }
            var s = "Δ = \(d.text) ⇒ \(v) = (\((-b).text) ± √\(d.text))/\(twoA.text)"
            if let sd = ExactNumber.sqrt(d) {
                let half = sd * twoA.reciprocal
                s += half.isRational ? " ⇒ " + result : " = \(ExactNumber(-b / twoA).text) ± \(half.text)"
            }
            return s
        default:
            return q.text(v) + " = 0"
        }
    }

    /// How p rel 0 is solved: "2x > 4 ⇒ x > 2", "x² − 9 ≤ 0 ⇒ kökler: x = −3, x = 3 ⇒ −3 ≤ x ≤ 3".
    static func inequalitySteps(_ p: RPoly, _ rel: Relation, variable v: String) -> String? {
        let (q, r) = integerized(p, rel, reduced: false)
        guard let set = solvePoly(q, r) else { return nil }
        let result = text(.set(set), variable: v)
        switch q.degree {
        case -1, 0:
            return result
        case 1:
            let a = q.coefficient(1)
            let c = q.coefficient(0)
            if a == .one { return result }
            return "\(a.text)\(v) \(r.text) \((-c).text) ⇒ " + result
        case 2:
            guard let rs = roots(q), case let .list(list) = rs else { return nil }
            let rootsText = list.isEmpty ? L("kök yok", "no root") : list.map { "\(v) = \($0.text)" }.joined(separator: ", ")
            return "\(q.text(v)) \(r.text) 0 ⇒ " + L("kökler: ", "roots: ") + rootsText + " ⇒ " + result
        default:
            return nil
        }
    }

    /// "lo rel₁ a₁x + a₀ rel₂ hi" taken apart: the constant moved, then the coefficient divided.
    private static func chainSteps(lo: Fraction, _ relLo: Relation, _ a: RPoly, _ relHi: Relation, hi: Fraction,
                                   variable v: String, steps: inout [String]) {
        guard a.degree == 1 else { return }
        let a1 = a.coefficient(1)
        let a0 = a.coefficient(0)
        var l = lo
        var h = hi
        var rl = relLo
        var rh = relHi
        if !a0.isZero {
            l = l - a0
            h = h - a0
            let move = a0.sign > 0
                ? L("Her taraftan \(a0.text) çıkar: ", "Subtract \(a0.text) from each part: ")
                : L("Her tarafa \((-a0).text) ekle: ", "Add \((-a0).text) to each part: ")
            let middle = a1 == .one ? v : "\(a1.text)\(v)"
            steps.append(move + "\(l.text) \(rl.text) \(middle) \(rh.text) \(h.text)")
        }
        if a1 != .one {
            l = l / a1
            h = h / a1
            var line = L("\(a1.text) ile böl: ", "Divide by \(a1.text): ")
            if a1.sign < 0 {
                (l, h) = (h, l)
                (rl, rh) = (rh.flipped, rl.flipped)
                line = L("\(a1.text) ile böl (negatif: yönler döner): ", "Divide by \(a1.text) (negative: the signs flip): ")
            }
            steps.append(line + "\(l.text) \(rl.text) \(v) \(rh.text) \(h.text)")
        }
    }

    /// "Durum 1: A = B ⇒ …", "Durum 2: A = −(B) ⇒ …", with B's sign checked when it has the unknown.
    private static func caseSteps(_ a: RPoly, _ b: RPoly, check: Bool, variable v: String, steps: inout [String]) {
        for (k, sign) in [(1, Fraction.one), (2, -Fraction.one)] {
            let rhs = b.scaled(sign)
            let rhsText = sign == .one ? b.text(v) : (b.isConstant ? rhs.constant.text : "−(\(b.text(v)))")
            var line = caseLabel(k) + "\(a.text(v)) = \(rhsText) ⇒ " + equationSteps(a - rhs, variable: v)
            if check, let rs = roots(a - rhs), case let .list(list) = rs {
                for r in list {
                    guard let bv = b.evaluate(r) else { continue }
                    line += " (\(b.text(v)) = \(bv.text)" + (bv.sign >= 0 ? " ≥ 0 ✓)" : " < 0 ✗)")
                }
            }
            steps.append(line)
        }
    }

    // MARK: Solving a relation

    private static func solution(_ rs: Roots, excluding: [ExactNumber] = []) -> Solution {
        switch rs {
        case .every:
            return excluding.isEmpty ? .identity : .set(excluding.reduce(IntervalSet.all) { $0.excluding($1) })
        case let .list(list):
            return .roots(sorted(list.filter { !excluding.contains($0) }))
        }
    }

    static func solveRelation(_ l: RExpr, _ rel: Relation, _ r: RExpr, variable v: String, steps: inout [String]) -> Solution? {
        // k₁|A| rel k₂|B| with different insides: (k₁A)² rel (k₂B)², i.e. (k₁A − k₂B)(k₁A + k₂B) rel 0.
        if let k1 = l.num.pureAbs, let k2 = r.num.pureAbs, let a = l.num.inner, let b = r.num.inner, a != b,
           k1.sign > 0, k2.sign > 0, l.den == .one, r.den == .one {
            let ka = a.scaled(k1)
            let kb = b.scaled(k2)
            let p = ka - kb
            let q = ka + kb
            if rel == .eq {
                guard let rp = roots(p), let rq = roots(q) else { return nil }
                caseSteps(ka, kb, check: false, variable: v, steps: &steps)
                if rp == .every || rq == .every { return .identity }
                guard case let .list(x) = rp, case let .list(y) = rq else { return nil }
                return .roots(sorted(x + y))
            }
            guard let s = solveProduct(p, q, rel) else { return nil }
            let (pi, _) = integerized(p, rel)
            let (qi, _) = integerized(q, rel)
            steps.append("|\(ka.text(v))| \(rel.text) |\(kb.text(v))| ⇒ (\(ka.text(v)) − (\(kb.text(v))))(\(ka.text(v)) + \(kb.text(v))) \(rel.text) 0")
            steps.append("(\(pi.text(v)))(\(qi.text(v))) \(rel.text) 0 ⇒ " + text(.set(s), variable: v))
            return .set(s)
        }
        guard let e = l - r, e.ok else { return nil }
        if e.num.isPoly {
            let n = e.num.poly
            if e.den == .one {
                if rel == .eq {
                    steps.append(equationSteps(n, variable: v))
                    return roots(n).map { solution($0) }
                }
                guard let line = inequalitySteps(n, rel, variable: v) else { return nil }
                steps.append(line)
                return solvePoly(n, rel).map(Solution.set)
            }
            // n / d: the roots of d are outside the domain.
            guard let dr = roots(e.den), case let .list(excluded) = dr else { return nil }
            let (ni, ri) = integerized(n, rel)
            let (di, _) = integerized(e.den, .eq)
            let zeros = excluded.isEmpty ? L("yok", "none") : excluded.map { "\(v) = \($0.text)" }.joined(separator: ", ")
            if rel == .eq {
                steps.append(L("Pay: ", "Numerator: ") + equationSteps(n, variable: v))
                steps.append(L("Payda sıfır olamaz: ", "The denominator may not be zero: ") + zeros)
                return roots(n).map { solution($0, excluding: excluded) }
            }
            guard let s = solveProduct(n, e.den, rel) else { return nil }
            let set = excluded.reduce(s) { $0.excluding($1) }
            steps.append("(\(ni.text(v)))/(\(di.text(v))) \(ri.text) 0")
            steps.append(L("Pay sıfır: ", "Numerator zero: ") + equationSteps(n, variable: v) + "; " + L("payda sıfır (tanımsız): ", "denominator zero (undefined): ") + zeros)
            steps.append(L("İşaret tablosu: ", "Sign chart: ") + text(.set(set), variable: v))
            return .set(set)
        }
        guard e.den == .one, let a = e.num.inner else { return nil }
        switch e.num.tDegree {
        case 1:
            // c₁|A| + c₀(x) rel 0 → |A| rel' B with B = −c₀/c₁.
            let c1 = e.num.term(1)
            guard c1.isConstant, !c1.constant.isZero else { return nil }
            let b = (-e.num.term(0)).scaled(c1.constant.reciprocal)
            return solveAbs(a, c1.constant.sign < 0 ? rel.flipped : rel, b, variable: v, steps: &steps)
        case 2:
            guard e.num.terms.allSatisfy(\.isConstant) else { return nil }
            return solveAbsPoly(a, RPoly(e.num.terms.map(\.constant)), rel, variable: v, steps: &steps)
        default:
            return nil
        }
    }

    /// |A| rel B.
    static func solveAbs(_ a: RPoly, _ rel: Relation, _ b: RPoly, variable v: String, steps: inout [String]) -> Solution? {
        let aText = a.text(v)
        let bText = b.text(v)
        let minusB = b.isConstant ? (-b.constant).text : "−(\(bText))"
        switch rel {
        case .eq:
            if b.isConstant, b.constant.sign < 0 {
                steps.append("|\(aText)| = \(bText): " + L("mutlak değer negatif olamaz, çözüm yok", "an absolute value is never negative, no solution"))
                return .roots([])
            }
            var out: [ExactNumber] = []
            var sets: IntervalSet?
            for sign in [Fraction.one, -Fraction.one] {
                // A = ±B, and B may not be negative there.
                guard let rs = roots(a - b.scaled(sign)) else { return nil }
                switch rs {
                case .every:
                    guard let s = solvePoly(b, .ge) else { return nil }
                    sets = (sets ?? .empty).union(s)
                case let .list(list):
                    for r in list {
                        guard let bv = b.evaluate(r) else { return nil }
                        if bv.sign >= 0 { out.append(r) }
                    }
                }
            }
            caseSteps(a, b, check: !b.isConstant, variable: v, steps: &steps)
            if let sets { return .set(sets.union(IntervalSet(out.map(Interval.point)))) }
            return .roots(sorted(out))
        case .lt, .le:
            // −B < A < B
            let strict: Relation = rel == .lt ? .gt : .ge
            guard let s1 = solvePoly(a + b, strict), let s2 = solvePoly(b - a, strict) else { return nil }
            steps.append("|\(aText)| \(rel.text) \(bText) ⇒ \(minusB) \(rel.text) \(aText) \(rel.text) \(bText)")
            if b.isConstant, a.degree == 1 {
                chainSteps(lo: -b.constant, rel, a, rel, hi: b.constant, variable: v, steps: &steps)
            } else if let upper = inequalitySteps(b - a, strict, variable: v), let lower = inequalitySteps(a + b, strict, variable: v) {
                steps.append("\(aText) \(rel.text) \(bText) ⇒ " + upper)
                steps.append("\(aText) \(rel.flipped.text) \(minusB) ⇒ " + lower)
            }
            return .set(s1.intersection(s2))
        case .gt, .ge:
            // A > B or A < −B
            guard let s1 = solvePoly(a - b, rel), let s2 = solvePoly(a + b, rel.flipped) else { return nil }
            steps.append("|\(aText)| \(rel.text) \(bText) ⇒ \(aText) \(rel.text) \(bText) " + L("veya", "or") + " \(aText) \(rel.flipped.text) \(minusB)")
            if let first = inequalitySteps(a - b, rel, variable: v), let second = inequalitySteps(a + b, rel.flipped, variable: v) {
                steps.append("\(aText) \(rel.text) \(bText) ⇒ " + first)
                steps.append("\(aText) \(rel.flipped.text) \(minusB) ⇒ " + second)
            }
            return .set(s1.union(s2))
        }
    }

    /// p(t) rel 0 with t = |A|.
    static func solveAbsPoly(_ a: RPoly, _ p: RPoly, _ rel: Relation, variable v: String, steps: inout [String]) -> Solution? {
        let (pi, ri) = integerized(p, rel)
        steps.append("t = |\(a.text(v))| ⇒ \(pi.text("t")) \(ri.text) 0")
        if rel == .eq {
            guard let tr = roots(p) else { return nil }
            guard case let .list(ts) = tr else { return .identity }
            let rejected = ts.filter { $0.sign < 0 }
            var line = equationSteps(p, variable: "t")
            if !rejected.isEmpty {
                let out = rejected.map { "t = \($0.text)" }.joined(separator: ", ")
                line += L(" (t ≥ 0: \(out) olmaz)", " (t ≥ 0, so \(out) is out)")
            }
            steps.append(line)
            var out: [ExactNumber] = []
            var last: [String] = []
            for t in ts where t.sign >= 0 {
                var found: [ExactNumber] = []
                for sign in [Fraction.one, -Fraction.one] {
                    if t.isRational {
                        guard let rs = roots(a - RPoly(constant: t.r * sign)), case let .list(list) = rs else { return nil }
                        found += list
                    } else {
                        // a₁x + a₀ = ±t
                        guard a.degree == 1 else { return nil }
                        found.append(((t * sign) + (-a.coefficient(0))) * a.coefficient(1).reciprocal)
                    }
                }
                last.append("|\(a.text(v))| = \(t.text) ⇒ " + text(.roots(sorted(found)), variable: v))
                out += found
            }
            if !last.isEmpty { steps.append(last.joined(separator: "; ")) }
            return .roots(sorted(out))
        }
        guard let ts = solvePoly(p, rel) else { return nil }
        let nonNegative = ts.intersection(IntervalSet([Interval(lo: .value(ExactNumber(.zero)), hi: .posInf, loClosed: true, hiClosed: false)]))
        var out = IntervalSet.empty
        for i in nonNegative.intervals {
            for j in [i, i.mirrored] {
                guard let s = within(a, j) else { return nil }
                out = out.union(s)
            }
        }
        if let line = inequalitySteps(p, rel, variable: "t") { steps.append(line + " (t ≥ 0)") }
        steps.append("|\(a.text(v))| " + L("buna göre: ", "accordingly: ") + text(.set(out), variable: v))
        return .set(out)
    }

    /// Every x with A(x) in the interval.
    private static func within(_ a: RPoly, _ j: Interval) -> IntervalSet? {
        var s = IntervalSet.all
        if let lo = j.lo.exact {
            guard lo.isRational, let t = solvePoly(a - RPoly(constant: lo.r), j.loClosed ? .ge : .gt) else { return nil }
            s = s.intersection(t)
        }
        if let hi = j.hi.exact {
            guard hi.isRational, let t = solvePoly(a - RPoly(constant: hi.r), j.hiClosed ? .le : .lt) else { return nil }
            s = s.intersection(t)
        }
        return s
    }

    /// The solution of a relation or a chain written on the page, and the steps to it.
    static func solve(given: String, variable v: String, steps: inout [String]) -> Solution? {
        guard let (parts, rels) = splitRelation(given) else { return nil }
        var sides: [RExpr] = []
        for p in parts {
            guard let x = expression(p, variable: v) else { return nil }
            sides.append(x)
        }
        if rels.count == 1 {
            return solveRelation(sides[0], rels[0], sides[1], variable: v, steps: &steps)
        }
        guard rels.allSatisfy({ $0 != .eq }) else { return nil }
        // lo rel₁ a₁x + a₀ rel₂ hi: taken apart like a textbook.
        let middle = sides[1]
        if middle.den == .one, middle.num.isPoly, middle.num.poly.degree == 1, sides[0].num.isPoly, sides[2].num.isPoly,
           sides[0].den == .one, sides[2].den == .one, sides[0].num.poly.isConstant, sides[2].num.poly.isConstant,
           let s1 = solveRelation(sides[0], rels[0], sides[1], variable: v, steps: &steps),
           let s2 = solveRelation(sides[1], rels[1], sides[2], variable: v, steps: &steps), case let .set(a) = s1, case let .set(b) = s2 {
            steps.removeAll()
            let a1 = middle.num.poly
            if a1 != .x {
                chainSteps(lo: sides[0].num.poly.constant, rels[0], a1, rels[1], hi: sides[2].num.poly.constant, variable: v, steps: &steps)
            }
            return .set(a.intersection(b))
        }
        var first: [String] = []
        var second: [String] = []
        guard let s1 = solveRelation(sides[0], rels[0], sides[1], variable: v, steps: &first),
              let s2 = solveRelation(sides[1], rels[1], sides[2], variable: v, steps: &second),
              case let .set(a) = s1, case let .set(b) = s2 else { return nil }
        steps.append("\(parts[0]) \(rels[0].text) \(parts[1]) ⇒ " + text(.set(a), variable: v))
        steps.append("\(parts[1]) \(rels[1].text) \(parts[2]) ⇒ " + text(.set(b), variable: v))
        return .set(a.intersection(b))
    }

    // MARK: Words

    static func text(_ solution: Solution, variable v: String) -> String {
        switch solution {
        case let .roots(rs):
            if rs.isEmpty { return L("çözüm yok", "no solution") }
            if rs.count == 2, rs[0] == -rs[1] { return "\(v) = ±\(rs[1].text)" }
            return rs.map { "\(v) = \($0.text)" }.joined(separator: L(" veya ", " or "))
        case .identity:
            return L("her gerçek sayı", "all real numbers")
        case let .set(s):
            if s.isEmpty { return L("çözüm yok (∅)", "no solution (∅)") }
            if s.isAll { return L("bütün gerçek sayılar (ℝ)", "all real numbers (ℝ)") }
            if s.intervals.count == 1 {
                let i = s.intervals[0]
                if i.isPoint { return "\(v) = \(i.lo.text)" }
                if i.isBounded { return "\(i.lo.text) \(i.loClosed ? "≤" : "<") \(v) \(i.hiClosed ? "≤" : "<") \(i.hi.text)" }
                if i.lo.exact != nil { return "\(v) \(i.loClosed ? "≥" : ">") \(i.lo.text)" }
                return "\(v) \(i.hiClosed ? "≤" : "<") \(i.hi.text)"
            }
            return s.notation
        }
    }

    /// The engine's answer to a question's stem, nil when the engine cannot be certain. The working
    /// is one to three lines a teacher would write, in the answer's language.
    static func solve(_ stem: String) -> Answer? {
        guard let reading = read(stem) else { return nil }
        var steps: [String] = []
        guard let solution = solve(given: reading.given, variable: reading.variable, steps: &steps) else { return nil }
        let v = reading.variable
        if let form = reading.form {
            return rewrite(solution, form: form, blanks: reading.blanks, variable: v, given: reading.given, steps: steps)
        }
        let answer = text(solution, variable: v)
        if steps.isEmpty { steps = [answer] }
        return Answer(answer: answer, working: Array(steps.prefix(3)), variable: v, given: reading.given)
    }

    /// "a = −4, b = 8": the solution written in the form the question names.
    private static func rewrite(_ solution: Solution, form: String, blanks: [String], variable v: String, given: String,
                                steps: [String]) -> Answer? {
        guard case let .set(s) = solution, s.intervals.count == 1, let i = s.intervals.first, i.isBounded,
              let lo = i.lo.exact, let hi = i.hi.exact, let (parts, rels) = splitRelation(form) else { return nil }
        var values: [String: ExactNumber] = [:]
        var work: [String] = []
        if form.contains("|") {
            // |x − a| ≤ b: a is the midpoint, b the half-width.
            guard parts.count == 2, let e = MathParser.parse(parts[0]), case let .call("abs", inside) = e,
                  parts[1].count == 1, parts[1] != v else { return nil }
            let (center, flip): (String, Bool)
            switch inside {
            case let .subtract(.variable(x), .variable(a)) where x == v: (center, flip) = (a, false)
            case let .subtract(.variable(a), .variable(x)) where x == v: (center, flip) = (a, false)
            case let .add(.variable(x), .variable(a)) where x == v, let .add(.variable(a), .variable(x)) where x == v: (center, flip) = (a, true)
            default: return nil
            }
            guard let sum = lo + hi, let diff = hi + (-lo) else { return nil }
            let mid = sum * Fraction(1, 2)
            let radius = diff * Fraction(1, 2)
            values[center] = flip ? -mid : mid
            values[parts[1]] = radius
            let inner = mid.isZero ? v : (mid.sign < 0 ? "\(v) + \((-mid).text)" : "\(v) − \(mid.text)")
            work = [L("Orta nokta: ", "Midpoint: ") + "\(center) = (\(lo.text) + \(hi.text))/2 = \(values[center]!.text)",
                    L("Yarı genişlik: ", "Half-width: ") + "\(parts[1]) = (\(hi.text) − \(parenthesized(lo)))/2 = \(radius.text)",
                    L("Yani ", "So ") + "|\(inner)| \(rels[0].text) \(radius.text)"]
            if given.contains("|"), let first = steps.first {
                work = [first] + work.prefix(2)
            }
        } else {
            // a < x < b
            guard parts.count == 3, parts[1] == v, parts[0].count == 1, parts[2].count == 1, rels[0] == rels[1] else { return nil }
            let ascending = rels[0] == .lt || rels[0] == .le
            values[parts[0]] = ascending ? lo : hi
            values[parts[2]] = ascending ? hi : lo
            work = steps
        }
        var answer: [String] = []
        for b in blanks {
            guard let value = values[b] else { return nil }
            answer.append("\(b) = \(value.text)")
        }
        let line = answer.joined(separator: ", ")
        if !form.contains("|") {
            work = (work.count > 2 ? [work[0], work[work.count - 1]] : work) + [line]
        }
        return Answer(answer: line, working: Array(work.prefix(3)), variable: v, given: given)
    }

    private static func parenthesized(_ v: ExactNumber) -> String {
        v.sign < 0 ? "(\(v.text))" : v.text
    }

    // MARK: Checking the model's answer

    enum Verdict: Equatable {
        case holds
        /// Why the answer is wrong, and what the engine found by substitution, if anything.
        case fails(reason: String, hint: String?)
    }

    private static let noSolutionWords = ["no solution", "no real solution", "çözüm yok", "çözümü yok", "boş küme", "∅"]

    /// The values a model's answer line claims for the unknown ("x = −7/4", "x = 1 or x = 3",
    /// "x = ±√7", "x ∈ {1, 3}"); an empty list says "no solution"; nil when it cannot be read.
    static func claimed(in answer: String, variable v: String) -> [Double]? {
        let lower = answer.lowercased()
        if noSolutionWords.contains(where: { lower.contains($0) }) { return [] }
        var texts: [String] = []
        let ns = answer as NSString
        if let set = try? NSRegularExpression(pattern: "[=∈]\\s*\\{([^}]*)\\}"),
           let m = set.firstMatch(in: answer, range: NSRange(location: 0, length: ns.length)) {
            texts = ns.substring(with: m.range(at: 1)).components(separatedBy: ",")
        } else {
            guard let rx = try? NSRegularExpression(pattern: "(?<![A-Za-z])\(NSRegularExpression.escapedPattern(for: v))\\s*[=≈]\\s*") else { return nil }
            let matches = rx.matches(in: answer, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { return nil }
            for (k, m) in matches.enumerated() {
                let start = m.range.location + m.range.length
                let end = k + 1 < matches.count ? matches[k + 1].range.location : ns.length
                var piece = ns.substring(with: NSRange(location: start, length: end - start))
                for cut in [",", ";", "\n", " or ", " veya ", " ve ", " and ", " (", "≈", "→", " i.e", " yani", " for ", " için",
                            " because", " since", " çünkü", " so ", " which", " olduğ"] {
                    if let r = piece.range(of: cut) { piece = String(piece[..<r.lowerBound]) }
                }
                texts.append(piece)
            }
        }
        var out: [Double] = []
        for raw in texts {
            var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while let last = t.last, ".*_ ".contains(last) { t.removeLast() }
            t = t.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            let variants = t.contains("±") ? [t.replacingOccurrences(of: "±", with: "+"), t.replacingOccurrences(of: "±", with: "-")] : [t]
            for s in variants {
                guard let e = MathParser.parse(s), e.variables.isEmpty, let value = e.evaluate([:]) else { return nil }
                out.append(value)
            }
        }
        return out
    }

    /// Whether the model's answer to an equation in one unknown holds by substitution and misses no
    /// root the engine finds; nil when the question or the answer cannot be checked.
    static func verify(question: String, answer: String) -> Verdict? {
        guard let reading = read(question), reading.form == nil, let (parts, rels) = splitRelation(reading.given),
              rels == [.eq], let lhs = MathParser.parse(parts[0]), let rhs = MathParser.parse(parts[1]) else { return nil }
        let v = reading.variable
        guard lhs.variables.union(rhs.variables) == [v], let values = claimed(in: answer, variable: v) else { return nil }
        let f: (Double) -> Double? = { x in
            guard let a = lhs.evaluate([v: x]), let b = rhs.evaluate([v: x]) else { return nil }
            return a - b
        }
        for x in values {
            let xs = MathFormat.decimal(x)
            guard let a = lhs.evaluate([v: x]), let b = rhs.evaluate([v: x]) else {
                return .fails(reason: L("\(v) = \(xs) denklemde tanımsız", "\(v) = \(xs) is undefined in the equation"), hint: nil)
            }
            if abs(a - b) > 1e-7 * (1 + abs(a) + abs(b)) {
                let hint = engineRoots(f, variable: v)
                return .fails(reason: L("\(v) = \(xs) yerine konunca sağlanmıyor: sol taraf \(MathFormat.decimal(a)), sağ taraf \(MathFormat.decimal(b))",
                                        "\(v) = \(xs) does not satisfy the equation: left side \(MathFormat.decimal(a)), right side \(MathFormat.decimal(b))"),
                              hint: hint)
            }
        }
        if case let .roots(found, periodic) = MathEngine.solve(f), !periodic {
            let missed = found.filter { r in !values.contains { abs($0 - r) <= 1e-6 * (1 + abs(r)) } }
            if let r = missed.first {
                let hint = MathFormat.roots(found, variable: v, trig: false)
                return .fails(reason: values.isEmpty
                              ? L("\(v) = \(MathFormat.number(r)) denklemi sağlıyor", "\(v) = \(MathFormat.number(r)) satisfies the equation")
                              : L("\(v) = \(MathFormat.number(r)) kökü eksik", "the root \(v) = \(MathFormat.number(r)) is missing"),
                              hint: hint)
            }
        }
        return .holds
    }

    /// What the engine finds by substitution, as a hint for a second try.
    private static func engineRoots(_ f: (Double) -> Double?, variable v: String) -> String? {
        guard case let .roots(found, _) = MathEngine.solve(f), !found.isEmpty else { return nil }
        return MathFormat.roots(found, variable: v, trig: false)
    }
}
