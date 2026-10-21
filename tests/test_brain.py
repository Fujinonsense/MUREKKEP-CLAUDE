"""The downloadable model (BrainCatalog.swift through tests/ports/brain.py): the iPad's memory picks the
model, only the files MLX needs come down, and a thinking reply is read for its answer and choice."""
import re
from pathlib import Path

from ports import brain

GIB = brain.GIB
APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def test_memory_picks_the_model():
    assert brain.best(16 * GIB, 9_000_000_000) == "mlx-community/Qwen3.5-9B-4bit"
    # 16 GB but little free right now: the 4B, which surely fits.
    assert brain.best(16 * GIB, 5_000_000_000) == "mlx-community/Qwen3.5-4B-4bit"
    # Unknown free memory does not hold the 9B back.
    assert brain.best(12 * GIB, None) == "mlx-community/Qwen3.5-9B-4bit"
    # An 8 GB iPad reports a little under 8 GiB.
    assert brain.best(int(7.6 * GIB), 4_500_000_000) == "mlx-community/Qwen3.5-4B-4bit"
    assert brain.best(6 * GIB, None) == "mlx-community/Qwen3.5-2B-4bit"
    assert brain.best(4 * GIB, None) is None


def test_only_model_files_come_down():
    take = ["config.json", "model.safetensors", "model.safetensors.index.json", "tokenizer.json",
            "tokenizer_config.json", "chat_template.jinja", "vocab.json", "generation_config.json"]
    skip = ["README.md", ".gitattributes", "images/demo.png", "onnx/model.json"]
    assert all(brain.wanted(f) for f in take)
    assert not any(brain.wanted(f) for f in skip)


def test_thinking_and_answer_are_split():
    raw = "Önce şıkları tartalım. 12+3=15.\n</think>\n\nB şıkkı doğrudur.\nCevap: B"
    thinking, answer, answering = brain.split(raw, thinking=True)
    assert thinking == "Önce şıkları tartalım. 12+3=15." and answer.endswith("Cevap: B") and answering
    # Still thinking: nothing is an answer yet.
    assert brain.split("Önce şıklar", thinking=True) == ("Önce şıklar", "", False)
    # An explicit open tag counts the same.
    assert brain.split("<think>düşünce</think>Cevap: A", thinking=True) == ("düşünce", "Cevap: A", True)
    # Thinking off: all of it is the answer.
    assert brain.split("Kısa cevap.", thinking=False) == ("", "Kısa cevap.", True)


def test_the_choice_is_read():
    letters = list("ABCDE")
    assert brain.choice("Gerekçe...\nCevap: C", letters) == "C"
    assert brain.choice("**Cevap: B**", letters) == "B"
    assert brain.choice("Doğru cevap **D) 12** çünkü toplam 12 eder.", letters) == "D"
    assert brain.choice("Answer: (a)", letters) == "A"
    assert brain.choice("The correct answer is E.", letters) == "E"
    assert brain.choice("Doğru şık C'dir.", letters) == "C"
    assert brain.choice("YANIT: D", letters) == "D"
    # The last statement wins over a choice ruled out on the way.
    assert brain.choice("Cevap A olamaz, çünkü fiil yok.\nCevap: D", letters) == "D"
    # Turkish words starting with a letter are not choices.
    assert brain.choice("Cevap açık değil; cevap edilebilir bir soru.", letters) is None
    # Only the question's own letters.
    assert brain.choice("Cevap: E", list("ABCD")) is None
    # No statement: the first bold letter.
    assert brain.choice("Bence **B** çünkü...", letters) == "B"


def test_the_choice_is_read_from_an_option_by_option_verdict():
    # Qwen3.5 4B went through every option and ran out of answer tokens before "Cevap: D".
    letters = list("ABCDE")
    cut = "**Şıkların Değerlendirilmesi:**\nA) 8: Yanlış.\nB) 0: Yanlış.\nC) Tanımsızdır: Yanlış, limit var.\nD) 4: Doğru.\nE) 2: Yanlış."
    assert brain.choice(cut, letters) == "D"
    assert brain.choice("A) went: incorrect\nB) has gone — Correct, present perfect.\nC) go: wrong", letters) == "B"
    assert brain.choice("* **C)** 3/4: **Doğru**", letters) == "C"
    # Two options called right, or "doğru değil": no choice from the verdicts.
    assert brain.choice("A) 1: Doğru\nB) 2: Doğru", letters) is None
    assert brain.choice("C) x − 2: Doğru değil.", letters) is None
    # A stated answer still wins.
    assert brain.choice("A) 8: Doğru gibi görünüyor ama değil.\nCevap: D", letters) == "D"


def test_explanation_drops_the_choice_line():
    text = "Metinde yazar umudu anlatıyor.\nBu yüzden B.\nCevap: B"
    assert brain.explanation(text) == "Metinde yazar umudu anlatıyor.\nBu yüzden B."
    kept = "**Cevap: B**, çünkü metnin tamamı umudu anlatıyor."
    assert brain.explanation(kept) == kept


def test_arithmetic_gets_more_thinking():
    assert brain.thinking_budget("3x + 5 = 20 ise x kaçtır?") == 2048
    assert brain.thinking_budget("√16 + 2² − 3 = ?") == 2048
    assert brain.thinking_budget("Parçada asıl anlatılmak istenen nedir?") == 768
    assert brain.thinking_budget("1923 yılında ne oldu?") == 768


def test_swift_matches_the_twin():
    swift = (APP / "BrainCatalog.swift").read_text(encoding="utf-8")
    for model, need, working_set in brain.MODELS:
        line = next(l for l in swift.splitlines() if f'id: "{model}"' in l)
        rest = swift[swift.index(line):]
        assert f"minimumMemoryGiB: {need}" in rest.split("\n")[1]
        assert f"workingSet: {working_set:_}" in rest.split("\n")[1]
    pattern = brain.FINAL.pattern
    swift_pattern = re.search(r'pattern: "(\(\?:cevap[^"]+)"', swift).group(1).replace("\\\\", "\\")
    assert swift_pattern == pattern
    assert "2_048 : 768" in swift
