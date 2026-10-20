import Foundation

// MARK: - Expressions

/// A parsed math expression. Evaluation never crashes; it returns nil outside the domain.
indirect enum MathExpr {
    case number(Double)
    case variable(String)
    case negate(MathExpr)
    case add(MathExpr, MathExpr)
    case subtract(MathExpr, MathExpr)
    case multiply(MathExpr, MathExpr)
    case divide(MathExpr, MathExpr)
    case power(MathExpr, MathExpr)
    case call(String, MathExpr)
    case factorial(MathExpr)
    case degrees(MathExpr)

    func evaluate(_ env: [String: Double]) -> Double? {
        switch self {
        case let .number(v):
            return v
        case let .variable(name):
            return env[name]
        case let .negate(e):
            return e.evaluate(env).map { -$0 }
        case let .add(a, b):
            guard let x = a.evaluate(env), let y = b.evaluate(env) else { return nil }
            return MathExpr.finite(x + y)
        case let .subtract(a, b):
            guard let x = a.evaluate(env), let y = b.evaluate(env) else { return nil }
            return MathExpr.finite(x - y)
        case let .multiply(a, b):
            guard let x = a.evaluate(env), let y = b.evaluate(env) else { return nil }
            return MathExpr.finite(x * y)
        case let .divide(a, b):
            guard let x = a.evaluate(env), let y = b.evaluate(env), y != 0 else { return nil }
            return MathExpr.finite(x / y)
        case let .power(a, b):
            guard let x = a.evaluate(env), let y = b.evaluate(env) else { return nil }
            if x < 0 && y.rounded() != y {
                // Odd roots of negative numbers: (-8)^(1/3) = -2.
                let inv = 1 / y
                if abs(inv) < 1_000_000, inv.rounded() == inv, Int(inv) % 2 != 0 {
                    return MathExpr.finite(-pow(-x, y))
                }
                return nil
            }
            if x == 0 && y < 0 { return nil }
            return MathExpr.finite(pow(x, y))
        case let .call(name, arg):
            guard let x = arg.evaluate(env) else { return nil }
            let angle = MathExpr.trigNames.contains(name) && arg.isLikelyDegreeLiteral ? x * .pi / 180 : x
            return MathExpr.apply(name, angle)
        case let .factorial(e):
            guard let x = e.evaluate(env), x >= 0, x <= 170, x.rounded() == x else { return nil }
            var r = 1.0
            var k = 2.0
            while k <= x {
                r *= k
                k += 1
            }
            return r
        case let .degrees(e):
            return e.evaluate(env).map { $0 * .pi / 180 }
        }
    }

    var variables: Set<String> {
        switch self {
        case .number:
            return []
        case let .variable(name):
            return [name]
        case let .negate(e), let .call(_, e), let .factorial(e), let .degrees(e):
            return e.variables
        case let .add(a, b), let .subtract(a, b), let .multiply(a, b), let .divide(a, b), let .power(a, b):
            return a.variables.union(b.variables)
        }
    }

    /// Uses a trigonometric function of something that depends on a variable.
    var hasTrig: Bool {
        switch self {
        case .number, .variable:
            return false
        case let .call(name, e):
            return (MathExpr.trigNames.contains(name) && !e.variables.isEmpty) || e.hasTrig
        case let .negate(e), let .factorial(e), let .degrees(e):
            return e.hasTrig
        case let .add(a, b), let .subtract(a, b), let .multiply(a, b), let .divide(a, b), let .power(a, b):
            return a.hasTrig || b.hasTrig
        }
    }

    /// "sin 30" in handwriting nearly always means degrees: a plain number that is a multiple of 15.
    var isLikelyDegreeLiteral: Bool {
        guard case let .number(v) = self else { return false }
        return v >= 15 && v <= 720 && v.truncatingRemainder(dividingBy: 15) == 0
    }

    static let trigNames: Set<String> = ["sin", "cos", "tan", "cot", "sec", "csc"]

    static func finite(_ v: Double) -> Double? {
        v.isFinite ? v : nil
    }

    static func apply(_ name: String, _ x: Double) -> Double? {
        let v: Double
        switch name {
        case "sin": v = sin(x)
        case "cos": v = cos(x)
        case "tan":
            guard abs(cos(x)) > 1e-12 else { return nil }
            v = tan(x)
        case "cot":
            guard abs(sin(x)) > 1e-12 else { return nil }
            v = cos(x) / sin(x)
        case "sec":
            guard abs(cos(x)) > 1e-12 else { return nil }
            v = 1 / cos(x)
        case "csc":
            guard abs(sin(x)) > 1e-12 else { return nil }
            v = 1 / sin(x)
        case "asin", "arcsin":
            guard abs(x) <= 1 else { return nil }
            v = asin(x)
        case "acos", "arccos":
            guard abs(x) <= 1 else { return nil }
            v = acos(x)
        case "atan", "arctan": v = atan(x)
        case "sinh": v = sinh(x)
        case "cosh": v = cosh(x)
        case "tanh": v = tanh(x)
        case "sqrt":
            guard x >= 0 else { return nil }
            v = x.squareRoot()
        case "cbrt": v = cbrt(x)
        case "ln":
            guard x > 0 else { return nil }
            v = log(x)
        case "log", "lg":
            guard x > 0 else { return nil }
            v = log10(x)
        case "exp": v = exp(x)
        case "abs": v = abs(x)
        default: return nil
        }
        return finite(v)
    }
}

