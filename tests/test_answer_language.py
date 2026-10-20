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


def test_long_requests_are_not_page_commands():
    assert not is_page_command("Bu metinde yazarın asıl anlatmak istediği nedir kısaca açıklar mısın lütfen bana")
    assert is_page_command("Bu soruyu çöz")
    assert not is_page_command("What is photosynthesis?")
