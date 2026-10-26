import SwiftUI

/// A straight stroke between two points of the unit square.
private struct StrokeLine: Shape {
    var from: UnitPoint
    var to: UnitPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * from.x, y: rect.minY + rect.height * from.y))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * to.x, y: rect.minY + rect.height * to.y))
        return path
    }
}

/// XOX against the iPad: the player is X and taps or draws in a cell; the iPad answers with O after
/// a moment's thought — Kolay mostly at random, Orta with a plan, Zor without a single mistake. The
/// marks draw themselves on; three in a row ends the game with a line through them, and "Tekrar"
/// starts again with the other side first. Wins are counted per difficulty.
struct XOXGame: View {
    @ObservedObject var store: GameProgressStore
    @State private var game = TicTacToe()
    @State private var rng = GameRandom()
    @State private var humanFirst = true
    /// Each placed mark's drawing progress, 0…1.
    @State private var drawn: [Int: CGFloat] = [:]
    @State private var lineProgress: CGFloat = 0
    /// Counts the iPad's turns; each one runs the reply task afresh.
    @State private var pendingReply = 0
    @State private var counted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let human = TicTacToe.Mark.x
    private static let device = TicTacToe.Mark.o
    private static let lineWidth: CGFloat = 4

    private var difficulty: GameDifficulty { store[.xox].difficulty }
    private var wins: Int { store[.xox].best[difficulty] ?? 0 }

    var body: some View {
        VStack(spacing: 8) {
            DifficultyPicker(difficulty: Binding(get: { store[.xox].difficulty }, set: { store.setDifficulty($0, for: .xox) }))
            HStack {
                Text(status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(game.isOver ? Theme.ink : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(Loc.t("Galibiyet: {0}", "\(wins)"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(height: 22)
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                board(side: side)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text(difficulty == .hard ? Loc.t("Zor: iPad hata yapmaz; berabere kalmak başarıdır.") : difficulty == .easy ? Loc.t("Kolay: iPad çoğu zaman rastgele oynar.") : Loc.t("Orta: iPad kazanmayı ve engellemeyi bilir."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button {
                    restart()
                } label: {
                    Label(Loc.t("Tekrar"), systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                .opacity(game.isOver ? 1 : 0)
                .disabled(!game.isOver)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: game.isOver)
            }
        }
        .task(id: pendingReply) {
            await reply()
        }
        .onChange(of: difficulty) { _, _ in
            restart(keepTurn: true)
        }
        .onChange(of: game.isOver) { _, over in
            guard over, !counted else { return }
            counted = true
            if case .won(let mark, _)? = game.outcome, mark == Self.human {
                store.record(.xox, score: wins + 1, at: difficulty)
            }
        }
    }

    private var status: String {
        switch game.outcome {
        case .won(let mark, _)?:
            return mark == Self.human ? Loc.t("Kazandın!") : Loc.t("iPad kazandı.")
        case .draw?:
            return Loc.t("Berabere.")
        case nil:
            return game.turn == Self.human ? Loc.t("Sıra sende: X çiz.") : Loc.t("iPad düşünüyor…")
        }
    }

    private var winningLine: [Int]? {
        if case .won(_, let line)? = game.outcome { return line }
        return nil
    }

    private func board(side: CGFloat) -> some View {
        ZStack {
            Canvas { context, size in
                var grid = Path()
                for i in 1...2 {
                    let at = size.width * CGFloat(i) / 3
                    grid.move(to: CGPoint(x: at, y: 8))
                    grid.addLine(to: CGPoint(x: at, y: size.height - 8))
                    grid.move(to: CGPoint(x: 8, y: at))
                    grid.addLine(to: CGPoint(x: size.width - 8, y: at))
                }
                context.stroke(grid, with: .color(Theme.ink.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            ForEach(0..<9, id: \.self) { cell in
                if let mark = game.cells[cell] {
                    markView(mark, progress: drawn[cell] ?? 1, cell: side / 3)
                        .frame(width: side / 3, height: side / 3)
                        .position(Self.centre(of: cell, side: side))
                        .allowsHitTesting(false)
                }
            }
            if let line = winningLine, let first = line.first, let last = line.last {
                StrokeLine(from: Self.unit(of: first), to: Self.unit(of: last))
                    .trim(from: 0, to: lineProgress)
                    .stroke(Theme.ink.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .allowsHitTesting(false)
            }
        }
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.6))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onEnded { value in tap(at: value.startLocation, side: side) }
        )
        .accessibilityLabel(Loc.t("XOX tahtası"))
        .accessibilityValue(status)
    }

    @ViewBuilder
    private func markView(_ mark: TicTacToe.Mark, progress: CGFloat, cell: CGFloat) -> some View {
        let inset = 0.27
        switch mark {
        case .x:
            ZStack {
                StrokeLine(from: UnitPoint(x: inset, y: inset), to: UnitPoint(x: 1 - inset, y: 1 - inset))
                    .trim(from: 0, to: min(1, progress * 2))
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                StrokeLine(from: UnitPoint(x: 1 - inset, y: inset), to: UnitPoint(x: inset, y: 1 - inset))
                    .trim(from: 0, to: max(0, progress * 2 - 1))
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
            }
        case .o:
            Circle()
                .trim(from: 0, to: progress)
                .rotation(.degrees(-90))
                .stroke(Color.primary.opacity(0.7), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .padding(cell * CGFloat(inset))
        }
    }

    private static func unit(of cell: Int) -> UnitPoint {
        UnitPoint(x: (Double(cell % 3) + 0.5) / 3, y: (Double(cell / 3) + 0.5) / 3)
    }

    private static func centre(of cell: Int, side: CGFloat) -> CGPoint {
        let point = Self.unit(of: cell)
        return CGPoint(x: side * point.x, y: side * point.y)
    }

    /// The player's turn: the cell the touch began in takes an X, then the iPad thinks.
    private func tap(at point: CGPoint, side: CGFloat) {
        guard !game.isOver, game.turn == Self.human, side > 0 else { return }
        let col = Int(point.x / (side / 3))
        let row = Int(point.y / (side / 3))
        guard (0..<3).contains(col), (0..<3).contains(row) else { return }
        place(row * 3 + col)
        if !game.isOver { pendingReply += 1 }
    }

    /// The iPad's turn, after a moment; cancelled with the view if the panel closes first.
    private func reply() async {
        guard pendingReply > 0, !game.isOver, game.turn == Self.device else { return }
        try? await Task.sleep(nanoseconds: 550_000_000)
        guard !Task.isCancelled, !game.isOver, game.turn == Self.device else { return }
        var random = rng
        guard let move = game.move(for: Self.device, difficulty: difficulty, rng: &random) else { return }
        rng = random
        place(move)
    }

    private func place(_ cell: Int) {
        guard game.play(cell) else { return }
        let over = game.isOver
        if reduceMotion {
            drawn[cell] = 1
            if over { lineProgress = 1 }
            return
        }
        drawn[cell] = 0
        // The mark draws itself on from the next frame, and the winning line after it.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.35)) { drawn[cell] = 1 }
            if over {
                withAnimation(.easeInOut(duration: 0.4).delay(0.3)) { lineProgress = 1 }
            }
        }
    }

    /// A new game; the other side starts, unless the difficulty changed mid-game.
    private func restart(keepTurn: Bool = false) {
        if !keepTurn { humanFirst.toggle() }
        game = TicTacToe(first: humanFirst ? Self.human : Self.device)
        drawn = [:]
        lineProgress = 0
        counted = false
        if !humanFirst { pendingReply += 1 }
    }
}