// MARK: - Parsing

enum MathParser {
    enum Token: Equatable {
        case number(Double)
        case ident(String)
        case op(Character)
    }

    static let functions: [String] = [
        "arcsin", "arccos", "arctan", "asin", "acos", "atan", "sinh", "cosh", "tanh",
        "sqrt", "cbrt", "sin", "cos", "tan", "cot", "sec", "csc", "exp", "abs", "log", "ln", "lg",
    ]

    /// Turns handwriting / OCR math into a parseable string: "2,5 × 4 − √9" → "2.5*4-√9".
    static func normalize(_ raw: String) -> String {
        var s = raw
        let map: [(String, String)] = [
            ("×", "*"), ("·", "*"), ("∙", "*"), ("⋅", "*"), ("÷", "/"), ("−", "-"), ("–", "-"), ("—", "-"),
            ("≈", "="), ("＝", "="), ("[", "("), ("]", ")"), ("{", "("), ("}", ")"), ("π", "pi"), ("Π", "pi"),
            ("²", "^2"), ("³", "^3"), ("⁴", "^4"), ("⁵", "^5"), ("⁶", "^6"), ("⁷", "^7"), ("⁸", "^8"),
            ("⁹", "^9"), ("⁰", "^0"), ("¹", "^1"), ("½", "(1/2)"), ("¼", "(1/4)"), ("¾", "(3/4)"),
            ("**", "^"),
        ]
        for (k, v) in map {
            s = s.replacingOccurrences(of: k, with: v)
        }
        // Turkish percent comes first: %20 → (20/100); 20% too.
        s = s.replacingOccurrences(of: "%\\s*([0-9]+(?:[.,][0-9]+)?)", with: "($1/100)", options: .regularExpression)
        // A colon between numbers is division in Turkish schools.
        s = s.replacingOccurrences(of: "(?<=[0-9)])\\s*:\\s*(?=[0-9(])", with: "/", options: .regularExpression)
        // Decimal comma.
        s = s.replacingOccurrences(of: "(?<=[0-9]),(?=[0-9])", with: ".", options: .regularExpression)
        // "3 x 4" and "3x4" between numbers is multiplication.
        s = s.replacingOccurrences(of: "(?<=[0-9)])\\s*[xX×]\\s*(?=[0-9(])", with: "*", options: .regularExpression)
        // OCR letters inside numbers: 1O → 10, l5 → 15.
        s = s.replacingOccurrences(of: "(?<=[0-9])[oO](?![a-zA-ZçğıöşüÇĞİÖŞÜ])", with: "0", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<![a-zA-ZçğıöşüÇĞİÖŞÜ])[oO](?=[0-9])", with: "0", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<=[0-9])[lI|](?=[0-9])", with: "1", options: .regularExpression)
        return s
    }

    static func tokenize(_ s: String) -> [Token]? {
        var out: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
                continue
            }
            if c.isASCII && (c.isNumber || c == ".") {
                var j = i
                var text = ""
                while j < chars.count, chars[j].isASCII, chars[j].isNumber || chars[j] == "." {
                    text.append(chars[j])
                    j += 1
                }
                // Scientific notation: 1.5e3, 2E-4.
                if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                    var k = j + 1
                    var exp = "e"
                    if k < chars.count, chars[k] == "-" || chars[k] == "+" {
                        exp.append(chars[k])
                        k += 1
                    }
                    if k < chars.count, chars[k].isASCII, chars[k].isNumber {
                        while k < chars.count, chars[k].isASCII, chars[k].isNumber {
                            exp.append(chars[k])
                            k += 1
                        }
                        text += exp
                        j = k
                    }
                }
                guard let v = Double(text) else { return nil }
                out.append(.number(v))
                i = j
                continue
            }
            if c.isLetter {
                var j = i
                var text = ""
                while j < chars.count, chars[j].isLetter {
                    text.append(chars[j])
                    j += 1
                }
                out.append(contentsOf: splitIdentifier(text))
                i = j
                continue
            }
            if "+-*/^()!%°√|,".contains(c) {
                out.append(.op(c))
                i += 1
                continue
            }
            if c == "'" || c == "\"" || c == "_" {
                i += 1
                continue
            }
            return nil
        }
        return out
    }

    /// "sinx" → sin, x; "2ab" letters → a, b; "pi" stays a constant.
    private static func splitIdentifier(_ text: String) -> [Token] {
        let lower = text.lowercased()
        var out: [Token] = []
        var rest = Substring(lower)
        let original = Array(text)
        var consumed = 0
        while !rest.isEmpty {
            if let f = functions.first(where: { rest.hasPrefix($0) }) {
                out.append(.ident(f))
                rest = rest.dropFirst(f.count)
                consumed += f.count
            } else if rest.hasPrefix("pi") {
                out.append(.ident("pi"))
                rest = rest.dropFirst(2)
                consumed += 2
            } else {
                // Keep the case of single-letter variables (V and v are different quantities).
                let ch = consumed < original.count ? String(original[consumed]) : String(rest.first!)
                out.append(.ident(ch))
                rest = rest.dropFirst()
                consumed += 1
            }
        }
        return out
    }

    static func parse(_ raw: String) -> MathExpr? {
        guard let tokens = tokenize(normalize(raw)), !tokens.isEmpty else { return nil }
        var p = Parser(tokens: tokens)
        guard let e = p.expression(), p.atEnd else { return nil }
        return e
    }

    private struct Parser {
        let tokens: [Token]
        var pos = 0

        var atEnd: Bool { pos >= tokens.count }

        func peek() -> Token? {
            pos < tokens.count ? tokens[pos] : nil
        }

        mutating func expression() -> MathExpr? {
            guard var value = term() else { return nil }
            while let t = peek(), t == .op("+") || t == .op("-") {
                pos += 1
                guard let rhs = term() else { return nil }
                value = t == .op("+") ? .add(value, rhs) : .subtract(value, rhs)
            }
            return value
        }

        mutating func term() -> MathExpr? {
            guard var value = unary() else { return nil }
            while let t = peek() {
                if t == .op("*") || t == .op("/") {
                    pos += 1
                    guard let rhs = unary() else { return nil }
                    value = t == .op("*") ? .multiply(value, rhs) : .divide(value, rhs)
                } else if startsOperand(t) {
                    // Implicit multiplication: 2x, 3(4+1), (a+b)(a-b), 2π, 4√2
                    guard let rhs = power() else { return nil }
                    value = .multiply(value, rhs)
                } else {
                    break
                }
            }
            return value
        }

        func startsOperand(_ t: Token) -> Bool {
            switch t {
            case .number, .ident:
                return true
            case let .op(c):
                return c == "(" || c == "√"
            }
        }

        mutating func unary() -> MathExpr? {
            if let t = peek(), t == .op("-") || t == .op("+") {
                pos += 1
                guard let v = unary() else { return nil }
                return t == .op("-") ? .negate(v) : v
            }
            return power()
        }

        mutating func power() -> MathExpr? {
            guard let base = postfix() else { return nil }
            if peek() == .op("^") {
                pos += 1
                guard let exponent = unary() else { return nil }
                return .power(base, exponent)
            }
            return base
        }

        mutating func postfix() -> MathExpr? {
            guard var value = primary() else { return nil }
            while let t = peek() {
                if t == .op("!") {
                    pos += 1
                    value = .factorial(value)
                } else if t == .op("%") {
                    pos += 1
                    value = .divide(value, .number(100))
                } else if t == .op("°") {
                    pos += 1
                    value = .degrees(value)
                } else {
                    break
                }
            }
            return value
        }

        mutating func primary() -> MathExpr? {
            guard let t = peek() else { return nil }
            switch t {
            case let .number(v):
                pos += 1
                return .number(v)
            case let .ident(name):
                pos += 1
                if name == "pi" { return .number(.pi) }
                if name == "e" { return .number(M_E) }
                if MathParser.functions.contains(name) {
                    return functionArgument().map { MathExpr.call(name, $0) }
                }
                return .variable(name)
            case .op("("):
                pos += 1
                guard let v = expression(), peek() == .op(")") else { return nil }
                pos += 1
                return v
            case .op("√"):
                pos += 1
                return functionArgument().map { MathExpr.call("sqrt", $0) }
            case .op("|"):
                pos += 1
                guard let v = expression(), peek() == .op("|") else { return nil }
                pos += 1
                return .call("abs", v)
            default:
                return nil
            }
        }

        /// sin(…), sin30, sin 2x, √2 — without parentheses the argument is a tight product.
        mutating func functionArgument() -> MathExpr? {
            if peek() == .op("(") {
                pos += 1
                guard let v = expression(), peek() == .op(")") else { return nil }
                pos += 1
                return postfixOnly(v)
            }
            guard var value = power() else { return nil }
            while let t = peek() {
                if case let .ident(n) = t, !MathParser.functions.contains(n) {
                    guard let rhs = power() else { return nil }
                    value = .multiply(value, rhs)
                } else {
                    break
                }
            }
            return value
        }

        mutating func postfixOnly(_ e: MathExpr) -> MathExpr {
            var value = e
            while peek() == .op("°") {
                pos += 1
                value = .degrees(value)
            }
            return value
        }
    }
}

