"""A note or an index this build cannot read is never written over (1.1).

An ink file that did not decode opened as an empty page, and the next stroke saved that empty page
over it; one index entry that did not decode emptied the whole library, and the next save wrote
the empty list. Now a damaged ink file is copied aside ("ink.bak-<date>") and the note opens
read-only, a file a newer Mürekkep wrote is left alone the same way, and index entries are read
one at a time, the unreadable ones kept and written back. The decoding and the copy themselves
are checked by tools/safefilescheck/run.ps1; this checks the wiring in the app's source."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Murekkep.swiftpm"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def body(text, start, end):
    return text[text.index(start):text.index(end)]


def test_unreadable_ink_opens_read_only_and_keeps_the_file():
    model = src("EditorModel.swift")
    assert "(try? InkCodec.decode(data)) ?? []" not in model
    load = body(model, "let inkURL = store.inkURL(for: meta.id)", "if meta.kind == .notebook {")
    assert "loaded = try InkCodec.decode(data)" in load
    assert "readOnly = true" in load
    # A newer build's file is only told about; a damaged one also gets a copy next to it.
    assert re.search(r"if InkCodec\.isNewerFormat\(data\) \{\s*inkError = Loc\.t\(", load)
    assert re.search(r"\} else \{\s*FileBackup\.keep\(inkURL\)\s*inkError = Loc\.t\(", load)
    assert "inkReadOnly = readOnly" in model
    assert "@Published private(set) var inkReadOnly = false" in model
    # The user sees why, in the card the editor already shows for an unreadable PDF.
    assert 'loadError = problems.isEmpty ? nil : problems.joined(separator: "\\n\\n")' in model


def test_a_read_only_note_is_never_saved_or_edited():
    model = src("EditorModel.swift")
    save = body(model, "func saveNow() {", "// MARK: Lecture replay")
    assert "guard dirty, !inkReadOnly else { return }" in save
    close = body(model, "func close() {", "// MARK: Content for Claude and export")
    assert close.index("guard !inkReadOnly else { return }") < close.index("InkTextCache.refresh")
    assert close.index("guard !inkReadOnly else { return }") < close.index("store.makeThumbnail")
    # Every way ink or stickers change asks first, and the user is told.
    assert 'banner = Loc.t("Not salt okunur: yeni yazılar kaydedilmez.")' in body(model, "private func allowsEdit()", "func addStroke(")
    for entry in ("func addStroke(_ stroke: Stroke, toPage page: Int) {",
                  "func replaceStrokes(page: Int, removing ids: Set<Int>, adding new: [Stroke]) {",
                  "func beginSelectionEdit() {",
                  "private func change(page: Int, _ body: (inout PageInk) -> Void) {",
                  "func beginErase(page: Int) {",
                  "func addPage() {",
                  "func setPaper(_ style: PaperStyle) {"):
        after = model[model.index(entry) + len(entry):]
        assert "allowsEdit()" in after[:200], entry
    assert "guard pages.indices.contains(page), !inkReadOnly else { return }" in body(model, "func erase(page: Int", "func endErase()")


def test_a_newer_ink_format_is_told_apart_from_damage():
    codec = src("InkCodec.swift")
    assert "static func formatVersion(of data: Data) -> UInt32?" in codec
    assert "static func isNewerFormat(_ data: Data) -> Bool" in codec
    assert "(formatVersion(of: data) ?? 0) > version" in codec
    assert "guard try r.u32() == version else { throw CodecError.unsupportedVersion }" in codec


def test_the_copy_is_dated_by_the_file_and_made_once():
    safe = src("SafeFiles.swift")
    assert 'static let marker = ".bak-"' in safe
    assert 'f.dateFormat = "yyyyMMdd-HHmmss"' in safe
    keep = body(safe, "static func keep(_ url: URL) -> URL? {", "enum LenientList")
    assert "[.modificationDate] as? Date" in keep
    assert keep.index("if fm.fileExists(atPath: copy.path) { return copy }") < keep.index("try fm.copyItem(at: url, to: copy)")


def test_the_index_is_read_entry_by_entry():
    store = src("LibraryStore.swift")
    assert "try? decoder.decode([NoteMeta].self, from: data)" not in store
    assert "try? decoder.decode([NoteSection].self, from: data)" not in store
    load = body(store, "private func load() {", "private func persist() {")
    assert "LenientList.decode(NoteMeta.self, from: data, decoder: decoder)" in load
    assert "LenientList.decode(NoteSection.self, from: data, decoder: decoder)" in load
    assert "unreadableNotes = read.unreadable" in load and "unreadableSections = read.unreadable" in load
    # A file that is not a list at all is copied aside before a save replaces it.
    assert "FileBackup.keep(indexURL)" in load and "FileBackup.keep(sectionsURL)" in load
    assert "LenientList.encode(notes, unreadable: unreadableNotes, encoder: encoder)" in body(store, "private func persist() {", "private func persistSections() {")
    assert "LenientList.encode(sections, unreadable: unreadableSections, encoder: encoder)" in body(store, "private func persistSections() {", "// MARK: Sections")
    safe = src("SafeFiles.swift")
    # The whole list first (the common case), then entry by entry.
    decode = body(safe, "static func decode<T: Decodable>", "static func encode<T: Encodable>")
    assert decode.index("try? decoder.decode([T].self, from: data)") < decode.index("JSONSerialization.jsonObject(with: data)")
    assert "reading.unreadable.append(entry)" in decode


def test_the_swift_harness_compiles_the_new_files():
    run = (ROOT / "tools" / "safefilescheck" / "run.ps1").read_text(encoding="utf-8")
    assert '"InkCodec.swift", "SafeFiles.swift"' in run
    main = (ROOT / "tools" / "safefilescheck" / "main.swift").read_text(encoding="utf-8")
    for name in ("FileBackup.keep(", "LenientList.decode(", "InkCodec.isNewerFormat("):
        assert name in main
    # Foundation only, so the Windows toolchain can build them.
    for name in ("SafeFiles.swift", "InkCodec.swift"):
        imports = re.findall(r"^import (\w+)", src(name), re.M)
        assert imports == ["Foundation"], (name, imports)
