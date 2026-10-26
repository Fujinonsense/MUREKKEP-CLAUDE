"""Textbook exercises on a page: each with its instruction, its items, its gaps and the words that may
fill them, so a small model answers one item at a time and never invents an option letter.

The High Note 3 pages (fixtures/highnote3_p<N>.txt, N the 0-based PDF page as in heads_highnote3.json)
are the scanned book read by EasyOCR, a stand-in for Vision, in the app's reading order: grammar
lessons whose text or dialogue only shows the structures, revision and Use of English pages, and
reading lessons where the text is the material. A grammar exercise's prompt holds its instruction,
its items and its notes and never the page's text; a comprehension exercise's prompt holds the text."""
import json
from pathlib import Path

from ports.exercises import (REFERENCE_LABEL, TEXT_RULE, article, choices, exercise_prompt, fill_numbered,
                             instructions, is_reference, render, split, unit_instructions, unit_prompt, units)
from ports.questions import split as split_questions
from ports.reading_order import Piece, lines

FIXTURES = Path(__file__).parent / "fixtures"
FIXTURE = FIXTURES / "ocr_highnote_p12.json"
ARTICLES = ["ø", "a", "an", "the"]
MATH_SIGNS = "=+×÷√≤≥≠^∫∑π²³<>|−±∞"


def page():
    d = json.loads(FIXTURE.read_text(encoding="utf-8"))
    return "\n".join(lines([Piece(l["text"], tuple(l["box"])) for l in d["lines"]]))


def highnote(index):
    return (FIXTURES / f"highnote3_p{index}.txt").read_text(encoding="utf-8")


def by_number(exercises):
    return {e.number: e for e in exercises}


def page_route(text):
    """The route AssistantModel takes for a page it solves: multiple choice and math pages go question
    by question, a page with an exercise to write goes exercise by exercise, the rest as a whole."""
    questions = split_questions(text)
    if sum(1 for q in questions if len(q.options) >= 2) >= 2:
        return "multiple-choice"
    if len(questions) >= 2 and sum(c in MATH_SIGNS for c in text) >= max(4, len(questions)):
        return "math"
    return "textbook" if any(e.kind != "skip" for e in split(text)) else "whole page"


def shape(found):
    return [(e.number, e.kind, len(e.items)) for e in found]


def check_prompts(found, longest=1500):
    """Each exercise's prompt is its own: short, and holding no other exercise's instruction (nothing
    swallowed the rest of the page); a "Text" line only when the exercise has a text."""
    for e in found:
        p = exercise_prompt(e)
        assert len(p) <= longest, (e.number, len(p))
        for other in found:
            if other is not e:
                assert other.instruction[:40] not in p, (e.number, other.number)
        assert ("\nText" in p) == (e.passage is not None), e.number


def grammar_page(index):
    """A page whose exercises never get a text: nothing on it is a passage to read."""
    text = highnote(index)
    assert page_route(text) == "textbook"
    found = split(text)
    assert all(e.passage is None for e in found), [e.number for e in found if e.passage]
    check_prompts(found)
    return found


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
    assert "\n" + REFERENCE_LABEL + ": READERS' LETTERS This week's star letter" in p
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


# High Note 3, grammar lessons: the dialogue or text on the page only shows the structures.

def test_6a_grammar_page_splits_into_its_nine_exercises():
    found = grammar_page(80)
    assert shape(found) == [(1, "short", 3), (2, "gaps", 4), (3, "short", 5), (4, "short", 0), (5, "skip", 0),
                            (6, "gaps", 3), (7, "short", 0), (8, "gaps", 4), (9, "gaps", 2)]
    by = by_number(found)
    # The scan lost the numbers of "4 Study the Grammar box …" and "7 2.30 Listen …": they start exercises all the same.
    assert by[4].instruction.startswith("Study the Grammar box.")
    assert by[7].instruction.startswith("Listen and write down the first conditional sentences.")
    # The grammar box is exercise 4's notes: not a running text to fill, not a passage.
    assert by[4].context.startswith("The first and second conditionals We use the first conditional")
    assert by[5].kind == "skip" and by[5].instruction.startswith("In pairs, say why")
    assert by[6].choices == list("abcdef")
    assert "2. If | (1) ___ (be) an animal," in exercise_prompt(by[8])
    assert "Grammar box" not in exercise_prompt(by[8]) and "conditionals We use" not in exercise_prompt(by[8])


