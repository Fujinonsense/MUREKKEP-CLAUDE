import Foundation

// The checks of MathText.swift and the math teacher's lines in Questions.swift, run with the Windows
// Swift toolchain (tools/mathtextcheck/run.ps1). Prints every failure and a final count.

var failures = 0
var total = 0

func check(_ ok: Bool, _ name: String, got: String = "") {
    total += 1
    if !ok {
        failures += 1
        print("FAIL \(name)" + (got.isEmpty ? "" : " — got: \(got.debugDescription)"))
    }
}

func same(_ input: String, _ expected: String, _ name: String) {
    let got = MathText.plain(input)
    check(got == expected, name, got: got)
    // Applying it again changes nothing.
    check(MathText.plain(got) == got, name + " (idempotent)", got: MathText.plain(got))
}

// MARK: LaTeX fragments the assistant showed raw

same("$-15 \\le x \\le 7$", "−15 ≤ x ≤ 7", "inequality chain")
same("$\\frac{-15 + 7}{2} = -4$", "(−15 + 7)/2 = −4", "fraction with a sum")
same("$x^2 - 9$", "x² − 9", "square")
same("$\\sqrt{x+1}$", "√(x+1)", "root of a sum")
same("[2, \\infty)", "[2, ∞)", "bare infinity")
same("**(1) $|x-2| < 6$** Answer: $-4 < x < 8$ Steps: 1. Remove absolute value: $-6 < x-2 < 6$.",
     "**(1) |x−2| < 6** Answer: −4 < x < 8 Steps: 1. Remove absolute value: −6 < x−2 < 6.", "the shown answer, bold kept")
same("Answer: $|x - 1| \\le 14$", "Answer: |x − 1| ≤ 14", "absolute value with le")
same("$\\frac{1}{2}$, $\\dfrac{3}{4}$, $\\frac{a+b}{c}$, $\\frac{x}{2}$, $\\frac{x^2}{4}$",
     "½, ¾, (a+b)/c, x/2, x²/4", "fractions")
same("$x_{1} + x_2 = a_n$", "x₁ + x₂ = aₙ", "subscripts")
same("$\\left( \\frac{a}{b} \\right)^2$", "(a/b)²", "left right")
same("$\\sqrt[3]{27} = 3$ and $\\sqrt{16}$ and $\\sqrt{x}$", "∛27 = 3 and √16 and √x", "roots")
same("$\\pi r^2$", "πr²", "pi glued to r")
same("$e^{-x}$, $2^{10}$, $x^{n+1}$, $a^{1/2}$, $f^{-1}(x)$", "e⁻ˣ, 2¹⁰, xⁿ⁺¹, a^(1/2), f⁻¹(x)", "superscripts")
same("$\\text{for } x \\in \\mathbb{R}$", "for x ∈ ℝ", "text and blackboard")
same("$$\\int_0^1 x\\,dx = \\frac{1}{2}$$", "∫₀¹ x dx = ½", "display block")
same("$5 and $10", "$5 and $10", "money is not math")
same("```\n$x^2$\n```\n$x^2$", "```\n$x^2$\n```\nx²", "code block kept")
same("x^2 - 9 and \\le and \\frac{1}{3}", "x² - 9 and ≤ and ⅓", "bare prose commands")
same("**Cevap:** $x = 3$", "**Cevap:** x = 3", "bold label")
same("\\(x^2\\) and \\[a \\ne b\\]", "x² and a ≠ b", "paren and bracket delimiters")
same("$x \\neq 0$, $a \\times b \\div c \\pm d$, $\\{1, 2\\} \\cup \\{3\\}$", "x ≠ 0, a × b ÷ c ± d, {1, 2} ∪ {3}", "symbols")
same("$\\alpha + \\beta = \\pi$", "α + β = π", "greek")
same("$45^\\circ$", "45°", "degrees")
same("$A \\cap B = \\emptyset$, $x \\to \\infty$, $p \\Rightarrow q$", "A ∩ B = ∅, x → ∞, p ⇒ q", "sets and arrows")
same("$\\sin x + \\cos x$", "sin x + cos x", "functions keep their space")
same("$\\sqrt{2gh}$ and $\\sqrt{(x+1)}$", "√(2gh) and √(x+1)", "root not doubly wrapped")
same("Hiç matematik yok.", "Hiç matematik yok.", "plain text untouched")
same("$\\lim_{x \\to 0} \\frac{\\sin x}{x} = 1$", "lim_(x → 0) (sin x)/x = 1", "limit")
same("$\\begin{aligned} a &= b \\\\ c &= d \\end{aligned}$", "a = b\nc = d", "aligned")
same("A multi\nline $x$ text\n$$\n\\frac{a}{b}\n$$\nend", "A multi\nline x text\na/b\nend", "lines kept")
check(MathText.plain("$x = 5") == "$x = 5", "unclosed dollar stays", got: MathText.plain("$x = 5"))

// MARK: Second thoughts

