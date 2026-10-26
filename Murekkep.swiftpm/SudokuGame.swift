import SwiftUI

/// The puzzle on screen, kept in UserDefaults between visits (the panel closes, the app goes away).
final class SudokuModel: ObservableObject {
    @Published private(set) var save: SudokuSave?
    @Published var selected: Int?
    @Published var notesMode = false
    @Published private(set) var generating = false
    @Published private(set) var solved = false
    private let defaults = UserDefaults.standard
    private static let key = GameProgress.Keys.saved("sudoku")

    init() {
        if let data = defaults.data(forKey: Self.key), let kept = SudokuSave.decode(data) {
            save = kept
            solved = Sudoku.isSolved(kept.entries)
        }
    }

    var conflicts: Set<Int> { save.map { Sudoku.conflicts($0.entries) } ?? [] }
    var elapsed: Int { save?.elapsed ?? 0 }

    /// A fresh puzzle, made off the main thread (a hard one takes a moment).
    func newPuzzle(difficulty: GameDifficulty) {
        guard !generating else { return }
        generating = true
        solved = false
        selected = nil
        let seed = UInt64(max(0, Date().timeIntervalSinceReferenceDate * 1000))
        Task.detached(priority: .userInitiated) { [weak self] in
            let puzzle = Sudoku.generate(difficulty: difficulty, seed: seed)
            await MainActor.run {
                guard let self else { return }
                self.save = SudokuSave(difficulty: difficulty, givens: puzzle.givens, solution: puzzle.solution,
                                       entries: puzzle.givens, notes: [:], elapsed: 0)
                self.generating = false
                self.persist()
            }
        }
    }

    /// A digit for the selected cell: written, or as a pencil mark in notes mode; the same digit again clears it.
    func enter(_ digit: Int) {
        guard var kept = save, let i = selected, kept.givens[i] == 0, !solved else { return }
        if notesMode {
            var marks = Set(kept.notes[i] ?? [])
            if marks.contains(digit) { marks.remove(digit) } else { marks.insert(digit) }
            kept.notes[i] = marks.isEmpty ? nil : marks.sorted()
            kept.entries[i] = 0
        } else {
            kept.entries[i] = kept.entries[i] == digit ? 0 : digit
            kept.notes[i] = nil
        }
        save = kept
        if Sudoku.isSolved(kept.entries) { solved = true }
        persist()
    }

    func erase() {
        guard var kept = save, let i = selected, kept.givens[i] == 0, !solved else { return }
        kept.entries[i] = 0
        kept.notes[i] = nil
        save = kept
        persist()
    }

    /// One second more on the clock.
    func tick() {
        guard var kept = save, !solved, !generating else { return }
        kept.elapsed += 1
        save = kept
        if kept.elapsed % 5 == 0 { persist() }
    }

    func abandon() {
        save = nil
        solved = false
        selected = nil
        defaults.removeObject(forKey: Self.key)
    }

