import Foundation

// The math engine on a page of textbook exercises (CALCULUS p.14, "1.2 Exercises", as the page's
// text layer gives them to the assistant), run with the Windows Swift toolchain
// (tools/mathcheck/run.ps1). Prints every failure and a final count.

var failures = 0
var total = 0

func check(_ ok: Bool, _ name: String, got: String = "") {
    total += 1
    if !ok {
        failures += 1
        print("FAIL \(name)" + (got.isEmpty ? "" : " — got: \(got.debugDescription)"))
    }
}

/// The engine's answer line to a question's stem, or "-" when it leaves it to the model.
func exact(_ stem: String) -> String {
    ExactMath.solve(stem)?.answer ?? "-"
}

func steps(_ stem: String) -> [String] {
    ExactMath.solve(stem)?.working ?? []
}

var solvedStems: [String] = []

func expect(_ stem: String, _ answer: String, _ name: String) {
    let got = exact(stem)
    check(got == answer, name, got: got)
    if got != "-" { solvedStems.append(stem) }
}

func expectSteps(_ stem: String, _ lines: [String], _ name: String) {
    let got = steps(stem)
    check(got == lines, name, got: got.joined(separator: " | "))
}

AnswerLanguage.bound = .english

// MARK: The parser reads absolute values in products and powers

check(MathParser.parse("3|x-2|") != nil && MathParser.parse("|x-2|^2+3|x-2|-4") != nil, "parser: a bar after an operand opens one")
check(MathParser.parse("|x|+|x-1|") != nil && MathParser.parse("|2x+1|") != nil && MathParser.parse("|x") == nil, "parser: bars pair up")
check(MathParser.parse("2|-3|")?.evaluate([:]) == 6, "parser: 2|−3| = 6")
if case let .solved(_, _, roots, _, _)? = MathEngine.analyze("|4x+23|=|4x-9|") {
    check(roots == [-1.75], "math engine: the numeric root of |4x+23| = |4x−9|", got: "\(roots)")
} else {
    check(false, "math engine: the numeric root of |4x+23| = |4x−9|")
}

// MARK: The page's exercises, exactly

let ex = [
    "The inequality |x − 2| < 6 can be expressed in the form a < x < b where a = ____ and b = ____.",
    "The inequality −15 ≤ x ≤ 7 can be expressed in the form |x − a| ≤ b where a = ____ and b = ____.",
    "Solve the equation |4x + 23| = |4x − 9|.",
    "Solve the equation |x² + 2| = |x² − 11|.",
    "Solve the equation |2x − 5| = 7.",
    "Solve the equation |x − 2|² + 3|x − 2| − 4 = 0.",
    "The inequality −4 ≤ x ≤ 10 can be expressed in the form |x − a| ≤ b where a = ____ and b = ____.",
    "Solve the equation |x + 1| = 3x − 5.",
    "Solve the inequality |x + 4| < 7.",
    "Solve the inequality |3x + 7| < 5.",
    "Solve the equation |x² − 9| = |x² − 5|.",
    "Solve the inequality |(2x² − 3)/14| ≤ 1/2.",
    "Solve the inequality |x − 3| ≥ 6.",
    "Solve the inequality |2x + 1| > 3.",
    "Solve the inequality |x² − 4| ≤ 5.",
    "Solve the inequality |5 − 2x| ≤ 1.",
    "Solve the equation x² − 2x − 4 = 0.",
]
expect(ex[0], "a = −4, b = 8", "ex 1: |x − 2| < 6 as a < x < b")
expect(ex[1], "a = −4, b = 11", "ex 2: −15 ≤ x ≤ 7 as |x − a| ≤ b")
expect(ex[2], "x = −7/4", "ex 3: |4x + 23| = |4x − 9|")
expect(ex[3], "x = ±3√2/2", "ex 4: |x² + 2| = |x² − 11|")
expect(ex[4], "x = −1 or x = 6", "ex 5: |2x − 5| = 7")
expect(ex[5], "x = 1 or x = 3", "ex 6: a quadratic in |x − 2|")
expect(ex[6], "a = 3, b = 7", "ex 7: −4 ≤ x ≤ 10 as |x − a| ≤ b")
expect(ex[7], "x = 3", "ex 8: |x + 1| = 3x − 5 keeps only the root with 3x − 5 ≥ 0")
expect(ex[8], "−11 < x < 3", "ex 9: |x + 4| < 7")
expect(ex[9], "−4 < x < −2/3", "ex 10: |3x + 7| < 5")
expect(ex[10], "x = ±√7", "ex 11: |x² − 9| = |x² − 5|")
expect(ex[11], "−√5 ≤ x ≤ √5", "ex 12: |(2x² − 3)/14| ≤ 1/2")
expect(ex[12], "(−∞, −3] ∪ [9, ∞)", "ex 13: |x − 3| ≥ 6")
expect(ex[13], "(−∞, −2) ∪ (1, ∞)", "ex 14: |2x + 1| > 3")
expect(ex[14], "−3 ≤ x ≤ 3", "ex 15: |x² − 4| ≤ 5")
expect(ex[15], "2 ≤ x ≤ 3", "ex 16: |5 − 2x| ≤ 1")
expect(ex[16], "x = 1 − √5 or x = 1 + √5", "ex 17: a quadratic with surd roots")

