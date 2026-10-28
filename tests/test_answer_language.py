from ports.answer_language import for_answer, is_page_command

ENGLISH_PAGE = "Read the text and answer the questions. 1. What is the main idea of the passage?"
TURKISH_PAGE = "Metni okuyun ve soruları cevaplayın. 1. Parçanın ana fikri aşağıdakilerden hangisidir?"


def test_turkish_request_about_an_english_question_is_answered_in_english():
    assert for_answer("Bu soruyu çöz", False, ENGLISH_PAGE) == "en"
    assert for_answer("3. soruyu cevapla", False, ENGLISH_PAGE) == "en"


def test_english_request_about_a_turkish_question_is_answered_in_turkish():
    assert for_answer("solve question 2", False, TURKISH_PAGE) == "tr"


def test_a_question_in_the_users_own_words_keeps_its_language():
    assert for_answer("What is the main idea of photosynthesis?", False, TURKISH_PAGE) == "en"
    assert for_answer("Fotosentezin ana fikri nedir, kısaca anlatır mısın?", False, ENGLISH_PAGE) == "tr"


def test_ready_made_actions_follow_the_page():
    assert for_answer("Özetle", True, ENGLISH_PAGE) == "en"


def test_page_without_text_falls_back_to_the_request():
    assert for_answer("bu soruyu çöz", False, "") == "tr"


def test_a_page_of_calculations_is_answered_in_the_language_of_the_request():
    # The ad recording of 28 Oct: "Check my solution" on a page of algebra under "Homework" came
    # back in Turkish; and a Turkish label ("Ödev") alone must not decide either.
    english_action = "Check my handwritten solution on the page. If there's a mistake, say which step it's in."
    turkish_action = "Sayfadaki el yazısı çözümümü kontrol et. Hata varsa hangi adımda olduğunu söyle."
    assert for_answer(english_action, True, "Homework\n5x - 3 = 2x + 9\n3x = 12\nx = 5") == "en"
    assert for_answer(english_action, True, "Ödev\n3 + 3 = 33\n2x + 3 = 11") == "en"
    assert for_answer(turkish_action, True, "Homework\n5x - 3 = 2x + 9") == "tr"
    # A page with prose still decides.
    assert for_answer(english_action, True, TURKISH_PAGE) == "tr"


def test_the_swift_twin_has_the_same_rule():
    from pathlib import Path
    swift = (Path(__file__).resolve().parent.parent / "Murekkep.swiftpm" / "AIEngine.swift").read_text(encoding="utf-8")
    assert "guard proseWords(page) >= 3 else { return detect(question) }" in swift
    assert "text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 3 }.count" in swift


def test_long_requests_are_not_page_commands():
    assert not is_page_command("Bu metinde yazarın asıl anlatmak istediği nedir kısaca açıklar mısın lütfen bana")
    assert is_page_command("Bu soruyu çöz")
    assert not is_page_command("What is photosynthesis?")
