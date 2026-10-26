"""Port of ExerciseSplitter (Murekkep.swiftpm/Exercises.swift): the exercises of a textbook page, so a
small model answers one item at a time with the exercise's instruction in front of it.

An exercise starts on a line "N <instruction>" whose N follows the previous exercise's number (the
first may be any number) and whose text is an instruction: a sentence that starts with an instruction
verb ("Complete", "In pairs, match"), a Turkish instruction verb anywhere ("tamamlayınız"), or a
section label ("SPEAKING"). Scans lose or misread the printed exercise numbers, so a line that can only
be an instruction also starts an exercise without a number (a track number "2.30 Listen …", a label
with a verb, a writing verb first, or another verb with a strong cue such as "the Grammar box") or
with a number that does not follow (at most three past the last one); it is numbered after the one
before it. The instruction runs on to the end of its sentence (at most four lines); then come items
"N text" numbered from 1 (or 0 for the example; one lost number is skipped, and a first item that lost
its number is the unnumbered lines before item 2), or, when the instruction says to complete or fill,
a running text whose gaps are numbered inside it. A short heading ("Articles", "WATCH OUT!") ends the
items; what follows is the exercise's context (a grammar box) — unless the next item follows within
three lines, when the heading was a key word printed between the items ("FOCUSED"). Examples before the
items and a grammar box after them are the context, never items.

Gaps are printed blanks ("___", see reading_order.normalize_blanks). In a running text a gap's number
may be glued to the word before it ("is3"), stand alone ("2 ___"), be misread ("1o" for 10) or have
lost its blank ("wearing5 old"); gaps are counted in order, so a lost number costs nothing. The
words that may fill a gap come from the instruction ("with ø (no article), a/an or the", "rules a-g")
or from a box of words. Exercises with no writing to do (speaking, discussion) are skipped.

The page's text before the first exercise is its passage. An exercise gets the passage only when its
instruction points at it ("Read the text", "from the article", "according to the text") and the passage
is a real text (120 letters); when the text is printed after the exercise instead, the exercise's
context is the passage. A grammar or vocabulary exercise that points at the text ("find more examples
of the rules in the text") gets it labelled as reference only, so the model answers the items and not
the text."""
import re
from dataclasses import dataclass, field

from ports.questions import _options
from ports.reading_order import normalize_blanks

HEADER = re.compile(r"^\s*(\d{1,2})[.)]?\s+(\S.*)$")
TRACK = re.compile(r"^(?:\S{1,3}\)\s*)?[A-Z]?\d{1,3}\.\d{1,2}\s+")
LABEL = re.compile(r"^(?:[A-ZÇĞİÖŞÜ]{4,}\s+)+(?=\S)")
LEAD = re.compile(r"^(?:(?:in pairs|in groups|then|now|first|finally|individually)\s*,?\s*)+", re.IGNORECASE)
WRITE_VERBS = {"complete", "fill", "choose", "circle", "underline", "match", "rewrite", "write", "put", "correct",
               "order", "tick", "find", "answer", "translate", "decide", "label", "add", "replace", "change",
               "join", "combine", "cross", "number", "sort", "make", "use", "mark", "identify", "unscramble",
               "rearrange", "transform", "select", "give", "report"}
OTHER_VERBS = {"read", "listen", "discuss", "study", "look", "work", "talk", "ask", "say", "check", "think",
               "imagine", "compare", "describe", "practise", "practice", "repeat", "watch", "note", "guess",
               "tell", "share", "play", "act", "prepare", "take", "plan", "present", "review", "follow"}
# An instruction with one of these verbs and one of these nouns ("Complete the text with …") has a
# running text under it, with the gaps numbered inside it.
GAP_VERBS = {"complete", "fill", "put", "use", "write", "add", "insert"}
RUNNING_CUE = re.compile(r"\b(?:texts?|stor(?:y|ies)|dialogues?|conversations?|emails?|letters?|articles?|gaps|"
                         r"extracts?|paragraphs?|notes|news items?|metni|metin|boşluk|diyalog|paragraf)\b", re.IGNORECASE)
