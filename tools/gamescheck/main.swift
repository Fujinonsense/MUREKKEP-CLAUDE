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
check(field.bubbles.isEmpty && field.score == 0 && field.timeLeft == 60 && !field.isOver, "bubbles: an empty field at the start")
check(abs(field.spawnInterval - 1.1) < 1e-9 && abs(field.riseSpeed - 38) < 1e-9, "bubbles: easy at the start")
for _ in 0..<40 { field.advance(by: 1.0 / 20) }
check(abs(field.elapsed - 2) < 1e-9, "bubbles: two seconds in (\(field.elapsed))")
check(field.bubbles.count >= 2, "bubbles: bubbles have come up (\(field.bubbles.count))")
check(field.bubbles.allSatisfy { $0.x >= $0.radius && $0.x <= Double(fieldSize.width) - $0.radius }, "bubbles: every bubble is inside the width")
check(field.bubbles.allSatisfy { $0.radius >= 13 && $0.radius <= 30 }, "bubbles: sizes in range")
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
let target = field.bubbles[0]
let before = field.bubbles.count
let gain = field.pop(at: CGPoint(x: target.x + target.radius + 8, y: target.y))
check(gain == target.worth && field.bubbles.count == before - 1 && !field.bubbles.contains(target), "bubbles: a touch beside the bubble's edge pops it")
check(field.score == target.worth && field.popped == 1 && field.splashes.count == 1, "bubbles: the pop is scored and splashes")
check((target.radius < 20 && target.worth == 2) || (target.radius >= 20 && target.worth == 1), "bubbles: small bubbles are worth two, big ones one")
check(field.pop(at: CGPoint(x: -500, y: -500)) == nil && field.score == target.worth, "bubbles: a touch on nothing scores nothing")
var crowd = BubbleField(size: fieldSize, seed: 1)
for _ in 0..<200 { crowd.advance(by: 1.0 / 30) }
if crowd.bubbles.count >= 2 {
    let a = crowd.bubbles[0]
    let b = crowd.bubbles[1]
    let nearA = CGPoint(x: a.x + (b.x - a.x) * 0.1, y: a.y + (b.y - a.y) * 0.1)
    crowd.pop(at: nearA)
    let aGone = !crowd.bubbles.contains(a)
    let bStays = crowd.bubbles.contains(b)
    check(aGone && bStays, "bubbles: the nearest bubble pops")
}

// Splashes fade, bubbles that reach the top leave, the pace picks up, the round ends at 60 s.
var fading = field
for _ in 0..<12 { fading.advance(by: 0.05) }
check(fading.splashes.isEmpty, "bubbles: a splash is gone after half a second")
var long = BubbleField(size: fieldSize, seed: 3)
for _ in 0..<(30 * 30) { long.advance(by: 1.0 / 30) }
check(abs(long.elapsed - 30) < 1e-6 && abs(long.difficulty - 0.5) < 1e-6, "bubbles: half way (\(long.elapsed))")
check(abs(long.spawnInterval - 0.775) < 1e-6 && abs(long.riseSpeed - 59) < 1e-6, "bubbles: the pace picks up half way (\(long.spawnInterval), \(long.riseSpeed))")
check(long.bubbles.allSatisfy { $0.y + $0.radius >= 0 }, "bubbles: bubbles above the top are gone")
check(long.bubbles.count < 60, "bubbles: the field does not fill up (\(long.bubbles.count))")
for _ in 0..<(31 * 30) { long.advance(by: 1.0 / 30) }
check(long.isOver && long.timeLeft == 0 && abs(long.elapsed - 60) < 1e-6, "bubbles: the round ends at 60 s (\(long.elapsed))")
check(abs(long.spawnInterval - 0.45) < 1e-9 && abs(long.riseSpeed - 80) < 1e-9, "bubbles: hardest at the end")
let frozen = long
long.advance(by: 0.5)
let lastBubble = long.bubbles.first
let popAfterEnd = long.pop(at: CGPoint(x: lastBubble?.x ?? 0, y: lastBubble?.y ?? 0))
check(long == frozen && popAfterEnd == nil, "bubbles: nothing moves or pops after the end")
check(BubbleField.bestKey == "breakBubblesBest", "bubbles: the best score's key")

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

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
