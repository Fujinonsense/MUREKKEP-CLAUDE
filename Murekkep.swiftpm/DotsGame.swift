import SwiftUI

/// Kare kapmaca against the iPad, the game of a notebook's back pages: tap between two neighbouring
/// dots, or draw the line, to join them; close a box to take it and draw again. Kolay is 3×3, Orta
/// 4×4, Zor 5×5 against an iPad that counts the end through. "Tekrar" starts again with the other
/// side first; wins are counted per difficulty.
struct DotsGame: View {
    @ObservedObject var store: GameProgressStore
    @State private var board: DotsBoard
    @State private var rng = GameRandom()
    @State private var humanFirst = true
    /// Counts the iPad's turns; each one runs the reply task afresh.
    @State private var pendingReply = 0
    @State private var counted = false
    /// The line under the pencil before it lifts, and the line drawn last.
    @State private var hover: DotsEdge?
    @State private var latest: DotsEdge?
    /// Games won here, for the success tap (the kept wins change with the difficulty).
    @State private var wonRounds = 0
    /// True while a finger or the pencil is down; it falls back by itself when the system cancels the
    /// touch, which then clears the line under it.
    @GestureState private var pressing = false

    /// The iPad's lines and boxes, in amber against the player's ink.
    private static let deviceInk = GameCorner.ink(3)

    init(store: GameProgressStore) {
        _store = ObservedObject(wrappedValue: store)
        _board = State(initialValue: DotsBoard(size: DotsBoard.size(store[.dots].difficulty)))
    }

    private var difficulty: GameDifficulty { store[.dots].difficulty }
    private var wins: Int { store[.dots].best[difficulty] ?? 0 }

