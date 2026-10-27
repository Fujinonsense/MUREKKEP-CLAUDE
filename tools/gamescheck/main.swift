import Foundation

// Runs the break corner's game logic (Murekkep.swiftpm/MiniGameLogic.swift) on Windows.
// usage: check.exe

var failures = 0

func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { failures += 1 }
}

func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: Double = 1e-6) -> Bool {
    abs(Double(a.x - b.x)) < tolerance && abs(Double(a.y - b.y)) < tolerance
}

// MARK: Ink mandala (MandalaSymmetry)

let centre = CGPoint(x: 150, y: 150)
let tip = CGPoint(x: 190, y: 120)
let copies = MandalaSymmetry.copies(of: tip, around: centre)
check(copies.count == 16, "mandala: eight turns, each with its mirror (\(copies.count))")
check(close(copies[0], tip), "mandala: the first copy is the point itself")
let reach = 50.0
func fromCentre(_ p: CGPoint) -> Double {
    let dx = Double(p.x) - Double(centre.x)
    let dy = Double(p.y) - Double(centre.y)
    return (dx * dx + dy * dy).squareRoot()
}
check(copies.allSatisfy { abs(fromCentre($0) - reach) < 1e-6 }, "mandala: every copy is as far from the centre")
check(close(copies[1], CGPoint(x: 110, y: 120)), "mandala: the mirror image stands across the vertical axis (\(copies[1]))")
let c45 = cos(Double.pi / 4)
let s45 = sin(Double.pi / 4)
let turnedTip = CGPoint(x: 150 + 40 * c45 + 30 * s45, y: 150 + 40 * s45 - 30 * c45)
check(close(copies[2], turnedTip), "mandala: the second turn is 45° on")
check(close(copies[8], CGPoint(x: 110, y: 180)), "mandala: half a turn is the point through the centre (\(copies[8]))")
// The set is closed: turning any copy by 45° gives another copy, as does mirroring it.
let turned = copies.map { p -> CGPoint in
    let dx = Double(p.x) - Double(centre.x)
    let dy = Double(p.y) - Double(centre.y)
    return CGPoint(x: Double(centre.x) + dx * c45 - dy * s45, y: Double(centre.y) + dx * s45 + dy * c45)
}
check(turned.allSatisfy { t in copies.contains { close($0, t, 1e-6) } }, "mandala: the flower looks the same turned by 45°")
let mirrored = copies.map { CGPoint(x: 2 * centre.x - $0.x, y: $0.y) }
check(mirrored.allSatisfy { m in copies.contains { close($0, m, 1e-6) } }, "mandala: the flower looks the same in a mirror")
check(MandalaSymmetry.copies(of: centre, around: centre).allSatisfy { close($0, centre) }, "mandala: the centre stays put")
check(MandalaSymmetry.copies(of: tip, around: centre, folds: 6).count == 12, "mandala: other fold counts")
check(MandalaSymmetry.hue(at: 0) == 0 && abs(MandalaSymmetry.hue(at: 12) - 0.5) < 1e-9 && abs(MandalaSymmetry.hue(at: 30) - 0.25) < 1e-9,
      "mandala: the hue goes once round in 24 s")
check(MandalaSymmetry.hue(at: -6) > 0.74 && MandalaSymmetry.hue(at: -6) < 0.76, "mandala: a negative time still gives a hue in 0…1")

// MARK: Ink bubbles (BubbleField)

let fieldSize = CGSize(width: 300, height: 320)
var field = BubbleField(size: fieldSize, seed: 7)
check(field.bubbles.isEmpty && field.score == 0 && field.timeLeft == 60 && !field.isOver && field.combo == 1, "bubbles: an empty field at the start")
check(abs(field.spawnInterval - 1.0) < 1e-9 && abs(field.riseSpeed - 44) < 1e-9 && field.radiusRange == 11...28 && abs(field.blotShare - 0.12) < 1e-9,
      "bubbles: gentle at the start")
for _ in 0..<40 { field.advance(by: 1.0 / 20) }
check(abs(field.elapsed - 2) < 1e-9, "bubbles: two seconds in (\(field.elapsed))")
check(field.bubbles.count >= 2, "bubbles: bubbles have come up (\(field.bubbles.count))")
check(field.bubbles.allSatisfy { $0.x >= $0.radius && $0.x <= Double(fieldSize.width) - $0.radius }, "bubbles: every bubble is inside the width")
check(field.bubbles.allSatisfy { $0.kind == .blot ? ($0.radius >= 13 && $0.radius <= 21) : ($0.radius >= 11 && $0.radius <= 28) }, "bubbles: sizes in range")
check(field.bubbles.allSatisfy { $0.y < Double(fieldSize.height) + $0.radius }, "bubbles: they rise from the bottom")
check(Set(field.bubbles.map(\.id)).count == field.bubbles.count, "bubbles: every bubble has its own id")
let same = { () -> BubbleField in
    var f = BubbleField(size: fieldSize, seed: 7)
    for _ in 0..<40 { f.advance(by: 1.0 / 20) }
    return f
}()
check(same == field, "bubbles: the same seed gives the same field")

// A step never jumps further than a tenth of a second (a pause, a slow frame).
var jumped = field
jumped.advance(by: 5)
check(abs(jumped.elapsed - 2.1) < 1e-9, "bubbles: a long gap moves the field by 0.1 s only (\(jumped.elapsed))")
var still = field
still.advance(by: 0)
still.advance(by: -1)
check(still == field, "bubbles: zero or negative steps change nothing")

// Popping: the bubble under the touch goes, the nearest when two are close, nothing far away.
let target = field.bubbles.first { $0.kind == .ink }!
let before = field.bubbles.count
let firstPop = field.pop(at: CGPoint(x: target.x + target.radius + 8, y: target.y))
check(firstPop == .popped(points: target.worth, combo: 1) && field.bubbles.count == before - 1 && !field.bubbles.contains(target),
      "bubbles: a touch beside the bubble's edge pops it")
check(field.score == target.worth && field.popped == 1 && field.splashes.count == 1 && !field.splashes[0].blot, "bubbles: the pop is scored and splashes")
let worthRight = (target.radius < 15 && target.worth == 3) || (target.radius >= 15 && target.radius < 21 && target.worth == 2) || (target.radius >= 21 && target.worth == 1)
check(worthRight, "bubbles: small bubbles are worth three, middling two, big one")
check(field.pop(at: CGPoint(x: -500, y: -500)) == .miss && field.score == target.worth && field.combo == 1, "bubbles: a touch on nothing scores nothing and breaks the row")
var crowd = BubbleField(size: fieldSize, seed: 1)
for _ in 0..<200 { crowd.advance(by: 1.0 / 30) }
let inkOnly = crowd.bubbles.filter { $0.kind == .ink }
if inkOnly.count >= 2 {
    let a = inkOnly[0]
    let b = inkOnly[1]
    let nearA = CGPoint(x: a.x + (b.x - a.x) * 0.1, y: a.y + (b.y - a.y) * 0.1)
    crowd.pop(at: nearA)
    let aGone = !crowd.bubbles.contains(a)
    let bStays = crowd.bubbles.contains(b)
    check(aGone && bStays, "bubbles: the nearest bubble pops")
}

