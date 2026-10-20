import SwiftUI
import UIKit

// MARK: - Radial palette (Apple Pencil double tap and squeeze)

/// Opens at the pencil tip. The first ring holds the tools (pen, highlighter, text pen, lasso,
/// ruler, shapes, compass, eraser); picking a pen turns the ring into that pen's colors and widths.
struct RadialPalette: View {
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings
    let request: PaletteRequest
    let container: CGSize
    @State private var appeared = false
    @State private var mode: PaletteRequest.Mode = .tools

    private let radius: CGFloat = 108

    private struct Item {
        let title: String
        let label: AnyView
        let action: () -> Void
    }

    var body: some View {
        let diameter = radius * 2 + 84
        let items = mode == .tools ? toolItems : colorItems
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
                    .frame(width: diameter, height: diameter)
                ForEach(items.indices, id: \.self) { i in
                    let angle = Double(i) / Double(items.count) * 2 * .pi - .pi / 2
                    Button(action: items[i].action) {
                        VStack(spacing: 3) {
                            items[i].label
                            if mode == .tools {
                                Text(items[i].title)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(items[i].title)
                    .offset(x: CGFloat(cos(angle)) * radius * (appeared ? 1 : 0.4),
                            y: CGFloat(sin(angle)) * radius * (appeared ? 1 : 0.4) + (mode == .tools ? 6 : 0))
                }
                centerButton
            }
            .frame(width: diameter, height: diameter)
            widthRow
        }
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .position(clampedCenter(width: diameter, height: diameter + 118))
        .onAppear {
            mode = request.mode
            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
                appeared = true
            }
        }
    }

    private func clampedCenter(width: CGFloat, height: CGFloat) -> CGPoint {
        let rx = width / 2 + 8
        let ry = height / 2 + 8
        let x = min(max(request.location.x, rx), max(rx, container.width - rx))
        let y = min(max(request.location.y, ry), max(ry, container.height - ry))
        return CGPoint(x: x, y: y)
    }

    private func close() {
        editor.palette = nil
    }