    private func persist() {
        if let data = save?.encoded() {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// Sudoku: tap a cell, then a digit on the pad (or a pencil mark with Notlar on); repeated digits
/// show softly in red; a solved grid stops the clock, and the best time of each difficulty is kept.
struct SudokuGame: View {
    @ObservedObject var store: GameProgressStore
    @StateObject private var model = SudokuModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recorded = false
    @State private var newBest = false

    var body: some View {
        if let kept = model.save {
            puzzle(kept)
        } else {
            start
        }
    }

    private var start: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "number.square")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.ink)
            Text(Loc.t("Her satır, sütun ve kutuda 1–9."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            DifficultyPicker(difficulty: Binding(get: { store[.sudoku].difficulty }, set: { store.setDifficulty($0, for: .sudoku) }))
            if let best = store[.sudoku].best[store[.sudoku].difficulty] {
                Text(Loc.t("En iyi süre: {0}", GameCorner.clock(best)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                recorded = false
                newBest = false
                model.newPuzzle(difficulty: store[.sudoku].difficulty)
            } label: {
                if model.generating {
                    ProgressView()
                        .tint(.white)
                        .frame(height: 20)
                } else {
                    Label(Loc.t("Yeni bulmaca"), systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .disabled(model.generating)
            Spacer(minLength: 0)
        }
    }

    private func puzzle(_ kept: SudokuSave) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(kept.difficulty.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(GameCorner.clock(model.elapsed))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .onChange(of: timeline.date) { _, _ in
                            if scenePhase == .active { model.tick() }
                        }
                }
                .accessibilityLabel(Loc.t("Süre: {0}", GameCorner.clock(model.elapsed)))
                Spacer()
                Button {
                    model.abandon()
                } label: {
                    Label(Loc.t("Yeni"), systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            ZStack {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    board(kept, side: side)
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if model.solved {
                    solvedCard(kept)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: model.solved)
            pad(kept)
        }
        .onChange(of: model.solved) { _, done in
            guard done, !recorded else { return }
            recorded = true
            newBest = store.record(.sudoku, score: kept.elapsed, at: kept.difficulty, lowerIsBetter: true)
        }
    }

    private func board(_ kept: SudokuSave, side: CGFloat) -> some View {
        let conflicts = model.conflicts
        let selected = model.selected
        let selectedDigit = selected.map { kept.entries[$0] } ?? 0
        return Canvas { context, size in
            let cell = size.width / 9
            for i in 0..<Sudoku.cells {
                let row = Sudoku.row(i)
                let col = Sudoku.col(i)
                let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                var tint: Color?
                if let selected {
                    if i == selected {
                        tint = Theme.ink.opacity(0.22)
                    } else if selectedDigit != 0, kept.entries[i] == selectedDigit {
                        tint = Theme.ink.opacity(0.14)
                    } else if Sudoku.row(selected) == row || Sudoku.col(selected) == col || Sudoku.box(selected) == Sudoku.box(i) {
                        tint = Theme.ink.opacity(0.06)
                    }
                }
                if conflicts.contains(i) { tint = Color.red.opacity(0.16) }
                if let tint { context.fill(Path(rect), with: .color(tint)) }
                let digit = kept.entries[i]
                if digit != 0 {
                    let given = kept.givens[i] != 0
                    context.draw(Text("\(digit)")
                                    .font(.system(size: cell * 0.55, weight: given ? .semibold : .regular, design: .rounded))
                                    .foregroundStyle(given ? Color.primary : Theme.ink),
                                 at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
                } else if let marks = kept.notes[i] {
                    for mark in marks {
                        let x = rect.minX + cell * (CGFloat((mark - 1) % 3) + 0.5) / 3
                        let y = rect.minY + cell * (CGFloat((mark - 1) / 3) + 0.5) / 3
                        context.draw(Text("\(mark)").font(.system(size: cell * 0.26)).foregroundStyle(.secondary),
                                     at: CGPoint(x: x, y: y), anchor: .center)
                    }
                }
            }
            var thin = Path()
            var thick = Path()
            for k in 0...9 {
                let at = CGFloat(k) * cell
                if k % 3 == 0 {
                    thick.move(to: CGPoint(x: at, y: 0))
                    thick.addLine(to: CGPoint(x: at, y: size.height))
                    thick.move(to: CGPoint(x: 0, y: at))
                    thick.addLine(to: CGPoint(x: size.width, y: at))
                } else {
                    thin.move(to: CGPoint(x: at, y: 0))
                    thin.addLine(to: CGPoint(x: at, y: size.height))
                    thin.move(to: CGPoint(x: 0, y: at))
                    thin.addLine(to: CGPoint(x: size.width, y: at))
                }
            }
            context.stroke(thin, with: .color(Theme.ink.opacity(0.25)), lineWidth: 0.6)
            context.stroke(thick, with: .color(Theme.ink.opacity(0.75)), lineWidth: 1.6)
        }
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onEnded { value in select(at: value.startLocation, side: side) }
        )
        .accessibilityLabel(Loc.t("Sudoku tahtası"))
    }

    private func select(at point: CGPoint, side: CGFloat) {
        guard side > 0, !model.solved else { return }
        let col = Int(point.x / (side / 9))
        let row = Int(point.y / (side / 9))
        guard (0..<9).contains(col), (0..<9).contains(row) else { return }
        model.selected = row * 9 + col
    }

    private func pad(_ kept: SudokuSave) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(1...9, id: \.self) { digit in
                    let placed = kept.entries.filter { $0 == digit }.count
                    Button {
                        model.enter(digit)
                    } label: {
                        Text("\(digit)")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(placed >= 9 ? Color.secondary : Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.ink.opacity(0.1)))
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Loc.t("Rakam {0}", "\(digit)"))
                }
            }
            HStack(spacing: 8) {
                Toggle(isOn: $model.notesMode) {
                    Label(Loc.t("Notlar"), systemImage: "pencil.line")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.button)
                .tint(Theme.ink)
                Button {
                    model.erase()
                } label: {
                    Label(Loc.t("Sil"), systemImage: "delete.left")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                Spacer()
                Text(model.notesMode ? Loc.t("Not modu: küçük rakamlar") : Loc.t("Hücreye dokun, rakamı seç"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func solvedCard(_ kept: SudokuSave) -> some View {
        VStack(spacing: 8) {
            Text(Loc.t("Çözüldü!"))
                .font(Theme.display(.title3))
            Text(Loc.t("Süre: {0}", GameCorner.clock(kept.elapsed)))
                .font(.headline)
            if newBest {
                Text(Loc.t("Yeni rekor!"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            Button {
                model.abandon()
            } label: {
                Label(Loc.t("Yeni bulmaca"), systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
        }
        .padding(16)
        .glassCard(radius: 18)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
    }
}
