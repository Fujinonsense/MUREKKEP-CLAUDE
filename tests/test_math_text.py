"""Math in the assistant's answers reads like a textbook, never as raw LaTeX, and "Solve the questions
on the page" gives one tidy block per question (the result first, a few steps, no second thoughts).

MathText.swift itself is Foundation only and is checked with the Windows Swift toolchain
(tools/mathtextcheck/run.ps1); this checks the wiring in the app's source."""
from pathlib import Path

from ports.questions import split

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"

CALCULUS = """1.2 Exercises
(1) The inequality |x − 2| < 6 can be expressed in the form a < x < b where a = ____ and b = ____.
(2) The inequality −15 ≤ x ≤ 7 can be expressed in the form |x − a| ≤ b where a = ____ and b = ____.
(3) Solve the equation |4x + 23| = |4x − 9|.
"""


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_latex_is_turned_into_text_where_answers_are_shown_and_kept():
    text = src("MathText.swift")
    assert text.startswith("import Foundation") and "import UIKit" not in text and "import SwiftUI" not in text
    for fn in ("static func plain(", "static func tidy(", "static func markBlanks(", "static func looksMath("):
        assert fn in text
    view = src("AssistantView.swift")
    assert "MathText.plain(text).components" in view
    assert "UIPasteboard.general.string = MathText.plain(message.text)" in view
    # Every answer of the downloaded model is kept as text, so history and copies are clean too.
    assert "return MathText.plain(answer)" in src("AssistantModel.swift")


def test_the_models_are_told_to_write_unicode_not_latex():
    assert "LaTeX kullanma" in src("AssistantModel.swift")
    questions = src("Questions.swift")
    assert "static func mathInstructions(language: AnswerLanguage)" in questions
    teacher = questions.split("static func mathInstructions")[1].split("static let pageSolvingRules")[0]
    for phrase in ("LaTeX kullanma", '\\"Cevap: …\\"', "en fazla üç kısa adım", "OCR yorumu olmasın", "≤ ≥ ≠ × ÷ √ ² ³ π ∞"):
        assert phrase in teacher, phrase
    rules = questions.split("static let pageSolvingRules")[1].split("\n")[0]
    for phrase in ("ilk satırda kalın kesin sonuç", "en fazla üç kısa adım", "OCR yorumu olmasın", "LaTeX yazma"):
        assert phrase in rules, phrase


def test_a_page_of_worded_math_questions_is_solved_one_at_a_time():
    model = src("AssistantModel.swift")
    assert "let mathPage = questions.count >= 2 && MathText.looksMath(sourceText, questions: questions.count)" in model
    assert "let textbook = !multipleChoice && !mathPage && exercises.contains { $0.kind != .skip }" in model
    assert "solveWithBrain(questions, language: language, math: mathPage)" in model
    assert "let worded = q.options.count < 2 && (math || BrainBudget.isMath(q.promptText))" in model
    assert "thinking: worded ? BrainBudget.mathQuestion : BrainBudget.thinking(for: q.promptText)" in model
    assert "QuestionSolving.openLine(q, answer: MathText.withoutFiller(MathText.tidy(answer), question: q.stem)," in model
    assert "static let mathQuestion = 768" in src("BrainCatalog.swift")


def test_the_math_engine_answers_what_it_can_solve_exactly_and_checks_the_rest():
    """ExactMath.swift (Foundation only, checked by tools/mathcheck) solves a page's equations and
    inequalities exactly; the flow shows its result as the answer line with the model's steps under
    it, and checks the model's own result by substitution where the engine could not solve."""
    exact = src("ExactMath.swift")
    assert exact.startswith("import Foundation") and "import UIKit" not in exact and "import SwiftUI" not in exact
    for fn in ("static func solve(_ stem: String) -> Answer?", "static func verify(question: String, answer: String) -> Verdict?"):
        assert fn in exact
    model = src("AssistantModel.swift")
    # An engine-solved question is shown at once with the engine's own working; the model is not asked.
    engine = "if worded, let exact = AnswerLanguage.$bound.withValue(language, operation: { ExactMath.solve(q.stem) }) {"
    assert engine in model
    shown = "appendToAnswer(QuestionSolving.engineLine(q, answer: exact.answer, steps: exact.working, language: language))"
    assert model.count(shown) == 2  # the downloaded model's loop and Apple's, the fallback
    block = model.split(engine)[1].split("let request = BrainRuntime.Request")[0]
    assert shown in block and "continue" in block and "runBrain" not in block
    assert "ExactMath.verify(question: q.stem, answer: final)" in model
    assert "QuestionSolving.retryNote(reason: reason, hint: hint, language: language)" in model
    assert "language: language, note: note))" in model
    # The page's text reaches the engine and the model with lookalike characters unified and blanks marked.
    assert "p.text = MathText.markBlanks(MathText.unifiedMath(page.text))" in model
    assert "} else if let exact = ExactMath.solve(line) {" in src("OfflineBrain.swift")
    questions = src("Questions.swift")
    for fn in ("static func engineLine(", "static func retryNote(", "static func stepsBody("):
        assert fn in questions
    assert "stepsInstructions" not in questions and "mathSteps" not in src("BrainCatalog.swift")


def test_the_whole_page_answer_gets_the_rules_and_is_tidied():
    model = src("AssistantModel.swift")
    assert 'if action == .solve { system += "\\n" + QuestionSolving.pageSolvingRules }' in model
    assert "action == .solve ? MathText.withoutFiller(MathText.tidy(answer), question: pageText) : answer" in model


def test_lost_blanks_reach_the_model():
    model = src("AssistantModel.swift")
    assert "p.text = MathText.markBlanks(MathText.unifiedMath(page.text))" in model
    # Before the questions are split, so the blanks are in the stems.
    assert model.index("MathText.markBlanks") < model.index("QuestionSplitter.split(sourceText)")


def test_parenthesised_numbers_start_questions():
    qs = split(CALCULUS)
    assert [q.number for q in qs] == [1, 2, 3]
    assert all(q.options == [] for q in qs)
    assert qs[2].stem == "Solve the equation |4x + 23| = |4x − 9|."
    assert qs[0].stem.endswith("a = ____ and b = ____.")
    assert r'#"^\s*\(?(\d{1,2}|[lI])\s*[.)]\s+(\S.*)$"#' in src("Questions.swift")
