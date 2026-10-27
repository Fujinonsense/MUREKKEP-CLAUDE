"""A notebook always ends in a blank page (2026-10-27). The pull at the end that added pages is gone:
the moment ink or a picture lands on the last page, a blank one joins after it. An opened note gets
it in memory only (opening writes nothing), PDFs never do, and the shared PDF leaves it out."""
from pathlib import Path

from ports.navigation import keep_blank_page_at_end, pages_on_open, shared_page_count

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def body(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]


def test_writing_on_the_last_page_brings_the_next_one():
    assert keep_blank_page_at_end([False]) == [False]
    assert keep_blank_page_at_end([True]) == [True, False]
    assert keep_blank_page_at_end([True, True, True]) == [True, True, True, False]


def test_writing_on_an_earlier_page_adds_nothing():
    assert keep_blank_page_at_end([True, False]) == [True, False]
    assert keep_blank_page_at_end([False, False]) == [False, False]


def test_pages_are_never_taken_away():
    # Writing on the last page, then undoing it, leaves two blank pages: the rule only adds.
    after_write = keep_blank_page_at_end([True, True])
    after_undo = keep_blank_page_at_end([True, False] + after_write[2:])
    assert after_undo == [True, False, False]


def test_pdfs_keep_their_pages():
    assert keep_blank_page_at_end([True, True], is_pdf=True) == [True, True]
    assert pages_on_open([True], is_pdf=True) == [True]


def test_an_opened_notebook_gets_its_blank_page_unless_it_is_read_only():
    assert pages_on_open([True, True]) == [True, True, False]
    assert pages_on_open([True, False]) == [True, False]
    assert pages_on_open([True], read_only=True) == [True]


def test_the_shared_pdf_leaves_the_blank_pages_at_the_end_out():
    assert shared_page_count([True, True, False]) == 2
    assert shared_page_count([True, False, False]) == 1
    assert shared_page_count([False]) == 1
    assert shared_page_count([True, False, True, False]) == 3
    assert shared_page_count([True, False, False], is_pdf=True) == 3


def test_every_edit_keeps_the_blank_page():
    model = src("EditorModel.swift")
    record = body(model, "private func record(_ edit: InkEdit) {", "private func trimUndo()")
    assert record.rstrip().endswith("keepBlankPageAtEnd()\n    }")
    assert record.index("onInkChange?()") < record.index("keepBlankPageAtEnd()")
    keep = body(model, "private func keepBlankPageAtEnd() {", "private func appendBlankPage() {")
    assert "guard !isPDF, let last = pages.indices.last, pageIsUsed(last) else { return }" in keep
    assert "appendBlankPage()" in keep
    # The pen bar's button and the rule share one way of adding a page.
    add = body(model, "func addPage() {", "private func keepBlankPageAtEnd()")
    assert "guard !isPDF, allowsEdit() else { return }" in add and "appendBlankPage()" in add
    append = body(model, "private func appendBlankPage() {", "/// Changes the template of every page")
    for line in ("pages.append(PageInk(strokes: [], version: 1))", "meta.pageCount = sizes.count",
                 "store.update(meta)", "markDirty()", "onLayoutChange?()"):
        assert line in append, line


def test_opening_adds_the_page_in_memory_without_saving():
    model = src("EditorModel.swift")
    opened = model[model.index("// An opened notebook ends in a blank page too"):]
    opened = opened[:opened.index("\n    }\n")]
    assert "if meta.kind == .notebook, !readOnly, let last = pages.last, !(last.strokes.isEmpty && last.stickers.isEmpty) {" in opened
    assert "pages.append(PageInk(strokes: [], version: 1))" in opened
    assert "layout = DocumentLayout(pageSizes: layout.pageSizes + [NoteMeta.a4])" in opened
    for writes in ("markDirty()", "store.update", "store.touch", "saveNow()"):
        assert writes not in opened, writes


def test_the_shared_pdf_stops_at_the_last_written_page():
    export = body(src("EditorModel.swift"), "func exportPDF() throws -> URL {", "let safe = meta.title")
    assert "let count = isPDF ? layout.count : (pages.indices.last(where: pageIsUsed) ?? 0) + 1" in export
    assert "for i in 0..<count {" in export and "for i in 0..<layout.count {" not in export


def test_the_pull_at_the_end_is_gone():
    canvas = src("CanvasView.swift")
    for gone in ("pullToAddPage", "pullHint", "pullArmed", "pullStartBottom", "pullProgress", "updatePullHint",
                 "pulledPastEnd", "lastPageBottom", "model.addPage()"):
        assert gone not in canvas, gone
    end = body(canvas, "func scrollViewWillEndDragging", "func viewForZooming")
    assert "guard singlePage, let page = singlePageTarget(velocity: velocity.y) else { return }" in end
    translations = src("Translations.swift")
    for gone in ("Son sayfa henüz boş", "Bırak, yeni sayfa eklensin", "Yeni sayfa için yukarı çek", "Yeni sayfa eklendi"):
        assert gone not in translations, gone