// MARK: The engine's own steps, as a teacher writes them (English)

expectSteps(ex[0], ["|x − 2| < 6 ⇒ −6 < x − 2 < 6", "Add 2 to each part: −4 < x < 8", "a = −4, b = 8"], "steps 1: the bars removed, then the blanks")
expectSteps(ex[1], ["Midpoint: a = (−15 + 7)/2 = −4", "Half-width: b = (7 − (−15))/2 = 11", "So |x + 4| ≤ 11"], "steps 2: midpoint and half-width")
expectSteps(ex[2], ["Case 1: 4x + 23 = 4x − 9 ⇒ no solution", "Case 2: 4x + 23 = −(4x − 9) ⇒ 8x = −14 ⇒ x = −7/4"], "steps 3: the two cases")
expectSteps(ex[3], ["Case 1: x² + 2 = x² − 11 ⇒ no solution", "Case 2: x² + 2 = −(x² − 11) ⇒ 2x² = 9 ⇒ x² = 9/2 ⇒ x = ±3√2/2"], "steps 4: a square in the cases")
expectSteps(ex[4], ["Case 1: 2x − 5 = 7 ⇒ 2x = 12 ⇒ x = 6", "Case 2: 2x − 5 = −7 ⇒ 2x = −2 ⇒ x = −1"], "steps 5: |A| = c")
expectSteps(ex[5], ["t = |x − 2| ⇒ t² + 3t − 4 = 0", "(t + 4)(t − 1) = 0 ⇒ t = −4 or t = 1 (t ≥ 0, so t = −4 is out)", "|x − 2| = 1 ⇒ x = 1 or x = 3"],
            "steps 6: the quadratic in t")
expectSteps(ex[7], ["Case 1: x + 1 = 3x − 5 ⇒ 2x = 6 ⇒ x = 3 (3x − 5 = 4 ≥ 0 ✓)", "Case 2: x + 1 = −(3x − 5) ⇒ 4x = 4 ⇒ x = 1 (3x − 5 = −2 < 0 ✗)"],
            "steps 8: each case checked against the right side")
expectSteps(ex[8], ["|x + 4| < 7 ⇒ −7 < x + 4 < 7", "Subtract 4 from each part: −11 < x < 3"], "steps 9: |A| < c")
expectSteps(ex[9], ["|3x + 7| < 5 ⇒ −5 < 3x + 7 < 5", "Subtract 7 from each part: −12 < 3x < −2", "Divide by 3: −4 < x < −2/3"], "steps 10: subtract, then divide")
expectSteps(ex[11], ["|(2x² − 3)/14| ≤ 1/2 ⇒ −1/2 ≤ (2x² − 3)/14 ≤ 1/2",
                     "(2x² − 3)/14 ≤ 1/2 ⇒ x² − 5 ≤ 0 ⇒ roots: x = −√5, x = √5 ⇒ −√5 ≤ x ≤ √5",
                     "(2x² − 3)/14 ≥ −1/2 ⇒ x² + 2 ≥ 0 ⇒ roots: no root ⇒ all real numbers (ℝ)"], "steps 12: a quadratic inside the bars")
expectSteps(ex[12], ["|x − 3| ≥ 6 ⇒ x − 3 ≥ 6 or x − 3 ≤ −6", "x − 3 ≥ 6 ⇒ x ≥ 9", "x − 3 ≤ −6 ⇒ x ≤ −3"], "steps 13: |A| ≥ c")
expectSteps(ex[15], ["|2x − 5| ≤ 1 ⇒ −1 ≤ 2x − 5 ≤ 1", "Add 5 to each part: 4 ≤ 2x ≤ 6", "Divide by 2: 2 ≤ x ≤ 3"], "steps 16: add, then divide")
expectSteps(ex[16], ["Δ = 20 ⇒ x = (2 ± √20)/2 = 1 ± √5"], "steps 17: the discriminant")
for stem in solvedStems {
    let n = steps(stem).count
    check(n >= 1 && n <= 3, "every solved exercise has 1–3 step lines: \"\(stem)\"", got: "\(n)")
    check(!steps(stem).contains { $0.lowercased().contains("note") || $0.contains("Correction") }, "no self-correction in the steps of \"\(stem)\"")
}

// MARK: More shapes

