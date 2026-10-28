"""Port of how the assistant picks the language of its answer (AnswerLanguage in AIEngine.swift).
`detect` stands in for NLLanguageRecognizer: "tr", "en", or None when the text does not tell."""
import re

TURKISH_LETTERS = re.compile("[çğıöşüÇĞİÖŞÜ]")


def detect(text, context="", fallback=None, app="tr"):
    t = text.strip()
    if TURKISH_LETTERS.search(t):
        return "tr"
    sample = t if len(t) >= 14 else (t + " " + context[:800])
    if len(sample.strip()) < 3:
        return fallback or app
    if TURKISH_LETTERS.search(sample):
        return "tr"
    return "en" if re.search(r"\b(the|is|what|which|of|and)\b", sample.lower()) else (fallback or app)


CUES = ("soru", "çöz", "cevap", "yanıt", "şık", "sayfa", "alıştırma",
        "solve", "question", "answer", "exercise", "page")


def is_page_command(text):
    words = re.findall(r"\w+", text.lower())
    return 0 < len(words) <= 8 and any(w.startswith(c) for w in words for c in CUES)


def prose_words(text):
    """AnswerLanguage.proseWords: words of three letters or more."""
    return len([w for w in re.findall(r"[^\W\d_]+", text) if len(w) >= 3])


def for_answer(question, is_action, page):
    if is_action or is_page_command(question):
        # A page of calculations and labels has too few words to tell: the request decides.
        if prose_words(page) < 3:
            return detect(question)
        return detect(page, fallback=detect(question))
    return detect(question, context=page)
