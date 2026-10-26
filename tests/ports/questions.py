"""Port of QuestionSplitter (Murekkep.swiftpm/Questions.swift): the questions of a page (text layer
or OCR), each with its stem, its options and the passage it refers to.

A question starts on a line "N.", "N)" or "(N)" whose N follows the previous question's number (the
first one may be any number; OCR's "l." or "I." counts as 1 when a "2." follows). Numbered lines that
break the count stay inside the question. A directive ("3. - 5. soruları …", "Questions 1-2 refer to
…") starts a passage that belongs to the questions it names. Options are markers A) B) C) D) (E) in
order, also several on one line, also "(A)" and "A."; fewer than two means an open question."""
import re
from dataclasses import dataclass, field

QUESTION = re.compile(r"^\s*\(?(\d{1,2}|[lI])\s*[.)]\s+(\S.*)$")
DIRECTIVES = [
    re.compile(r"^\s*(\d{1,2})\s*\.?\s*(?:-|–|ve|ile)\s*(\d{1,2})\s*\.?\s*sorular", re.IGNORECASE),
    re.compile(r"^\s*questions?\s+(\d{1,2})\s*(?:-|–|and|to)\s*(\d{1,2})", re.IGNORECASE),
]
OPTION = re.compile(r"(?:(?<=\s)|^)[(]?([A-Ea-e])\s*[).\]]\s+")
PASSAGE_MIN_LETTERS = 120


@dataclass
class Option:
    letter: str
    text: str


@dataclass
class Question:
    number: int
    stem: str
    options: list = field(default_factory=list)
    passage: str | None = None


def _directive(line):
    for rx in DIRECTIVES:
        m = rx.match(line)
        if m:
            return int(m.group(1)), int(m.group(2))
    return None


def _number(token, expected, rest_lines):
    if token in ("l", "I"):
        # OCR reads "1." as "l." or "I.": only the first question, and only when a "2." follows.
        if expected not in (None, 1):
            return None
        return 1 if any(re.match(r"^\s*\(?2\s*[.)]\s+\S", ln) for ln in rest_lines) else None
    n = int(token)
    return n if expected is None or n == expected else None


def _options(text):
    """(stem, options) from a question's text."""
    marks = list(OPTION.finditer(text))
    best = []
    for i, m in enumerate(marks):
        if m.group(1) not in "Aa":
            continue
        run = [m]
        want = chr(ord(m.group(1)) + 1)
        for later in marks[i + 1:]:
            if later.group(1) == want:
                run.append(later)
                want = chr(ord(want) + 1)
        if len(run) >= len(best):
            best = run
    if len(best) < 2:
        return text.strip(), []
    stem = text[:best[0].start()].strip()
    options = []
    for k, m in enumerate(best):
        end = best[k + 1].start() if k + 1 < len(best) else len(text)
        options.append(Option(m.group(1), text[m.end():end].strip()))
    return stem, options


def split(text):
    lines = text.splitlines()
    blocks = []          # [number, lines, passage]
    pre = []             # lines before the first question
    directive = None     # [first, last, lines] while its passage is being read
    passages = {}        # question number -> passage
    for i, line in enumerate(lines):
        if not line.strip():
            continue
        d = _directive(line)
        if d:
            directive = [d[0], d[1], []]
            continue
        m = QUESTION.match(line)
        expected = blocks[-1][0] + 1 if blocks else None
        n = _number(m.group(1), expected, lines[i + 1:]) if m else None
        if n is not None:
            if directive and n == directive[0]:
                body = " ".join(directive[2]).strip()
                for k in range(directive[0], directive[1] + 1):
                    passages[k] = body
                directive = None
            blocks.append([n, [m.group(2)]])
            continue
        if directive:
            directive[2].append(line.strip())
        elif blocks:
            blocks[-1][1].append(line.strip())
        else:
            pre.append(line.strip())
    shared = " ".join(pre).strip()
    shared = shared if sum(c.isalpha() for c in shared) >= PASSAGE_MIN_LETTERS else None
    out = []
    for number, body in blocks:
        stem, options = _options(" ".join(body))
        out.append(Question(number, stem, options, passages.get(number, shared)))
    return out