expect("Solve 2x + 3 = 7.", "x = 2", "linear equation")
expectSteps("Solve 2x + 3 = 7.", ["2x = 4 ⇒ x = 2"], "steps: linear equation")
expect("Solve x² − 5x + 6 = 0.", "x = 2 or x = 3", "quadratic with rational roots")
expectSteps("Solve x² − 5x + 6 = 0.", ["(x − 2)(x − 3) = 0 ⇒ x = 2 or x = 3"], "steps: factored")
expectSteps("Solve 2x² − 10x + 12 = 0.", ["Δ = 4 ⇒ x = (10 ± √4)/4 ⇒ x = 2 or x = 3"], "steps: a quadratic with a leading coefficient keeps its numbers")
expect("Solve the equation x² + 1 = 0.", "no solution", "no real root")
expectSteps("Solve the equation x² + 1 = 0.", ["x² = −1 ⇒ no solution"], "steps: a negative square")
expect("Solve the inequality x² − 4x + 4 ≤ 0.", "x = 2", "a double root as an inequality")
expect("Solve the inequality x² + 1 < 0.", "no solution (∅)", "an inequality with no solution")
expect("Solve the inequality x² ≥ 0.", "all real numbers (ℝ)", "an inequality that always holds")
expect("Solve the inequality −3 < 2x + 1 ≤ 5.", "−2 < x ≤ 2", "a chain")
expectSteps("Solve the inequality −3 < 2x + 1 ≤ 5.", ["Subtract 1 from each part: −4 < 2x ≤ 4", "Divide by 2: −2 < x ≤ 2"], "steps: a chain taken apart")
expect("Solve the inequality 2x − 1 > 3.", "x > 2", "a half line")
expectSteps("Solve the inequality 2x − 1 > 3.", ["2x > 4 ⇒ x > 2"], "steps: a half line")
expect("Solve the equation |x − 1| = −2.", "no solution", "|x − 1| = −2 has no solution")
expectSteps("Solve the equation |x − 1| = −2.", ["|x − 1| = −2: an absolute value is never negative, no solution"], "steps: a negative absolute value")
expect("Solve the equation |x| = x.", "x ≥ 0", "|x| = x holds for x ≥ 0")
expect("Solve the inequality (x + 1)/(x − 3) ≥ 0.", "(−∞, −1] ∪ (3, ∞)", "rational inequality, the pole stays out")
expectSteps("Solve the inequality (x + 1)/(x − 3) ≥ 0.", ["(x + 1)/(x − 3) ≥ 0", "Numerator zero: x = −1; denominator zero (undefined): x = 3", "Sign chart: (−∞, −1] ∪ (3, ∞)"],
            "steps: rational inequality")
expect("Solve the inequality 1/(x − 2) < 3.", "(−∞, 2) ∪ (7/3, ∞)", "rational inequality with a constant")
expect("Solve the equation (x² − 1)/(x − 1) = 2.", "no solution", "a rational equation whose only root is a pole")
expect("Solve |x − 1| ≤ 2x.", "x ≥ 1/3", "|A| ≤ B with x on the right")
expect("Solve |x − 1| > 2x.", "x < 1/3", "|A| > B with x on the right")
expect("Solve the inequality |x − 2| ≤ 0.", "x = 2", "|x − 2| ≤ 0 is one point")
expect("Solve |x + 1|² = 4.", "x = −3 or x = 1", "a square of an absolute value")
expect("Solve the equation 3|x + 1| = 6.", "x = −3 or x = 1", "a coefficient before the bars")
expect("Solve the inequality |x| ≥ |x − 2|.", "x ≥ 1", "|A| ≥ |B| with linear insides")
expect("Solve the equation 2x = 7.", "x = 7/2", "a fraction, never 3.5")
expect("Solve 0,5x = 2.", "x = 4", "a decimal comma in the coefficient")
expect("Solve x <= 3.", "x ≤ 3", "ASCII <=")

// The page's text layer, as a PDF gives it: italic math letters, ⩽, lost blanks, a bare "a =".
expect("The inequality |𝑥 − 2| < 6 can be expressed in the form 𝑎 < 𝑥 < 𝑏 where 𝑎 = and 𝑏 =", "a = −4, b = 8", "text layer: italic letters and blanks lost")
expect("The inequality −15 ⩽ 𝑥 ⩽ 7 can be expressed in the form |𝑥 − 𝑎| ⩽ 𝑏 where 𝑎 = and 𝑏 = .", "a = −4, b = 11", "text layer: ⩽ and a bare \"a =\"")
expect("Solve the equation ∣4𝑥 + 23∣ = ∣4𝑥 − 9∣.", "x = −7/4", "text layer: the divides sign as a bar")
expect("The inequality |x – 2| < 6 can be expressed in the form a < x < b where a = ___ and b = ___.", "a = −4, b = 8", "text layer: en dash and short blanks")
expect(MathText.markBlanks(MathText.unifiedMath("The inequality |𝑥 − 2| < 6 can be expressed in the form 𝑎 < 𝑥 < 𝑏 where 𝑎 = and 𝑏 =")),
       "a = −4, b = 8", "text layer: through the app's own unifying and blank marking")
check(MathText.unifiedMath("𝑥² ⩽ 𝟗 and 𝐀") == "x² ≤ 9 and A" && MathText.unifiedMath("Questions 1–2 refer to") == "Questions 1–2 refer to",
      "unified math: letters, digits and signs; a directive's dash stays", got: MathText.unifiedMath("𝑥² ⩽ 𝟗 and 𝐀"))

