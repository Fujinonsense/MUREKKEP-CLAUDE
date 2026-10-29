"""Photos come into the library as a PDF (2026-10-26): from Files, from the Photos library and by
drag and drop. Photos added together become one PDF, a page per photo."""
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_the_add_button_offers_files_and_photos():
    view = src("LibraryView.swift")
    assert "import PhotosUI" in view
    assert ".fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image]" in view
    assert ".photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhotos" in view
    assert 'Loc.t("Fotoğraflar\'dan")' in view and 'Loc.t("Dosyalar\'dan (PDF ya da fotoğraf)")' in view
    # The add action asks where from instead of opening Files straight away.
    action = view[view.index("importPDF: { section in"):]
    assert "askImportSource = true" in action[:120]


def test_photos_become_one_pdf():
    view = src("LibraryView.swift")
    files = view[view.index("private func importFiles"):view.index("private static func isPhoto")]
    assert "convertPhotos(" in files and "store.importPDF(" in files
    assert "convertPhotos(photos, title: LibraryStore.photoTitle(fileName: nil)" in view
    assert "store.importPhotos(photos, title: title, section: section)" in view[view.index("private func convertPhotos"):]
    store = src("LibraryStore.swift")
    assert "func importPhotos(_ photos: [Data], title: String, section: UUID? = nil," in store
    assert "progress: @escaping (Int, Int) -> Void = { _, _ in }) async throws -> NoteMeta" in store
    assert "PhotoPDF.write(photos, to: url) { done, total in" in store
    pdf = src("PhotoPDF.swift")
    assert "UIGraphicsPDFRenderer" in pdf and "beginPage(withBounds:" in pdf
    assert "jpegData(compressionQuality:" in pdf  # pages stay compressed


def test_photos_are_converted_off_the_main_thread_with_a_count():
    # Thirty photos decoded, scaled and compressed on the main actor froze the library (1.1).
    store = src("LibraryStore.swift")
    convert = store[store.index("func importPhotos("):store.index("static func photoTitle")]
    assert "@MainActor" in store[store.index("func importPhotos(") - 120:store.index("func importPhotos(")]
    assert "try await Task.detached(priority: .userInitiated) {" in convert
    assert "DispatchQueue.main.async { progress(done, total) }" in convert
    # The note lands in the library on the main actor, after the PDF is written.
    assert convert.index(".value") < convert.index("return try importPDF(from: url, section: section)")
    pdf = src("PhotoPDF.swift")
    assert "progress: (Int, Int) -> Void = { _, _ in }) throws -> Int" in pdf
    assert "autoreleasepool {" in pdf and "progress(i + 1, photos.count)" in pdf
    view = src("LibraryView.swift")
    assert "@State private var photoProgress: PhotoImportProgress?" in view
    assert 'Loc.t("Fotoğraflar PDF\'e dönüştürülüyor ({0}/{1})", "\\(p.done)", "\\(p.total)")' in view
    assert "photoProgressBanner" in view[view.index(".overlay(alignment: .bottom) {"):][:120]
    # Every way photos come in shows the count and converts them off the main thread.
    for start in ("private func importFiles", "private func importPicked", "private func handleDrop"):
        part = view[view.index(start):]
        assert "convertPhotos(" in part[:2600], start
    files = view[view.index("private func importFiles"):view.index("private func finishImport")]
    assert "await Task.detached(priority: .userInitiated) {" in files  # the files are read there too
    convert_view = view[view.index("private func convertPhotos"):view.index("private func showPhotoProgress")]
    assert "defer { showPhotoProgress(nil) }" in convert_view
    assert "photoProgress = PhotoImportProgress(done: done, total: total)" in convert_view


def test_photos_can_be_dropped_everywhere_a_pdf_can():
    for name in ("LibraryView.swift", "LibraryPanes.swift"):
        text = src(name)
        assert ".onDrop(of: [.pdf]," not in text, name
    # The notes (one pane for every list of the sidebar), a course, and the sidebar's course rows.
    assert src("LibraryPanes.swift").count(".onDrop(of: [.pdf, .image],") == 2
    assert src("LibraryView.swift").count(".onDrop(of: [.pdf, .image],") == 1
    view = src("LibraryView.swift")
    drop = view[view.index("private func handleDrop"):]
    assert "UTType.image.identifier" in drop and "convertPhotos(" in drop


def test_photo_texts_are_translated():
    table = src("Translations.swift")
    for key in ("PDF ya da fotoğraf ekle", "Dosyalar'dan (PDF ya da fotoğraf)", "Fotoğraflar'dan",
                "Fotoğraflar tek bir PDF olur, her fotoğraf bir sayfa.", "PDF / Foto", "Fotoğraf okunamadı."):
        assert f'"{key}":' in table, key