// A row of quick pops multiplies: ×2, ×3, ×4 and no more; a slow one starts over.
var rowField = BubbleField(size: fieldSize, seed: 1)
var rowSeed: UInt64 = 1
while rowField.bubbles.filter({ $0.kind == .ink }).count < 5 && rowSeed < 200 {
    rowSeed += 1
    rowField = BubbleField(size: fieldSize, seed: rowSeed)
    for _ in 0..<100 { rowField.advance(by: 1.0 / 20) }
}
var combos: [Int] = []
var multipliers: [Int] = []
for bubble in rowField.bubbles.filter({ $0.kind == .ink }).prefix(5) {
    if case .popped(let points, let combo) = rowField.pop(at: CGPoint(x: bubble.x, y: bubble.y)) {
        combos.append(combo)
        multipliers.append(points / bubble.worth)
    }
}
check(combos == [1, 2, 3, 4, 4] && multipliers == combos, "bubbles: a row of quick pops multiplies ×2, ×3, ×4 and stays there (\(combos))")
check(rowField.combo == 4 && rowField.popped == 5, "bubbles: the row is kept (\(rowField.combo))")
for _ in 0..<12 { rowField.advance(by: 0.1) }
if let late = rowField.bubbles.first(where: { $0.kind == .ink }) {
    if case .popped(_, let combo) = rowField.pop(at: CGPoint(x: late.x, y: late.y)) {
        check(combo == 1, "bubbles: a pop after more than 0.9 s starts a new row (\(combo))")
    } else {
        check(false, "bubbles: the late pop")
    }
}

// Blots: a touch costs five points and three seconds and breaks the row.
var blotField = BubbleField(size: fieldSize, seed: 2)
var blotSeed: UInt64 = 2
while !blotField.bubbles.contains(where: { $0.kind == .blot }) && blotSeed < 300 {
    blotSeed += 1
    blotField = BubbleField(size: fieldSize, seed: blotSeed)
    for _ in 0..<80 { blotField.advance(by: 1.0 / 20) }
}
let blot = blotField.bubbles.first { $0.kind == .blot }!
let scoreBefore = blotField.score
let leftBefore = blotField.timeLeft
let touched = blotField.pop(at: CGPoint(x: blot.x, y: blot.y))
check(touched == .blot(points: 5, seconds: 3) && blotField.blotsHit == 1 && blotField.combo == 1, "bubbles: a touched blot costs (\(String(describing: touched)))")
check(blotField.score == max(0, scoreBefore - 5) && abs(blotField.timeLeft - (leftBefore - 3)) < 1e-9 && blotField.splashes.last?.blot == true,
      "bubbles: five points and three seconds gone, a dark splash")
check(blot.worth == 0, "bubbles: a blot is worth nothing")

// Splashes fade, bubbles that reach the top leave and break the row, the pace picks up and the bubbles shrink.
var fading = field
for _ in 0..<12 { fading.advance(by: 0.05) }
check(fading.splashes.isEmpty, "bubbles: a splash is gone after half a second")
var long = BubbleField(size: fieldSize, seed: 3)
for _ in 0..<(30 * 30) { long.advance(by: 1.0 / 30) }
check(abs(long.elapsed - 30) < 1e-6 && abs(long.difficulty - 0.5) < 1e-6, "bubbles: half way (\(long.elapsed))")
check(abs(long.spawnInterval - 0.675) < 1e-6 && abs(long.riseSpeed - 82) < 1e-6 && abs(long.radiusRange.upperBound - 23.1) < 1e-6 && abs(long.blotShare - 0.21) < 1e-6,
      "bubbles: the pace picks up and the bubbles shrink half way (\(long.spawnInterval), \(long.riseSpeed))")
check(long.bubbles.allSatisfy { $0.y + $0.radius >= 0 } && long.escaped > 0 && long.combo == 1, "bubbles: bubbles over the top are gone and counted (\(long.escaped))")
check(long.bubbles.count < 60, "bubbles: the field does not fill up (\(long.bubbles.count))")
for _ in 0..<(31 * 30) { long.advance(by: 1.0 / 30) }
check(long.isOver && long.timeLeft == 0 && abs(long.elapsed - 60) < 1e-6, "bubbles: the round ends at 60 s (\(long.elapsed))")
check(abs(long.spawnInterval - 0.35) < 1e-9 && abs(long.riseSpeed - 120) < 1e-9 && abs(long.radiusRange.lowerBound - 7.15) < 1e-9 && abs(long.blotShare - 0.3) < 1e-9,
      "bubbles: hardest at the end")
let frozen = long
long.advance(by: 0.5)
let lastBubble = long.bubbles.first
let popAfterEnd = long.pop(at: CGPoint(x: lastBubble?.x ?? 0, y: lastBubble?.y ?? 0))
check(long == frozen && popAfterEnd == .miss, "bubbles: nothing moves or pops after the end")
// Blots' seconds shorten the round.
var shortened = blotField
for _ in 0..<2000 where !shortened.isOver { shortened.advance(by: 0.1) }
check(shortened.isOver && abs(shortened.elapsed - 57) < 1e-6, "bubbles: a blot's three seconds end the round sooner (\(shortened.elapsed))")
check(BubbleField.bestKey == "breakBubblesBest", "bubbles: the best score's old key")

// MARK: XOX (TicTacToe)

var board = TicTacToe()
check(board.turn == .x && board.outcome == nil && board.free.count == 9, "xox: a new board, X to play")
check(board.play(4) && board.cells[4] == .x && board.turn == .o, "xox: X plays the centre")
check(!board.play(4) && board.turn == .o, "xox: a taken cell is refused")
check(!board.play(9) && !board.play(-1), "xox: cells outside the board are refused")
check(board.play(0) && board.play(1) && board.play(8) && board.play(7), "xox: moves in turn")
check(board.outcome == .won(.x, line: [1, 4, 7]), "xox: a column wins (\(String(describing: board.outcome)))")
check(board.isOver && !board.play(2), "xox: no move after the end")

func played(_ moves: [Int], first: TicTacToe.Mark = .x) -> TicTacToe {
    var b = TicTacToe(first: first)
    for m in moves { b.play(m) }
    return b
}
check(played([0, 3, 1, 4, 2]).outcome == .won(.x, line: [0, 1, 2]), "xox: a row wins")
check(played([0, 4, 1, 2, 3, 6]).outcome == .won(.o, line: [2, 4, 6]), "xox: a diagonal wins for O")
check(played([0, 1, 2, 4, 3, 5, 7, 6, 8]).outcome == .draw, "xox: a full board without a line is a draw")
check(played([0, 1, 2, 4, 3, 5, 7, 6]).outcome == nil, "xox: one cell left, no result yet")
check(played([], first: .o).turn == .o, "xox: O can start")

var rng = GameRandom(seed: 11)
check(played([0, 3, 1]).winningCell(for: .x) == 2 && played([0, 3, 1]).winningCell(for: .o) == nil, "xox: the cell that completes a line")
check(played([0, 3, 1, 4]).bestMove(for: .x, rng: &rng, whim: 1) == 2, "xox: the iPad takes a win, whatever its whim")
check(played([0, 3, 1]).bestMove(for: .o, rng: &rng, whim: 1) == 2, "xox: the iPad blocks, whatever its whim")
check(played([0, 2, 4, 8, 3]).bestMove(for: .o, rng: &rng, whim: 1) == 5, "xox: a block comes before anything else")
check(played([0]).bestMove(for: .o, rng: &rng, whim: 0) == 4, "xox: the centre when it is free")
let cornerMove = played([4]).bestMove(for: .o, rng: &rng, whim: 0)
check(cornerMove.map { TicTacToe.corners.contains($0) } == true, "xox: a corner when the centre is taken (\(cornerMove.map(String.init) ?? "nil"))")
// A fork: X threatens 3 and 7 at once; the iPad blocks one of them (an edge), not a corner.
let forkReply = played([0, 4, 8, 2, 6]).bestMove(for: .o, rng: &rng, whim: 0)
check(forkReply == 3 || forkReply == 7, "xox: a fork is still answered with a block (\(forkReply.map(String.init) ?? "nil"))")
let rowWin = played([0, 4, 2, 1, 6, 3, 8]).bestMove(for: .o, rng: &rng, whim: 0)
check(rowWin == 5, "xox: with the centre and the corners gone, O still takes its row (\(rowWin.map(String.init) ?? "nil"))")
check(played([0, 1, 2, 4, 3, 5, 7, 6, 8]).bestMove(for: .x, rng: &rng) == nil, "xox: no move on a finished board")
var whimsy = Set<Int>()
for _ in 0..<40 {
    if let m = played([0]).bestMove(for: .o, rng: &rng, whim: 0.5) { whimsy.insert(m) }
}
check(whimsy.contains(4) && whimsy.count > 1 && whimsy.allSatisfy { $0 != 0 }, "xox: a little whim varies the reply, always to a free cell (\(whimsy.sorted()))")