// Turkish wording, Turkish answers and steps.
AnswerLanguage.bound = .turkish
expect("|x − 2| < 6 eşitsizliğini çözünüz.", "−4 < x < 8", "tr: an inequality")
expect("|2x + 1| = 5 denkleminin çözüm kümesini bulunuz.", "x = −3 veya x = 2", "tr: an equation with two roots")
expect("x² + 1 = 0 denklemini çözünüz.", "çözüm yok", "tr: no solution")
expect("−15 ≤ x ≤ 7 eşitsizliğini |x − a| ≤ b biçiminde yazınız: a = ____, b = ____.", "a = −4, b = 11", "tr: the blanks")
expect("|x − 2| < 6 eşitsizliğini sağlayan x değerlerini bulunuz.", "−4 < x < 8", "tr: \"sağlayan\" still solves")
expectSteps(ex[0], ["|x − 2| < 6 ⇒ −6 < x − 2 < 6", "Her tarafa 2 ekle: −4 < x < 8", "a = −4, b = 8"], "tr steps 1")
expectSteps(ex[1], ["Orta nokta: a = (−15 + 7)/2 = −4", "Yarı genişlik: b = (7 − (−15))/2 = 11", "Yani |x + 4| ≤ 11"], "tr steps 2")
expectSteps(ex[2], ["Durum 1: 4x + 23 = 4x − 9 ⇒ çözüm yok", "Durum 2: 4x + 23 = −(4x − 9) ⇒ 8x = −14 ⇒ x = −7/4"], "tr steps 3")
expectSteps(ex[9], ["|3x + 7| < 5 ⇒ −5 < 3x + 7 < 5", "Her taraftan 7 çıkar: −12 < 3x < −2", "3 ile böl: −4 < x < −2/3"], "tr steps 10")
expectSteps(ex[12], ["|x − 3| ≥ 6 ⇒ x − 3 ≥ 6 veya x − 3 ≤ −6", "x − 3 ≥ 6 ⇒ x ≥ 9", "x − 3 ≤ −6 ⇒ x ≤ −3"], "tr steps 13")
AnswerLanguage.bound = .english

// MARK: Questions the engine leaves to the model

for stem in ["Show that x = 2 satisfies x² − 4 = 0.", "Find a and b if 2a + b = 5 and a − b = 1.", "If f(x) = 3x + 2, find f(4).",
             "Ali'nin 3 elması var, 2 tane daha alırsa kaç elması olur?", "x = 5 is a solution of which equation?",
             "Explain why |x| ≥ 0 for every x.", "Solve the equation x³ − x = 0.", "Solve sin x = 0.5.", "Evaluate 3 + 4 × 2.",
             "Solve |x| + |x − 1| = 3.", "Solve x|x| = 4.", "Solve the equation x² = y."] {
    check(exact(stem) == "-", "the model's: \"\(stem)\"", got: exact(stem))
}

// MARK: Exact numbers

check(ExactNumber.sqrt(Fraction(72))?.text == "6√2" && ExactNumber.sqrt(Fraction(9, 2))?.text == "3√2/2"
      && ExactNumber.sqrt(Fraction(49))?.text == "7" && ExactNumber.sqrt(Fraction(-1)) == nil, "exact: square roots simplified")
check(Fraction(0.3)?.text == "3/10" && Fraction(-1.75)?.text == "−7/4" && Fraction(Double.pi) == nil && Fraction(1.0 / 3) == nil
      && Fraction(0.125)?.text == "1/8", "exact: decimals as fractions",
      got: "\(Fraction(0.3)?.text ?? "nil") \(Fraction(-1.75)?.text ?? "nil") \(Fraction(Double.pi)?.text ?? "nil") \(Fraction(1.0 / 3)?.text ?? "nil")")
check((Fraction(1, 3) + Fraction(1, 6)).text == "1/2" && (Fraction(2, 3) * Fraction(3, 4)).text == "1/2", "exact: fraction arithmetic")
check(((ExactNumber(Fraction(1)) + ExactNumber.sqrt(Fraction(5))!)!).sign == 1
      && ((ExactNumber(Fraction(-3)) + ExactNumber.sqrt(Fraction(5))!)!).sign == -1, "exact: the sign of a + b√n")
check(RPoly([Fraction(-3, 14), .zero, Fraction(1, 7)]).text("x") == "(2x² − 3)/14" && RPoly([.zero, Fraction(1, 2)]).text("x") == "x/2",
      "poly text: a common denominator", got: RPoly([Fraction(-3, 14), .zero, Fraction(1, 7)]).text("x"))

// MARK: Checking the model's answer by substitution

let q3 = "Solve the equation |4x + 23| = |4x − 9|."
if case let .fails(reason, hint)? = ExactMath.verify(question: q3, answer: "x = 0.3") {
    check(reason == "x = 0.3 does not satisfy the equation: left side 24.2, right side 7.8", "verify: the wrong 0.3 is caught", got: reason)
    check(hint == "x = -7/4 (≈ -1.75)", "verify: the hint is what substitution finds", got: hint ?? "nil")
} else {
    check(false, "verify: the wrong 0.3 is caught")
}
check(ExactMath.verify(question: q3, answer: "x = −7/4") == .holds, "verify: −7/4 holds")
check(ExactMath.verify(question: q3, answer: "**x = -1.75**.") == .holds, "verify: a decimal that holds, bold stripped")
let q6 = "Solve the equation |x − 2|² + 3|x − 2| − 4 = 0."
check(ExactMath.verify(question: q6, answer: "x = 1 or x = 3") == .holds && ExactMath.verify(question: q6, answer: "x = 3 veya x = 1") == .holds,
      "verify: both roots listed")
