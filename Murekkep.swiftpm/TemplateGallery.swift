import SwiftUI
import UIKit

/// All page templates by category: used to start a notebook and to change the template of one.
struct TemplateGallery: View {
    let title: String
    var current: PaperStyle?
    let onPick: (PaperStyle) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var category: TemplateCategory?

    private let columns = [GridItem(.adaptive(minimum: 118, maximum: 168), spacing: 18)]

    private var shown: [TemplateCategory] {
        if let category { return [category] }
        return TemplateCategory.allCases
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(nil, title: Loc.t("Tümü"))
                            ForEach(TemplateCategory.allCases) { c in
                                filterChip(c, title: c.title)
                            }
                        }
                    }
                    ForEach(shown) { cat in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(cat.title)
                                .font(.title3.weight(.bold))
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(cat.styles) { style in
                                    tile(style)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.libraryBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Loc.t("Vazgeç")) { dismiss() }
                }
            }
        }
    }

    private func filterChip(_ c: TemplateCategory?, title: String) -> some View {
        let selected = category == c
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { category = c }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color.primary.opacity(0.07))))
        }
        .buttonStyle(.plain)
    }

    private func tile(_ style: PaperStyle) -> some View {
        Button {
            onPick(style)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                PaperPreview(style: style)
                    .aspectRatio(NoteMeta.a4.width / NoteMeta.a4.height, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.ink, lineWidth: current == style ? 3 : 0)
                    )
                HStack(spacing: 5) {
                    Image(systemName: style.symbol)
                    Text(style.title)
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(current == style ? .isSelected : [])
    }
}

/// Miniature of a template, drawn with the same code as the real pages.
struct PaperPreview: View {
    let style: PaperStyle

    var body: some View {
        Canvas { ctx, size in
            ctx.withCGContext { cg in
                let page = NoteMeta.a4
                cg.scaleBy(x: size.width / page.width, y: size.height / page.height)
                PaperDrawer.draw(style, size: page, in: cg)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
        .shadow(color: Theme.shadow.opacity(0.10), radius: 8, y: 4)
    }
}