    private func showColors() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { mode = .colors }
        editor.onHaptic?(.selection)
    }

    /// Tools: the current ink and tool; colors: back to the tools.
    private var centerButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                mode = mode == .tools ? .colors : .tools
            }
            editor.onHaptic?(.selection)
        } label: {
            ZStack {
                Circle()
                    .fill(editor.color(for: editor.activeBrush).swiftUIColor)
                    .frame(width: 60, height: 60)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                if mode == .tools {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                } else {
                    VStack(spacing: 1) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 15, weight: .bold))
                        Text(Loc.t("Araçlar"))
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .tools ? Loc.t("Renkler") : Loc.t("Araçlara dön"))
    }

    // MARK: Rings

    private func disc<Content: View>(selected: Bool, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 46, height: 46)
            .background(Circle().fill(Color(uiColor: .systemBackground).opacity(0.94)))
            .overlay(Circle().strokeBorder(selected ? tint : Color.primary.opacity(0.10), lineWidth: selected ? 3 : 1))
            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
    }

    private func symbolDisc(_ symbol: String, selected: Bool) -> AnyView {
        AnyView(disc(selected: selected, tint: Theme.ink) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? Theme.ink : Color.primary)
        })
    }

    private var toolItems: [Item] {
        let pen = editor.lastBrush == .highlighter ? Brush.pen : editor.lastBrush
        let penInk = editor.color(for: pen).swiftUIColor
        let marker = editor.color(for: .highlighter).swiftUIColor
        let tool = editor.tool
        let rulerOn = editor.instrument != nil
        return [
            Item(title: Loc.t("Kalem"), label: AnyView(disc(selected: tool == .brush(pen), tint: penInk) {
                ToolIcon(brush: pen, ink: penInk, side: 38)
            }), action: {
                editor.select(.brush(pen))
                showColors()
            }),
            Item(title: Loc.t("Fosforlu"), label: AnyView(disc(selected: tool == .brush(.highlighter), tint: marker) {
                ToolIcon(brush: .highlighter, ink: marker, side: 38)
            }), action: {
                editor.select(.brush(.highlighter))
                showColors()
            }),
            Item(title: Loc.t("Metin"), label: AnyView(disc(selected: tool == .textPen, tint: penInk) {
                Text("Aa")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(penInk)
            }), action: {
                editor.select(.textPen)
                showColors()
            }),
            Item(title: Loc.t("Seç"), label: symbolDisc("lasso", selected: tool == .lasso), action: {
                editor.select(.lasso)
                close()
            }),
            Item(title: Loc.t("Cetvel"), label: symbolDisc("ruler", selected: rulerOn), action: {
                editor.showInstrument(rulerOn ? nil : .ruler)
                close()
            }),
            Item(title: Loc.t("Şekil"), label: symbolDisc(editor.shapeKind.symbol, selected: tool == .shape), action: {
                editor.select(.shape)
                close()
            }),
            Item(title: Loc.t("Pergel"), label: symbolDisc("compass.drawing", selected: tool == .compass), action: {
                editor.select(.compass)
                close()
            }),
            Item(title: Loc.t("Silgi"), label: AnyView(disc(selected: tool == .eraser, tint: .gray) {
                ToolIcon(brush: nil, ink: .clear, side: 36)
            }), action: {
                editor.select(.eraser)
                close()
            }),
        ]
    }

    private var colorItems: [Item] {
        let brush = editor.activeBrush
        var colors = brush.palette
        for c in settings.recentColors where !colors.contains(c) && colors.count < 12 {
            colors.append(c)
        }
        return colors.map { color in
            let selected = editor.color(for: brush) == color
            return Item(title: Loc.t("Renk"), label: AnyView(
                Circle()
                    .fill(color.swiftUIColor)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: selected ? 3.5 : 1.5))
                    .overlay(Circle().stroke(Color.primary.opacity(selected ? 0.5 : 0), lineWidth: 1).padding(-3))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            ), action: {
                editor.setColor(color, for: brush)
                editor.onHaptic?(.selection)
                close()
            })
        }
    }

    /// Width of the pen in hand (the last pen while another tool is in hand): the line it draws, a
    /// slider and three quick steps.
    private var widthRow: some View {
        let brush = editor.activeBrush
        let range = brush.widthRange
        let ink = editor.color(for: brush).swiftUIColor
        let current = editor.width(for: brush)
        let steps: [Float] = [0.12, 0.38, 0.75].map { range.lowerBound + (range.upperBound - range.lowerBound) * $0 }
        let nearest = steps.min(by: { abs($0 - current) < abs($1 - current) })
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(brush.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                // The line at its real width on the page (1 point = 1 point at 100 %).
                Capsule()
                    .fill(ink)
                    .frame(width: 46, height: max(1, min(CGFloat(current), 26)))
                    .frame(height: 26)
                Text(ShapeBuilder.mm(CGFloat(current) / pointsPerMillimetre))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 48, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Circle().fill(ink).frame(width: 5, height: 5)
                Slider(value: Binding(get: { Double(editor.width(for: brush)) },
                                      set: { editor.setWidth(Float($0), for: brush) }),
                       in: Double(range.lowerBound)...Double(range.upperBound))
                    .tint(ink)
                    .accessibilityLabel(Loc.t("Kalınlık"))
                Circle().fill(ink).frame(width: 15, height: 15)
            }
            HStack(spacing: 18) {
                ForEach(steps.indices, id: \.self) { i in
                    let w = steps[i]
                    Button {
                        editor.setWidth(w, for: brush)
                        editor.onHaptic?(.selection)
                    } label: {
                        Circle()
                            .fill(ink)
                            .frame(width: CGFloat(6 + i * 6), height: CGFloat(6 + i * 6))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.primary.opacity(w == nearest ? 0.12 : 0)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Loc.t([Loc.t("İnce"), Loc.t("Orta"), Loc.t("Kalın")][i]))
                }
            }
        }
        .frame(width: 264)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassCard(radius: 22)
    }
}