if case let .fails(reason, _)? = ExactMath.verify(question: q6, answer: "x = 3") {
    check(reason.contains("x = 1") && reason.contains("missing"), "verify: a missing root is caught", got: reason)
} else {
    check(false, "verify: a missing root is caught")
}
check(ExactMath.verify(question: "Solve the equation x² + 1 = 0.", answer: "No solution.") == .holds, "verify: no solution, correctly")
if case let .fails(reason, _)? = ExactMath.verify(question: "Solve the equation x² − 4 = 0.", answer: "no real solution") {
    check(reason.contains("satisfies"), "verify: a wrong \"no solution\" is caught", got: reason)
} else {
    check(false, "verify: a wrong \"no solution\" is caught")
}
check(ExactMath.verify(question: "Solve the equation x² − 7 = 0.", answer: "x = ±√7") == .holds, "verify: ± and a root sign")
check(ExactMath.verify(question: "Solve the inequality |x + 4| < 7.", answer: "−11 < x < 3") == nil, "verify: an inequality is not checked")
check(ExactMath.verify(question: q3, answer: "The cases differ.") == nil, "verify: an answer without a value is not checked")
check(ExactMath.verify(question: "Solve the equation x³ − x = 0.", answer: "x = −1, x = 0, x = 1") == .holds, "verify: a cubic the exact solver skips is still checked")
check(ExactMath.claimed(in: "x ∈ {1, 3}", variable: "x") == [1, 3] && ExactMath.claimed(in: "x = 2 because 2·2 = 4", variable: "x") == [2],
      "verify: sets and reasons are read")

// MARK: Filler and second thoughts dropped from the model's steps

let shown = """
Here is the solution to the equation: To solve the equation |4x + 23| = |4x − 9|, we consider the definition of absolute value.
Steps:
1. Case 1: 4x + 23 = 4x − 9 gives 23 = −9, no solution.
2. Case 2: 4x + 23 = −(4x − 9), so 8x = −14 and x = −7/4.
Answer: x = −7/4
"""
let trimmed = MathText.withoutFiller(shown, question: q3)
check(trimmed == """
1. Case 1: 4x + 23 = 4x − 9 gives 23 = −9, no solution.
2. Case 2: 4x + 23 = −(4x − 9), so 8x = −14 and x = −7/4.
Answer: x = −7/4
""", "filler: the opening and the heading go, the working stays", got: trimmed)
check(MathText.withoutFiller("Çözüm:\nİşte çözüm. Mutlak değer tanımına göre iki durum vardır.\n- Önce 2x − 5 = 7 → x = 6.\n- Sonra 2x − 5 = −7 → x = −1.",
                             question: "|2x − 5| = 7 denklemini çözünüz.")
      == "- Önce 2x − 5 = 7 → x = 6.\n- Sonra 2x − 5 = −7 → x = −1.", "filler: Turkish openings",
      got: MathText.withoutFiller("Çözüm:\nİşte çözüm. Mutlak değer tanımına göre iki durum vardır.\n- Önce 2x − 5 = 7 → x = 6.\n- Sonra 2x − 5 = −7 → x = −1.",
                                  question: "|2x − 5| = 7 denklemini çözünüz."))
check(MathText.withoutFiller("To solve, split into two cases: 4x+23 = 4x−9 or 4x+23 = −(4x−9).", question: q3)
      == "To solve, split into two cases: 4x+23 = 4x−9 or 4x+23 = −(4x−9).", "filler: a real step that opens like filler stays")
check(MathText.withoutFiller("1. Remove the bars: −6 < x − 2 < 6.\n2. Add 2: −4 < x < 8.", question: "Solve |x − 2| < 6.")
      == "1. Remove the bars: −6 < x − 2 < 6.\n2. Add 2: −4 < x < 8.", "filler: numbered steps untouched")
check(MathText.withoutFiller("Here is the solution: 8x = −14, so x = −7/4.\nCevap: çözüm yok", question: q3)
      == "8x = −14, so x = −7/4.\nCevap: çözüm yok", "filler: after \"Here is …:\" the work stays; an answer line is kept whole",
      got: MathText.withoutFiller("Here is the solution: 8x = −14, so x = −7/4.\nCevap: çözüm yok", question: q3))
check(MathText.mathRuns(in: "The inequality |x − 2| < 6 can be expressed in the form a < x < b where a = ____ and b = ____.")
      == ["|x − 2| < 6", "a < x < b", "a = ____", "b = ____"], "math runs of a question", got: "\(MathText.mathRuns(in: "The inequality |x − 2| < 6 can be expressed in the form a < x < b where a = ____ and b = ____."))")
