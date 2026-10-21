"""Textbook exercises on a page: each with its instruction, its items, its gaps and the words that may
fill them, so a small model answers one item at a time and never invents an option letter."""
import json
from pathlib import Path

from ports.exercises import article, choices, exercise_prompt, fill_numbered, render, split, unit_prompt, units
from ports.reading_order import Piece, lines

FIXTURE = Path(__file__).parent / "fixtures" / "ocr_highnote_p12.json"
ARTICLES = ["ø", "a", "an", "the"]


def page():
    d = json.loads(FIXTURE.read_text(encoding="utf-8"))
    return "\n".join(lines([Piece(l["text"], tuple(l["box"])) for l in d["lines"]]))


def by_number(exercises):
    return {e.number: e for e in exercises}


def test_the_grammar_page_has_six_exercises():
    ex = split(page())
    assert [e.number for e in ex] == [1, 2, 3, 4, 5, 6]
    assert [e.kind for e in ex] == ["skip", "short", "gaps", "gaps", "short", "skip"]


def test_running_text_has_fourteen_numbered_gaps():
    e = by_number(split(page()))[3]
    assert e.instruction == "Complete the gaps with ø (no article), a/an or the. Then listen and check."
    assert e.choices == ARTICLES
    assert e.running
    gaps = [g for item in e.items for g in item.gaps]
    assert [g.number for g in gaps] == list(range(1, 15))
    assert gaps[0].given == "ø" and all(g.given is None for g in gaps[1:])
    text = e.items[0].text
    assert text.startswith("They say that (1) ø girls care more about clothes than (2) ___ boys")
    assert "Today I'm wearing (5) ___ old pair of jeans and (6) ___ cotton top. (7) ___ jeans were (8) ___ present" in text
    assert text.endswith("to be (13) ___ fashion designer in (14) ___ future.")


def test_sentence_items_keep_their_gaps():
    e = by_number(split(page()))[4]
    assert e.instruction == "In pairs, complete the sentences with ø (no article), a/an or the."
    assert e.choices == ARTICLES
    assert not e.running
    assert [i.number for i in e.items] == [1, 2, 3, 4]
    assert [len(i.gaps) for i in e.items] == [2, 2, 2, 4]
    assert e.items[0].text == "I think ___ sport is more fun than ___ fashion."
    assert e.items[2].text == "I saw ___ pair of shoes in the shop last Monday that I loved, but when I went back on Tuesday ___ shoes were gone."


def test_matching_items_answer_with_the_rule_letters_and_see_the_rules():
    e = by_number(split(page()))[2]
    assert e.choices == list("abcdefg")
    assert [i.number for i in e.items] == list(range(1, 9))
    assert e.items[7].text == "I'm wearing a leather jacket. The jacket looks great."
    assert "a We use no article (ø) with plurals" in e.context
    assert "g We use a/an when we mention" in e.context


def test_speaking_and_discussion_are_skipped_but_underlining_is_not():
    ex = by_number(split(page()))
    assert ex[1].kind == "skip" and ex[6].kind == "skip"
    assert ex[5].kind == "short" and [i.number for i in ex[5].items] == [1, 2, 3]
    assert "WATCH OUT" in ex[5].context


def test_gap_numbers_read_in_many_ways():
    text = ("1 Complete the text with ø (no article), a, an or the.\n"
            "My friend has 1 o dog and 2 ___ cat. 3___ dog is called Rex and\n"
            "he eats4\n"
            "food every day. It is lo ___ end.")
    e = split(text)[0]
    gaps = [g for item in e.items for g in item.gaps]
    assert [g.number for g in gaps] == [1, 2, 3, 4, 5]
    assert gaps[0].given == "ø"
    assert e.choices == ARTICLES
    assert e.items[0].text == "My friend has (1) ø dog and (2) ___ cat. (3) ___ dog is called Rex and he eats (4) ___ food every day. It is lo (5) ___ end."


def test_a_missed_gap_does_not_shift_the_numbers_after_it():
    text = ("1 Complete the text with a, an or the.\n"
            "There is ___ cat in ___ garden and 4 ___ dog in 5 ___ house.")
    e = split(text)[0]
    assert [g.number for g in e.items[0].gaps] == [1, 2, 4, 5]
    assert e.items[0].text == "There is (1) ___ cat in (2) ___ garden and (4) ___ dog in (5) ___ house."


def test_choices_come_from_the_instruction():
    assert choices("Complete the sentences with in, on or at.") == ["in", "on", "at"]
    assert choices("Complete the gaps with ø (no article), a/an or the.") == ARTICLES
    assert choices("Fill in the blanks with - (no article), a, an or the.") == ARTICLES
    assert choices("Match the words in sentences 1-8 with rules a–g.") == list("abcdefg")
    assert choices("Choose the correct option.") == []
    assert choices("Complete the sentences with the correct form of the verbs.") == []