def test_7e_grammar_page_keeps_the_caption_and_the_box_out_of_the_exercises():
    found = grammar_page(101)
    assert shape(found) == [(1, "skip", 2), (2, "skip", 0), (3, "gaps", 2), (4, "short", 4), (5, "skip", 0),
                            (6, "short", 4), (7, "skip", 0), (8, "short", 0)]
    by = by_number(found)
    # An item that starts with a verb ("2 Read the definition below …") stays an item of exercise 1.
    assert by[1].items[1].text.startswith("Read the definition below")
    assert by[2].instruction.startswith("Listen to a phone call.")
    assert by[4].instruction.startswith("Report the questions Michael asked Bella")
    assert [i.number for i in by[4].items] == [1, 2, 3, 5]
    assert by[6].instruction.startswith("Change the reported questions")
    for n in (4, 6):
        assert "So You Think You Can Dance" not in exercise_prompt(by[n])
        assert "WATCH OUT" not in exercise_prompt(by[n])


def test_8f_grammar_page_items_follow_their_own_instruction():
    found = grammar_page(116)
    # A sub-instruction inside exercise 3 ("Choose the correct option:") takes a number of its own, so the
    # exercises after it count one higher than the book; each keeps its own items.
    assert shape(found) == [(1, "short", 3), (2, "short", 0), (3, "short", 2), (4, "short", 0), (5, "gaps", 4),
                            (6, "gaps", 4), (7, "short", 3)]
    by = by_number(found)
    assert by[5].instruction.startswith("Complete the sentences about Kerry and Max")
    assert by[5].items[0].text.startswith("Max doesn't cut his own hair")
    assert by[6].instruction.startswith("Complete the sentences with the correct form of the words in brackets")
    assert "When we pay someone to do ajob" in by[4].context
    assert "When we pay someone" not in exercise_prompt(by[5])


def test_9a_grammar_page_the_grammar_box_is_never_the_story():
    found = grammar_page(126)
    assert shape(found) == [(1, "skip", 0), (2, "short", 0), (3, "skip", 0), (4, "gaps", 3), (5, "short", 0),
                            (6, "gaps", 1), (7, "gaps", 1), (8, "gaps", 4)]
    by = by_number(found)
    # "… sentences a and b from the story …" points at a story, but the box after the items is grammar.
    assert "We use the third conditional" in by[4].context and by[4].passage is None
    assert by[6].instruction.startswith("Use the third conditional to complete the text")
    assert by[6].running and "Tilly Smith" in by[6].items[0].text and "(not be)" in by[6].items[0].text
    assert by[5].choices == list("abcdef")


def test_9d_grammar_page_has_its_eight_exercises():
    found = grammar_page(129)
    assert shape(found) == [(1, "short", 0), (2, "short", 0), (3, "options", 2), (4, "short", 0), (5, "skip", 0),
                            (6, "gaps", 1), (7, "gaps", 5), (8, "short", 4)]
    by = by_number(found)
    assert by[1].instruction == "Match sentences 1-3 with photos A-C."
    assert by[3].items[0].options and by[3].items[0].options[0].text.startswith("a regret in the past")
    assert by[6].running and "(be) athome" in by[6].items[0].text
    assert by[7].instruction.startswith("Write sentences with wish/if only")
    assert by[8].instruction.startswith("In groups, complete the sentences")


def test_7a_grammar_page_exercises_see_the_box_but_no_text():
    found = grammar_page(96)
    assert shape(found) == [(5, "short", 0), (6, "gaps", 6), (7, "short", 0), (8, "short", 5), (9, "skip", 0),
                            (10, "short", 0)]
    by = by_number(found)
    assert by[5].context.startswith("Reported speech Direct speech")
    # "… to complete the news story" names no text printed on the page.
    assert by[7].instruction.startswith("Rewrite the quotes in Exercise 6") and by[7].passage is None
    assert by[6].items[0].text.startswith("'After I had read the headlines")


# High Note 3, revision and Use of English pages.

def test_revision_page_reads_column_by_column_into_five_exercises():
    found = grammar_page(91)
    assert shape(found) == [(1, "gaps", 1), (2, "gaps", 3), (3, "gaps", 5), (4, "gaps", 6), (5, "gaps", 1)]
    by = by_number(found)
    assert by[1].running
    assert by[1].items[0].text.startswith("'Will you \"cover (1) ___ for me this afternoon at the club, Georgie?")
    assert "(12) ___" in by[1].items[0].text and "ask back crazy" not in by[1].items[0].text
    assert by[3].choices == ["ask", "back", "crazy", "fun", "go", "love", "put", "temper", "trouble", "up", "with"]
    assert by[5].running and by[5].items[0].text.startswith("Alex Hi Jack")


def test_use_of_english_key_words_do_not_end_the_items():
    found = grammar_page(92)
    assert shape(found) == [(6, "gaps", 4), (7, "short", 0), (9, "short", 0), (10, "short", 2)]
    by = by_number(found)
    assert [i.number for i in by[6].items] == [1, 2, 3, 5]
    # The key word "FOCUSED" printed between the items belongs to item 1, which lost its number.
    assert by[6].items[0].text.startswith("Jane doesn't focus") and "FOCUSED" in by[6].items[0].text
    assert "EYEBROW" in by[6].items[2].text
    assert by[7].instruction.startswith("You are going to hear a woman talking about her work: Complete the notes below")
    assert by[7].context.startswith("STRATEGY Notes completion")