let doubtful = """
Answer: |x − 1| ≤ 14
Steps:
1. Find midpoint a = (−15 + 7)/2 = −4. Wait, the target form is |x−a| ≤ b.
2. Midpoint a = (−15 + 7)/2 = −4.
3. Distance b = 7 − (−4) = 11.
*Correction*: Let's check the OCR text carefully. a= and b=.
Hmm, usually for −k ≤ x ≤ k the midpoint is 0.
Answer: a = −4, b = 11
"""
let tidied = MathText.tidy(doubtful)
check(tidied == """
Answer: |x − 1| ≤ 14
Steps:
1. Find midpoint a = (−15 + 7)/2 = −4.
2. Midpoint a = (−15 + 7)/2 = −4.
3. Distance b = 7 − (−4) = 11.
Answer: a = −4, b = 11
""", "second thoughts dropped", got: tidied)
check(MathText.tidy("Durum böyle. Dur, yanlış.\nAslında b = 11.\n- Düzeltme: a = −4.") == "Durum böyle.", "turkish cues, whole words",
      got: MathText.tidy("Durum böyle. Dur, yanlış.\nAslında b = 11.\n- Düzeltme: a = −4."))
check(MathText.tidy("x = 4.\n\nCheck: 4·4 = 16.") == "x = 4.\n\nCheck: 4·4 = 16.", "a check line stays")

// MARK: Lost blanks

let marked = MathText.markBlanks("in the form a < x < b where a = and b =\nin the form |x − a| ≤ b where a = and b = .")
check(marked == "in the form a < x < b where a = ____ and b = ____\nin the form |x − a| ≤ b where a = ____ and b = ____.", "empty equals", got: marked)
same("x^(n+1) and a^(1/2)", "xⁿ⁺¹ and a^(1/2)", "parenthesised exponents")
check(MathText.markBlanks("a = ____ and b = ____.") == "a = ____ and b = ____.", "blanks stay")
check(MathText.markBlanks("a = _ _ _ _ and b = ........") == "a = ____ and b = ____", "underscores and leaders", got: MathText.markBlanks("a = _ _ _ _ and b = ........"))
check(MathText.markBlanks("x = 5 and y = 7, f(x) =\nSolve |4x + 23| = |4x − 9|.") == "x = 5 and y = 7, f(x) =\nSolve |4x + 23| = |4x − 9|.", "equations untouched")

// MARK: A page of worded math questions

let calculus = """
1.2 Exercises
(1) The inequality |x − 2| < 6 can be expressed in the form a < x < b where a = ____ and b = ____.
(2) The inequality −15 ≤ x ≤ 7 can be expressed in the form |x − a| ≤ b where a = ____ and b = ____.
(3) Solve the equation |4x + 23| = |4x − 9|.
"""
let grammar = """
1 Complete the sentences with a/an.
1 I have ___ apple.
2 She is ___ doctor.
3 Discuss in pairs.
"""
check(MathText.looksMath(calculus, questions: 3) && !MathText.looksMath(grammar, questions: 3), "math page vs grammar page")
let qs = QuestionSplitter.split(calculus)
check(qs.map(\.number) == [1, 2, 3] && qs.allSatisfy { $0.options.isEmpty }, "parenthesised numbers start questions", got: "\(qs.map(\.number))")
check(qs.last?.stem == "Solve the equation |4x + 23| = |4x − 9|.", "stem without its number", got: qs.last?.stem ?? "")
check(qs.first?.stem.hasSuffix("a = ____ and b = ____.") == true, "blanks reach the stem")
let yks = QuestionSplitter.split("1. Soru?\nA) a B) b C) c\n2. Soru?\nA) a B) b")
check(yks.map(\.number) == [1, 2] && yks[0].options.count == 3, "plain numbering still splits")

// MARK: The math teacher's line

let q2 = PageQuestion(number: 2, stem: "The inequality …", options: [], passage: nil)
let line = QuestionSolving.openLine(q2, answer: tidied, language: .english)
check(line.hasPrefix("**2)** **Answer: a = −4, b = 11**\nSteps:\n1. Find midpoint"), "answer first, steps under it", got: line)
check(!line.contains("|x − 1| ≤ 14"), "the first answer line is gone")
check(QuestionSolving.openLine(q2, answer: "Cevap: **x = 3**\n- 4x = 12", language: .turkish) == "**2)** **Cevap: x = 3**\n- 4x = 12\n\n",
      "bold inside the answer line", got: QuestionSolving.openLine(q2, answer: "Cevap: **x = 3**\n- 4x = 12", language: .turkish))
check(QuestionSolving.openLine(q2, answer: "x = −7/4 because 4x + 23 = −(4x − 9).", language: .english)
      == "**2)** x = −7/4 because 4x + 23 = −(4x − 9).\n\n", "no answer line: the text as it is")
check(QuestionSolving.finalAnswer(in: "**Answer:** a = −4") == "a = −4" && QuestionSolving.finalAnswer(in: "1. Remove the bars.") == nil,
      "answer line read")
check(QuestionSolving.mathInstructions(language: .english).contains("LaTeX kullanma")
      && QuestionSolving.mathInstructions(language: .english).hasSuffix("RESPONSE LANGUAGE: English."), "math instructions")

print("mathtextcheck \(total - failures)/\(total) ok" + (failures == 0 ? "" : ", \(failures) failed"))
exit(failures == 0 ? 0 : 1)
