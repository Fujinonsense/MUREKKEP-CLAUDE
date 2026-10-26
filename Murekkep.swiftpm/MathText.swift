import Foundation

/// Math in an answer as a textbook prints it. The models are told to write Unicode (≤, √, x²), but
/// small ones still slip into LaTeX; what arrives is turned into readable text before it is shown or
/// kept: "$\frac{-15 + 7}{2} = -4$" → "(−15 + 7)/2 = −4". Also the printed blanks a page's text layer
/// lost and the second thoughts a model writes into its answer, which the "solve the page" answers go
/// through. Foundation only (checked by tools/mathtextcheck).
enum MathText {
    // MARK: - LaTeX → text

    /// Every LaTeX fragment of `text` ($…$, $$…$$, \(…\), \[…\] and bare commands such as \le or
    /// \frac{}{} in the prose) as plain Unicode; fenced code blocks stay as they are. Applying it to
    /// its own result changes nothing.
    static func plain(_ text: String) -> String {
        guard text.contains("$") || text.contains("\\") || text.contains("^") else { return text }
        var out: [String] = []
        var block: [String] = []
        var inCode = false
        for line in text.components(separatedBy: "\n") {
            let fence = line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            if fence || inCode {
                if !block.isEmpty {
                    out.append(prose(block.joined(separator: "\n")))
                    block.removeAll()
                }
                out.append(line)
                if fence { inCode.toggle() }
            } else {
                block.append(line)
            }
        }
        if !block.isEmpty { out.append(prose(block.joined(separator: "\n"))) }
        return out.joined(separator: "\n")
    }