TURKISH_VERB = re.compile(
    r"(?<![\wçğıöşü])(?:tamamla|doldur|eşleştir|işaretle|cevapla|yanıtla|düzelt|sırala|çevir|belirle|birleştir)"
    r"(?:y?[ıiuü]n(?:[ıiuü]z)?)?(?![\wçğıöşü])"
    r"|(?<![\wçğıöşü])(?:yaz|seç|bul|çiz)[ıiuü]n(?:[ıiuü]z)?(?![\wçğıöşü])", re.IGNORECASE)
TURKISH_GAP = re.compile(r"(?<![\wçğıöşü])(?:tamamla|doldur|yaz)", re.IGNORECASE)
TURKISH_SKIP = re.compile(r"(?<![\wçğıöşü])(?:tartış|konuş|dinle)", re.IGNORECASE)
STRONG = re.compile(r"\b(?:the|these|each) (?:gaps?|sentences?|texts?|questions?|words?|blanks?|dialogues?|tables?|box|boxes|"
                    r"emails?|paragraphs?|conversations?|stor(?:y|ies)|articles?|quotes?|examples?|verbs?|photos?|pictures?|"
                    r"notes|tasks?|instructions?|correct|odd|first|second|underlined|highlighted|missing)\b"
                    r"|\b(?:grammar|fact|writing|vocabulary) box\b|\bin (?:brackets|bold|pairs|groups)\b|\bexercise \d",
                    re.IGNORECASE)
GRAMMAR_BOX = re.compile(r"\bwe (?:use|form|can use|sometimes use|often use|don't use|do not use)\b|\bgrammar reference\b|"
                         r"\bwatch out\b", re.IGNORECASE)
FOOTER = re.compile(r"^(?:use of english|grammar reference)\b.*\bpage \d", re.IGNORECASE)
PASSAGE_CUE = re.compile(r"\b(?:the|this) (?:text|passage|letter|email|story|article|blog|review|extract|report|interview|"
                         r"poster|leaflet|advert(?:isement)?|news item|fact box)s?\b"
                         r"|\baccording to\b|\btrue or false\b|\bnot given\b|\b(?:metin|metne|metni|parça)", re.IGNORECASE)
REFERENCE_CUE = re.compile(r"\b(?:grammar|rules?|examples?|underlined|highlighted|in bold|form of|tenses?|structures?|"
                           r"verbs?|nouns?|adjectives?|phrases?|words? (?:and phrases )?(?:from|in) the|"
                           r"find (?:the |more )?(?:words|phrases|expressions|examples))\b", re.IGNORECASE)
NO_ARTICLE = re.compile(r"(?:^|(?<=\s))[-–o0Øø]\s*\((?:no article|ø|o|0)\)", re.IGNORECASE)
ARTICLE_O = re.compile(r"\bno article \([o0Ø]\)", re.IGNORECASE)
LETTER_RANGE = re.compile(r"(?:with|to|rules?|options?|endings?|letters?|from)\s+([a-h])\s*[-–]\s*([a-h])\b")
LIST_TAIL = re.compile(r"\b(?:with|using)\s+(.+?)(?:[.:;!?](?:\s|$)|$)", re.IGNORECASE)
GLUED = re.compile(r"(.*?[^\d\s])(\d{1,2})")
BOX_CUE = re.compile(r"\b(?:box|below|list|kutu)", re.IGNORECASE)
SUPERSCRIPT_MISREAD = "éèêº°¹²³⁴⁵⁶⁷⁸⁹⁰"
GIVEN_O = {"o", "0", "-", "–"}
MAX_INSTRUCTION_LINES = 4
MAX_LOST_GAPS = 3
MAX_LOST_ITEMS = 1      # item numbers the scan may have lost between two items
MAX_JUMP = 3            # a misread exercise number is at most this far past the previous one
FOLD_LINES = 3          # a heading at most this many lines before the next item is a key word
CONTEXT_CHARS = 1500
PASSAGE_CHARS = 3000
UNIT_PASSAGE_CHARS = 1500
PASSAGE_MIN_LETTERS = 120

