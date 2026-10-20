import PDFKit
import SwiftUI

/// A course or topic in the library ("Calculus", "Anatomi"): notes and PDFs are filed under it and
/// the assistant can answer from all of them together.
struct NoteSection: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
    var colorIndex: Int
    var created = Date()

    static let colors: [Color] = [
        Color(red: 0.10, green: 0.33, blue: 0.80), Color(red: 0.45, green: 0.30, blue: 0.96),
        Color(red: 0.07, green: 0.60, blue: 0.70), Color(red: 0.16, green: 0.62, blue: 0.32),
        Color(red: 0.92, green: 0.55, blue: 0.10), Color(red: 0.85, green: 0.22, blue: 0.30),
        Color(red: 0.88, green: 0.36, blue: 0.62), Color(red: 0.40, green: 0.42, blue: 0.48),
    ]

    static let symbols = ["function", "x.squareroot", "atom", "flask", "cross.case", "heart.text.square", "brain.head.profile",
                          "gearshape.2", "bolt", "building.columns", "globe.europe.africa", "chart.line.uptrend.xyaxis",
                          "book.closed", "text.book.closed", "music.note", "paintpalette", "laptopcomputer", "leaf"]

    var color: Color { Self.colors[((colorIndex % Self.colors.count) + Self.colors.count) % Self.colors.count] }
}

/// Reads notes for section-wide questions and for the Studio: every PDF page (its text layer, or OCR
/// when it is a scan), and the handwriting of notebooks through on-device OCR. Runs off the main
/// thread; with a note id, pages read once are kept on disk.
enum SectionReader {
    struct Page: Sendable {
        let page: Int
        let text: String
        let fromOCR: Bool
        /// Read from the user's handwriting (not from the PDF).
        var isHandwriting = false
    }

    /// The pages of `range` (all pages when nil); a longer range is sampled evenly down to `maxPages`.
    /// `progress` gets (pages done, pages to read).
    static func pages(pdf: URL?, ink: URL, maxPages: Int, noteID: UUID? = nil, range: ClosedRange<Int>? = nil,
                      progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [Page] {
        await Task.detached(priority: .userInitiated) { () async -> [Page] in
            var out: [Page] = []
            if let pdf, let doc = PDFDocument(url: pdf), doc.pageCount > 0 {
                let lo = max(0, range?.lowerBound ?? 0)
                let hi = min(doc.pageCount - 1, range?.upperBound ?? doc.pageCount - 1)
                if lo <= hi {
                    let picks = PageSample.pages(count: hi - lo + 1, limit: maxPages).map { lo + $0 }
                    for (n, i) in picks.enumerated() {
                        if Task.isCancelled { break }
                        progress?(n, picks.count)
                        let read = await PDFPageReader.read(doc, page: i, noteID: noteID)
                        if PDFPageReader.letterCount(read.text) >= (read.fromOCR ? 6 : TextLayer.minLetters) {
                            out.append(Page(page: i, text: read.text, fromOCR: read.fromOCR))
                        }
                    }
                }
            }
            // Handwriting (the ink of notebooks, or notes written on a PDF).
            var inkPages = 0
            if let data = try? Data(contentsOf: ink), let pages = try? InkCodec.decode(data) {
                for (i, strokes) in pages.enumerated() where !strokes.isEmpty && inkPages < maxPages && (range?.contains(i) ?? true) {
                    if Task.isCancelled { break }
                    guard let raster = InkRaster.render(strokes) else { continue }
                    let found = await PageOCR.lines(in: raster)
                    let text = await MainActor.run { Spelling.polish(found) }.map(\.text).joined(separator: "\n")
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 {
                        out.append(Page(page: i, text: text, fromOCR: true, isHandwriting: true))
                        inkPages += 1
                    }
                }
            }
            return out
        }.value
    }
}

// MARK: - Library UI

/// The row of sections at the top of the library.
struct SectionBar: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var selected: UUID?
    let onNew: () -> Void
    let onEdit: (NoteSection) -> Void
    let onDelete: (NoteSection) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip(title: Loc.t("Tümü"), symbol: "tray.full", color: .secondary, count: store.notes.count, isOn: selected == nil) {
                    selected = nil
                }
                ForEach(store.sections) { section in
                    chip(title: section.name, symbol: section.symbol, color: section.color,
                         count: store.notes.filter { $0.sectionID == section.id }.count, isOn: selected == section.id) {
                        selected = section.id
                    }
                    .contextMenu {
                        Button {
                            onEdit(section)
                        } label: {
                            Label(Loc.t("Düzenle"), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDelete(section)
                        } label: {
                            Label(Loc.t("Bölümü sil (notlar kalır)"), systemImage: "trash")
                        }
                    }
                }
                Button(action: onNew) {
                    Label(Loc.t("Bölüm"), systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.t("Yeni bölüm"))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    private func chip(title: String, symbol: String, color: Color, count: Int, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(isOn ? Color.white.opacity(0.25) : color.opacity(0.14)))
            }
            .foregroundStyle(isOn ? Color.white : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(isOn ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.10))))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Create or edit a section: name, icon and color.
struct SectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    @State var symbol: String
    @State var colorIndex: Int
    let isNew: Bool
    let onSave: (String, String, Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Loc.t("Bölüm adı (ör. Calculus, Anatomi)"), text: $name)
                        .font(.title3)
                }
                Section(Loc.t("Simge")) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(NoteSection.symbols, id: \.self) { s in
                            Button {
                                symbol = s
                            } label: {
                                Image(systemName: s)
                                    .font(.system(size: 18, weight: .medium))
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(symbol == s ? Color.white : NoteSection.colors[colorIndex])
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(symbol == s ? NoteSection.colors[colorIndex] : NoteSection.colors[colorIndex].opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section(Loc.t("Renk")) {
                    HStack(spacing: 12) {
                        ForEach(NoteSection.colors.indices, id: \.self) { i in
                            Button {
                                colorIndex = i
                            } label: {
                                Circle()
                                    .fill(NoteSection.colors[i])
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Color.primary.opacity(colorIndex == i ? 0.8 : 0), lineWidth: 2).padding(-4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Label(Loc.t("Bölüme PDF'lerini ve defterlerini topla. Asistanda \"Tüm bölüm\"ü seçince sorularını bölümdeki bütün notlardan yanıtlar."),
                          systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? Loc.t("Yeni bölüm") : Loc.t("Bölümü düzenle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Loc.t("Vazgeç")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? Loc.t("Oluştur") : Loc.t("Kaydet")) {
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), symbol, colorIndex)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