// Beatable: the corner trap. X corner, O centre, X the opposite corner; the iPad takes a corner,
// X blocks and forks, and wins however the iPad answers.
var trap = TicTacToe()
trap.play(0)
check(trap.bestMove(for: .o, rng: &rng, whim: 0) == 4, "xox trap: O takes the centre")
trap.play(4)
trap.play(8)
let reply = trap.bestMove(for: .o, rng: &rng, whim: 0)!
check(TicTacToe.corners.contains(reply), "xox trap: O takes a corner (\(reply))")
trap.play(reply)
let fork = trap.bestMove(for: .x, rng: &rng, whim: 0)!
trap.play(fork)
check(trap.outcome == nil, "xox trap: X blocks (\(fork))")
let block = trap.bestMove(for: .o, rng: &rng, whim: 0)!
trap.play(block)
let finish = trap.bestMove(for: .x, rng: &rng, whim: 0)!
trap.play(finish)
var xWon = false
if case .won(.x, _)? = trap.outcome { xWon = true }
check(xWon, "xox trap: X wins, so the iPad can be beaten")

// The iPad against itself always ends, in a draw or a win, never in an illegal move.
var ended = 0
var draws = 0
for seed in 1...200 {
    var r = GameRandom(seed: UInt64(seed))
    var g = TicTacToe(first: seed % 2 == 0 ? .x : .o)
    var moves = 0
    while !g.isOver, moves < 9 {
        guard let m = g.bestMove(for: g.turn, rng: &r, whim: 0.3), g.play(m) else { break }
        moves += 1
    }
    if g.isOver { ended += 1 }
    if g.outcome == .draw { draws += 1 }
}
check(ended == 200, "xox: 200 games against itself all end (\(ended))")
check(draws > 20 && draws < 200, "xox: some draws, some wins, with the whim (\(draws) draws)")

// MARK: XOX difficulties (TicTacToe.move, perfectMoves)

check(TicTacToe().perfectMoves(for: .x).count == 9, "xox zor: every first move is as good as another")
check(played([0, 4, 8]).perfectMoves(for: .o).sorted() == [1, 3, 5, 7], "xox zor: against two corners only an edge holds the draw")
check(played([0, 4, 8, 2]).perfectMoves(for: .x) == [6], "xox zor: the block comes first")
check(played([0, 4, 1]).perfectMoves(for: .o) == [2], "xox zor: a win is taken at once")
// Zor never loses, whatever a random player does, as X or as O.
var zorLost = 0
var zorWon = 0
for seed in 1...300 {
    var r = GameRandom(seed: UInt64(seed))
    let device: TicTacToe.Mark = seed % 2 == 0 ? .o : .x
    var g = TicTacToe(first: .x)
    while !g.isOver {
        let cell = g.turn == device ? g.move(for: device, difficulty: .hard, rng: &r)! : g.free.randomElement(using: &r)!
        g.play(cell)
    }
    if case .won(let w, _)? = g.outcome {
        if w == device { zorWon += 1 } else { zorLost += 1 }
    }
}
check(zorLost == 0 && zorWon > 100, "xox zor: never loses to a random player (\(zorLost) lost, \(zorWon) won of 300)")
// Kolay loses to the Orta heuristic now and then; Orta never loses to Kolay's whims badly enough to matter.
var kolayLost = 0
for seed in 1...300 {
    var r = GameRandom(seed: UInt64(seed) &* 7)
    var g = TicTacToe(first: seed % 2 == 0 ? .x : .o)
    while !g.isOver {
        let cell = g.turn == .o ? g.move(for: .o, difficulty: .easy, rng: &r)! : g.move(for: .x, difficulty: .medium, rng: &r)!
        g.play(cell)
    }
    if case .won(.x, _)? = g.outcome { kolayLost += 1 }
}
check(kolayLost > 60, "xox kolay: mostly random, so it loses often (\(kolayLost) of 300)")
check(played([0, 3, 1]).move(for: .o, difficulty: .medium, rng: &rng) == 2, "xox orta: is today's heuristic")
var easyMoves = Set<Int>()
for _ in 0..<60 {
    if let m = played([0, 3, 1]).move(for: .o, difficulty: .easy, rng: &rng) { easyMoves.insert(m) }
}
check(easyMoves.count > 3 && easyMoves.contains(2), "xox kolay: sometimes blocks, often wanders (\(easyMoves.sorted()))")

// MARK: Bubbles at each difficulty (BubbleField.Tuning)

check(BubbleField.pace(.easy) == 0.8 && BubbleField.pace(.medium) == 1 && BubbleField.pace(.hard) == 1.3, "bubbles: the paces")
let kolayTuning = BubbleField.Tuning.tuning(.easy)
let zorTuning = BubbleField.Tuning.tuning(.hard)
check(kolayTuning.reach > BubbleField.Tuning.tuning(.medium).reach && zorTuning.reach < BubbleField.Tuning.tuning(.medium).reach, "bubbles: kolay forgives a wider touch, zor a narrower")
check(kolayTuning.blotsAtEnd < BubbleField.Tuning.tuning(.medium).blotsAtEnd && zorTuning.blotsAtStart > BubbleField.Tuning.tuning(.medium).blotsAtStart, "bubbles: zor has more blots")
let hardField = BubbleField(size: fieldSize, seed: 7, difficulty: .hard)
check(abs(hardField.spawnInterval - 1.0 / 1.3) < 1e-9 && abs(hardField.riseSpeed - 44 * 1.3) < 1e-9 && abs(hardField.blotShare - 0.18) < 1e-9, "bubbles zor: faster to come and rise")
let easyField = BubbleField(size: fieldSize, seed: 7, difficulty: .easy)
check(abs(easyField.spawnInterval - 1.0 / 0.8) < 1e-9 && abs(easyField.riseSpeed - 44 * 0.8) < 1e-9 && abs(easyField.blotShare - 0.06) < 1e-9, "bubbles kolay: slower, fewer blots")
check(BubbleField(size: fieldSize, seed: 7) == BubbleField(size: fieldSize, seed: 7, difficulty: .medium) && BubbleField(size: fieldSize, seed: 7).pace == 1,
      "bubbles: orta is the default")
// Over a whole round at Orta, more comes up than anyone pops: the field keeps the player busy.
var busy = BubbleField(size: fieldSize, seed: 9)
var spawned = 0
var lastID = 0
for _ in 0..<(60 * 30) {
    busy.advance(by: 1.0 / 30)
    if let newest = busy.bubbles.map(\.id).max(), newest > lastID {
        spawned += newest - lastID
        lastID = newest
    }
}
check(spawned >= 95 && spawned <= 130, "bubbles orta: about a hundred bubbles in a round (\(spawned))")

// MARK: Progression (GameProgress)

var progress = GameProgress()
check(progress.unlockedLevel == 1 && progress.isUnlocked(1) && !progress.isUnlocked(2) && progress.difficulty == .medium, "progress: a fresh game")
progress.complete(level: 1, stars: 2, levels: 12)
check(progress.unlockedLevel == 2 && progress.stars(at: 1) == 2 && progress.totalStars == 2, "progress: a finished level opens the next")
progress.complete(level: 1, stars: 1, levels: 12)
check(progress.stars(at: 1) == 2, "progress: stars never go down")
progress.complete(level: 1, stars: 3, levels: 12)
check(progress.stars(at: 1) == 3 && progress.unlockedLevel == 2, "progress: better stars are kept")
progress.complete(level: 2, stars: 0, levels: 12)
check(progress.unlockedLevel == 2 && progress.stars(at: 2) == 0, "progress: a failed level opens nothing")
progress.complete(level: 12, stars: 5, levels: 12)
check(progress.unlockedLevel == 12 && progress.stars(at: 12) == 3, "progress: the last level stays last, stars stop at three")
check(progress.record(score: 0, at: .medium) == false && progress.best[.medium] == 0, "progress: a first score of nothing is no record")
check(progress.record(score: 12, at: .medium) && progress.record(score: 12, at: .medium) == false && progress.record(score: 13, at: .medium),
      "progress: a higher score is a record")