AN_WORDS = ("hour", "honest", "honour", "honor", "heir")
A_PREFIXES = ("unic", "unif", "unio", "uniq", "unit", "univ", "use", "usu", "usa", "uti", "ure", "eu", "one", "ewe",
              "ufo", "uk")
AN_LETTERS = set("AEFHILMNORSX")

REFERENCE_LABEL = ("Text (reference only: it just shows the words and structures; answer only the numbered items "
                   "of the exercise)")
TEXT_RULE = "Answer only this exercise's items as the instruction says; do not write anything else about the text."


@dataclass
class Gap:
    number: int
    given: str | None = None


@dataclass
class Item:
    number: int
    text: str
    gaps: list = field(default_factory=list)
    options: list = field(default_factory=list)

    @property
    def example(self):
        return self.number == 0


@dataclass
class Exercise:
    number: int
    instruction: str
    kind: str                 # "gaps", "options", "short" or "skip"
    choices: list
    items: list
    running: bool = False     # one item: a text whose gaps are numbered in it
    context: str = ""         # what follows the items (a grammar box)
    passage: str | None = None


@dataclass
class Unit:
    """One call to the model: an item, or a sentence of a running text."""
    number: int               # the item's number, 0 for a running text
    text: str                 # gaps to fill marked "(n) ___"
    gaps: list                # the gaps to fill, in order
    before: str = ""          # the sentence before it


def _words(s):
    return re.findall(r"[A-Za-z']+", s.lower())


def _letters(s):
    return sum(c.isalpha() for c in s)


def _sentences(s):
    return [t for t in re.split(r"(?<=[.!?])\s+", s.strip()) if t]


def _clean_header(rest):
    rest = re.sub(r"^___\s+", "", rest)
    rest = TRACK.sub("", rest)
    rest = LABEL.sub("", rest)
    return rest.strip()


def _is_instruction(rest):
    if _very_strong(rest) or TURKISH_VERB.search(rest):
        return True
    for sentence in _sentences(_clean_header(TRACK.sub("", rest))):
        words = _words(LEAD.sub("", sentence))
        if words and words[0] in WRITE_VERBS | OTHER_VERBS:
            return True
    return False


def _lead_verb(s):
    """The instruction verb the first sentence of s starts with (after "In pairs," and the like), or None."""
    sentences = _sentences(s)
    words = _words(LEAD.sub("", sentences[0])) if sentences else []
    return words[0] if words and words[0] in WRITE_VERBS | OTHER_VERBS else None


def _very_strong(rest):
    """A track number or a section label: the mark of an exercise even when its verb is on the next line."""
    rest = re.sub(r"^___\s+", "", rest)
    return bool(TRACK.match(rest) or LABEL.match(TRACK.sub("", rest)))


def _strong(rest):
    rest = re.sub(r"^___\s+", "", rest)
    return bool(TRACK.match(rest) or LABEL.match(TRACK.sub("", rest)) or STRONG.search(rest)
                or TURKISH_VERB.search(rest))


def _unnumbered_start(line):
    """A line without a number that can only be an exercise's instruction."""
    if FOOTER.match(line):
        return False
    head = re.sub(r"^___\s+", "", line)
    if TRACK.match(head):
        return True
    verb = _lead_verb(_clean_header(line))
    if verb is None:
        return False
    return bool(LABEL.match(head)) or verb in WRITE_VERBS or bool(STRONG.search(line))


def _ends_sentence(s):
    return bool(re.search(r"[.!?:]['\"’”)]?$", s.strip()))


def _heading(line):
    s = line.strip()
    if not s or s[0].isdigit() or not s[0].isupper() or re.search(r"[.,;:?]$", s):
        return False
    return len(s.split()) <= 4


