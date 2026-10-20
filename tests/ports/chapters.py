"""Port of ChapterFinder (Murekkep.swiftpm/Chapters.swift): the chapters of a long book.

Input: the PDF outline and the first lines of every page ("heads"; a contents page keeps all its
lines). The outline's top level wins when it has at least two chapters. Otherwise every rule below
proposes chapter openers, each rule keeps the first page per number and only increasing numbers, and
the rule with the most chapters wins (ties: section outline, then words, then padded numbers):
  - section outline: a page listing two or more "N.k Title" lines of one N, including N.1;
  - words: "Unit 3 …", "Chapter 2: …", "BÖLÜM 4", "3. ÜNİTE …" (one family per word kind);
  - padded numbers: a first line "03 Active and healthy".
Contents pages (and pages listing sections of several chapters) never open a chapter.

The contents give titles ("12 Introduction to Calculus 1175"), the sections with their pages (the
printed page plus the chapter's offset between printed and PDF pages) and where back matter starts.
Without contents, sections come from the pages' first lines ("1.2 …", "1B …", "TEXT 2 …"). The last
chapter ends before back matter (answer key, index, appendix, grammar reference …). Fewer than two
chapters → none."""
import re
from dataclasses import dataclass, field

HEAD_LINES = 8
CONTENTS = re.compile(r"^(contents|table of contents|içindekiler)\b", re.IGNORECASE)
NUMBERED_LINE = re.compile(r"\s\d{1,4}$")
SECTION = re.compile(r"^(\d{1,2})\.(\d{1,2})\s+([^\d\s].*?)(?:\s+\d{1,4})?$")
WORDS = {
    "chapter": ["chapter", "bölüm"],
    "unit": ["unit", "ünite"],
    "module": ["module", "modül"],
    "part": ["part", "kısım"],
    "lesson": ["lesson", "ders"],
}
ALL_WORDS = "|".join(w for ws in WORDS.values() for w in ws)
WORD_FIRST = re.compile(r"^(?P<kw>" + ALL_WORDS + r")\s*[:.]?\s*(?P<num>\d{1,2}|[IVX]{1,4})\b\s*[:.\-–]?\s*(?P<title>.*)$",
                        re.IGNORECASE)
NUMBER_FIRST = re.compile(r"^(?P<num>\d{1,2})\s*\.\s*(?P<kw>" + ALL_WORDS + r")\b\s*[:.\-–]?\s*(?P<title>.*)$",
                          re.IGNORECASE)
PADDED = re.compile(r"^(0[1-9]|[1-9]\d)\s+([^\W\d_].{2,})$")
CONTENTS_CHAPTER = re.compile(r"^(?:(?:" + ALL_WORDS + r")\s+)?(\d{1,2})\s+([^\d\s].*?)\s+(\d{1,4})$", re.IGNORECASE)
CONTENTS_SECTION = re.compile(r"^(\d{1,2})\.(\d{1,2})\s+([^\d\s].*?)\s+(\d{1,4})$")
CONTENTS_BACK = re.compile(r"^(?:[A-H]\s+\S.*|(?:appendix|answer key|answers|index|glossary|references|bibliography|"
                           r"ekler|cevap anahtarı|dizin|kaynakça|sözlük)\b.*?)\s+(\d{1,4})$", re.IGNORECASE)
LESSON = re.compile(r"^(\d{1,2})([A-H])\s+([^\W\d_].*)$")
TEXT_SECTION = re.compile(r"^(text|reading|section|metin|okuma)\s*(\d{1,2})\b\s*[:.\-–]?\s*(.*)$", re.IGNORECASE)
BACK_MATTER = re.compile(r"^(answer key|answers|index|glossary|appendix|references|bibliography|credits|"
                         r"acknowledg|grammar reference|irregular verbs|cevap anahtarı|cevaplar|dizin|kaynakça|"
                         r"sözlük|ekler)", re.IGNORECASE)
NOT_A_SECTION = re.compile(r"^(section exercises|exercises|review|chapter review|key terms|key concepts)\b", re.IGNORECASE)
BYLINE = re.compile(r"\s+by\s+[A-Z][\w.'-]*(\s+[A-Z][\w.'-]*)*\s*$")
ROMAN = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7, "VIII": 8, "IX": 9, "X": 10}
SMALL = {"and", "or", "of", "the", "a", "an", "to", "in", "for", "on", "at", "by", "ve", "ile", "ya", "da", "de"}
TURKISH = set("ÇĞİÖŞÜçğıöşü")


@dataclass
class PageHead:
    page: int
    lines: list