check(progress.record(score: 300, at: .hard, lowerIsBetter: true) && progress.record(score: 250, at: .hard, lowerIsBetter: true)
      && !progress.record(score: 260, at: .hard, lowerIsBetter: true) && progress.best[.hard] == 250, "progress: a shorter time is a record")
check(progress.best[.easy] == nil, "progress: each difficulty has its own best")
check(GameProgress.Keys.unlocked("flyer") == "break.flyer.unlocked" && GameProgress.Keys.stars("shooter") == "break.shooter.stars"
      && GameProgress.Keys.best("bubbles", .hard) == "break.bubbles.best.hard" && GameProgress.Keys.difficulty("xox") == "break.xox.difficulty"
      && GameProgress.Keys.saved("sudoku") == "break.sudoku.saved" && GameProgress.Keys.legacyBubblesBest == BubbleField.bestKey, "progress: the keys")

// MARK: The panel's one larger step (GamePanelSize)

check(GamePanelSize.compact == CGSize(width: 340, height: 420) && GamePanelSize.larger == CGSize(width: 400, height: 500), "panel: the two sizes")
let roomy = GamePanelSize.larger(in: CGSize(width: 1180, height: 760), leading: 72, trailing: 12, top: 12, bottom: 104)
check(roomy == CGSize(width: 400, height: 500), "panel: a landscape iPad gets the full larger step (\(roomy))")
let tight = GamePanelSize.larger(in: CGSize(width: 1080, height: 700), leading: 72, trailing: 12, top: 12, bottom: 104)
check(Double(tight.width) * Double(tight.height) <= 1080.0 * 700 / 4 + 1 && tight.width < 400 && tight.height < 500 && tight.width >= 340,
      "panel: a smaller canvas gets at most a quarter of itself (\(tight))")
check(abs(Double(tight.width) / Double(tight.height) - 0.8) < 0.01, "panel: the larger step keeps its shape when it shrinks")
let low = GamePanelSize.larger(in: CGSize(width: 1180, height: 600), leading: 72, trailing: 12, top: 12, bottom: 104)
check(low.height <= 484 && Double(low.width) * Double(low.height) <= 1180.0 * 600 / 4 + 1 && low.height > 420, "panel: a low canvas keeps the panel under its top (\(low))")
check(GamePanelSize.larger(in: CGSize(width: 700, height: 600), leading: 72, trailing: 12, top: 12, bottom: 104) == GamePanelSize.compact,
      "panel: when a quarter is less than compact, the panel stays compact")
check(GamePanelSize.larger(in: CGSize(width: 320, height: 900), leading: 12, trailing: 12, top: 12, bottom: 104) == GamePanelSize.compact,
      "panel: a slide-over window stays compact")

// MARK: Uçan damla (FlyerWorld)

let sky = CGSize(width: 316, height: 290)
let easyFlight = FlyerSettings.settings(difficulty: .easy, level: 1)
let hardFlight = FlyerSettings.settings(difficulty: .hard, level: 1)
check(hardFlight.speed > easyFlight.speed && hardFlight.gap < easyFlight.gap && hardFlight.gravity > easyFlight.gravity, "flyer: zor is faster, tighter, heavier")
check(FlyerSettings.settings(difficulty: .medium, level: 12).speed > FlyerSettings.settings(difficulty: .medium, level: 1).speed
      && FlyerSettings.settings(difficulty: .medium, level: 12).gap < FlyerSettings.settings(difficulty: .medium, level: 1).gap, "flyer: later levels tighten")
check(FlyerWorld.goal(level: 1) == 6 && FlyerWorld.goal(level: 12) == 28 && FlyerWorld.levels == 12, "flyer: the levels' lengths")
var world = FlyerWorld(size: sky, level: 3, difficulty: .medium, seed: 5)
check(world.phase == .ready && world.obstacles.count == 10 && world.lives == 3 && world.passed == 0, "flyer: a level waits for the first tap")
check(world.obstacles.allSatisfy { $0.top >= 30 && $0.bottom <= 260 }, "flyer: every gap is inside the page")
check(zip(world.obstacles, world.obstacles.dropFirst()).allSatisfy { abs($0.gapY - $1.gapY) <= 0.38 * 290 + 1e-9 }, "flyer: gaps stay within reach of each other")
check(zip(world.obstacles, world.obstacles.dropFirst()).allSatisfy { abs(($1.x - $0.x) - world.settings.spacing) < 1e-9 }, "flyer: evenly spaced")
check(world.flagX > world.obstacles.last!.x, "flyer: the flag stands after the last pencil")
check(FlyerWorld(size: sky, level: 3, difficulty: .medium, seed: 5) == world, "flyer: the same seed gives the same level")
world.advance(by: 0.5)
check(world.phase == .ready && world.dropY == 145 && world.elapsed == 0, "flyer: nothing moves before the first tap")
world.flap()
check(world.phase == .flying && world.velocity < 0, "flyer: the first tap starts the flight upwards")
var fallen = world
for _ in 0..<60 { fallen.advance(by: 1.0 / 30) }
check(fallen.lives == 2 && fallen.graceLeft > 0, "flyer: a drop that falls to the floor costs one life, then bounces safely for a moment (\(fallen.lives))")
var crashed = world
for _ in 0..<600 where crashed.phase == .flying { crashed.advance(by: 1.0 / 30) }
check(crashed.phase == .failed && crashed.lives == 0, "flyer: three falls end the level")
// Collisions: in the gap is safe, on the pencil is not.
let pencil = FlyerObstacle(id: 0, x: world.dropX, gapY: 150, gap: 120, kind: .pencilBelow)
func dropAt(_ y: Double) -> FlyerWorld {
    var w = FlyerWorld(size: sky, level: 1, difficulty: .medium, seed: 1)
    w.flap()
    // the drop falls from 145 by gravity; steer by stepping until it is near y
    var steps = 0
    while w.dropY < y && steps < 200 { w.advance(by: 0.01); steps += 1 }
    return w
}
check(!dropAt(150).collides(pencil), "flyer: the drop in the gap is safe")
check(dropAt(230).collides(pencil), "flyer: the drop on the pencil is hit")
check(!dropAt(230).collides(FlyerObstacle(id: 1, x: world.dropX + 60, gapY: 150, gap: 120, kind: .pencilAbove)), "flyer: a pencil elsewhere does not touch")
// An autopilot that taps when below the next gap's centre flies every level at every difficulty with all three drops.
func autopilot(level: Int, difficulty: GameDifficulty) -> FlyerWorld {
    var w = FlyerWorld(size: sky, level: level, difficulty: difficulty, seed: UInt64(level * 31 + 1))
    w.flap()
    var steps = 0
    while w.phase == .flying && steps < 20_000 {
        let target = w.obstacles.first { !$0.passed && $0.x + FlyerObstacle.width / 2 >= w.dropX - FlyerWorld.dropRadius }?.gapY ?? Double(sky.height) / 2
        if w.dropY > target + 10 && w.velocity > 0 { w.flap() }
        w.advance(by: 1.0 / 60)
        steps += 1
    }
    return w
}
for difficulty in GameDifficulty.allCases {
    var cleared = 0
    var starsGot = 0
    for level in 1...FlyerWorld.levels {
        let w = autopilot(level: level, difficulty: difficulty)
        if w.phase == .complete { cleared += 1 }
        starsGot += w.stars
    }
    check(cleared == FlyerWorld.levels && starsGot >= FlyerWorld.levels * 3 - 2, "flyer \(difficulty.rawValue): every level can be flown with three drops (\(cleared) cleared, \(starsGot) stars)")
}
let flown = autopilot(level: 2, difficulty: .medium)
check(flown.passed == flown.goal && flown.progress == 1 && flown.isOver, "flyer: every pencil counts once (\(flown.passed) of \(flown.goal))")
var late = flown
late.flap()
late.advance(by: 0.1)
check(late == flown, "flyer: nothing moves after the flag")