def _box_words(line, boxed=False):
    """The words of a box line: parts set off by separators or wide spaces, or, when the instruction
    names a box, plain lowercase words."""
    parts = [p.strip() for p in re.split(r"\s*[/•|,]\s*|\s{2,}", line.strip()) if p.strip()]
    if 3 <= len(parts) <= 15 and all(len(p.split()) <= 2 and not p[0].isdigit() for p in parts):
        return parts
    toks = [t for t in line.split() if t != "___"]
    if boxed and 3 <= len(toks) <= 15 and all(re.fullmatch(r"[a-zçğıöşü'/-]+", t) for t in toks):
        return toks
    return None


def _no_article(s):
    s = NO_ARTICLE.sub("ø (no article)", s)
    return ARTICLE_O.sub("no article (ø)", s)


def _running_text(instruction):
    """The exercise is a text to complete, not sentences: its body is one item with numbered gaps."""
    gaps = bool(set(_words(instruction)) & GAP_VERBS) or bool(TURKISH_GAP.search(instruction))
    return gaps and bool(RUNNING_CUE.search(instruction))


def choices(instruction):
    """The words that may fill a gap, from the instruction; [] when it does not list them."""
    s = _no_article(instruction)
    m = LETTER_RANGE.search(s)
    if m and m.group(1) <= m.group(2):
        return [chr(c) for c in range(ord(m.group(1)), ord(m.group(2)) + 1)]
    if re.search(r"\btrue or false\b", s, re.IGNORECASE):
        return ["True", "False"]
    m = LIST_TAIL.search(s)
    if not m:
        return []
    tail = re.sub(r"\([^)]*\)", "", m.group(1))
    tokens = [t.strip(" '\"") for t in re.split(r",\s*|\s+or\s+|\s+and\s+|/", tail)]
    tokens = [t for t in tokens if t]
    if not 2 <= len(tokens) <= 8 or any(len(t.split()) > 2 for t in tokens):
        return []
    out = []
    for t in tokens:
        t = "ø" if t in ("ø", "Ø", "-", "–") else t
        if t not in out:
            out.append(t)
    return out


def _given(token, options):
    if token in ("ø", "Ø"):
        return "ø"
    if token in GIVEN_O and "ø" in options:
        return "ø"
    if token in options:
        return token
    return None


def _gap_number(token, k, slack):
    """(base, n) when the token is a gap number n from k to k + slack, alone ("2", "1o") or glued to
    the word before it ("is3", base "is"); else None."""
    if re.fullmatch(r"[0-9oOlI]{1,2}", token) and re.search(r"\d", token):
        n = int(token.translate(str.maketrans("oOlI", "0011")))
        return ("", n) if k <= n <= k + slack else None
    m = GLUED.fullmatch(token)
    if m and k <= int(m.group(2)) <= k + slack and re.search(r"[A-Za-z]", m.group(1)):
        return m.group(1), int(m.group(2))
    return None


def _strip_misread(token):
    while len(token) > 1 and token[-1] in SUPERSCRIPT_MISREAD:
        token = token[:-1]
    return token


def _number_gaps(text, options):
    """A running text with its gaps written "(n) ___" (or "(n) ø" for a printed example)."""
    toks = text.split()
    out, gaps, k, i = [], [], 1, 0
    while i < len(toks):
        t = toks[i]
        nxt = toks[i + 1] if i + 1 < len(toks) else None
        # A number just before a blank may skip a gap the scan lost; the count follows the book.
        hit = _gap_number(t, k, MAX_LOST_GAPS if nxt == "___" else 0)
        if hit:
            base, k = hit
            if base:
                out.append(base)
            if nxt == "___":
                out.append(f"({k}) ___")
                gaps.append(Gap(k))
                k, i = k + 1, i + 2
                continue
            given = _given(nxt, options) if nxt is not None and not base else None
            if given:
                out.append(f"({k}) {given}")
                gaps.append(Gap(k, given))
                k, i = k + 1, i + 2
                continue
            if base:
                out.append(f"({k}) ___")
                gaps.append(Gap(k))
                k, i = k + 1, i + 1
                continue
            out.append(t)
            i += 1
            continue
        if t == "___":
            out.append(f"({k}) ___")
            gaps.append(Gap(k))
            k, i = k + 1, i + 1
            continue
        out.append(_strip_misread(t) if nxt == "___" else t)
        i += 1
    return " ".join(out), gaps