def test_revision_page_with_a_text_to_complete():
    text = highnote(121)
    assert page_route(text) == "textbook"
    found = split(text)
    check_prompts(found)
    by = by_number(found)
    assert by[1].instruction.startswith("Choose the correct words to complete the sentences")
    assert by[5].instruction.startswith("Rewrite the sentences in the passive")
    assert by[5].items[0].text.startswith("We have ordered the book foryou.")
    # The text with the numbered gaps goes with the exercise that completes it, as its text.
    assert by[6].instruction.startswith("Choose the correct words a-d to complete the text")
    assert by[6].passage.startswith("Black Friday is the eagerly-awaited") and not is_reference(by[6])
    assert "\nText: Black Friday" in exercise_prompt(by[6])
    assert [e.number for e in found if e.passage] == [6]


# High Note 3, reading lessons: the text is the material.

def test_9f_reading_page_comprehension_gets_the_whole_text():
    text = highnote(131)
    assert page_route(text) == "textbook"
    found = split(text)
    assert shape(found) == [(1, "short", 2), (2, "short", 0), (3, "gaps", 4)]
    by = by_number(found)
    assert by[1].passage.startswith("FACT BOX Easdale island")
    # The text is printed after the questions; it is the exercise's text, not its notes, and not cut short.
    assert by[3].passage.startswith("How a music video changed my life by Carrie Kane")
    assert "walked around the island" in by[3].passage and by[3].context == ""
    p = exercise_prompt(by[3])
    assert "\nText: How a music video changed my life" in p and REFERENCE_LABEL not in p
    assert "1. Which of these sentences is true about the music video Carrie saw?" in p
    assert p.endswith(TEXT_RULE)
    check_prompts(found, longest=4000)


def test_gapped_text_reading_page_keeps_the_text_and_the_sentences():
    text = highnote(78)
    assert page_route(text) == "textbook"
    found = split(text)
    assert shape(found) == [(7, "short", 0), (8, "skip", 0), (9, "skip", 0), (10, "short", 0)]
    by = by_number(found)
    assert by[7].instruction.startswith("Read the text: Match sentences A-F with gaps 1-5 in the text")
    assert "THE BEST SUMMER EVER?" in by[7].passage and "A Thurried off too" in by[7].passage
    p = exercise_prompt(by[7])
    assert "\nText: STRATEGY | Gapped text" in p and "the ship started to move" in p
    check_prompts(found, longest=4000)


def test_6b_reading_page_without_its_story_on_the_page():
    text = highnote(81)
    assert page_route(text) == "textbook"
    found = split(text)
    assert shape(found) == [(1, "short", 4), (2, "skip", 0), (3, "short", 0), (4, "short", 2), (5, "gaps", 1),
                            (6, "short", 6), (8, "skip", 0), (9, "skip", 0)]
    by = by_number(found)
    # The story is on the next page: the page header is not a text, the sentence bank after the exercise is.
    assert by[2].passage is None
    assert by[3].passage.startswith("They didn't know the story was covered") and "H 'But nobody" in by[3].passage
    assert by[4].instruction == "In pairs, ask and answer the questions."
    assert by[6].instruction == "Choose the correct verbs." and [i.number for i in by[6].items] == [1, 2, 3, 5, 6, 8]
    check_prompts(found)


def test_a_grammar_text_is_labelled_as_reference_in_both_prompts():
    e = by_number(split(page()))[2]
    assert is_reference(e)
    p = exercise_prompt(e)
    assert "\n" + REFERENCE_LABEL + ": READERS' LETTERS" in p
    assert p.index("Text (reference only") < p.index("\n1. She has won the £100 prize.")
    assert p.endswith(TEXT_RULE)


def test_a_short_passage_is_no_passage():
    text = ("6B READING\n2 Look at the title of the story. Say what you think the person will do.\n"
            "3 Read the story again. Answer the questions.\n1 Who found the bag?\n2 What did they do?")
    found = split(text)
    assert all(e.passage is None for e in found)
    assert "Text" not in exercise_prompt(found[1])


def test_the_instructions_keep_the_model_on_the_exercise():
    s = instructions("Answer in English.")
    for phrase in ("yalnızca numaralı maddelerini cevapla",
                   "seç (choose), tamamla (complete), yeniden yaz (rewrite), eşleştir (match)",
                   "dil bilgisi konusundan çıkma", "\"Text\" ile verilen metin yalnızca kaynaktır", "metni özetleme",
                   "ø boşluğun boş kalacağı", "Answer in English."):
        assert phrase in s
    assert "reference only" in unit_instructions(True) and "never answer about the text" in unit_instructions(True)
    assert "yalnızca verilen maddeyi çöz" in unit_instructions(False, "Answer in English.")
    assert unit_instructions(False, "Answer in English.").endswith("Answer in English.")