// MARK: Renk patlat (HexGrid, ShooterLevels, ShooterBoard)

let hex = HexGrid(cols: 9, radius: 16)
check(hex.width == 288 && abs(hex.rowHeight - 27.7128) < 1e-3 && hex.width(ofRow: 0) == 9 && hex.width(ofRow: 1) == 8, "shooter: the honeycomb's measures")
check(ShooterBoard.deadRow == 9, "shooter: the dead row leaves eight rows of play in the compact panel")
check(hex.centre(ShooterCell(0, 0)) == CGPoint(x: 16, y: 16) && hex.centre(ShooterCell(1, 0)) == CGPoint(x: 32, y: 16 + hex.rowHeight), "shooter: odd rows stand half a cell right")
check(Set(hex.neighbours(of: ShooterCell(2, 3))) == [ShooterCell(2, 2), ShooterCell(2, 4), ShooterCell(1, 2), ShooterCell(1, 3), ShooterCell(3, 2), ShooterCell(3, 3)],
      "shooter: an even cell's six neighbours")
check(Set(hex.neighbours(of: ShooterCell(1, 0))) == [ShooterCell(1, 1), ShooterCell(0, 0), ShooterCell(0, 1), ShooterCell(2, 0), ShooterCell(2, 1)],
      "shooter: an odd cell at the edge has five")
check(hex.neighbours(of: ShooterCell(0, 8)).allSatisfy(hex.contains) && !hex.contains(ShooterCell(1, 8)) && !hex.contains(ShooterCell(-1, 0)), "shooter: the edges")
check(hex.nearestFreeCell(to: CGPoint(x: 33, y: 42), taken: []) == ShooterCell(1, 0)
      && hex.nearestFreeCell(to: CGPoint(x: 33, y: 42), taken: [ShooterCell(1, 0)]) != ShooterCell(1, 0), "shooter: the nearest free cell")
check(ShooterLevels.count >= 12, "shooter: at least twelve levels (\(ShooterLevels.count))")
for (i, level) in ShooterLevels.all.enumerated() {
    var board = ShooterBoard(level: level, difficulty: .medium, seed: 1)
    let count = board.cells.count
    let rowsFit = level.rows.count <= 8 && level.rows.enumerated().allSatisfy { r, text in text.count <= hex.width(ofRow: r) }
    let hanging = board.fallOrphans(grid: hex).isEmpty
    check(count >= 12 && rowsFit && hanging && level.shots >= 8 && level.shots <= 24 && board.cells.keys.allSatisfy { $0.row < ShooterBoard.deadRow - 1 },
          "shooter level \(i + 1): \(count) bubbles, all hanging from the top, \(level.shots) shots")
}
let first = ShooterLevels.all[0]
let kolayBoard = ShooterBoard(level: first, difficulty: .easy, seed: 1)
let ortaBoard = ShooterBoard(level: first, difficulty: .medium, seed: 1)
let zorBoard = ShooterBoard(level: first, difficulty: .hard, seed: 1)
check(kolayBoard.colours == 3 && ortaBoard.colours == 4 && zorBoard.colours == 5, "shooter: three, four, five colours")
check(kolayBoard.coloursOnBoard.count <= 3 && zorBoard.coloursOnBoard.contains(4) && !ortaBoard.coloursOnBoard.contains(4), "shooter: the colours on the board follow")
check(kolayBoard.shotsLeft == 16 && ortaBoard.shotsLeft == 10 && zorBoard.shotsLeft == 7, "shooter: the shots per difficulty")
check(ShooterBoard.shots(5, .hard) == 4, "shooter: zor keeps at least four shots")
check(ortaBoard.coloursOnBoard.contains(ortaBoard.loaded) && ortaBoard.coloursOnBoard.contains(ortaBoard.next), "shooter: the pen holds a colour that is on the board")
// A tiny level: one bubble at the top middle; a shot straight up lands beside it.
let one = ShooterLevel(rows: ["....R...."], shots: 5)
var tiny = ShooterBoard(level: one, difficulty: .easy, seed: 3)
let launch = CGPoint(x: hex.width / 2, y: 11 * hex.rowHeight)
let up = tiny.flight(from: launch, direction: CGPoint(x: 0, y: -1), grid: hex)
check(up.landing.row == 1 && (up.landing.col == 3 || up.landing.col == 4), "shooter: straight up lands under the bubble (\(up.landing))")
check(up.path.first == launch && up.path.count > 5 && up.path.last!.y > hex.radius && abs(Double(up.path.last!.x) - hex.width / 2) < 1e-9, "shooter: the path runs straight")
let slant = tiny.flight(from: launch, direction: CGPoint(x: 0.8, y: -0.6), grid: hex)
check(slant.path.allSatisfy { Double($0.x) <= hex.width - hex.radius + 1e-9 && Double($0.x) >= hex.radius - 1e-9 } && slant.path.contains { Double($0.x) > hex.width - hex.radius - 4 },
      "shooter: a slanted shot bounces off the wall")
check(slant.landing.row == 0 || slant.landing.row == 1, "shooter: and comes to rest at the top (\(slant.landing))")
check(tiny.loaded == 0 && tiny.shotsLeft == 11, "shooter kolay: the pen holds the red, six shots more than orta")
let second = tiny.shoot(from: launch, direction: CGPoint(x: 0, y: -1), grid: hex)
check(second?.popped.isEmpty == true && second?.fell.isEmpty == true && tiny.cells.count == 2 && tiny.shotsLeft == 10 && tiny.score == 0, "shooter: two of a colour hang on")
let third = tiny.shoot(from: launch, direction: CGPoint(x: 0, y: -1), grid: hex)
check(third?.popped.count == 3 && tiny.cells.isEmpty && tiny.phase == .won && tiny.score == 30 && tiny.stars == 3,
      "shooter: three of a colour pop and clear the level, three times par is three stars (\(String(describing: third?.popped)))")
check(tiny.shoot(from: launch, direction: CGPoint(x: 0, y: -1), grid: hex) == nil, "shooter: no shot after the end")
var downward = ShooterBoard(level: one, difficulty: .easy, seed: 3)
check(downward.shoot(from: launch, direction: CGPoint(x: 0, y: 1), grid: hex) == nil, "shooter: no shot downwards")
// Orphans: a bubble under the popped ones falls and scores more.
let hanger = ShooterLevel(rows: ["...RRB...", "....G..."], shots: 5)
var hung = ShooterBoard(level: hanger, difficulty: .easy, seed: 3)
check(hung.fallOrphans(grid: hex).isEmpty && hung.cells.count == 4, "shooter: the green hangs from the red")
var orphaned = ShooterBoard(level: ShooterLevel(rows: ["R........", "........", "....G...."], shots: 5), difficulty: .easy, seed: 3)
check(orphaned.fallOrphans(grid: hex) == [ShooterCell(2, 4)] && orphaned.cells.count == 1, "shooter: a bubble hanging on nothing falls")
// Shots run out: the level is lost with bubbles left.
var starved = ShooterBoard(level: ShooterLevel(rows: ["RBRBRBRBR"], shots: 5), difficulty: .hard, seed: 2)
var fired = 0
while starved.phase == .playing && fired < 10 {
    _ = starved.shoot(from: launch, direction: CGPoint(x: 0.3, y: -0.95), grid: hex)
    fired += 1
}
check(starved.phase == .lost && starved.shotsLeft == 0 && fired == 4, "shooter zor: four shots, then the level is lost (\(starved.phase))")
// A bubble resting at the dead row loses the level.
var deep = ShooterBoard(level: ShooterLevel(rows: ["R........", "R.......", "R........", "R.......", "R........", "R.......", "R........", "R.......", "R........", "B......."], shots: 30), difficulty: .easy, seed: 2)
_ = deep.shoot(from: CGPoint(x: 16, y: 11 * hex.rowHeight), direction: CGPoint(x: 0, y: -1), grid: hex)
check(deep.phase == .lost, "shooter: a bubble at the dead row loses the level")
check(ShooterBoard(level: first, difficulty: .medium, seed: 9) == ShooterBoard(level: first, difficulty: .medium, seed: 9), "shooter: the same seed, the same board")