// What the iPad showed for question 2: the model's wandering steps, the self-correction dropped.
let wandering = """
• Start with the given inequality: −15 ≤ x ≤ 7.
• Add 1 to all parts to center the interval around a = 1: −16 ≤ x − 1 ≤ 8.
• Note: The correct transformation requires |x − a| ≤ b where a = (−15 + 7)/2 = −4 and b = (7 − (−15))/2 = 22/2 = 11.
• Not: aslında b = 11.
• Correction: a = −4.
• Wait, the midpoint is −4.
• Thus, |x − (−4)| ≤ 11, which simplifies to |x + 4| ≤ 11.
"""
let tidied = MathText.tidy(wandering)
check(tidied == """
• Start with the given inequality: −15 ≤ x ≤ 7.
• Add 1 to all parts to center the interval around a = 1: −16 ≤ x − 1 ≤ 8.
• Thus, |x − (−4)| ≤ 11, which simplifies to |x + 4| ≤ 11.
""", "tidy: Note, Not, Correction and Wait lines go", got: tidied)
check(MathText.tidy("Not defteri: x = 2.") == "Not defteri: x = 2.", "tidy: \"not\" without a colon is a word")

// MARK: The answer line

let q = PageQuestion(number: 3, stem: q3, options: [], passage: nil)
check(QuestionSolving.engineLine(q, answer: "x = −7/4", steps: ["Case 1: 4x + 23 = 4x − 9 ⇒ no solution", "Case 2: 4x + 23 = −(4x − 9) ⇒ 8x = −14 ⇒ x = −7/4"], language: .english)
      == "**3)** **Answer: x = −7/4**\nCase 1: 4x + 23 = 4x − 9 ⇒ no solution\nCase 2: 4x + 23 = −(4x − 9) ⇒ 8x = −14 ⇒ x = −7/4\n\n",
      "engine line: the engine's answer and its working",
      got: QuestionSolving.engineLine(q, answer: "x = −7/4", steps: ["Case 1: 4x + 23 = 4x − 9 ⇒ no solution", "Case 2: 4x + 23 = −(4x − 9) ⇒ 8x = −14 ⇒ x = −7/4"], language: .english))
check(QuestionSolving.engineLine(q, answer: "x = −7/4", steps: [], language: .turkish) == "**3)** **Cevap: x = −7/4**\n\n", "engine line: no steps")
// The page's first block, as the iPad showed it: the model's list written twice is shown once.
let twice = "Answer: −4 < x < 8\n1. Subtract 2: −6 < x − 2 < 6.\n2. Add 2: −4 < x < 8.\n3. Identify a and b.\n\n1. Subtract 2: −6 < x − 2 < 6.\n2. Add 2: −4 < x < 8.\n3. Identify a and b.\n"
check(QuestionSolving.openLine(PageQuestion(number: 1, stem: ex[0], options: [], passage: nil), answer: twice, language: .english)
      == "**1)** **Answer: −4 < x < 8**\n1. Subtract 2: −6 < x − 2 < 6.\n2. Add 2: −4 < x < 8.\n3. Identify a and b.\n\n", "open line: repeated steps shown once",
      got: QuestionSolving.openLine(PageQuestion(number: 1, stem: ex[0], options: [], passage: nil), answer: twice, language: .english))
check(QuestionSolving.engineLine(q, answer: "x = 1", steps: ["a", "a", "", "", "b", "a"], language: .english) == "**3)** **Answer: x = 1**\na\n\nb\n\n",
      "engine line: no repeats, no piled blank lines", got: QuestionSolving.engineLine(q, answer: "x = 1", steps: ["a", "a", "", "", "b", "a"], language: .english))
check(QuestionSolving.openLine(q, answer: "Answer: x = 0.3\n1. Guess.", language: .english, note: "x = 0.3 does not satisfy the equation")
      == "**3)** **Answer: x = 0.3** ⚠️ x = 0.3 does not satisfy the equation\n1. Guess.\n\n", "open line: the failed check is said",
      got: QuestionSolving.openLine(q, answer: "Answer: x = 0.3\n1. Guess.", language: .english, note: "x = 0.3 does not satisfy the equation"))
check(QuestionSolving.finalAnswer(of: "Answer: x = 1\nsteps\nAnswer: x = 2") == "x = 2" && QuestionSolving.finalAnswer(of: "1. no answer") == nil,
      "the last answer line of an answer")
check(QuestionSolving.retryNote(reason: "x = 0.3 does not satisfy the equation", hint: "x = -7/4 (≈ -1.75)", language: .english)
      == "YOUR FIRST ANSWER WAS WRONG: x = 0.3 does not satisfy the equation. By substitution the math engine finds that x = -7/4 (≈ -1.75) satisfies the equation; solve again towards that and check every case.",
      "retry note", got: QuestionSolving.retryNote(reason: "x = 0.3 does not satisfy the equation", hint: "x = -7/4 (≈ -1.75)", language: .english))

// MARK: The page as its PDF gives it (tests/fixtures/calculus_p14_pdftotext.txt), through the app's own pipeline

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let fixture = (try? String(contentsOfFile: root + "/tests/fixtures/calculus_p14_pdftotext.txt", encoding: .utf8)) ?? ""
check(!fixture.isEmpty, "the PDF's text fixture is read")

/// The answers of a page's text, question by question, as AssistantModel prepares and solves it.
func pageAnswers(_ text: String) -> [Int: String] {
    var out: [Int: String] = [:]
    for q in QuestionSplitter.split(MathText.pageForSolving(text)) {
        out[q.number] = ExactMath.solve(q.stem)?.answer ?? "-"
    }
    return out
}

