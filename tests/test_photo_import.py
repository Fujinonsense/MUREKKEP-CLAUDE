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
    assert "store.importPhotos(" in files and "store.importPDF(" in files
    assert "importPhotos(photos, title: LibraryStore.photoTitle(fileName: nil)" in view
    store = src("LibraryStore.swift")
    assert "func importPhotos(_ photos: [Data], title: String, section: UUID? = nil) throws -> NoteMeta" in store
    assert "PhotoPDF.write(photos, to: url)" in store
    pdf = src("PhotoPDF.swift")
    assert "UIGraphicsPDFRenderer" in pdf and "beginPage(withBounds:" in pdf
    assert "jpegData(compressionQuality:" in pdf  # pages stay compressed


def test_photos_can_be_dropped_everywhere_a_pdf_can():
    for name in ("LibraryView.swift", "LibraryPanes.swift"):
        text = src(name)
        assert ".onDrop(of: [.pdf]," not in text, name
    assert src("LibraryPanes.swift").count(".onDrop(of: [.pdf, .image],") == 4
    view = src("LibraryView.swift")
    drop = view[view.index("private func handleDrop"):]
    assert "UTType.image.identifier" in drop and "importPhotos(" in drop


def test_photo_texts_are_translated():
    table = src("Translations.swift")
    for key in ("PDF ya da fotoğraf ekle", "Dosyalar'dan (PDF ya da fotoğraf)", "Fotoğraflar'dan",
                "Fotoğraflar tek bir PDF olur, her fotoğraf bir sayfa.", "PDF / Foto", "Fotoğraf okunamadı."):
        assert f'"{key}":' in table, key
