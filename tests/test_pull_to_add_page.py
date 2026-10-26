"""Pulling the end of a notebook up adds a page (1.1). The pull is measured from the last page itself
and from where the drag began, not from the end of the free margin under the page (a third of the
screen), and a hint under the page says when letting go adds one."""
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def canvas():
    return (APP / "CanvasView.swift").read_text(encoding="utf-8")


def test_the_pull_counts_from_the_page_and_the_drag_start():
    src = canvas()
    assert "private static let pullToAddPage: CGFloat = 0.4" in src
    progress = src[src.index("private func pullProgress()"):src.index("private func updatePullHint()")]
    assert "lastPageBottom()" in progress and "pullStartBottom" in progress
    assert "guard bottom < height else { return nil }" in progress
    begin = src[src.index("func scrollViewWillBeginDragging"):][:200]
    assert "pullStartBottom = lastPageBottom() ?? .infinity" in begin
    end = src[src.index("func scrollViewWillEndDragging"):src.index("private func lastPageBottom()")]
    assert "if let pull = pullProgress(), pull >= 1, velocity.y >= 0 {" in end
    # The old measure from the end of the inset margin is gone.
    assert "scrollView.contentOffset.y - maxY > Self.pullToAddPage" not in src


def test_a_hint_shows_while_pulling_with_a_tick_when_armed():
    src = canvas()
    hint = src[src.index("private func updatePullHint()"):src.index("private func pulledPastEnd()")]
    for key in ("Son sayfa henüz boş", "Bırak, yeni sayfa eklensin", "Yeni sayfa için yukarı çek"):
        assert f'Loc.t("{key}")' in hint
    assert "playHaptic(.selection, at: nil)" in hint
    scrolled = src[src.index("func scrollViewDidScroll"):][:400]
    assert "updatePullHint()" in scrolled