def _item_gaps(text, options):
    toks = text.split()
    gaps, out = [], []
    for i, t in enumerate(toks):
        nxt = toks[i + 1] if i + 1 < len(toks) else None
        if t == "___":
            gaps.append(Gap(len(gaps) + 1))
        elif t in ("ø", "Ø") or (t in GIVEN_O and "ø" in options and t not in ("-", "–")):
            gaps.append(Gap(len(gaps) + 1, "ø"))
            t = "ø"
        elif nxt == "___":
            t = _strip_misread(t)
        out.append(t)
    return " ".join(out), gaps


def _draft(number, rest):
    cur = {"number": number, "instruction": [_clean_header(rest)], "mode": "instruction",
           "items": [], "body": [], "preface": [], "box": None, "context": [], "fold": 0}
    if _ends_sentence(cur["instruction"][0]):
        cur["mode"] = "body"
    return cur


def _item_number_fits(cur, n, rest):
    """n continues the items: the next number (one may be lost), or 0/1 to start them, or 2/3 when the
    first item lost its number and stands unnumbered in the body (not in a running text, whose gap
    numbers start lines too: "2 ___ boys")."""
    if cur["items"]:
        want = cur["items"][-1][0] + 1
        return want <= n <= want + MAX_LOST_ITEMS
    if n in (0, 1):
        return True
    return n in (2, 3) and bool(cur["body"]) and not rest.startswith("___") \
        and not _running_text(" ".join(cur["instruction"]))


def _can_fold(cur):
    return cur["mode"] == "context" and 0 < cur["fold"] <= FOLD_LINES


def split(text):
    lines = [normalize_blanks(l) for l in text.splitlines()]
    lines = [l for l in lines if l]
    pre, found = [], []
    cur = None
    prev = ""
    for line in lines:
        # An instruction without its number follows a finished line, never a line cut mid-sentence.
        after_sentence = _ends_sentence(prev) or prev.endswith("___")
        prev = line
        m = HEADER.match(line)
        if m:
            n, rest = int(m.group(1)), m.group(2)
            if _is_instruction(rest):
                expected = cur["number"] + 1 if cur else None
                # The next item's number too: only a strong instruction starts an exercise then.
                ambiguous = cur is not None and _item_number_fits(cur, n, rest) and (cur["mode"] == "body" or _can_fold(cur))
                strong = _strong(rest)
                if expected is None or n == expected:
                    if not ambiguous or strong:
                        cur = _draft(n, rest)
                        found.append(cur)
                        continue
                elif (_very_strong(rest) or (strong and not ambiguous)) and n <= cur["number"] + MAX_JUMP:
                    # The scan misread the number: the exercise follows the one before it.
                    cur = _draft(n if n > cur["number"] else cur["number"] + 1, rest)
                    found.append(cur)
                    continue
        elif cur is not None and cur["mode"] != "instruction" and (cur["items"] or cur["body"] or cur["context"]) \
                and after_sentence and _unnumbered_start(line):
            # The scan lost the number: the exercise follows the one before it.
            cur = _draft(cur["number"] + 1, line)
            found.append(cur)
            continue
        if cur is None:
            pre.append(line)
            continue
        if cur["mode"] == "instruction":
            if m and int(m.group(1)) in (0, 1):
                cur["mode"] = "body"
            elif len(cur["instruction"]) < MAX_INSTRUCTION_LINES and not _ends_sentence(" ".join(cur["instruction"])):
                cur["instruction"].append(line)
                if _ends_sentence(line):
                    cur["mode"] = "body"
                continue
            else:
                cur["mode"] = "body"
        if m and _item_number_fits(cur, int(m.group(1)), m.group(2)) and (cur["mode"] == "body" or _can_fold(cur)):
            n = int(m.group(1))
            if cur["mode"] == "context":
                # The heading was a key word between the items: it belongs to the item before.
                folded = cur["context"][-cur["fold"]:]
                del cur["context"][-cur["fold"]:]
                if cur["items"]:
                    cur["items"][-1][1].extend(folded)
                else:
                    cur["body"].extend(folded)
                cur["mode"], cur["fold"] = "body", 0
            if not cur["items"] and cur["body"]:
                if n >= 2:
                    cur["items"].append((1, cur["body"]))
                else:
                    cur["preface"] = cur["body"]
                cur["body"] = []
            cur["items"].append((n, [m.group(2)]))
            continue
        if cur["mode"] == "body":
            if _heading(line):
                cur["mode"], cur["fold"] = "context", 1
                cur["context"].append(line)
                continue
            if not cur["items"] and not cur["body"] and cur["box"] is None:
                box = _box_words(line, BOX_CUE.search(" ".join(cur["instruction"])) is not None)
                if box:
                    cur["box"] = box
                    continue
            if cur["items"]:
                cur["items"][-1][1].append(line)
            else:
                cur["body"].append(line)
            continue
        cur["context"].append(line)
        cur["fold"] += 1
    passage = " ".join(pre).strip() or None
    return [_finish(c, passage) for c in found]


