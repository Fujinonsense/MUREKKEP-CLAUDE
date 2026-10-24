"""Twin of BrainCatalog.swift: which downloadable model an iPad gets, which repository files it
takes, and how a thinking model's reply is read (thinking, answer, chosen option)."""
import re

GIB = 1_073_741_824

# id, physical memory needed (GiB), memory free needed while answering (bytes); strongest first.
MODELS = [
    ("mlx-community/Qwen3.5-9B-4bit", 11.5, 7_200_000_000),
    ("mlx-community/Qwen3.5-4B-4bit", 7.0, 3_900_000_000),
    ("mlx-community/Qwen3.5-2B-4bit", 5.0, 2_400_000_000),
]


def best(physical, available):
    gib = physical / GIB
    for i, (model, need, working_set) in enumerate(MODELS):
        if gib >= need:
            if i == 0 and available is not None and available < working_set:
                continue
            return model
    return None


def wanted(path):
    name = path.lower()
    if "/" in name or name.startswith("."):
        return False
    if name.endswith((".safetensors", ".json", ".jinja")):
        return True
    return name in ("tokenizer.model", "merges.txt")


def split(raw, thinking):
    """(thinking, answer, answering)"""
    close = raw.find("</think>")
    if close >= 0:
        head = raw[:close]
        open_ = head.find("<think>")
        if open_ >= 0:
            head = head[open_ + len("<think>"):]
        return head.strip(), raw[close + len("</think>"):].strip(), True
    open_ = raw.find("<think>")
    if open_ >= 0:
        return raw[open_ + len("<think>"):].strip(), raw[:open_].strip(), False
    if thinking:
        return raw.strip(), "", False
    return "", raw.strip(), True


FINAL = re.compile(
    r"(?:cevap|yan[ıi]t|doğru (?:cevap|şık|seçenek)|answer|correct (?:answer|option))(?:\s+is)?\s*[:：]?\s*\**\s*\(?([A-Ea-e])\)?(?![A-Za-zÇĞİÖŞÜçğıöşü])",
    re.IGNORECASE)
BOLD = re.compile(r"\*\*\s*\(?([A-Ea-e])\)?\s*\*\*")
# "D) 4: Doğru." — an option-by-option verdict, when the answer ran out before its "Cevap:" line.
VERDICT = re.compile(r"^[\s*\-•]*\(?([A-Ea-e])\)[^\n]*?[:：—–\-]\s*\**\s*(?:doğru|correct)\b(?!\s*değil)",
                     re.IGNORECASE | re.MULTILINE)


def choice(answer, letters):
    allowed = {l.upper() for l in letters}
    found = [m.group(1).upper() for m in FINAL.finditer(answer)]
    found = [c for c in found if c in allowed]
    if found:
        return found[-1]
    marked = {m.group(1).upper() for m in VERDICT.finditer(answer)} & allowed
    if len(marked) == 1:
        return marked.pop()
    for m in BOLD.finditer(answer):
        c = m.group(1).upper()
        if c in allowed:
            return c
    return None


def explanation(answer):
    kept = []
    for line in answer.split("\n"):
        m = FINAL.search(line)
        if m and len(line) - (m.end() - m.start()) <= 12:
            continue
        kept.append(line)
    return "\n".join(kept).strip()


OPERATORS = set("+−×÷*/=^√<>≤≥∫∑π%²³")


def is_math(text):
    digits = sum(1 for ch in text if ch.isnumeric())
    operators = sum(1 for ch in text if ch in OPERATORS)
    return operators >= 3 or (digits >= 3 and operators >= 1)


def thinking_budget(text):
    return 1024 if is_math(text) else 512