/// What iPadOS PDFKit may give instead of poppler: a true minus sign, single spaces where the sign
/// was lost, and two lines joined without a space.
func pdfKitLike(_ text: String) -> String {
    text.replacingOccurrences(of: "(?<=[\\s|])-(?=[0-9\\s])", with: "−", options: .regularExpression)
        .replacingOccurrences(of: "  ", with: " ")
        .replacingOccurrences(of: " and\nb = .", with: " andb = .")
}

let mustSolve: [Int: String] = [
    1: "a = −4, b = 8", 2: "a = −4, b = 11", 3: "x = −7/4", 4: "x = ±3√2/2", 6: "x = 1 or x = 3", 7: "a = 3, b = 7",
    9: "a = −11, b = 3", 10: "(−4, −2/3)", 11: "x = ±√7", 13: "(−∞, −3] ∪ [9, ∞)",
]
// Solved right, or left to the model: never a wrong engine answer.
let mayLeave: [Int: String] = [
    5: "[−1/2, 1) ∪ [2, ∞)", 12: "[−√5, √5]", 14: "(−∞, −2) ∪ [−2/3, 4)", 15: "(−∞, −3) ∪ [−7/4, 2)", 16: "(−1, 3]",
    17: "x = −10 or x = −7/2 or x = −5/2 or x = 4", 18: "[−1, 0) ∪ [2, ∞)",
]
for (name, text) in [("poppler", fixture), ("pdfkit-like", pdfKitLike(fixture))] {
    let answers = pageAnswers(text)
    check(answers.count == 18, "\(name): 18 questions split", got: "\(answers.keys.sorted())")
    for (n, a) in mustSolve.sorted(by: { $0.key < $1.key }) {
        check(answers[n] == a, "\(name) (\(n)): \(a)", got: answers[n] ?? "nil")
    }
    for (n, a) in mayLeave.sorted(by: { $0.key < $1.key }) {
        check(answers[n] == a || answers[n] == "-", "\(name) (\(n)): right or the model's", got: answers[n] ?? "nil")
    }
    check(answers[8] == "-", "\(name) (8): a graph is the model's", got: answers[8] ?? "nil")
}
let poppler = pageAnswers(fixture)
check([12, 14, 15, 17, 18].allSatisfy { poppler[$0] == mayLeave[$0] }, "poppler: the split fractions and the quadratic in |x + 3| are solved",
      got: [12, 14, 15, 17, 18].map { "\($0): \(poppler[$0] ?? "nil")" }.joined(separator: " | "))
check(poppler[5] == "-" && poppler[16] == "-", "poppler: cubic denominators stay the model's", got: "\(poppler[5] ?? "nil") \(poppler[16] ?? "nil")")
// The pieces: squares put back, a lost sign marked, a template read, the fractions rebuilt.
check(MathText.restoredSquares("|x2 + 2| = |x2 - 11| and |x - 2|2 + 3|x - 2| - 4 = 0 and 2|x + 3|2 - 15|x + 3|, x3 + x2, 3|2 - x| < 2, x = 2")
      == "|x² + 2| = |x² − 11| and |x − 2|² + 3|x − 2| − 4 = 0 and 2|x + 3|² − 15|x + 3|, x³ + x², 3|2 − x| < 2, x = 2"
      .replacingOccurrences(of: "−", with: "-"), "squares restored only after an operand",
      got: MathText.restoredSquares("|x2 + 2| = |x2 - 11| and |x - 2|2 + 3|x - 2| - 4 = 0 and 2|x + 3|2 - 15|x + 3|, x3 + x2, 3|2 - x| < 2, x = 2"))
check(ExactMath.withGaps("-15 x 7") == "-15 ⟂ x ⟂ 7" && ExactMath.withGaps("|x - a| b") == "|x - a| ⟂ b" && ExactMath.withGaps("| x - 3 | 6") == "| x - 3 | ⟂ 6"
      && ExactMath.withGaps("|x - 3| < 6") == nil && ExactMath.withGaps("x x + 2 x + 3 x - 4") == nil && ExactMath.withGaps("3x") == nil,
      "gaps: operands side by side, bars paired, nothing else", got: "\(ExactMath.withGaps("| x - 3 | 6") ?? "nil")")
check(ExactMath.intervalTemplate(in: "Answer: ( , ]  [ , 2 ) .") == [ExactMath.Template(loClosed: false, hiClosed: true, lo: nil, hi: nil),
                                                                       ExactMath.Template(loClosed: true, hiClosed: false, lo: nil, hi: Fraction(2))]
      && ExactMath.intervalTemplate(in: "is (-, )  [ , 2 ).").count == 2 && ExactMath.intervalTemplate(in: "Solve (x + 1)/(x - 2) ≥ 0.").isEmpty,
      "template: brackets and the numbers already there")
check(ExactMath.solve("Solve the inequality |x - 3|  6. Answer: ( , )  ( , ).")?.answer == "(−∞, −3) ∪ (9, ∞)", "a lost sign: strict rays make it >",
      got: ExactMath.solve("Solve the inequality |x - 3|  6. Answer: ( , )  ( , ).")?.answer ?? "nil")
