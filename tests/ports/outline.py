"""Port of VideoOutline (Murekkep.swiftpm/VideoOutline.swift): the order of a video overview's scenes,
as in NotebookLM's explainers — greeting and topic, a hook question (key words in **…**), the roadmap,
a numbered card per section followed by its scenes, a recap, and a closing question. At most six
sections: the neighbours with the fewest scenes are merged until six are left."""
import re
from dataclasses import dataclass, field

MAX_SECTIONS = 6
CARD_TR = ["Birinci", "İkinci", "Üçüncü", "Dördüncü", "Beşinci", "Altıncı"]
CARD_TR_LOWER = ["birinci", "ikinci", "üçüncü", "dördüncü", "beşinci", "altıncı"]
LIST_TR = ["Birincisi", "İkincisi", "Üçüncüsü", "Dördüncüsü", "Beşincisi", "Altıncısı"]
CARD_EN = ["one", "two", "three", "four", "five", "six"]
LIST_EN = ["First", "Second", "Third", "Fourth", "Fifth", "Sixth"]


@dataclass
class Scene:
    layout: str
    title: str
    subtitle: str | None = None
    bullets: list = field(default_factory=list)
    narration: str = ""
    number: int | None = None


@dataclass
class Section:
    title: str
    subtitle: str
    scenes: list


def plain(s):
    return re.sub(r"\*\*", "", s)


def merge(sections):
    sections = list(sections)
    while len(sections) > MAX_SECTIONS:
        i = min(range(len(sections) - 1), key=lambda k: len(sections[k].scenes) + len(sections[k + 1].scenes))
        a, b = sections[i], sections[i + 1]
        sections[i:i + 2] = [Section(a.title, a.subtitle or b.title, a.scenes + b.scenes)]
    return sections


def assemble(title, hook, hook_narration, sections, closing, english):
    parts = merge(sections)
    titles = [s.title for s in parts]
    n = len(parts)
    out = [Scene("title", title, "Video overview" if english else "Video özeti",
                 narration=(f"Hi everyone. In this video we're going to explore {title} together. Let's get started."
                            if english else
                            f"Herkese merhaba. Bu videoda {title} konusunu birlikte keşfedeceğiz. Hazırsanız başlayalım.")),
           Scene("question", hook, narration=hook_narration)]
    if n:
        if english:
            items = [f"{LIST_EN[i]}, {t}." for i, t in enumerate(titles[:-1])] + [("And finally, " if n > 1 else "") + f"{titles[-1]}."]
            road = "Here's our roadmap. " + " ".join(items)
        else:
            items = [f"{LIST_TR[i]}, {t}." for i, t in enumerate(titles[:-1])] + [("Ve son olarak, " if n > 1 else "") + f"{titles[-1]}."]
            road = "İşte yol haritamız. " + " ".join(items)
        out.append(Scene("agenda", "Our roadmap" if english else "Yol haritamız", bullets=titles, narration=road))
    for i, s in enumerate(parts):
        last = i == n - 1 and n > 1
        if english:
            card = (f"And finally, section {CARD_EN[i]}: {s.title}." if last else f"Section {CARD_EN[i]}: {s.title}.")
        else:
            card = (f"Ve son olarak {CARD_TR_LOWER[i]} bölümümüz: {s.title}." if last else f"{CARD_TR[i]} bölümümüz: {s.title}.")
        out.append(Scene("section", s.title, s.subtitle, narration=card, number=i + 1))
        out.extend(s.scenes)
    if n:
        joined = (", ".join(titles[:-1]) + (" and " if english else " ve ") + titles[-1]) if n > 1 else titles[0]
        out.append(Scene("summary", "To sum up" if english else "Özetle", bullets=titles,
                         narration=(f"To sum up, we covered {joined}." if english else f"Özetlersek, {joined} konularını gördük.")))
    out.append(Scene("question", closing, narration=plain(closing) + (" See you in the next one." if english else
                                                                      " Bir sonraki videoda görüşmek üzere.")))
    return out