// MARK: - Findings

enum MathFinding {
    /// "3·4 =" or "√81" → a value.
    case value(String, Double)
    /// "2+2=5": a numeric claim. `left`/`right` are the first pair that disagrees (or the last pair).
    case claim(String, holds: Bool, left: Double, right: Double, rightText: String)
    /// An equation in one unknown and its real solutions.
    case solved(String, variable: String, roots: [Double], periodic: Bool, trig: Bool)
    case noRealSolution(String, variable: String)
    /// True for every value of the unknown.
    case identity(String, variable: String)
    /// Never true ("0 = 3").
    case contradiction(String, variable: String)
}

struct MathSystemSolution {
    let equations: [String]
    let variables: [String]
    let values: [Double]
}

enum MathEngine {
    /// Removes question numbering and Turkish question words: "Soru 3) 2x+1=7 ise x kaçtır?" → "2x+1=7".
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            "^(?i)(soru|s)\\s*\\d{1,2}\\s*[:.)\\-]\\s*",
            "^\\(?\\d{1,2}[).]\\s+",
            "^[a-eA-E][).]\\s+",
        ]
        for p in patterns {
            s = s.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        let words = ["ise", "kaçtır", "kaç eder", "kaç", "nedir", "sonucu", "hesaplayınız", "hesaplayın", "hesapla",
                     "bulunuz", "bulun", "çözünüz", "çözün", "çöz", "işleminin", "işlemi", "ifadesinin", "değeri",
                     "değerini", "sonucunu", "solve", "find", "calculate"]
        for w in words {
            s = s.replacingOccurrences(of: "(?i)(^|\\s)" + w + "(?=\\s|$|\\?|=)", with: " ", options: .regularExpression)
        }
        // "x=?" asks for x: the equation is the rest of the line.
        s = s.replacingOccurrences(of: "[,;]?\\s*[a-zA-Z]\\s*=\\s*\\?\\s*$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\?", with: "", options: .regularExpression)
        return s.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;")))
    }

    /// Reads one handwritten line. nil when it isn't math.
    static func analyze(_ raw: String) -> MathFinding? {
        let line = clean(raw)
        guard line.count >= 2, line.count <= 160 else { return nil }
        guard line.contains(where: { $0.isNumber }) || line.contains("=") else { return nil }
        let normalized = MathParser.normalize(line)
        let parts = normalized.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
        let pieces = parts.filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return nil }

        // "3·4 =" (or a lone expression with an operator): compute it.
        if pieces.count == 1 {
            guard let e = MathParser.parse(pieces[0]), e.variables.isEmpty, let v = e.evaluate([:]) else { return nil }
            let hasOperator = pieces[0].contains(where: { "+-*/^√!%".contains($0) }) || pieces[0].contains("(")
            guard hasOperator || parts.count > 1 else { return nil }
            return .value(line, v)
        }

        var exprs: [MathExpr] = []
        for p in pieces {
            guard let e = MathParser.parse(p) else { return nil }
            exprs.append(e)
        }
        let vars = exprs.reduce(Set<String>()) { $0.union($1.variables) }
        if vars.isEmpty {
            let values = exprs.compactMap { $0.evaluate([:]) }
            guard values.count == exprs.count else { return nil }
            for k in 1..<values.count where !approxEqual(values[k - 1], values[k], written: pieces[k]) {
                return .claim(line, holds: false, left: values[k - 1], right: values[k], rightText: pieces[k])
            }
            return .claim(line, holds: true, left: values[values.count - 2], right: values[values.count - 1],
                          rightText: pieces[pieces.count - 1])
        }
        guard vars.count == 1, let variable = vars.first else { return nil }
        let lhs = exprs[0]
        let rhs = exprs[1]
        let trig = lhs.hasTrig || rhs.hasTrig
        let f: (Double) -> Double? = { x in
            guard let a = lhs.evaluate([variable: x]), let b = rhs.evaluate([variable: x]) else { return nil }
            return a - b
        }
        switch solve(f) {
        case let .roots(roots, periodic):
            return .solved(line, variable: variable, roots: roots, periodic: periodic, trig: trig)
        case .noReal:
            return .noRealSolution(line, variable: variable)
        case .identity:
            return .identity(line, variable: variable)
        case .contradiction:
            return .contradiction(line, variable: variable)
        }
    }

    /// Linear systems in 2–3 unknowns written on separate lines ("x+y=5", "x-y=1").
    static func solveSystem(_ lines: [String]) -> MathSystemSolution? {
        var equations: [(text: String, f: ([String: Double]) -> Double?)] = []
        var vars = Set<String>()
        for raw in lines {
            let line = clean(raw)
            let pieces = MathParser.normalize(line).components(separatedBy: "=")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard pieces.count == 2, let l = MathParser.parse(pieces[0]), let r = MathParser.parse(pieces[1]) else { continue }
            let v = l.variables.union(r.variables)
            guard v.count >= 2, v.count <= 3 else { continue }
            vars.formUnion(v)
            equations.append((text: line, f: { env in
                guard let a = l.evaluate(env), let b = r.evaluate(env) else { return nil }
                return a - b
            }))
        }
        let names = vars.sorted()
        let n = names.count
        guard n >= 2, n <= 3, equations.count >= n else { return nil }
        // Every equation must be linear: f(p) = c + a·p.
        var rows: [[Double]] = []
        var rhs: [Double] = []
        var used: [String] = []
        for eq in equations {
            let zero = Dictionary(uniqueKeysWithValues: names.map { ($0, 0.0) })
            guard let c = eq.f(zero) else { continue }
            var a: [Double] = []
            var ok = true
            for name in names {
                var env = zero
                env[name] = 1
                guard let v = eq.f(env) else {
                    ok = false
                    break
                }
                a.append(v - c)
            }
            guard ok else { continue }
            let probe = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, 1.7 + Double($0.offset) * 2.3) })
            guard let check = eq.f(probe) else { continue }
            let predicted = c + zip(a, names).reduce(0.0) { $0 + $1.0 * (probe[$1.1] ?? 0) }
            guard abs(check - predicted) <= 1e-7 * (1 + abs(check)) else { continue }
            rows.append(a)
            rhs.append(-c)
            used.append(eq.text)
            if rows.count == n { break }
        }
        guard rows.count == n, let solution = gaussian(rows, rhs) else { return nil }
        return MathSystemSolution(equations: used, variables: names, values: solution)
    }

    // MARK: Solving

    enum SolveResult {
        case roots([Double], periodic: Bool)
        case noReal
        case identity
        case contradiction
    }

    static func solve(_ f: (Double) -> Double?) -> SolveResult {
        if let poly = polynomial(f) {
            return solvePolynomial(poly)
        }
        var roots = scan(f, from: -60, to: 60, steps: 24_000)
        if roots.isEmpty {
            roots = scan(f, from: -10_000, to: 10_000, steps: 40_000)
        }
        guard !roots.isEmpty else { return .noReal }
        if roots.count > 8 {
            // Periodic (trigonometric): the ones closest to zero, non-negative first.
            let principal = roots.filter { $0 >= -1e-9 }.sorted().prefix(4)
            return .roots(Array(principal.isEmpty ? roots.prefix(4) : principal), periodic: true)
        }
        return .roots(roots, periodic: false)
    }

    /// Coefficients (constant first) when f is a polynomial of degree ≤ 4.
    static func polynomial(_ f: (Double) -> Double?) -> [Double]? {
        let xs: [Double] = [0, 1, 2, 3, 4, 5, 6, -1.3, 2.7, 0.37, -3.1]
        var ys: [Double] = []
        for x in xs {
            guard let y = f(x) else { return nil }
            ys.append(y)
        }
        let scale = ys.map { abs($0) }.max() ?? 1
        for degree in 0...4 {
            let n = degree + 1
            let matrix = (0..<n).map { i in (0..<n).map { j in pow(xs[i], Double(j)) } }
            guard let coeffs = gaussian(matrix, Array(ys.prefix(n))) else { continue }
            var fits = true
            for (x, y) in zip(xs, ys) {
                let p = coeffs.enumerated().reduce(0.0) { $0 + $1.element * pow(x, Double($1.offset)) }
                if abs(p - y) > 1e-7 * (1 + scale) {
                    fits = false
                    break
                }
            }
            if fits { return coeffs }
        }
        return nil
    }

    static func solvePolynomial(_ c: [Double]) -> SolveResult {
        var coeffs = c
        let scale = coeffs.map { abs($0) }.max() ?? 1
        while coeffs.count > 1, let last = coeffs.last, abs(last) <= 1e-10 * (1 + scale) {
            coeffs.removeLast()
        }
        switch coeffs.count {
        case 1:
            return abs(coeffs[0]) <= 1e-9 * (1 + scale) ? .identity : .contradiction
        case 2:
            return .roots([tidy(-coeffs[0] / coeffs[1])], periodic: false)
        case 3:
            let a = coeffs[2]
            let b = coeffs[1]
            let k = coeffs[0]
            let disc = b * b - 4 * a * k
            let tol = 1e-12 * max(b * b, abs(4 * a * k), 1)
            if disc < -tol { return .noReal }
            if abs(disc) <= tol { return .roots([tidy(-b / (2 * a))], periodic: false) }
            let s = disc.squareRoot()
            let r = [(-b - s) / (2 * a), (-b + s) / (2 * a)].map(tidy).sorted()
            return .roots(r, periodic: false)
        default:
            let lead = coeffs.last!
            let bound = 1 + coeffs.dropLast().map { abs($0 / lead) }.max()!
            let poly: (Double) -> Double? = { x in coeffs.enumerated().reduce(0.0) { $0 + $1.element * pow(x, Double($1.offset)) } }
            let roots = scan(poly, from: -bound - 1, to: bound + 1, steps: 40_000)
            return roots.isEmpty ? .noReal : .roots(roots, periodic: false)
        }
    }

    /// Sign changes on a grid, refined by bisection. Ignores poles (where |f| blows up).
    static func scan(_ f: (Double) -> Double?, from a: Double, to b: Double, steps: Int) -> [Double] {
        var roots: [Double] = []
        let h = (b - a) / Double(steps)
        var prevX = a
        var prevY = f(a)
        for i in 1...steps {
            let x = a + Double(i) * h
            let y = f(x)
            if let p = prevY, let q = y {
                if p == 0 {
                    roots.append(prevX)
                } else if p * q < 0 {
                    var lo = prevX
                    var hi = x
                    var flo = p
                    for _ in 0..<80 {
                        let mid = (lo + hi) / 2
                        guard let fm = f(mid) else { break }
                        if fm == 0 {
                            lo = mid
                            hi = mid
                            break
                        }
                        if (flo < 0) == (fm < 0) {
                            lo = mid
                            flo = fm
                        } else {
                            hi = mid
                        }
                    }
                    let r = (lo + hi) / 2
                    if let fr = f(r), abs(fr) <= 1e-6 * (1 + min(abs(p), abs(q))) || abs(fr) < 1e-9 {
                        roots.append(r)
                    }
                }
            }
            prevX = x
            prevY = y
        }
        var unique: [Double] = []
        for r in roots.map(tidy) where !unique.contains(where: { abs($0 - r) <= 1e-6 * (1 + abs(r)) }) {
            unique.append(r)
        }
        return unique
    }

    /// Snaps values that are within rounding noise of a short decimal.
    static func tidy(_ v: Double) -> Double {
        for digits in 0...9 {
            let m = pow(10, Double(digits))
            let r = (v * m).rounded() / m
            if abs(r - v) <= 1e-9 * max(1, abs(v)) { return r == 0 ? 0 : r }
        }
        return v
    }

    static func gaussian(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        let n = rhs.count
        guard matrix.count == n, matrix.allSatisfy({ $0.count == n }) else { return nil }
        var a = matrix
        var b = rhs
        for col in 0..<n {
            var pivot = col
            for row in col..<n where abs(a[row][col]) > abs(a[pivot][col]) {
                pivot = row
            }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot)
            b.swapAt(col, pivot)
            for row in 0..<n where row != col {
                let factor = a[row][col] / a[col][col]
                guard factor != 0 else { continue }
                for k in col..<n {
                    a[row][k] -= factor * a[col][k]
                }
                b[row] -= factor * b[col]
            }
        }
        return (0..<n).map { tidy(b[$0] / a[$0][$0]) }
    }

    /// Tolerance follows the decimals the student wrote: "3,14" matches π.
    static func approxEqual(_ a: Double, _ b: Double, written: String) -> Bool {
        var decimals = 0
        if let dot = written.lastIndex(of: ".") {
            decimals = written[written.index(after: dot)...].prefix(while: { $0.isNumber }).count
        }
        let tolerance = decimals > 0
            ? 0.5 * pow(10, -Double(decimals)) + 1e-9
            : max(1e-9, 1e-9 * max(abs(a), abs(b)))
        return abs(a - b) <= tolerance
    }

    static func sameRoots(_ a: [Double], _ b: [Double]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a.sorted(), b.sorted()).allSatisfy { abs($0 - $1) <= 1e-6 * (1 + abs($0)) }
    }
}