check(ExactMath.solve("Solve the inequality |x - 3|  6.") == nil && ExactMath.solve("Compute 3 x 4.") == nil
      && ExactMath.solve("The numbers -15 x 7 are given.") == nil, "a lost sign with nothing to decide it stays the model's")
check(ExactMath.solve("The inequality −15 x 7 can be expressed in the form |x − a| b where a = and b = .")?.working
      == ["Midpoint: a = (−15 + 7)/2 = −4", "Half-width: b = (7 − (−15))/2 = 11", "So |x + 4| ≤ 11"], "the chain's steps print the inferred ≤",
      got: "\(ExactMath.solve("The inequality −15 x 7 can be expressed in the form |x − a| b where a = and b = .")?.working ?? [])")
let rebuilt = MathText.rebuiltFractions("(5) Solve the inequality\n3x\nx2 + 2\n\n1\nx - 1\n. Express your answer in interval notation.\nAnswer: [ , )  [ 2 , ) .\n(6) Solve the equation |x - 2|2 + 3|x - 2| - 4 = 0.")
check(rebuilt == "(5) Solve the inequality (3x)/(x2 + 2)  (1)/(x - 1). Express your answer in interval notation.\nAnswer: [ , )  [ 2 , ) .\n(6) Solve the equation |x - 2|2 + 3|x - 2| - 4 = 0.",
      "fractions rebuilt on the sentence's line", got: rebuilt)
check(MathText.rebuiltFractions("Calculate the sums:\n3 + 4\n5 × 6\n(2) Next question") == "Calculate the sums:\n3 + 4\n5 × 6\n(2) Next question",
      "a list of sums is not a fraction")
check(MathText.rebuiltFractions("Complete the text with the words in the box.\n1\n2\npeople were waiting outside") == "Complete the text with the words in the box.\n1\n2\npeople were waiting outside",
      "a textbook's gap numbers on their own lines are not a fraction")
// What build 208 met on the iPad (PDFKit's text): a fraction laid flat with its square gone, and a
// form whose first blank did not survive.
check(ExactMath.solve("(5) Solve the inequality 3x x + 2 ≥ 1 x − 1 . Express your answer in interval notation. Answer: [ , ) ∪ [ 2 , ) .") == nil
      && ExactMath.solve("Solve the inequality 3x x2 + 2 ≥ 1 x − 1. Express your answer in interval notation.") == nil,
      "a fraction laid flat is the model's, never a product",
      got: ExactMath.solve("(5) Solve the inequality 3x x + 2 ≥ 1 x − 1 . Express your answer in interval notation. Answer: [ , ) ∪ [ 2 , ) .")?.answer ?? "nil")
check(ExactMath.solve("2 x + 3 = 7")?.answer == "x = 2", "a spaced coefficient is still one",
      got: ExactMath.solve("2 x + 3 = 7")?.answer ?? "nil")
check(ExactMath.solve("(1) The inequality |x − 2| < 6 can be expressed in the form a < x < b where b = .")?.answer == "a = −4, b = 8"
      && ExactMath.solve("The inequality −15 x 7 can be expressed in the form |x − a| b where b = .")?.answer == "a = −4, b = 11",
      "every letter of the form is filled, even when one blank was lost",
      got: ExactMath.solve("(1) The inequality |x − 2| < 6 can be expressed in the form a < x < b where b = .")?.answer ?? "nil")
check(ExactMath.verify(question: "Solve the equation |4x + 23| = |4x - 9|. Answer: x = .", answer: "x = −1") != nil
      && ExactMath.verify(question: "Solve the equation x3 - x = 0. Answer: x = , x = , and x = .", answer: "x = 0, x = 1, x = −1") == .holds,
      "verify: the page's own answer blanks do not stop the check", got: "\(String(describing: ExactMath.verify(question: "Solve the equation |4x + 23| = |4x - 9|. Answer: x = .", answer: "x = −1")))")

// MARK: The engine's earlier checks still hold (as tools/swiftcheck runs them)

func solved(_ line: String) -> (String, [Double])? {
    if case let .solved(text, _, roots, _, _)? = MathEngine.analyze(line) { return (text, roots) }
    return nil
}
check(solved("2x+3=7 ise x kaçtır?").map { $0.0 == "2x+3=7" && $0.1 == [2] } == true, "math engine: the x after \"ise\"")
check(solved("x²+3x=10 ise x kaçtır?")?.1 == [-5, 2], "math engine: a worded quadratic has both roots")
check(MathEngine.analyze("2x+3=7 ise 4x kaçtır?") == nil && MathEngine.analyze("f(x)=3x+2 ise f(4) kaçtır?") == nil, "math engine: no fact for other askings")
check(PageMath.engineSettles(["3+3=33"]) && !PageMath.engineSettles(["2x+3=7 ise x kaçtır?"]), "page math: what the engine settles alone")
check(PageMath.question("3+3=33 doğru mu?") != nil && PageMath.question("türev nedir?") == nil, "page math: chat questions")

print("mathcheck \(total - failures)/\(total) ok" + (failures == 0 ? "" : ", \(failures) failed"))
exit(failures == 0 ? 0 : 1)