@dataclass
class BookSection:
    number: str
    title: str
    page: int


@dataclass
class BookChapter:
    number: int
    title: str
    start: int
    end: int
    sections: list = field(default_factory=list)


def _fold(s):
    """For matching only: dotted capital İ folds to i (case-insensitive matching misses it)."""
    return s.replace("İ", "i")


def _title_case(words, turkish):
    out = []
    for k, w in enumerate(words):
        low = (w.replace("I", "ı").replace("İ", "i") if turkish else w).lower()
        if k > 0 and low in SMALL:
            out.append(low)
        else:
            first = "İ" if (turkish and low[0] == "i") else low[0].upper()
            out.append(first + low[1:])
    return out


def _is_caps(word):
    letters = [c for c in word if c.isalpha()]
    return bool(letters) and not any(c.islower() for c in letters)


def tidy(title):
    """A title as people write it: no bullets, bars or bylines; ALL-CAPS words in Title Case
    (Turkish-aware); a leading ALL-CAPS label before ordinary text becomes "Label – text"."""
    t = title.replace("•", " ").replace("|", " ")
    t = BYLINE.sub("", re.sub(r"\s+", " ", t)).strip(" :.-–")
    words = t.split()
    if not words:
        return ""
    turkish = any(c in TURKISH for c in t)
    if all(_is_caps(w) or not any(c.isalpha() for c in w) for w in words):
        return " ".join(_title_case(words, turkish)) if sum(c.isalpha() for c in t) >= 4 else t
    # A label is made of capital words of two letters or more ("WRITING A formal letter").
    caps = 0
    while caps < len(words) and _is_caps(words[caps]) and sum(c.isalpha() for c in words[caps]) >= 2:
        caps += 1
    letters = sum(c.isalpha() for c in " ".join(words[:caps]))
    if caps >= 1 and letters >= 4:
        return " ".join(_title_case(words[:caps], turkish)) + " – " + " ".join(words[caps:])
    return t


def _number(token):
    return int(token) if token.isdigit() else ROMAN.get(token.upper())