def _finish(c, passage):
    instruction = _no_article(" ".join(c["instruction"]).strip())
    options = choices(instruction)
    if not options and c["box"] and BOX_CUE.search(instruction):
        options = c["box"]
    items, running = [], False
    if c["items"]:
        for n, body in c["items"]:
            raw = _no_article(" ".join(body).strip())
            stem, opts = _options(raw)
            if len(opts) >= 2:
                items.append(Item(n, stem, [], opts))
                continue
            text, gaps = _item_gaps(raw, options)
            items.append(Item(n, text, gaps))
    elif c["body"] and _running_text(instruction):
        text, gaps = _number_gaps(_no_article(" ".join(c["body"])), options)
        if gaps:
            items, running = [Item(0, text, gaps)], True
    words = set(_words(instruction))
    has_gaps = any(i.gaps for i in items)
    if any(i.options for i in items):
        kind = "options"
    elif has_gaps:
        kind = "gaps"
    elif not (words & WRITE_VERBS) and not TURKISH_VERB.search(instruction) and not options:
        kind = "skip"
    elif TURKISH_SKIP.search(instruction) and not TURKISH_VERB.search(instruction):
        kind = "skip"
    else:
        kind = "short"
    # Examples before the items and a grammar box after them; an unnumbered body that is no running
    # text (a grammar box, a word list) is context too.
    before = c["preface"] + ([] if running else c["body"])
    context = _no_article(" ".join(before + c["context"]).strip())
    text = None
    if PASSAGE_CUE.search(instruction):
        if passage and _letters(passage) >= PASSAGE_MIN_LETTERS:
            text = passage
        elif _letters(context) >= PASSAGE_MIN_LETTERS and not GRAMMAR_BOX.search(context):
            # The text is printed after the exercise (a grammar box is not it).
            text, context = context, ""
    return Exercise(c["number"], instruction, kind, options, items, running, context, text)


def units(e):
    """The calls a model answers for an exercise, in order."""
    if e.kind == "skip":
        return []
    if e.running:
        out, before = [], ""
        for sentence in _sentences(e.items[0].text):
            numbers = [int(n) for n in re.findall(r"\((\d+)\) ___", sentence)]
            gaps = [g for g in e.items[0].gaps if g.number in numbers and g.given is None]
            if gaps:
                out.append(Unit(0, sentence, gaps, before))
            before = sentence
        return out
    out = []
    for item in e.items:
        if item.example:
            continue
        if e.kind == "gaps" and item.gaps:
            out.append(Unit(item.number, _numbered(item.text), [g for g in item.gaps if g.given is None]))
        else:
            out.append(Unit(item.number, item.text, []))
    return out