// MARK: Sudoku (Sudoku, SudokuSave)

check(Sudoku.row(40) == 4 && Sudoku.col(40) == 4 && Sudoku.box(40) == 4 && Sudoku.box(80) == 8 && Sudoku.box(20) == 0, "sudoku: rows, columns, boxes")
check(Sudoku.peers(of: 0).count == 20 && Sudoku.peers(of: 0).contains(10) && !Sudoku.peers(of: 0).contains(0) && !Sudoku.peers(of: 0).contains(30), "sudoku: twenty peers")
let empty = Array(repeating: 0, count: 81)
check(Sudoku.candidates(empty, at: 0) == Array(1...9) && Sudoku.solutionCount(empty, limit: 2) == 2 && Sudoku.solve(empty) != nil, "sudoku: an empty grid has many solutions")
let full = Sudoku.fill(seed: 4)
check(Sudoku.isSolved(full) && Sudoku.conflicts(full).isEmpty && Sudoku.fill(seed: 4) == full && Sudoku.fill(seed: 5) != full, "sudoku: a filled grid is a solution, the same for a seed")
var broken = full
broken[0] = broken[1]
// Cell 0 now repeats cell 1's digit, which also stands once in column 0: three cells show it.
check(Sudoku.conflicts(broken).isSuperset(of: [0, 1]) && Sudoku.conflicts(broken).count == 3 && !Sudoku.isSolved(broken), "sudoku: a repeated digit shows on every cell it clashes with")
var gapped = full
gapped[3] = 0
check(!Sudoku.isFull(gapped) && !Sudoku.isSolved(gapped) && Sudoku.candidates(gapped, at: 3) == [full[3]] && Sudoku.solve(gapped) == full, "sudoku: one gap, one candidate")
for difficulty in GameDifficulty.allCases {
    let puzzle = Sudoku.generate(difficulty: difficulty, seed: 11)
    let target = Sudoku.clues(difficulty)
    check(puzzle.clueCount <= target + 6 && puzzle.clueCount >= 17, "sudoku \(difficulty.rawValue): \(puzzle.clueCount) clues for a target of \(target)")
    check(Sudoku.solutionCount(puzzle.givens, limit: 2) == 1 && Sudoku.solve(puzzle.givens) == puzzle.solution, "sudoku \(difficulty.rawValue): one solution, the known one")
    check(Sudoku.isSolved(puzzle.solution) && zip(puzzle.givens, puzzle.solution).allSatisfy { $0 == 0 || $0 == $1 }, "sudoku \(difficulty.rawValue): the clues are part of the solution")
    check(Sudoku.generate(difficulty: difficulty, seed: 11) == puzzle && Sudoku.generate(difficulty: difficulty, seed: 12) != puzzle, "sudoku \(difficulty.rawValue): seeded")
}
check(Sudoku.generate(difficulty: .hard, seed: 11).clueCount < Sudoku.generate(difficulty: .easy, seed: 11).clueCount, "sudoku: zor keeps fewer clues than kolay")
let puzzle = Sudoku.generate(difficulty: .medium, seed: 2)
let save = SudokuSave(difficulty: .medium, givens: puzzle.givens, solution: puzzle.solution, entries: puzzle.givens, notes: [3: [1, 2], 40: [7]], elapsed: 95)
let saved = save.encoded()
check(saved != nil && SudokuSave.decode(saved!) == save, "sudoku: a half-done puzzle survives a save")
check(SudokuSave.decode(Data("{}".utf8)) == nil && SudokuSave.decode(Data("nonsense".utf8)) == nil, "sudoku: a broken save is nothing")

// MARK: Ebru (EbruTray)

func ebruRadius(_ outline: [CGPoint], _ centre: CGPoint) -> (min: Double, max: Double) {
    let d = outline.map { EbruTray.distance($0, centre) }
    return (d.min() ?? 0, d.max() ?? 0)
}
let traySize = CGSize(width: 316, height: 260)
var tray = EbruTray(size: traySize, seed: 3)
check(tray.paints.isEmpty && !tray.isPlaying && !tray.canUndo && !tray.isHoldingDrop, "ebru: an empty tray at the start")

// A drop pushes a point at distance d out to exactly √(d² + r²); paint right under it goes to its rim.
let push = EbruTray.map(.drop(centre: CGPoint(x: 100, y: 100), radius: 20, pigment: 0))
check(abs(EbruTray.distance(push(CGPoint(x: 130, y: 100)), CGPoint(x: 100, y: 100)) - 1300.0.squareRoot()) < 1e-9, "ebru: a drop pushes a point out to √(d² + r²)")
check(abs(EbruTray.distance(push(CGPoint(x: 100, y: 100)), CGPoint(x: 100, y: 100)) - 20) < 1e-9, "ebru: paint right under a drop goes to its rim")

// Two drops side by side: the first keeps its area when the second pushes it.
tray.touchBegan(at: CGPoint(x: 120, y: 130), tool: .drop, pigment: 0)
tray.touchEnded()
let firstArea = EbruTray.area(of: tray.paints[0].outline)
check(abs(firstArea - Double.pi * 81) / (Double.pi * 81) < 0.02, "ebru: a touch drops a circle of 9 pt (\(firstArea))")
tray.touchBegan(at: CGPoint(x: 150, y: 130), tool: .drop, pigment: 1)
tray.touchEnded()
check(tray.paints.count == 2 && tray.paints[1].pigment == 1 && tray.canUndo, "ebru: the second drop lies on top in its own colour")
let pushedArea = EbruTray.area(of: tray.paints[0].outline)
check(abs(pushedArea - firstArea) / firstArea < 0.01, "ebru: the pushed drop keeps its area (\(firstArea) → \(pushedArea))")

// Held still, a drop spreads (r² grows 900 a second) up to 60 pt; a long gap counts as 0.1 s.
var held = EbruTray(size: traySize, seed: 3)
let heldCentre = CGPoint(x: 158, y: 130)
held.touchBegan(at: heldCentre, tool: .drop, pigment: 2)
for _ in 0..<10 { held.hold(for: 0.1) }
let heldSecond = ebruRadius(held.paints[0].outline, heldCentre)
check(abs(heldSecond.max - 981.0.squareRoot()) < 1e-6 && heldSecond.max - heldSecond.min < 0.05, "ebru: held for a second, the drop spreads to √(81 + 900) (\(heldSecond))")
held.hold(for: 5)
check(abs(ebruRadius(held.paints[0].outline, heldCentre).max - 1071.0.squareRoot()) < 1e-6, "ebru: a long gap spreads it by a tenth of a second only")
for _ in 0..<60 { held.hold(for: 0.1) }
check(abs(ebruRadius(held.paints[0].outline, heldCentre).max - 60) < 1e-6, "ebru: a held drop stops at 60 pt")
let heldFull = held
held.hold(for: 0.1)
check(held == heldFull && held.isHoldingDrop && !held.isSpreading, "ebru: no spreading past the limit")
held.touchEnded()
check(!held.isHoldingDrop, "ebru: lifting the pencil stops the spreading")

// Moved while down, the drop tool leaves a trail of small drops, one every 16 pt or more.
var trail = EbruTray(size: traySize, seed: 1)
trail.touchBegan(at: CGPoint(x: 40, y: 130), tool: .drop, pigment: 3)
trail.touchMoved(to: CGPoint(x: 50, y: 130))
check(trail.paints.count == 1, "ebru: a short move adds no drop")
trail.touchMoved(to: CGPoint(x: 60, y: 130))
trail.touchMoved(to: CGPoint(x: 90, y: 130))
check(trail.paints.count == 3 && trail.isHoldingDrop, "ebru: a moving drop leaves a trail (\(trail.paints.count))")
trail.touchEnded()