    /// One LaTeX fragment (the inside of $…$) as text.
    static func fragment(_ latex: String) -> String {
        let converted = convert(latex, inMath: true)
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]*\\n[ \\t]*", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\( +", with: "(", options: .regularExpression)
            .replacingOccurrences(of: " +\\)", with: ")", options: .regularExpression)
        return converted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prose with its math fragments converted; bare commands in the prose are converted too.
    private static func prose(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var text = ""
        var i = 0
        func flush() {
            if !text.isEmpty {
                out += convert(text, inMath: false)
                text = ""
            }
        }
        func emit(_ slice: ArraySlice<Character>) {
            flush()
            out += fragment(String(slice))
        }
        while i < chars.count {
            let c = chars[i]
            if c == "$" {
                if i + 1 < chars.count, chars[i + 1] == "$" {
                    if let close = find("$$", in: chars, from: i + 2) {
                        emit(chars[(i + 2)..<close])
                        i = close + 2
                        continue
                    }
                } else if let close = inlineClose(chars, from: i + 1) {
                    emit(chars[(i + 1)..<close])
                    i = close + 1
                    continue
                }
            } else if c == "\\", i + 1 < chars.count, chars[i + 1] == "(" || chars[i + 1] == "[" {
                let closer = "\\" + (chars[i + 1] == "(" ? ")" : "]")
                if let close = find(closer, in: chars, from: i + 2) {
                    emit(chars[(i + 2)..<close])
                    i = close + 2
                    continue
                }
            }
            text.append(c)
            i += 1
        }
        flush()
        return out
    }

    private static func find(_ needle: String, in chars: [Character], from start: Int) -> Int? {
        let n = Array(needle)
        guard n.count <= chars.count - start else { return nil }
        var k = start
        while k + n.count <= chars.count {
            if Array(chars[k..<(k + n.count)]) == n { return k }
            k += 1
        }
        return nil
    }

    /// The "$" that closes an inline fragment opened just before `start`: on the same line, with no
    /// space inside the delimiters and no digit after the closing one ("$5 and $10" is money).
    private static func inlineClose(_ chars: [Character], from start: Int) -> Int? {
        guard start < chars.count, !chars[start].isWhitespace, chars[start] != "$" else { return nil }
        var k = start + 1
        while k < chars.count {
            let c = chars[k]
            if c == "\n" { return nil }
            if c == "$" {
                guard !chars[k - 1].isWhitespace else { return nil }
                if k + 1 < chars.count, chars[k + 1].isNumber { return nil }
                return k
            }
            k += 1
        }
        return nil
    }

    /// `s` converted; in math every "-" is a minus and braces only group.
    static func convert(_ s: String, inMath: Bool) -> String {
        var reader = Reader(s, inMath: inMath)
        return reader.parse(group: false)
    }

    private struct Reader {
        let chars: [Character]
        let inMath: Bool
        var i = 0

        init(_ s: String, inMath: Bool) {
            chars = Array(s)
            self.inMath = inMath
        }

        var next: Character? { i < chars.count ? chars[i] : nil }

        mutating func parse(group: Bool) -> String {
            var out = ""
            while let c = next {
                if group && c == "}" {
                    i += 1
                    return out
                }
                i += 1
                switch c {
                case "\\":
                    out += command()
                case "^":
                    out += script(MathText.superscripts, mark: "^")
                case "_" where inMath:
                    out += script(MathText.subscripts, mark: "_")
                case "{" where inMath:
                    out += parse(group: true)
                case "}" where inMath:
                    break
                case "-" where inMath:
                    out.append("−")
                case "*" where inMath:
                    out.append("·")
                case "&" where inMath, "~" where inMath:
                    out.append(" ")
                default:
                    out.append(c)
                }
            }
            return out
        }

        /// The argument of a command: a {group}, a \command or one character.
        mutating func group() -> String {
            while let c = next, c == " " { i += 1 }
            guard let c = next else { return "" }
            i += 1
            if c == "{" { return parse(group: true) }
            if c == "\\" { return command() }
            if inMath && c == "-" { return "−" }
            return String(c)
        }

        /// "[3]" before \sqrt's argument.
        mutating func optional() -> String? {
            guard next == "[" else { return nil }
            i += 1
            var inner = ""
            while let c = next, c != "]" {
                inner.append(c)
                i += 1
            }
            if next == "]" { i += 1 }
            return MathText.convert(inner, inMath: inMath)
        }

        /// "^{n+1}" → "ⁿ⁺¹" when every character has a raised form, else "^(n+q)"; "^(n+1)" reads the
        /// same way, so a result goes through again unchanged.
        mutating func script(_ map: [Character: String], mark: Character) -> String {
            guard let c = next, !c.isWhitespace else { return String(mark) }
            let braced = c == "{" || c == "("
            let arg = c == "(" ? parenthesised() : group()
            if arg.isEmpty { return String(mark) }
            if MathText.raised.contains(arg) { return arg }
            let mapped = arg.map { map[$0] }
            if mapped.allSatisfy({ $0 != nil }) { return mapped.compactMap { $0 }.joined() }
            return arg.count == 1 && !braced ? "\(mark)\(arg)" : "\(mark)(\(arg))"
        }

        /// The inside of "(…)" at the reader, converted; the parentheses are consumed.
        mutating func parenthesised() -> String {
            i += 1
            var inner = ""
            var depth = 1
            while let c = next {
                i += 1
                if c == "(" { depth += 1 }
                if c == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
                inner.append(c)
            }
            return MathText.convert(inner, inMath: inMath)
        }

        mutating func command() -> String {
            var name = ""
            while let c = next, c.isASCII, c.isLetter {
                name.append(c)
                i += 1
            }
            if name.isEmpty {
                guard let c = next else { return "\\" }
                i += 1
                switch c {
                case "\\": return "\n"
                case ",", ";", ":", " ": return " "
                case "!": return ""
                case "|": return "‖"
                case "{", "}", "%", "$", "&", "_", "#": return String(c)
                default: return inMath ? String(c) : "\\" + String(c)
                }
            }
            switch name {
            case "frac", "dfrac", "tfrac", "cfrac":
                let a = group()
                let b = group()
                return MathText.fraction(a, b)
            case "sqrt":
                let index = optional()
                return MathText.root(group(), index: index)
            case "text", "textrm", "textit", "textbf", "textsf", "texttt", "mathrm", "mathit", "mathbf", "mathsf",
                 "mathtt", "mathcal", "mathscr", "mathfrak", "boldsymbol", "bm", "operatorname", "boxed", "underline",
                 "overbrace", "underbrace":
                return group()
            case "mathbb":
                let a = group()
                return MathText.blackboard[a] ?? a
            case "overline", "bar", "widebar": return MathText.accent(group(), "\u{0304}")
            case "hat", "widehat": return MathText.accent(group(), "\u{0302}")
            case "vec", "overrightarrow": return MathText.accent(group(), "\u{20D7}")
            case "tilde", "widetilde": return MathText.accent(group(), "\u{0303}")
            case "dot": return MathText.accent(group(), "\u{0307}")
            case "ddot": return MathText.accent(group(), "\u{0308}")
            case "binom", "dbinom", "tbinom":
                let n = group()
                let k = group()
                return "C(\(n), \(k))"
            case "left", "right":
                return delimiter()
            case "begin", "end", "hspace", "vspace", "label", "tag", "phantom":
                _ = group()
                return ""
            case "displaystyle", "textstyle", "scriptstyle", "limits", "nolimits", "mathstrut", "nonumber", "notag":
                return ""
            case "quad", "qquad", "enspace", "thinspace":
                return " "
            default:
                if let symbol = MathText.symbols[name] {
                    // LaTeX swallows the space after "\pi" in "\pi r^2": a Greek letter glues to what follows.
                    if symbol.count == 1, symbol.first!.isLetter, next == " ", i + 1 < chars.count,
                       chars[i + 1].isLetter || chars[i + 1].isNumber {
                        i += 1
                    }
                    return symbol
                }
                if MathText.functions.contains(name) { return name }
                return inMath ? name : "\\" + name
            }
        }

        /// What follows \left or \right: the bracket itself, nothing for "\left.".
        mutating func delimiter() -> String {
            while let c = next, c == " " { i += 1 }
            guard let c = next else { return "" }
            i += 1
            if c == "." { return "" }
            if c == "\\" { return command() }
            return String(c)
        }
    }

    private static let vulgar = ["1/2": "½", "1/3": "⅓", "2/3": "⅔", "1/4": "¼", "3/4": "¾", "1/5": "⅕", "1/8": "⅛"]

    /// "a/b", the operands in parentheses unless they are one piece; "½" and the like for the common ones.
    static func fraction(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespaces)
        let b = b.trimmingCharacters(in: .whitespaces)
        if let v = vulgar["\(a)/\(b)"] { return v }
        return wrap(a) + "/" + wrap(b)
    }

    /// "√x", "√16", "√(x+1)"; "∛", "∜" and "ⁿ√" for other indices.
    static func root(_ a: String, index: String?) -> String {
        let a = a.trimmingCharacters(in: .whitespaces)
        let sign: String
        switch index?.trimmingCharacters(in: .whitespaces) ?? "" {
        case "", "2": sign = "√"
        case "3": sign = "∛"
        case "4": sign = "∜"
        case let n: sign = n.map { superscripts[$0] ?? String($0) }.joined() + "√"
        }
        let simple = !a.isEmpty && (a.allSatisfy(\.isNumber) || (a.count == 1 && a.first!.isLetter))
        return sign + (simple || wrapped(a) ? a : "(" + a + ")")
    }

    private static func accent(_ a: String, _ mark: String) -> String {
        a.count == 1 ? a + mark : a
    }

    private static func wrap(_ s: String) -> String {
        atom(s) || wrapped(s) ? s : "(" + s + ")"
    }

    /// One piece: letters, digits and the symbols that stand alone ("2x", "x²", "π", "a₁").
    private static func atom(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || "π∞.,′".contains($0) }
    }

    /// Already in one pair of parentheses.
    private static func wrapped(_ s: String) -> Bool {
        guard s.hasPrefix("("), s.hasSuffix(")"), s.count >= 2 else { return false }
        var depth = 0
        for (k, c) in s.enumerated() {
            if c == "(" { depth += 1 }
            if c == ")" {
                depth -= 1
                if depth == 0 && k < s.count - 1 { return false }
            }
        }
        return depth == 0
    }

    private static let raised: Set<String> = ["°", "′", "″", "‴"]

    static let superscripts: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", " ": "",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ", "k": "ᵏ",
        "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "w": "ʷ",
        "x": "ˣ", "y": "ʸ", "z": "ᶻ", "T": "ᵀ",
    ]

    static let subscripts: [Character: String] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "−": "₋", "=": "₌", "(": "₍", ")": "₎", " ": "",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ",
        "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
    ]

    private static let blackboard = ["R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "P": "ℙ", "E": "𝔼"]

    /// Function names written "\sin": the backslash goes, the name stays.
    private static let functions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "ln", "log",
        "lg", "exp", "lim", "max", "min", "sup", "inf", "det", "gcd", "lcm", "deg", "dim", "ker", "mod", "arg", "Pr",
    ]

    private static let symbols: [String: String] = [
        "le": "≤", "leq": "≤", "leqslant": "≤", "ge": "≥", "geq": "≥", "geqslant": "≥", "ne": "≠", "neq": "≠",
        "lt": "<", "gt": ">", "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓", "infty": "∞",
        "approx": "≈", "equiv": "≡", "sim": "∼", "simeq": "≃", "cong": "≅", "propto": "∝", "ll": "≪", "gg": "≫",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν",
        "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ",
        "chi": "χ", "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
        "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "cup": "∪", "cap": "∩", "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "subseteq": "⊆", "supset": "⊃",
        "supseteq": "⊇", "setminus": "∖", "emptyset": "∅", "varnothing": "∅",
        "to": "→", "rightarrow": "→", "longrightarrow": "→", "leftarrow": "←", "Rightarrow": "⇒", "implies": "⇒",
        "Leftarrow": "⇐", "Leftrightarrow": "⇔", "iff": "⇔", "leftrightarrow": "↔", "mapsto": "↦", "uparrow": "↑",
        "downarrow": "↓",
        "ldots": "…", "cdots": "…", "dots": "…", "vdots": "⋮", "ddots": "⋱",
        "degree": "°", "circ": "°", "angle": "∠", "perp": "⊥", "parallel": "∥", "triangle": "△", "square": "□",
        "sum": "Σ", "prod": "Π", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮", "partial": "∂", "nabla": "∇",
        "forall": "∀", "exists": "∃", "nexists": "∄", "neg": "¬", "lnot": "¬", "land": "∧", "wedge": "∧",
        "lor": "∨", "vee": "∨", "therefore": "∴", "because": "∵",
        "lvert": "|", "rvert": "|", "vert": "|", "mid": "|", "lVert": "‖", "rVert": "‖", "Vert": "‖",
        "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "langle": "⟨", "rangle": "⟩",
        "lbrace": "{", "rbrace": "}", "lbrack": "[", "rbrack": "]",
        "prime": "′", "star": "⋆", "ast": "∗", "bullet": "•", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ",
        "aleph": "ℵ", "top": "⊤", "bot": "⊥", "oplus": "⊕", "otimes": "⊗", "ominus": "⊖", "percent": "%",
    ]

    // MARK: - Second thoughts

    /// Sentence openings of a model thinking out loud in the answer itself.
    private static let doubts = [
        "wait", "hmm", "hold on", "actually", "correction", "oops", "sorry", "let me", "on second thought",
        "never mind", "scratch that", "i think", "maybe", "perhaps", "no wait", "but wait", "re-check", "recheck",
        "double-check", "dur", "bekle", "bir dakika", "bir saniye", "aslında", "düzeltme", "pardon", "yanlış yazdım",
        "yanlış hesapladım", "tekrar kontrol", "yeniden kontrol", "sanırım", "galiba", "belki", "hayır,", "yok,",
    ]

    private static let listMarker = try! NSRegularExpression(pattern: #"^\s*(?:[-*•]\s+|\d{1,2}[.)]\s+)?"#)
    private static let sentenceEnd = try! NSRegularExpression(pattern: #"(?<=[.!?])\s+"#)

    /// The answer without the model's second thoughts: from a sentence that opens with "Wait",
    /// "Actually", "Correction", "Dur", "Düzeltme"… or mentions the OCR, the rest of its line goes;
    /// a line left with nothing goes with it.
    static func tidy(_ answer: String) -> String {
        var lines: [String] = []
        for line in answer.components(separatedBy: "\n") {
            let ns = line as NSString
            let marker = listMarker.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range) } ?? ""
            let body = ns.substring(from: (marker as NSString).length)
            guard !body.trimmingCharacters(in: .whitespaces).isEmpty else {
                lines.append(line)
                continue
            }
            let kept = sentences(body).prefix { !isDoubt($0) }
            guard !kept.isEmpty else { continue }
            lines.append(marker + kept.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    private static func sentences(_ s: String) -> [String] {
        let ns = s as NSString
        var out: [String] = []
        var last = 0
        for m in sentenceEnd.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: - Filler

    /// Openings that never carry working: a sentence starting so goes whatever follows.
    private static let heralds = ["here is", "here's", "here are", "işte", "aşağıda"]

    /// Openings of a sentence that only announces the working ("To solve the equation …, we consider
    /// the definition of absolute value."): it goes when it holds no number or sign of its own.
    private static let preambles = [
        "to solve", "in order to solve", "we consider", "we need", "we can", "we use", "we apply", "we start", "we begin",
        "we have", "we know", "we want", "we must", "we will", "we'll", "we solve", "we find", "recall", "let's", "let us",
        "first,", "first of all", "the solution", "the answer", "the equation", "the inequality", "solution", "steps",
        "step 1", "çözüm", "adımlar", "çözmek için", "bunun için", "öncelikle", "ilk olarak", "önce ", "bu denklem",
        "bu eşitsizlik", "bu soru", "soruyu", "denklemi", "eşitsizliği", "mutlak değer",
    ]

    /// A "Cevap:"/"Answer:" line is the answer, never filler.
    private static let answerLabel = try! NSRegularExpression(
        pattern: #"^[\s*_#>-]*(?:cevap|yan[ıi]t|answer|sonu[çc]|result)\s*[:：]"#, options: [.caseInsensitive])

    /// Runs of math tokens in a sentence ("|x − 2| < 6", "a < x < b", "a = ____"): a token is math
    /// when it is only digits, signs, bars, brackets, blanks and single Latin letters. A run ends at a
    /// word or at a token's trailing comma or full stop.
    static func mathRuns(in text: String) -> [String] {
        let signs = "0123456789+-−–*/×÷^√|()[]{}.,=<>≤≥≠±∞²³¹⁰⁴⁵⁶⁷⁸⁹_½¼¾·"
        func isMath(_ t: String) -> Bool {
            guard !t.isEmpty else { return false }
            var run = 0
            for ch in t {
                if ch.isLetter {
                    run += 1
                    guard run == 1, ch.isASCII else { return false }
                } else if signs.contains(ch) {
                    run = 0
                } else {
                    return false
                }
            }
            return true
        }
        var runs: [String] = []
        var current: [String] = []
        func close() {
            if !current.isEmpty { runs.append(current.joined(separator: " ")) }
            current = []
        }
        for raw in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            var t = String(raw)
            var ends = false
            while let last = t.last, ".,;:?!".contains(last) {
                t.removeLast()
                ends = true
            }
            if isMath(t) {
                current.append(t)
                if ends { close() }
            } else {
                close()
            }
        }
        close()
        return runs
    }

    private static func squeezed(_ s: String) -> String {
        String(s.filter { !$0.isWhitespace }).replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
    }

    /// The answer without the model's filler: "Here is the solution:", "Steps:", a sentence that only
    /// restates the question's math and announces the work. A sentence with a number or a sign of its
    /// own (one the question does not contain) is working, and stays whole; after "Here is …:" only
    /// what follows the colon stays. A "Cevap:"/"Answer:" line is never touched.
    static func withoutFiller(_ answer: String, question: String) -> String {
        let known = mathRuns(in: question).map(squeezed).filter { $0.count >= 3 }
        let tr = Locale(identifier: "tr_TR")
        func opens(_ sentence: String, _ cues: [String]) -> Bool {
            let body = String(sentence.drop { !$0.isLetter })
            let lower = body.lowercased()
            let lowerTR = body.lowercased(with: tr)
            return cues.contains { lower.hasPrefix($0) || lowerTR.hasPrefix($0) }
        }
        func hasWork(_ sentence: String) -> Bool {
            var rest = squeezed(sentence)
            for k in known {
                rest = rest.replacingOccurrences(of: k, with: "")
            }
            return rest.contains { $0.isNumber || "=<>≤≥".contains($0) }
        }
        /// What of a sentence is shown: nil for filler.
        func kept(_ sentence: String) -> String? {
            if let r = sentence.range(of: ": "), opens(String(sentence[..<r.lowerBound]), heralds) {
                return kept(String(sentence[r.upperBound...]))
            }
            if opens(sentence, heralds) { return nil }
            if hasWork(sentence) { return sentence }
            return sentence.hasSuffix(":") || opens(sentence, preambles) ? nil : sentence
        }
        var lines: [String] = []
        for line in answer.components(separatedBy: "\n") {
            let ns = line as NSString
            guard answerLabel.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) == nil else {
                lines.append(line)
                continue
            }
            let marker = listMarker.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range) } ?? ""
            let body = ns.substring(from: (marker as NSString).length)
            guard !body.trimmingCharacters(in: .whitespaces).isEmpty else {
                lines.append(line)
                continue
            }
            let shown = sentences(body).compactMap(kept)
            guard !shown.isEmpty else { continue }
            lines.append(marker + shown.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    private static func isDoubt(_ sentence: String) -> Bool {
        if sentence.contains("OCR") { return true }
        let s = String(sentence.lowercased().drop { !$0.isLetter })
        for cue in doubts where s.hasPrefix(cue) {
            // The cue is a whole word ("dur", not "durum").
            if let after = s.dropFirst(cue.count).first, after.isLetter { continue }
            return true
        }
        return false
    }

    // MARK: - The page's text

    private static let underscores = try! NSRegularExpression(pattern: #"_(?:[ \t]?_)+"#)
    private static let leaders = try! NSRegularExpression(pattern: #"(?<!\.)\.{4,}(?!\.)|…{2,}"#)
    /// "a = and b =", "b = ." or "b =" at the end of the line: an answer line the text layer lost.
    private static let equalsBeforeWord = try! NSRegularExpression(
        pattern: #"(\b[A-Za-z])[ \t]*=[ \t]*(?=(?:and|or|ve|veya)\b)"#)
    private static let equalsBeforeEnd = try! NSRegularExpression(
        pattern: #"(\b[A-Za-z])[ \t]*=[ \t]*(?=[,;.)]|$)"#, options: [.anchorsMatchLines])

    /// Printed blanks as "____" (underscores, dot leaders), and an "=" that has nothing after it
    /// ("where a = and b =") given one, so a model sees what is to be filled.
    static func markBlanks(_ text: String) -> String {
        func replace(_ rx: NSRegularExpression, in s: String, with t: String) -> String {
            rx.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: t)
        }
        var t = replace(underscores, in: text, with: "____")
        t = replace(leaders, in: t, with: "____")
        t = replace(equalsBeforeWord, in: t, with: "$1 = ____ ")
        return replace(equalsBeforeEnd, in: t, with: "$1 = ____")
    }

    /// A page of worded math questions rather than a textbook exercise: enough signs of working
    /// (=, <, ≤, √, |…|) for its questions.
    static func looksMath(_ text: String, questions: Int) -> Bool {
        let signs = text.filter { "=+×÷√≤≥≠^∫∑π²³<>|−±∞".contains($0) }.count
        return signs >= max(4, questions)
    }
}