def article(fill, next_word):
    """"a" or "an" as the next word sounds; any other fill unchanged."""
    if fill not in ("a", "an") or not next_word:
        return fill
    w = re.sub(r"^[^\w]+|[^\w-]+$", "", next_word)
    if not w:
        return fill
    if w[0].isdigit():
        return "an" if re.match(r"(8|11|18|8\d)(?!\d)", w) else "a"
    if len(w) <= 5 and w.isupper() and len(w) > 1:
        return "an" if w[0] in AN_LETTERS else "a"
    low = w.lower()
    if low.startswith(AN_WORDS):
        return "an"
    if low.startswith(A_PREFIXES):
        return "a"
    return "an" if low[0] in "aeiou" else "a"


def fill_text(text, fills, options, bold=True):
    """The text with its blanks ("(n) ___", "___") filled in order and a printed "ø" kept, a/an as the
    next word sounds; bold for showing, plain for the next prompt."""
    toks = text.split()
    queue = list(fills)
    out = []
    i = 0
    while i < len(toks):
        t = toks[i]
        numbered = bool(re.fullmatch(r"\(\d+\)", t)) and i + 1 < len(toks)
        j = i + 1 if numbered else i
        if toks[j] not in ("___", "ø"):
            out.append(t)
            i += 1
            continue
        fill = "ø" if toks[j] == "ø" else (queue.pop(0) if queue else None)
        after = toks[j + 1] if j + 1 < len(toks) else ""
        if fill and "a" in options and "an" in options:
            fill = article(fill, after)
        shown = (f"**{fill}**" if bold else fill) if fill else ("**?**" if bold else "___")
        out.append(f"{t} {shown}" if numbered else shown)
        i = j + 1
    return " ".join(out)


def fill_numbered(text, known):
    """A running sentence with the gaps already answered written in ("(7) the")."""
    return re.sub(r"\((\d+)\) ___", lambda m: f"({m.group(1)}) {known[int(m.group(1))]}"
                  if int(m.group(1)) in known else m.group(0), text)


def _numbered(item_text):
    k = iter(range(1, 1000))
    return re.sub(r"(?<!\S)(___|ø)(?!\S)", lambda m: f"({next(k)}) {m.group(1)}", item_text)


def is_reference(e):
    """The passage only shows the words or structures of a grammar or vocabulary exercise."""
    return bool(REFERENCE_CUE.search(e.instruction))


def _text_line(e, limit):
    return (REFERENCE_LABEL if is_reference(e) else "Text") + ": " + e.passage[:limit]


def unit_prompt(e, u, before):
    """What a small model reads for one unit: the instruction, what it needs to know, the unit."""
    lines = [f"Exercise: {e.instruction}"]
    if e.context:
        lines.append("Notes: " + e.context[:CONTEXT_CHARS])
    if not u.gaps:
        if e.passage:
            lines.append(_text_line(e, UNIT_PASSAGE_CHARS))
        lines.append(f"Item {u.number}: {u.text}")
        lines.append("Answer with exactly one of: " + ", ".join(e.choices) + "." if e.choices
                     else f"Answer item {u.number} only, briefly.")
        return "\n".join(lines)
    if before:
        lines.append("Previous sentence: " + before)
    lines.append("Sentence: " + u.text)
    names = ", ".join(f"({g.number})" for g in u.gaps)
    tail = f"Fill the gaps {names} in this order." if len(u.gaps) > 1 else f"Fill the gap {names}."
    if e.choices:
        tail += " Each fill is exactly one of: " + ", ".join(e.choices) + "."
    if "ø" in e.choices:
        tail += " ø means the gap stays empty."
    lines.append(tail)
    return "\n".join(lines)