// MARK: - Formatting

enum MathFormat {
    /// Decimal comma in Turkish answers, decimal point in English ones.
    static var locale: Locale { Locale(identifier: AnswerLanguage.current == .english ? "en_US" : "tr_TR") }

    /// "4", "2,5", "1/3 (≈ 0,3333)", "1,2 × 10⁻⁵".
    static func number(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v.rounded() == v && abs(v) < 1e15 {
            return String(Int64(v))
        }
        if let frac = fraction(v), frac.1 > 1, frac.1 <= 64 {
            return "\(frac.0)/\(frac.1) (≈ \(decimal(v)))"
        }
        return decimal(v)
    }

    static func decimal(_ v: Double) -> String {
        let a = abs(v)
        if a != 0 && (a < 1e-4 || a >= 1e9) {
            let exponent = Int(floor(log10(a)))
            let mantissa = v / pow(10, Double(exponent))
            return "\(decimal(mantissa)) × 10" + superscript(exponent)
        }
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = a < 1 ? 6 : 4
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    static func fraction(_ v: Double) -> (Int, Int)? {
        for q in 2...64 {
            let p = (v * Double(q)).rounded()
            if abs(p / Double(q) - v) <= 1e-10 * max(1, abs(v)), abs(p) < 1e9 {
                return (Int(p), q)
            }
        }
        return nil
    }

    static func superscript(_ n: Int) -> String {
        let table: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
                                           "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).map { table[$0] ?? $0 })
    }

    static func roots(_ roots: [Double], variable: String, trig: Bool) -> String {
        roots.map { r -> String in
            var s = "\(variable) = \(number(r))"
            if trig {
                let deg = MathEngine.tidy(r * 180 / .pi)
                s += " rad (\(decimal(deg))°)"
            }
            return s
        }.joined(separator: L("  veya  ", "  or  "))
    }

    /// One line of the report, in Markdown.
    static func describe(_ finding: MathFinding) -> String {
        switch finding {
        case let .value(line, v):
            return "`\(line)` → **\(number(v))**"
        case let .claim(line, holds, left, right, rightText):
            if holds { return "✓ `\(line)` " + L("doğru", "is correct") }
            return "✗ `\(line)` " + L("yanlış: sol taraf **\(number(left))** eder, yazılan `\(rightText)` = \(number(right))", "is wrong: the left side is **\(number(left))**, the written `\(rightText)` = \(number(right))")
        case let .solved(line, variable, roots, periodic, trig):
            var s = "`\(line)` → **\(MathFormat.roots(roots, variable: variable, trig: trig))**"
            if periodic { s += L(" _(periyodik: k·2π eklenerek tekrar eder)_", " _(periodic: repeats every k·2π)_") }
            return s
        case let .noRealSolution(line, variable):
            return "`\(line)` → " + L("gerçek sayılarda \(variable) için çözüm yok", "no real solution for \(variable)")
        case let .identity(line, variable):
            return "`\(line)` → " + L("her \(variable) için doğru (özdeşlik)", "true for every \(variable) (identity)")
        case let .contradiction(line, _):
            return "`\(line)` → " + L("hiçbir değer için doğru değil (çelişki)", "true for no value (contradiction)")
        }
    }
}
