"""A video overview built like NotebookLM's: greeting and topic, a hook question, the roadmap,
numbered section cards each followed by its scenes, a recap and a closing question."""
from ports.outline import Scene, Section, assemble, plain


def sections(n, scenes_each=1):
    return [Section(f"Konu {i + 1}", f"Alt başlık {i + 1}",
                    [Scene("bullets", f"Sahne {i + 1}.{k + 1}", narration="…") for k in range(scenes_each)])
            for i in range(n)]


def test_shape_title_hook_agenda_sections_recap_closing():
    out = assemble("Türev", "Şampiyonun **anlık hızını** nasıl buluruz?", "Bir koşucuyu düşünün.", sections(3),
                   "Anlık değişimi **etrafında** nerede görüyorsun?", english=False)
    assert [s.layout for s in out] == ["title", "question", "agenda", "section", "bullets", "section", "bullets",
                                       "section", "bullets", "summary", "question"]
    assert out[0].title == "Türev" and "Türev" in out[0].narration
    assert out[1].title == "Şampiyonun **anlık hızını** nasıl buluruz?"
    assert out[1].narration == "Bir koşucuyu düşünün."
    assert out[2].bullets == ["Konu 1", "Konu 2", "Konu 3"]
    assert out[2].narration == "İşte yol haritamız. Birincisi, Konu 1. İkincisi, Konu 2. Ve son olarak, Konu 3."
    assert out[-1].narration.startswith("Anlık değişimi etrafında nerede görüyorsun?")
    assert "**" not in out[-1].narration


def test_section_cards_numbered_in_order():
    out = assemble("T", "H?", "n", sections(5), "C?", english=False)
    cards = [s for s in out if s.layout == "section"]
    assert [c.number for c in cards] == [1, 2, 3, 4, 5]
    words = ["birinci", "ikinci", "üçüncü", "dördüncü", "beşinci"]
    for card, word in zip(cards, words):
        assert f"{word} bölümümüz" in card.narration.lower().replace("i̇", "i")
    assert cards[0].narration == "Birinci bölümümüz: Konu 1."
    assert cards[-1].narration == "Ve son olarak beşinci bölümümüz: Konu 5."
    assert cards[1].subtitle == "Alt başlık 2"


def test_agenda_caps_at_six():
    many = sections(9)
    many[3].scenes *= 3  # a big section stays on its own
    out = assemble("T", "H?", "n", many, "C?", english=False)
    cards = [s for s in out if s.layout == "section"]
    assert len(cards) == 6 and [c.number for c in cards] == [1, 2, 3, 4, 5, 6]
    agenda = next(s for s in out if s.layout == "agenda")
    assert len(agenda.bullets) == 6
    assert sum(1 for s in out if s.layout == "bullets") == 9 + 2  # every content scene kept
    assert "Konu 4" in agenda.bullets


def test_english_ordinals():
    out = assemble("Functions", "Is every **relationship** reliable?", "Think about it.", sections(5), "Can **rules** predict?",
                   english=True)
    cards = [s for s in out if s.layout == "section"]
    assert [c.narration for c in cards] == ["Section one: Konu 1.", "Section two: Konu 2.", "Section three: Konu 3.",
                                            "Section four: Konu 4.", "And finally, section five: Konu 5."]
    agenda = next(s for s in out if s.layout == "agenda")
    assert agenda.narration.startswith("Here's our roadmap. First, Konu 1. Second, Konu 2.")
    assert out[0].narration.startswith("Hi everyone.")


def test_plain_drops_markers():
    assert plain("Şampiyonun **anlık hızını** nasıl buluruz?") == "Şampiyonun anlık hızını nasıl buluruz?"