def test_a_or_an_follows_the_next_word():
    assert article("a", "apple") == "an"
    assert article("an", "car") == "a"
    assert article("a", "hour") == "an"
    assert article("an", "university") == "a"
    assert article("an", "European") == "a"
    assert article("a", "MBA") == "an"
    assert article("an", "UK") == "a"
    assert article("a", "8-year-old") == "an"
    assert article("the", "apple") == "the"


def test_running_text_is_solved_sentence_by_sentence():
    e = by_number(split(page()))[3]
    us = units(e)
    assert [[g.number for g in u.gaps] for u in us] == [[2, 3, 4], [5, 6], [7, 8, 9, 10], [11], [12, 13, 14]]
    assert us[2].text.startswith("(7) ___ jeans were (8) ___ present")
    assert us[2].before.startswith("Today I'm wearing (5) ___ old pair")


def test_items_are_solved_one_by_one():
    e = by_number(split(page()))[4]
    assert [[g.number for g in u.gaps] for u in units(e)] == [[1, 2], [1, 2], [1, 2], [1, 2, 3, 4]]


def test_answers_are_shown_inside_the_sentences():
    e = by_number(split(page()))[4]
    fills = {1: ["ø", "ø"], 2: ["the", "ø"], 3: ["a", "the"], 4: ["the", "the", "the", "the"]}
    out = render(e, {i.number: fills[i.number] for i in e.items})
    assert out.startswith("**4** In pairs, complete the sentences with ø (no article), a/an or the.\n")
    assert "1. I think **ø** sport is more fun than **ø** fashion." in out
    assert "3. I saw **a** pair of shoes" in out


def test_running_answers_keep_the_gap_numbers():
    e = by_number(split(page()))[3]
    out = render(e, {0: ["the"] * 13})
    assert "They say that (1) **ø** girls care more about clothes than (2) **the** boys" in out


def test_question_pages_have_no_exercises():
    yks = ("1. Aşağıdaki cümlelerin hangisinde yazım yanlışı vardır?\nA) Herkes bu konuda hem fikirdi.\n"
           "B) Toplantı saat üçte başladı.\nC) Bu kitabı da okudum.\nD) Yarın sınav var mı?\nE) Sen de gel.\n"
           "2. Bir sayının 3 katının 5 fazlası 20'dir. Bu sayı kaçtır?\nA) 3 B) 4 C) 5 D) 6 E) 7")
    assert split(yks) == []


def test_turkish_instructions_are_exercises():
    text = ("1 Boşlukları uygun kelimelerle tamamlayınız.\n"
            "1 Ali okula ___ gitti.\n"
            "2 Ayşe kitabı ___ okudu.\n")
    e = split(text)[0]
    assert e.kind == "gaps" and [len(i.gaps) for i in e.items] == [1, 1]


def test_a_or_an_before_words_that_start_with_un():
    assert article("an", "unique") == "a"
    assert article("a", "unimportant") == "an"
    assert article("an", "usual") == "a"
    assert article("a", "umbrella") == "an"


def test_known_fills_are_written_into_a_running_sentence():
    assert fill_numbered("(7) ___ jeans were (8) ___ present.", {7: "the", 8: "a"}) == "(7) the jeans were (8) a present."
    assert fill_numbered("in (14) ___ future.", {}) == "in (14) ___ future."


def test_a_unit_prompt_names_the_gaps_and_the_words():
    e = by_number(split(page()))[3]
    u = units(e)[1]
    p = unit_prompt(e, u, "They say that (1) ø girls care more about clothes than (2) ø boys.")
    assert p == ("Exercise: Complete the gaps with ø (no article), a/an or the. Then listen and check.\n"
                 "Previous sentence: They say that (1) ø girls care more about clothes than (2) ø boys.\n"
                 "Sentence: Today I'm wearing (5) ___ old pair of jeans and (6) ___ cotton top.\n"
                 "Fill the gaps (5), (6) in this order. Each fill is exactly one of: ø, a, an, the. "
                 "ø means the gap stays empty.")


def test_a_short_answer_prompt_carries_the_rules():
    e = by_number(split(page()))[2]
    p = unit_prompt(e, units(e)[0], "")
    assert p.startswith("Exercise: Study the Grammar box and match")
    assert "\nNotes: Articles a We use no article (ø)" in p
    assert "\nText: READERS' LETTERS This week's star letter" in p
    assert p.endswith("\nItem 1: She has won the £100 prize.\nAnswer with exactly one of: a, b, c, d, e, f, g.")


def test_the_whole_exercise_for_a_strong_model():
    e = by_number(split(page()))[4]
    p = exercise_prompt(e)
    assert p.startswith("Exercise 4: In pairs, complete the sentences with ø (no article), a/an or the.\n"
                        "Words to use: ø, a, an, the (ø means the gap stays empty)\n"
                        "1. I think (1) ___ sport is more fun than (2) ___ fashion.\n")


def test_a_chosen_option_is_shown_with_its_text():
    e = split("5 Choose the correct answer.\n1 She ___ to school every day.\na) go b) goes c) going")[0]
    assert e.kind == "options"
    assert render(e, {1: ["B"]}) == "**5** Choose the correct answer.\n1. She ___ to school every day. — **b) goes**\n\n"