def exercise_prompt(e):
    """The whole exercise for a model strong enough to answer it at once. Notes are cut short unless they
    are all the exercise has; a text comes labelled, and a rule under the items keeps the answer to them."""
    lines = [f"Exercise {e.number}: {e.instruction}"]
    if e.choices:
        lines.append("Words to use: " + ", ".join(e.choices) + (" (ø means the gap stays empty)" if "ø" in e.choices else ""))
    if e.context:
        lines.append("Notes: " + e.context[:CONTEXT_CHARS if e.items else PASSAGE_CHARS])
    if e.passage:
        lines.append(_text_line(e, PASSAGE_CHARS))
    if e.running:
        lines.append(e.items[0].text)
    for item in e.items if not e.running else []:
        text = _numbered(item.text) if item.gaps else item.text
        line = f"{item.number}. {text}" + (" (example)" if item.example else "")
        for o in item.options:
            line += f"\n{o.letter}) {o.text}"
        lines.append(line)
    if e.passage:
        lines.append(TEXT_RULE)
    return "\n".join(lines)


def instructions(directive=""):
    """For models that answer a whole exercise at once (the downloaded model, the local server): only this
    exercise's items, the instruction's own task, the text as reference. `directive` names the answer's
    language."""
    return ("Sen dikkatli bir öğretmensin. Ders kitabından tek bir alıştırma çözüyorsun: yalnızca bu alıştırmanın "
            "yönergesini uygula ve yalnızca numaralı maddelerini cevapla; başka soru uydurma. Yönergenin görevine bağlı "
            "kal: seç (choose), tamamla (complete), yeniden yaz (rewrite), eşleştir (match), hataları düzelt (correct) "
            "neyse onu yap ve alıştırmanın dil bilgisi konusundan çıkma. \"Text\" ile verilen metin yalnızca kaynaktır: "
            "madde metinle ilgili bir soruysa cevabı metinden bul, dil bilgisi ya da kelime alıştırmasında metin yalnızca "
            "kelime ve yapıları gösterir; metni özetleme, metin hakkında kendi sorularını yazıp cevaplama. "
            "Boşluklu her maddeyi numarasıyla, boşlukları doldurulmuş tam cümle olarak yaz ve doldurduğun kelimeleri "
            "kalın yaz (örneğin **the**). Kullanılacak kelimeler verilmişse yalnızca onları kullan; ø boşluğun boş "
            "kalacağı anlamına gelir. Diğer maddelerde kısa cevabı kalın yaz ve bir cümleyle gerekçesini ekle. Şık harfi "
            "yalnızca maddenin şıkları varsa yaz. " + directive)


def unit_instructions(gaps, directive=""):
    """For the on-device model, which answers one unit: the gaps of a sentence, or a short answer."""
    if gaps:
        return ("You solve one item of a textbook exercise. Read the instruction and the sentence, decide what belongs "
                "in each numbered gap, then fill every gap in order. Use only the allowed words when they are given. "
                "A text, when given, is reference only: it shows the words and structures; never answer about the "
                "text. Never answer with an option letter.")
    return ("Sen dikkatli bir öğretmensin. Alıştırmanın yönergesini ve varsa notları oku, yalnızca verilen maddeyi çöz. "
            "\"Text\" ile verilen metin yalnızca kaynaktır; onu özetleme, onun hakkında soru uydurma. Şık harfi yalnızca "
            "izin verilen cevaplar harfse yaz. " + directive)


def render(e, fills, notes=None):
    """Markdown: the exercise number and instruction, then each item with its answers."""
    head = f"**{e.number}** {e.instruction}"
    if e.kind == "skip":
        return head + "\n_Konuşma/dinleme alıştırması, atlandı._\n\n"
    out = [head]
    notes = notes or {}
    if e.running:
        out.append(fill_text(e.items[0].text, fills.get(0, []), e.choices))
    else:
        for item in e.items:
            if item.example:
                continue
            got = fills.get(item.number, [])
            if e.kind == "gaps" and item.gaps:
                out.append(f"{item.number}. " + fill_text(item.text, got, e.choices))
            else:
                answer = got[0] if got else "?"
                letter = answer.strip(" *().:").lower()
                chosen = [o for o in item.options if o.letter.lower() == letter]
                if chosen:
                    answer = f"{chosen[0].letter}) {chosen[0].text}"
                out.append(f"{item.number}. {item.text} — **{answer}**")
            if notes.get(item.number):
                out.append(f"_{notes[item.number]}_")
    return "\n".join(out) + "\n\n"