def _contents_pages(heads):
    out, previous = [], False
    for h in heads:
        numbered = sum(bool(NUMBERED_LINE.search(ln)) for ln in h.lines)
        is_contents = bool(h.lines) and (CONTENTS.match(h.lines[0]) is not None
                                         or (previous and numbered >= max(3, len(h.lines) // 2)))
        if is_contents:
            out.append(h.page)
        previous = is_contents
    return out


def _contents_entries(heads, pages):
    """("chapter", n, title, printed) / ("section", "n.k", title, printed) / ("back", None, title, printed)."""
    entries = []
    for p in pages:
        for line in heads[p].lines:
            m = CONTENTS_SECTION.match(line)
            if m:
                entries.append(("section", f"{m.group(1)}.{m.group(2)}", m.group(3), int(m.group(4))))
                continue
            m = CONTENTS_CHAPTER.match(line)
            if m:
                entries.append(("chapter", int(m.group(1)), m.group(2), int(m.group(3))))
                continue
            m = CONTENTS_BACK.match(line)
            if m:
                entries.append(("back", None, line, int(m.group(1))))
    return entries


def _keep_increasing(candidates):
    """First page per number, numbers increasing along the book."""
    out, last = [], 0
    for page, n, title in sorted(candidates, key=lambda c: c[0]):
        if n is not None and n > last:
            out.append((page, n, title))
            last = n
    return out


def _outline_rule(heads, skip):
    found = []
    for h in heads:
        if h.page in skip:
            continue
        majors = [(int(m.group(1)), int(m.group(2))) for m in (SECTION.match(ln) for ln in h.lines[:HEAD_LINES]) if m]
        if len(majors) >= 2 and len({a for a, _ in majors}) == 1 and (majors[0][0], 1) in majors:
            found.append((h.page, majors[0][0], ""))
    return _keep_increasing(found)


def _word_rule(heads, skip, words):
    found = []
    for h in heads:
        if h.page in skip:
            continue
        lines = h.lines[:3]
        for k, line in enumerate(lines):
            m = WORD_FIRST.match(_fold(line)) or NUMBER_FIRST.match(_fold(line))
            if not m or m.group("kw").lower() not in words:
                continue
            title = line[m.start("title"):].strip() if m.group("title") else ""
            if not re.search(r"[^\W\d_]{3,}", title) and k + 1 < len(lines):
                title = lines[k + 1]
            found.append((h.page, _number(m.group("num")), title))
            break
    return _keep_increasing(found)


def _padded_rule(heads, skip):
    found = []
    for h in heads:
        if h.page in skip or not h.lines:
            continue
        m = PADDED.match(h.lines[0])
        if m:
            found.append((h.page, int(m.group(1)), m.group(2)))
    return _keep_increasing(found)


def _natural(number):
    return [int(x) if x.isdigit() else x for x in re.findall(r"\d+|\D+", number)]


def _sections_from_pages(heads, chapter):
    seen = {}
    for h in heads[chapter.start:chapter.end + 1]:
        for line in h.lines[:HEAD_LINES]:
            m = SECTION.match(line)
            if m and int(m.group(1)) == chapter.number:
                key, title = f"{m.group(1)}.{m.group(2)}", m.group(3)
            else:
                m = LESSON.match(line)
                if m and int(m.group(1)) == chapter.number:
                    key, title = m.group(1) + m.group(2), m.group(3)
                else:
                    m = TEXT_SECTION.match(_fold(line))
                    if not m:
                        continue
                    key, title = f"{m.group(1).capitalize()} {int(m.group(2))}", line[m.start(3):]
            if NOT_A_SECTION.match(tidy(title)):
                continue
            if key not in seen:
                seen[key] = BookSection(key, tidy(title), h.page)
    # In the order of their numbers ("1.2" before "1.10", "Text 2" before "Text 3").
    return sorted(seen.values(), key=lambda s: _natural(s.number))


def find(outline, heads, page_count):
    # 1. The PDF outline.
    top = sorted([(p, t) for t, level, p in outline if level == 0 and 0 <= p < page_count])
    if len(top) >= 2:
        chapters, back = [], page_count
        for p, t in top:
            if BACK_MATTER.match(t.strip()):
                if chapters:
                    back = min(back, p)
                continue
            if re.match(r"^(cover|title|copyright|contents|preface|foreword|kapak|önsöz|içindekiler)\b", t.strip(), re.I):
                continue
            chapters.append(BookChapter(len(chapters) + 1, tidy(t), p, p))
        chapters = [c for c in chapters if c.start < back]
        if len(chapters) >= 2:
            for k, c in enumerate(chapters):
                c.end = (chapters[k + 1].start if k + 1 < len(chapters) else back) - 1
            return chapters

    # 2. Openers found in the pages.
    contents = _contents_pages(heads)
    skip = set(contents)
    for h in heads:
        majors = {int(m.group(1)) for m in (SECTION.match(ln) for ln in h.lines[:HEAD_LINES]) if m}
        if len(majors) >= 2:
            skip.add(h.page)
    rules = [_outline_rule(heads, skip)]
    rules += [_word_rule(heads, skip, ws) for ws in WORDS.values()]
    rules.append(_padded_rule(heads, skip))
    best = max(rules, key=len)  # max keeps the first of equals: the priority order above
    if len(best) < 2:
        return []

    entries = _contents_entries(heads, contents)
    listed = {}
    for kind, key, title, printed in entries:
        if kind == "chapter" and key not in listed:
            listed[key] = (title, printed)

    chapters = []
    for page, n, title in best:
        name = title if re.search(r"[^\W\d_]{3,}", title or "") else listed.get(n, ("", 0))[0]
        chapters.append(BookChapter(n, tidy(name), page, page))
    offsets = {c.number: c.start - listed[c.number][1] for c in chapters if c.number in listed}

    # Back matter: from the contents (first entry after the last chapter's) or from the pages.
    back = page_count
    last = chapters[-1]
    after_last = False
    for kind, key, title, printed in entries:
        if kind == "chapter" and key == last.number:
            after_last = True
        elif after_last and kind == "back" and last.number in offsets:
            back = min(back, printed + offsets[last.number])
            break
    for h in heads[last.start + 1:back]:
        if any(BACK_MATTER.match(_fold(ln)) for ln in h.lines[:2]):
            back = h.page
            break

    for k, c in enumerate(chapters):
        c.end = (chapters[k + 1].start if k + 1 < len(chapters) else back) - 1
        listed_sections = [(key, title, printed) for kind, key, title, printed in entries
                           if kind == "section" and int(key.split(".")[0]) == c.number]
        if listed_sections and c.number in offsets:
            seen = {}
            for key, title, printed in listed_sections:
                if key not in seen:
                    page = min(max(printed + offsets[c.number], c.start), c.end)
                    seen[key] = BookSection(key, tidy(title), page)
            c.sections = sorted(seen.values(), key=lambda s: _natural(s.number))
        else:
            c.sections = _sections_from_pages(heads, c)
        if not c.title and c.sections:
            c.title = c.sections[0].title
    return chapters