// The needle drags paint along its path and leaves paint far from it exactly where it was.
var needled = EbruTray(size: traySize, seed: 3)
needled.touchBegan(at: CGPoint(x: 80, y: 130), tool: .drop, pigment: 0)
for _ in 0..<3 { needled.hold(for: 0.1) }
needled.touchEnded()
needled.touchBegan(at: CGPoint(x: 240, y: 60), tool: .drop, pigment: 1)
needled.touchEnded()
let farPaint = needled.paints[1].outline
let rightEdge = needled.paints[0].outline.map { Double($0.x) }.max() ?? 0
needled.touchBegan(at: CGPoint(x: 40, y: 130), tool: .needle, pigment: 0)
needled.touchMoved(to: CGPoint(x: 90, y: 130))
needled.touchMoved(to: CGPoint(x: 160, y: 130))
needled.touchEnded()
let dragged = needled.paints[0].outline.map { Double($0.x) }.max() ?? 0
check(needled.paints[1].outline == farPaint, "ebru: the needle leaves paint far from its path alone")
check(dragged > rightEdge + 12, "ebru: the needle drags the drop along (right edge \(rightEdge) → \(dragged))")

// The comb waits until its axis is clear, then pulls only along it.
var combed = EbruTray(size: traySize, seed: 3)
combed.touchBegan(at: CGPoint(x: 158, y: 130), tool: .drop, pigment: 2)
for _ in 0..<5 { combed.hold(for: 0.1) }
combed.touchEnded()
let combRadius = 531.0.squareRoot()
let beforeComb = combed.paints[0].outline
combed.touchBegan(at: CGPoint(x: 150, y: 40), tool: .comb, pigment: 0)
combed.touchMoved(to: CGPoint(x: 152, y: 43))
check(combed.paints[0].outline == beforeComb, "ebru: the comb waits until its axis is clear")
combed.touchMoved(to: CGPoint(x: 165, y: 220))
combed.touchEnded()
let combXs = combed.paints[0].outline.map { Double($0.x) }
let combYs = combed.paints[0].outline.map { Double($0.y) }
check((combXs.min() ?? 0) >= 158 - combRadius - 1e-6 && (combXs.max() ?? 0) <= 158 + combRadius + 1e-6, "ebru: the comb pulls only along its axis")
check((combYs.max() ?? 0) > 130 + combRadius + 8, "ebru: the comb pulls the paint down (bottom \(combYs.max() ?? 0))")

// A sprinkle queues its drops and they fall one a frame; the same seed gives the same tray.
var sprinkled = EbruTray(size: traySize, seed: 8)
sprinkled.sprinkle(pigment: 0)
check(sprinkled.pending.count == 34 && sprinkled.paints.isEmpty && sprinkled.isPlaying, "ebru: a sprinkle queues 34 drops on this tray")
var frames = 0
while sprinkled.advance() { frames += 1 }
check(frames == 34 && sprinkled.paints.count > 15 && !sprinkled.isPlaying, "ebru: the drops fall one a frame (\(sprinkled.paints.count) on the tray)")
var sprinkledAtOnce = EbruTray(size: traySize, seed: 8)
sprinkledAtOnce.sprinkle(pigment: 0)
sprinkledAtOnce.finish()
check(sprinkledAtOnce == sprinkled, "ebru: the same seed sprinkles the same tray, frame by frame or at once")
var bigTray = EbruTray(size: CGSize(width: 376, height: 340), seed: 8)
bigTray.sprinkle(pigment: 0)
check(bigTray.pending.count == 53, "ebru: a larger tray gets more drops (\(bigTray.pending.count))")

// Patterns: each tine and swirl in parts; tines and swirls keep every colour's area.
var inside = EbruTray(size: traySize, seed: 1)
for (i, centre) in [(100.0, 90.0), (158.0, 130.0), (215.0, 175.0), (125.0, 180.0), (205.0, 85.0)].enumerated() {
    inside.touchBegan(at: CGPoint(x: centre.0, y: centre.1), tool: .drop, pigment: i % 6)
    for _ in 0..<3 { inside.hold(for: 0.1) }
    inside.touchEnded()
}
let insideAreas = inside.paints.map { EbruTray.area(of: $0.outline) }
let expectedParts: [EbruPattern: Int] = [.gelgit: 48, .tarakli: 6, .sal: 42, .bulbul: 84]
for pattern in EbruPattern.allCases {
    var t = inside
    t.play(pattern)
    let parts = t.pending.count
    t.finish()
    let after = t.paints.map { EbruTray.area(of: $0.outline) }
    let worst = zip(insideAreas, after).map { abs($1 - $0) / $0 }.max() ?? 1
    check(parts == expectedParts[pattern] && after.count == insideAreas.count && worst < 0.02,
          "ebru \(pattern.rawValue): \(parts) parts, every colour keeps its area (worst \(String(format: "%.4f", worst)))")
}
// A tine's parts add up exactly to the whole tine.
let whole = EbruTray.map(.line(through: CGPoint(x: 0, y: 50), direction: CGPoint(x: 1, y: 0), shift: 36, sharpness: 10))
let part = EbruTray.map(.line(through: CGPoint(x: 0, y: 50), direction: CGPoint(x: 1, y: 0), shift: 9, sharpness: 10))
let probe = CGPoint(x: 37, y: 61)
check(close(part(part(part(part(probe)))), whole(probe), 1e-9), "ebru: four quarter tines make one tine")
check(EbruTray.nearestTine(27, spacing: 20) == 7 && EbruTray.nearestTine(-3, spacing: 20) == 3, "ebru: the distance to the nearest tine")
let fourSteps = EbruTray.steps(from: .zero, to: CGPoint(x: 10, y: 0))
check(fourSteps.count == 4 && abs(Double(fourSteps[3].tip.x) - 10) < 1e-9 && abs(Double(fourSteps[0].step.x) - 2.5) < 1e-9, "ebru: a 10 pt drag goes in four steps of 2.5")
check(EbruTray.steps(from: .zero, to: .zero).isEmpty, "ebru: no movement, no steps")

// Undo stops a pattern and brings the tray back; ten steps are kept.
var undone = inside
undone.play(.bulbul)
undone.advance()
undone.advance()
undone.undo()
check(undone.paints == inside.paints && !undone.isPlaying, "ebru: undo stops a pattern and brings the tray back")
var many = EbruTray(size: traySize, seed: 1)
for i in 0..<14 {
    many.touchBegan(at: CGPoint(x: 20 + Double(i) * 20, y: 130), tool: .drop, pigment: 0)
    many.touchEnded()
}
var undos = 0
while many.canUndo {
    many.undo()
    undos += 1
}
check(undos == 10 && many.paints.count == 4, "ebru: ten steps back at most (\(undos), \(many.paints.count) drops left)")

// Paint pushed wholly off the tray is let go.
var crowded = EbruTray(size: traySize, seed: 1)
crowded.touchBegan(at: CGPoint(x: 10, y: 130), tool: .drop, pigment: 0)
crowded.touchEnded()
crowded.touchBegan(at: CGPoint(x: 70, y: 130), tool: .drop, pigment: 1)
for _ in 0..<60 { crowded.hold(for: 0.1) }
crowded.touchEnded()
check(crowded.paints.count == 1 && crowded.paints[0].pigment == 1, "ebru: paint pushed off the tray is let go")

// A full tray: four sprinkles and the nightingale's nest stay inside the point budget.
var busyTray = EbruTray(size: traySize, seed: 5)
for pigment in [0, 2, 1, 5] {
    busyTray.sprinkle(pigment: pigment)
    busyTray.finish()
}
busyTray.play(.gelgit)
busyTray.finish()
busyTray.play(.bulbul)
busyTray.finish()
check(busyTray.pointCount < Int(Double(EbruTray.budget) * 1.6), "ebru: a busy tray stays near the budget (\(busyTray.pointCount) points)")