    var body: some View {
        VStack(spacing: 8) {
            DifficultyPicker(difficulty: Binding(get: { store[.dots].difficulty }, set: { store.setDifficulty($0, for: .dots) }))
            HStack(spacing: 8) {
                tally(Loc.t("Sen"), board.score(.you), Theme.ink, turn: board.turn == .you)
                Spacer(minLength: 4)
                Text(status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(board.isOver ? Theme.ink : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                tally("iPad", board.score(.device), Self.deviceInk, turn: board.turn == .device)
            }
            .frame(height: 24)
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                boardView(side: side)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text(difficulty == .hard ? Loc.t("Zor: 5×5; iPad oyunun sonunu hesaplar.")
                     : difficulty == .easy ? Loc.t("Kolay: 3×3; iPad sık sık dalgın.") : Loc.t("Orta: 4×4; iPad kolay kare vermez."))
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
                .opacity(board.isOver ? 1 : 0)
                .disabled(!board.isOver)
            }
        }
        .task(id: pendingReply) {
            await reply()
        }
        .onChange(of: difficulty) { _, _ in
            restart(keepTurn: true)
        }
        .onChange(of: board.isOver) { _, over in
            guard over, !counted else { return }
            counted = true
            if board.winner == .you {
                store.record(.dots, score: wins + 1, at: difficulty)
                wonRounds += 1
            }
        }
        .sensoryFeedback(.success, trigger: wonRounds)
        .sensoryFeedback(.selection, trigger: board.lines.count) { old, new in new > old }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.6), trigger: board.owners.count) { old, new in new > old }
    }

    private var status: String {
        if board.isOver {
            switch board.winner {
            case .you?: return Loc.t("Kazandın!")
            case .device?: return Loc.t("iPad kazandı.")
            case nil: return Loc.t("Berabere.")
            }
        }
        return board.turn == .you ? Loc.t("Sıra sende: bir çizgi çiz.") : Loc.t("iPad düşünüyor…")
    }

    /// A side's name and boxes, underlined while it is their turn.
    private func tally(_ name: String, _ boxes: Int, _ ink: Color, turn: Bool) -> some View {
        HStack(spacing: 4) {
            Text(name)
            Text("\(boxes)")
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(ink)
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(ink)
                .frame(height: 2)
                .opacity(turn && !board.isOver ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func boardView(side: CGFloat) -> some View {
        let inset = side * 0.09
        let step = (side - 2 * inset) / CGFloat(board.size)
        return Canvas { context, _ in
            draw(&context, inset: inset, step: step)
        }
        .gameBoard()
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($pressing) { _, down, _ in down = true }
                .onChanged { value in
                    let line = edge(near: Self.middle(value.startLocation, value.location), inset: inset, step: step)
                    if hover != line { hover = line }
                }
                .onEnded { value in
                    hover = nil
                    if let line = edge(near: Self.middle(value.startLocation, value.location), inset: inset, step: step) {
                        play(line)
                    }
                }
        )
        .onChange(of: pressing) { _, down in
            if !down { hover = nil }
        }
        .accessibilityLabel(Loc.t("Kare kapmaca tahtası"))
        .accessibilityValue(status)
    }

    /// The taken boxes washed in their taker's ink with a name, the line under the pencil, the lines
    /// drawn (the last one bolder), and the dots over them.
    private func draw(_ context: inout GraphicsContext, inset: CGFloat, step: CGFloat) {
        let n = board.size
        for (box, owner) in board.owners {
            let rect = CGRect(x: inset + CGFloat(box % n) * step, y: inset + CGFloat(box / n) * step, width: step, height: step).insetBy(dx: 4, dy: 4)
            let ink = owner == .you ? Theme.ink : Self.deviceInk
            context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(ink.opacity(0.14)))
            context.draw(Text(owner == .you ? Loc.t("Sen") : "iPad")
                            .font(.system(size: max(9, step * 0.2), weight: .semibold, design: .rounded))
                            .foregroundStyle(ink),
                         at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
        if let hover, board.turn == .you, !board.isOver {
            context.stroke(line(hover, inset: inset, step: step), with: .color(Theme.ink.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 5]))
        }
        for (edge, player) in board.lines {
            context.stroke(line(edge, inset: inset, step: step), with: .color(player == .you ? Theme.ink : Self.deviceInk),
                           style: StrokeStyle(lineWidth: edge == latest ? 4.5 : 3.2, lineCap: .round))
        }
        var dots = Path()
        for row in 0...n {
            for col in 0...n {
                let p = CGPoint(x: inset + CGFloat(col) * step, y: inset + CGFloat(row) * step)
                dots.addEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
            }
        }
        context.fill(dots, with: .color(Color.primary.opacity(0.75)))
    }

    private func line(_ edge: DotsEdge, inset: CGFloat, step: CGFloat) -> Path {
        let from = CGPoint(x: inset + CGFloat(edge.col) * step, y: inset + CGFloat(edge.row) * step)
        let to = edge.horizontal ? CGPoint(x: from.x + step, y: from.y) : CGPoint(x: from.x, y: from.y + step)
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }

    private static func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// The free line whose middle is nearest `point`, if it is within four tenths of a gap of it: a
    /// tap between two dots, or a short stroke from one to the other.
    private func edge(near point: CGPoint, inset: CGFloat, step: CGFloat) -> DotsEdge? {
        var nearest: DotsEdge?
        var reach = Double(step) * 0.4
        for edge in board.freeEdges {
            let mid = edge.horizontal
                ? CGPoint(x: inset + (CGFloat(edge.col) + 0.5) * step, y: inset + CGFloat(edge.row) * step)
                : CGPoint(x: inset + CGFloat(edge.col) * step, y: inset + (CGFloat(edge.row) + 0.5) * step)
            let dx = Double(mid.x - point.x)
            let dy = Double(mid.y - point.y)
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < reach {
                reach = distance
                nearest = edge
            }
        }
        return nearest
    }

    /// The player's line; when it closes nothing, the iPad thinks.
    private func play(_ edge: DotsEdge) {
        guard !board.isOver, board.turn == .you, board.draw(edge) != nil else { return }
        latest = edge
        if !board.isOver, board.turn == .device { pendingReply += 1 }
    }

    /// The iPad's turn: a line every moment until one closes nothing or the game ends; Zor's search
    /// runs off the main thread. Cancelled with the view if the panel closes first.
    private func reply() async {
        while pendingReply > 0, !board.isOver, board.turn == .device {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, !board.isOver, board.turn == .device else { return }
            let snapshot = board
            let level = difficulty
            let random = rng
            let (move, next) = await Task.detached(priority: .userInitiated) { () -> (DotsEdge?, GameRandom) in
                var stream = random
                let edge = DotsAI.move(on: snapshot, difficulty: level, rng: &stream)
                return (edge, stream)
            }.value
            guard !Task.isCancelled, board == snapshot, let move else { return }
            rng = next
            board.draw(move)
            latest = move
        }
    }

    /// A new game at the chosen size; the other side starts, unless the difficulty changed mid-game.
    private func restart(keepTurn: Bool = false) {
        if !keepTurn { humanFirst.toggle() }
        board = DotsBoard(size: DotsBoard.size(difficulty), first: humanFirst ? .you : .device)
        counted = false
        hover = nil
        latest = nil
        if !humanFirst { pendingReply += 1 }
    }
}