// MARK: Living ink (InkPond)

/// A fish drawn the usual way: the body from the nose round, then the tail fin, then an eye.
func fishDrawing(facingRight: Bool, at centre: CGPoint = CGPoint(x: 120, y: 120)) -> [[CGPoint]] {
    let body = (0...48).map { i -> CGPoint in
        let a = Double(i) / 48 * 2 * .pi
        return CGPoint(x: 40 * cos(a), y: 18 * sin(a))
    }
    let tail = [CGPoint(x: -40, y: 0), CGPoint(x: -62, y: -22), CGPoint(x: -62, y: 22), CGPoint(x: -40, y: 0)]
    let eye = [CGPoint(x: 24, y: -5), CGPoint(x: 25, y: -5)]
    let k: Double = facingRight ? 1 : -1
    return [body, tail, eye].map { $0.map { CGPoint(x: Double(centre.x) + k * Double($0.x), y: Double(centre.y) + Double($0.y)) } }
}

func sameStrokes(_ a: [[CGPoint]], _ b: [[CGPoint]], _ tolerance: Double = 1e-9) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { s, t in s.count == t.count && zip(s, t).allSatisfy { close($0, $1, tolerance) } }
}

let pondSize = CGSize(width: 316, height: 300)
check(InkPond.facesRight(fishDrawing(facingRight: true)), "living ink: a fish with its tail fin on the left faces right")
check(!InkPond.facesRight(fishDrawing(facingRight: false)), "living ink: its mirror image faces left")
let oval = (0...40).map { i -> CGPoint in
    let a = .pi + Double(i) / 40 * 2 * .pi
    return CGPoint(x: 150 + 40 * cos(a), y: 150 + 20 * sin(a))
}
check(!InkPond.facesRight([oval]) && InkPond.facesRight([oval.reversed().map { CGPoint(x: 300 - $0.x, y: $0.y) }]),
      "living ink: a drawing with even ends faces where it was begun")

var pond = InkPond(size: pondSize, seed: 4)
check(pond.isStill && pond.wake([[CGPoint(x: 5, y: 5)]], ink: 0) == nil, "living ink: a lone point does not wake")
let rightFish = fishDrawing(facingRight: true)
let leftFish = fishDrawing(facingRight: false, at: CGPoint(x: 200, y: 200))
pond.wake(rightFish, ink: 2)
pond.wake(leftFish, ink: 0)
check(pond.creatures.count == 2 && close(pond.creatures[0].position, CGPoint(x: 109, y: 120)), "living ink: a creature wakes in the middle of its drawing (\(pond.creatures.first?.position ?? .zero))")
check(pond.creatures[0].facing == 1 && pond.creatures[1].facing == -1, "living ink: each faces the way it was drawn")
check(sameStrokes(InkPond.pose(pond.creatures[0]), rightFish) && sameStrokes(InkPond.pose(pond.creatures[1]), leftFish),
      "living ink: just woken, it is exactly the drawing")
let startPosition = pond.creatures[0].position
for _ in 0..<30 { pond.advance(by: 1.0 / 60) }
check(!close(pond.creatures[0].position, startPosition, 0.5) && !sameStrokes(InkPond.pose(pond.creatures[0]), rightFish, 0.5),
      "living ink: half a second on it swims and its body bends")
check(Double(pond.creatures[0].position.x) > Double(startPosition.x), "living ink: it swims the way it faces")

// A long swim: everyone stays in the pond, turns round, and the wave's phase stays small.
var turnedRound = Set<Int>()
var firstFacing: [Int: Double] = [:]
for c in pond.creatures { firstFacing[c.id] = c.facing }
pond.wake(fishDrawing(facingRight: true, at: CGPoint(x: 250, y: 60)), ink: 4)
var stayedIn = true
for _ in 0..<(60 * 120) {
    pond.advance(by: 1.0 / 60)
    for c in pond.creatures {
        if let f = firstFacing[c.id], c.facing != f { turnedRound.insert(c.id) }
        let p = c.position
        if Double(p.x) < 0 || Double(p.x) > Double(pondSize.width) || Double(p.y) < 0 || Double(p.y) > Double(pondSize.height) { stayedIn = false }
    }
}
check(stayedIn, "living ink: two minutes of swimming stay inside the pond")
check(turnedRound.count == 2, "living ink: they turn round at the walls (\(turnedRound.count) of 2)")
check(pond.creatures.allSatisfy { $0.phase >= 0 && $0.phase < 2 * .pi }, "living ink: the wave's phase stays within a turn")
check(pond.bubbles.count < 40, "living ink: the bubbles rise and go (\(pond.bubbles.count) now)")

// Food: four crumbs sink; a creature eats them all.
var fed = InkPond(size: pondSize, seed: 9)
fed.wake(fishDrawing(facingRight: true, at: CGPoint(x: 100, y: 150)), ink: 1)
fed.feed()
check(fed.crumbs.count == 4 && fed.crumbs.allSatisfy { Double($0.position.y) < 0 }, "living ink: food starts at the top")
var mealTime = 0.0
while fed.meals < 4 && mealTime < 90 {
    fed.advance(by: 1.0 / 60)
    mealTime += 1.0 / 60
}
check(fed.meals == 4 && fed.crumbs.isEmpty, "living ink: the creature eats every crumb (\(fed.meals) in \(Int(mealTime)) s)")
for _ in 0..<4 { fed.feed() }
check(fed.crumbs.count == 12, "living ink: twelve crumbs in the water at most")

// A ninth creature: the oldest fades out to make room.
var crowdedPond = InkPond(size: pondSize, seed: 2)
for i in 0..<9 {
    crowdedPond.wake(fishDrawing(facingRight: i % 2 == 0, at: CGPoint(x: 60 + Double(i % 3) * 90, y: 60 + Double(i / 3) * 80)), ink: i % 5)
}
check(crowdedPond.creatures.count == 9 && crowdedPond.creatures[0].fade == 1 && crowdedPond.awake == 8, "living ink: a ninth sends the oldest fading")
for _ in 0..<60 { crowdedPond.advance(by: 1.0 / 60) }
check(crowdedPond.creatures.count == 8 && crowdedPond.creatures.allSatisfy { $0.id != 1 }, "living ink: the oldest is gone after its fade")

// A poke sends a creature dashing off; a poke on open water does nothing.
var poked = InkPond(size: pondSize, seed: 3)
poked.wake(fishDrawing(facingRight: true, at: CGPoint(x: 150, y: 150)), ink: 0)
for _ in 0..<60 { poked.advance(by: 1.0 / 60) }
let calm = poked.creatures[0].speed
check(!poked.poke(at: CGPoint(x: 10, y: 10)), "living ink: a poke on open water does nothing")
check(poked.poke(at: poked.creatures[0].position) && poked.creatures[0].dash > 0, "living ink: a poke startles the creature")
for _ in 0..<20 { poked.advance(by: 1.0 / 60) }
check(poked.creatures[0].speed > calm * 1.5, "living ink: and it dashes (\(calm) → \(poked.creatures[0].speed))")

// The same seed and the same drawings make the same pond; a busy drawing is thinned to 600 points.
var twinA = InkPond(size: pondSize, seed: 11)
var twinB = InkPond(size: pondSize, seed: 11)
twinA.wake(rightFish, ink: 1)
twinB.wake(rightFish, ink: 1)
for _ in 0..<300 {
    twinA.advance(by: 1.0 / 60)
    twinB.advance(by: 1.0 / 60)
}
check(twinA == twinB, "living ink: the same seed swims the same way")
let scribble = [(0..<2000).map { i in CGPoint(x: 50 + Double(i % 200), y: 50 + Double(i / 200) * 10) }]
var busyPond = InkPond(size: pondSize, seed: 1)
busyPond.wake(scribble, ink: 0)
check(busyPond.creatures[0].strokes.reduce(0) { $0 + $1.count } <= InkPond.pointBudget, "living ink: a busy drawing is thinned to the budget")

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
