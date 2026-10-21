import Foundation

// Runs the app's pure Swift logic on Windows against the answers of its Python twins (tests/ports).
// usage: check.exe <repo root>

var failures = 0

func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { failures += 1 }
}

func number(_ v: Any) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return (v as? NSNumber)?.doubleValue ?? .nan
}

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func json(_ path: String) -> Any {
    let data = try! Data(contentsOf: URL(fileURLWithPath: root + "/" + path))
    return try! JSONSerialization.jsonObject(with: data)
}

// MARK: Deskew (tests/ports/deskew.py)

let vectors = json("tests/fixtures/swift_vectors.json") as! [String: Any]
for item in vectors["deskew"] as! [[String: Any]] {
    let strokes = (item["strokes"] as! [Any]).map { stroke in
        (stroke as! [Any]).map { p -> CGPoint in
            let xy = p as! [Any]
            return CGPoint(x: number(xy[0]), y: number(xy[1]))
        }
    }
    let want = number(item["angle"]!)
    let got = InkDeskew.angle(strokes)
    check(abs(got - want) <= 0.5, "deskew \(item["name"]!): swift \(got), python \(want)")
}

// MARK: Reading order (tests/test_reading_order.py)

let scan = json("tests/fixtures/ocr_highnote_p12.json") as! [String: Any]
let scanPieces = (scan["lines"] as! [[String: Any]]).map { l -> ReadingOrder.Piece in
    let b = (l["box"] as! [Any]).map(number)
    return ReadingOrder.Piece(text: l["text"] as! String, box: CGRect(x: b[0], y: b[1], width: b[2], height: b[3]))
}
let ordered = ReadingOrder.lines(scanPieces)
let wantOrder = vectors["reading_order"] as! [String]
check(ordered == wantOrder, "reading order: \(ordered.count) lines, python \(wantOrder.count)"
      + (ordered == wantOrder ? "" : ", first difference: \(zip(ordered, wantOrder).first { $0.0 != $0.1 }.map { "\($0.0) | \($0.1)" } ?? "-")"))
let gapWords = ReadingOrder.Piece(text: "I think sport is", box: CGRect(x: 100, y: 100, width: 260, height: 30),
                                  words: [("I", CGRect(x: 100, y: 100, width: 10, height: 30)), ("think", CGRect(x: 118, y: 100, width: 70, height: 30)),
                                          ("sport", CGRect(x: 260, y: 100, width: 70, height: 30)), ("is", CGRect(x: 338, y: 100, width: 22, height: 30))])
check(ReadingOrder.lines([gapWords]) == ["I think ___ sport is"], "blank between words")
check(ReadingOrder.normalizeBlanks("Name .......... Date ……") == "Name ___ Date ___" && ReadingOrder.normalizeBlanks("fashion... ...is that") == "fashion... ...is that",
      "printed blanks")

// MARK: Exercises (tests/test_exercises.py)

func dump(_ found: [PageExercise]) -> String {
    var out: [String] = []
    for e in found {
        out.append("E \(e.number) \(e.kind.rawValue) running=\(e.running ? 1 : 0) choices=\(e.choices.joined(separator: "|")) "
            + "passage=\(e.passage == nil ? 0 : 1)")
        out.append("I " + e.instruction)
        out.append("C " + e.context)
        for it in e.items {
            let gaps = it.gaps.map { "\($0.number):\($0.given ?? "")" }.joined(separator: ",")
            let opts = it.options.map { "\($0.letter):\($0.text)" }.joined(separator: "|")
            out.append("  item \(it.number) [\(it.text)] gaps=\(gaps) options=\(opts)")
        }
        var fills: [Int: [String]] = [:]
        for (k, u) in ExerciseSplitter.units(e).enumerated() {
            out.append("  unit \(u.number) \(u.gaps.map { String($0.number) }.joined(separator: ",")) [\(u.text)] before=[\(u.before)]")
            out.append("  P " + ExerciseSplitter.unitPrompt(e, u, before: u.before).replacingOccurrences(of: "\n", with: "⏎"))
            let f = u.gaps.isEmpty
                ? [e.choices.isEmpty ? "x" : e.choices[k % e.choices.count]]
                : (0..<u.gaps.count).map { j in e.choices.isEmpty ? "x" : e.choices[(k + j) % e.choices.count] }
            fills[u.number, default: []] += f
        }
        out.append("X " + ExerciseSplitter.exercisePrompt(e).replacingOccurrences(of: "\n", with: "⏎"))
        var notes: [Int: String] = [:]
        for n in fills.keys { notes[n] = "note \(n)" }
        out.append("R " + ExerciseSplitter.render(e, fills: fills, notes: notes).replacingOccurrences(of: "\n", with: "⏎"))
    }
    return out.joined(separator: "\n")
}

let pageText = ReadingOrder.lines(scanPieces).joined(separator: "\n")
check(ExerciseSplitter.split(pageText).map(\.number) == [1, 2, 3, 4, 5, 6], "page exercises from Swift's own reading order")
for (i, item) in (vectors["exercises"] as! [[String: Any]]).enumerated() {
    let got = dump(ExerciseSplitter.split(item["text"] as! String))
    let want = item["dump"] as! String
    let diff = zip(got.components(separatedBy: "\n"), want.components(separatedBy: "\n")).first { $0.0 != $0.1 }
    check(got == want, "exercises \(i)" + (got == want ? "" : ": swift [\(diff?.0 ?? "-")] python [\(diff?.1 ?? "-")]"))
}
for item in vectors["choices"] as! [[String: Any]] {
    let got = ExerciseSplitter.choices(item["instruction"] as! String)
    check(got == item["choices"] as! [String], "choices \(item["instruction"]!): \(got)")
}
for item in vectors["articles"] as! [[String: Any]] {
    let got = ExerciseSplitter.article(item["fill"] as! String, next: item["next"] as! String)
    check(got == item["article"] as! String, "article \(item["fill"]!) \(item["next"]!): \(got)")
}
let numberedFill = ExerciseSplitter.fillNumbered("(7) ___ jeans were (8) ___ present and (9) ___ friend.", known: [7: "the", 9: "a"])
check(numberedFill == vectors["fill_numbered"] as! String, "fill numbered: \(numberedFill)")

// MARK: Chapters (tests/test_chapters.py)

func chapters(_ name: String) -> [BookChapter] {
    let d = json("tests/fixtures/heads_\(name).json") as! [String: Any]
    let pages = (d["pages"] as! [Any]).enumerated().map { i, lines in
        PageHead(page: i, lines: (lines as! [Any]).map { $0 as! String })
    }
    return ChapterFinder.find(outline: [], heads: pages, pageCount: pages.count)
}

let pre = chapters("precalculus")
check(pre.map(\.startPage) == [16, 168, 254, 406, 544, 624, 684, 774, 904, 1018, 1098, 1184], "precalculus starts \(pre.map(\.startPage))")
check(pre.first?.title == "Functions" && pre.last?.title == "Introduction to Calculus", "precalculus titles \(pre.first?.title ?? "-") … \(pre.last?.title ?? "-")")
check(pre.last?.endPage == 1249, "precalculus last end \(pre.last?.endPage ?? -1)")
check(pre.first.map { $0.sections.prefix(2).map { "\($0.number) \($0.title) \($0.page)" } } == ["1.1 Functions and Function Notation 16", "1.2 Domain and Range 42"],
      "precalculus sections \(pre.first?.sections.prefix(2).map(\.title) ?? [])")
let hn = chapters("highnote3")
check(hn.map(\.startPage) == [5, 19, 35, 49, 65, 79, 95, 109, 125, 139] && hn.last?.endPage == 172, "high note units \(hn.map(\.startPage)) end \(hn.last?.endPage ?? -1)")
check(hn.first?.title == "Looking good", "high note title \(hn.first?.title ?? "-")")
let rs = chapters("reading")
check(rs.map(\.startPage) == [0, 38, 74, 115, 157, 187, 216] && rs.last?.endPage == 244, "reading units \(rs.map(\.startPage))")
check(rs.prefix(4).map(\.title) == ["Culture", "Health", "Trends", "Education and Career"], "reading titles \(rs.prefix(4).map(\.title))")
check(rs.first.map { $0.sections.map { "\($0.number)|\($0.title)" } } == ["Text 1|Chinese Culture", "Text 2|Whatis It About the Erasmus Program?", "Text 3|A Universal Language"],
      "reading sections \(rs.first?.sections.map(\.title) ?? [])")
check(ChapterFinder.tidy("WRITING A formal letter") == "Writing – A formal letter", "tidy label")
check(ChapterFinder.tidy("SAYILAR VE İŞLEMLER") == "Sayılar ve İşlemler", "tidy turkish: \(ChapterFinder.tidy("SAYILAR VE İŞLEMLER"))")
check(ChapterFinder.tidy("IS IT A RITE OF PASSAGE?") == "Is It a Rite of Passage?", "tidy caps")

// MARK: Questions (tests/test_questions.py)

let yks = """
TÜRKÇE TESTİ
1. Aşağıdaki cümlelerin hangisinde yazım yanlışı vardır?
A) Herkes bu konuda hem fikirdi.
B) Toplantı saat üçte başladı.
C) Bu kitabı da okudum.
D) Yarın sınav var mı?
E) Sen de gel.
2. "Göz" sözcüğü aşağıdakilerin hangisinde mecaz anlamda kullanılmıştır?
A) Gözleri yorulmuştu.
B) Çantanın gözüne koydu.
C) Gözünü kırptı.
D) Göz doktoruna gitti.
E) Gözlüğünü taktı.
3. Bir sayının 3 katının 5 fazlası 20'dir. Bu sayı kaçtır?
A) 3 B) 4 C) 5 D) 6 E) 7
"""
let qs = QuestionSplitter.split(yks)
check(qs.map(\.number) == [1, 2, 3] && qs.allSatisfy { $0.options.map { String($0.letter) } == ["A", "B", "C", "D", "E"] }, "questions split")
check(qs.first?.stem == "Aşağıdaki cümlelerin hangisinde yazım yanlışı vardır?" && qs.last?.options[2].text == "5", "question stem and glued option")
let passage = """
3. - 5. soruları aşağıdaki parçaya göre cevaplayınız.
Kitap okumak insanın hayal gücünü geliştirir. Okuyan kişi başkalarının hayatlarını yaşar,
farklı düşünceleri tanır ve kendi fikirlerini sorgular. Bu yüzden okumak bir yolculuktur.
3. Bu parçada asıl anlatılmak istenen nedir?
A) Okumanın yararları B) Yazarların hayatı C) Kütüphaneler D) Yolculuklar E) Hayal gücünün sınırları
4. Parçada hangisine değinilmemiştir?
A) Hayal gücü B) Düşünceler C) Sorgulama D) Kitap fiyatları E) Yolculuk
6. 12 ile 18'in en büyük ortak böleni kaçtır?
A) 2 B) 3 C) 4 D) 6 E) 9
"""
let ps = QuestionSplitter.split(passage)
check(ps.first?.passage?.hasPrefix("Kitap okumak") == true && ps.first?.passage?.hasSuffix("yolculuktur.") == true, "passage attached")

// MARK: Speech (tests/test_speech.py)

check(SpeechText.turkishNumber(1250) == "bin iki yüz elli" && SpeechText.turkishNumber(2_000_000) == "iki milyon", "turkish numbers")
let cases: [(String, Bool, String)] = [
    ("x² + 3x = 10, %25, π", false, "iks kare artı üç iks eşittir on, yüzde yirmi beş, pi"),
    ("Bu sınavda 1.250 öğrenci vardı ve %25'i 3,5 saatte bitirdi.", false,
     "Bu sınavda bin iki yüz elli öğrenci vardı ve yüzde yirmi beşi üç virgül beş saatte bitirdi."),
    ("Sayfa 42'deki 7. soruda 2026 yılı soruluyor.", false, "Sayfa kırk ikideki yedinci soruda iki bin yirmi altı yılı soruluyor."),
    ("f(x) = x^2 - 4 ve saat 14:45", false, "fe iks eşittir iks üssü iki eksi dört ve saat on dört kırk beş"),
    ("Sıcaklık -5 derece, oran 0,05.", false, "Sıcaklık eksi beş derece, oran sıfır virgül sıfır beş."),
    ("Solve x² + 3x = 10 and find f(x) for π/2.", true, "Solve x squared plus 3 x equals 10 and find f of x for pi over 2."),
    ("Ödev: Kalkülüs-Giriş bölümünü oku; o da zor değil.", false, "Ödev: Kalkülüs-Giriş bölümünü oku; o da zor değil."),
]
for (input, english, want) in cases {
    let got = SpeechText.spokenMath(input, english: english)
    check(got == want, "spoken: \(got)")
}
let long = String(repeating: "Türev, bir fonksiyonun anlık değişim oranıdır. ", count: 6) + String(repeating: "Bu çok uzun bir cümle, ", count: 20) + "ve burada biter. Son cümle."
let parts = SpeechText.chunks(long, maxChars: 260)
check(parts.allSatisfy { $0.count <= 260 } && parts.joined(separator: " ") == long.split(whereSeparator: \.isWhitespace).joined(separator: " "),
      "speech chunks \(parts.count)")

// MARK: Ink meshes (InkMeshPlan)

func strokes(_ ids: [Int], highlighter: Set<Int> = [], grass: Set<Int> = []) -> [(id: Int, highlighter: Bool, grass: Bool)] {
    ids.map { (id: $0, highlighter: highlighter.contains($0), grass: grass.contains($0)) }
}
check(InkMeshPlan.plan(old: [4, 5, 6], new: strokes([4, 5, 6])) == .same, "mesh: same strokes keep the buffers")
check(InkMeshPlan.plan(old: [4, 5, 6], new: strokes([4, 5, 6, 9, 10])) == .append(from: 3), "mesh: new pen strokes are appended")
check(InkMeshPlan.plan(old: [2, 4, 5], new: strokes([4, 2, 5, 9], highlighter: [2])) == .append(from: 3),
      "mesh: buffer order puts highlighters first")
check(InkMeshPlan.plan(old: [4, 5], new: strokes([4, 5, 9], highlighter: [9])) == .rebuild, "mesh: a new highlighter rebuilds")
check(InkMeshPlan.plan(old: [4, 5], new: strokes([4, 5, 9], grass: [9])) == .rebuild, "mesh: new grass rebuilds")
check(InkMeshPlan.plan(old: [4, 5, 6], new: strokes([4, 6, 9])) == .rebuild, "mesh: an erased stroke rebuilds")
check(InkMeshPlan.plan(old: [4, 5, 6], new: strokes([5, 4, 6])) == .rebuild, "mesh: a reordered page rebuilds")
check(InkMeshPlan.plan(old: [], new: strokes([1, 2])) == .rebuild, "mesh: an empty page is built")

// MARK: Ink layer (InkLayer)

let layerKey = InkLayerKey(originX: 12, originY: -40, zoom: 1.5, width: 2048, height: 2732, pages: [3, 4], versions: [7, 2],
                           animate: true, dry: 2.5, cool: 6)
var movedKey = layerKey
movedKey.originY = -41
var editedKey = layerKey
editedKey.versions = [8, 2]
check(InkLayer.reuse(key: layerKey, old: layerKey, contentFPS: 0, age: 5), "layer: still content is reused")
check(!InkLayer.reuse(key: movedKey, old: layerKey, contentFPS: 0, age: 0.001), "layer: a scrolled view redraws it")
check(!InkLayer.reuse(key: editedKey, old: layerKey, contentFPS: 0, age: 0.001), "layer: an edited page redraws it")
check(InkLayer.reuse(key: layerKey, old: layerKey, contentFPS: 30, age: 0.02), "layer: 30 fps ink waits a frame of its own")
check(!InkLayer.reuse(key: layerKey, old: layerKey, contentFPS: 30, age: 0.04), "layer: 30 fps ink moves on after 1/30 s")
check(!InkLayer.reuse(key: layerKey, old: nil, contentFPS: 0, age: 0), "layer: no layer yet")

// MARK: Pen sound (tests/test_pen_sound.py)

var envelope = PenSoundEnvelope()
var penLevels: [Double] = []
for i in 0...120 {
    let t = Double(i) / 240
    let x = 160 * t + 14 * sin(2 * Double.pi * 6 * t)
    let y = 14 * cos(2 * Double.pi * 6 * t)
    penLevels.append(envelope.update(x: x, y: y, time: t, force: 1.3))
}
let penWant = [0.254202910267, 0.615480249498, 0.748007018803, 0.694638672664, 0.881360124266]
let penGot = [1, 5, 30, 60, 120].map { penLevels[$0] }
check(zip(penGot, penWant).allSatisfy { abs($0 - $1) < 1e-9 }, "pen sound: loops match python \(penGot)")
var glide = 0.0
for _ in 0..<529 {
    glide += (1 - glide) * PenSoundEnvelope.attack
}
check(abs(glide - 0.929464180816) < 1e-9, "pen sound: attack glide \(glide)")

// MARK: Recordings (tests/test_recording_sync.py)

let takeA = Recording(id: UUID(), start: 1000, duration: 60, title: "A")
let takeB = Recording(id: UUID(), start: 5000, duration: 30, title: "B")
check(RecordingSync.hidden(births: [(1, 990)], recording: takeA, time: 0).isEmpty, "recording: earlier ink shows")
check(RecordingSync.hidden(births: [(1, 1005), (2, 1030)], recording: takeA, time: 0) == [1, 2]
      && RecordingSync.hidden(births: [(1, 1005), (2, 1030)], recording: takeA, time: 5) == [2]
      && RecordingSync.hidden(births: [(1, 1005), (2, 1030)], recording: takeA, time: 40).isEmpty, "recording: ink follows the playhead")
check(RecordingSync.hidden(births: [(1, 2000)], recording: takeA, time: 0).isEmpty, "recording: later ink shows")
check(RecordingSync.hidden(births: [(1, 1060.4)], recording: takeA, time: 59) == [1], "recording: a lift just after stop belongs")
let seekA = RecordingSync.seek(birth: 1012, recordings: [takeA, takeB])
let seekB = RecordingSync.seek(birth: 5020, recordings: [takeA, takeB])
check(seekA?.id == takeA.id && seekA?.time == 10.5 && seekB?.id == takeB.id && seekB?.time == 18.5, "recording: tap seeks before the line")
check(RecordingSync.seek(birth: 1000.5, recordings: [takeA])?.time == 0, "recording: first line seeks to zero")
check(RecordingSync.seek(birth: 3000, recordings: [takeA, takeB]) == nil, "recording: ink outside takes does not seek")

// MARK: Zoom window (ZoomBox)

let zoomPage = CGSize(width: 600, height: 800)
func zb(_ x: CGFloat, _ y: CGFloat) -> ZoomBox { ZoomBox(page: 0, rect: CGRect(x: x, y: y, width: 200, height: 60)) }
check(zb(60, 100).advanced(pageSize: zoomPage, margin: 40).rect.origin == CGPoint(x: 210, y: 100), "zoom: moves on by 3/4 of its width")
check(zb(300, 100).advanced(pageSize: zoomPage, margin: 40).rect.origin == CGPoint(x: 360, y: 100), "zoom: stops at the right margin")
check(zb(360, 100).advanced(pageSize: zoomPage, margin: 40).rect.origin == CGPoint(x: 40, y: 151), "zoom: wraps to the next line")
check(zb(360, 700).advanced(pageSize: zoomPage, margin: 40) == zb(360, 700), "zoom: stays at the bottom of the page")
check(zb(210, 100).back(margin: 40).rect.origin == CGPoint(x: 60, y: 100) && zb(60, 100).back(margin: 40).rect.origin.x == 40,
      "zoom: goes back to the margin")
check(zb(250, 100).newLine(pageSize: zoomPage, margin: 40).rect.origin == CGPoint(x: 40, y: 151), "zoom: new line")
let firstBox = ZoomBox.initial(page: 2, pageSize: zoomPage, margin: 40, aspect: 4)
check(firstBox.page == 2 && firstBox.rect == CGRect(x: 40, y: 80, width: 240, height: 60), "zoom: first box \(firstBox.rect)")

// MARK: Spaced repetition (SpacedRepetition)

let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
func after(_ r: CardReview, _ ratings: [ReviewRating], from start: Date = t0) -> CardReview {
    var card = r
    var now = start
    for rating in ratings {
        card = SpacedRepetition.review(card, rating: rating, now: now)
        now = card.due ?? now
    }
    return card
}
func wait(_ r: CardReview, from start: Date = t0) -> Double { ((r.due ?? start).timeIntervalSince(start)) }
let fresh = CardReview()
check(abs(wait(SpacedRepetition.review(fresh, rating: .good, now: t0)) - 600) < 1, "srs: new card good -> 10 min")
check(abs(wait(SpacedRepetition.review(fresh, rating: .again, now: t0)) - 60) < 1, "srs: new card again -> 1 min")
let graduated = after(fresh, [.good, .good])
check(graduated.interval == 1 && !graduated.learning, "srs: good twice graduates to 1 day (\(graduated.interval))")
check(SpacedRepetition.review(fresh, rating: .easy, now: t0).interval == 4, "srs: easy graduates to 4 days")
let reviewed = SpacedRepetition.review(graduated, rating: .good, now: t0)
check(abs(reviewed.interval - 2.5) < 1e-9 && abs(wait(reviewed) - 2.5 * 86_400) < 1, "srs: good multiplies by ease (\(reviewed.interval))")
let lapsed = SpacedRepetition.review(reviewed, rating: .again, now: t0)
check(lapsed.learning && lapsed.lapses == 1 && abs(lapsed.ease - 2.3) < 1e-9 && abs(wait(lapsed) - 600) < 1, "srs: again relearns in 10 min")
let relearned = SpacedRepetition.review(lapsed, rating: .good, now: t0)
check(!relearned.learning && abs(relearned.interval - 1.25) < 1e-9, "srs: relearned at half the interval (\(relearned.interval))")
var mature = CardReview()
mature.learning = false
mature.interval = 10
mature.reps = 5
mature.due = t0
check(abs(SpacedRepetition.review(mature, rating: .hard, now: t0).interval - 12) < 1e-9, "srs: hard x1.2")
let easyMature = SpacedRepetition.review(mature, rating: .easy, now: t0)
check(abs(easyMature.interval - 32.5) < 1e-9 && abs(easyMature.ease - 2.65) < 1e-9, "srs: easy x ease x 1.3, ease up")
var floor = mature
floor.ease = 1.35
check(abs(SpacedRepetition.review(floor, rating: .again, now: t0).ease - 1.3) < 1e-9, "srs: ease never below 1.3")
check(SpacedRepetition.isDue(fresh, now: t0) && !SpacedRepetition.isDue(graduated, now: t0), "srs: new cards are due, graduated ones wait")

// MARK: Study tools (StudyOffline, MindMapLayout)

let turkishParts = [
    (title: "Türev", text: """
    Türev, bir fonksiyonun anlık değişim oranıdır. Bir eğrinin bir noktadaki teğetinin eğimine o noktadaki türev denir.
    Türevin işareti fonksiyonun artan ya da azalan olduğunu gösterir. Türev sıfır olduğunda fonksiyonun kritik noktası vardır.
    Limit kavramı türevin tanımında kullanılır ve süreklilik türevlenebilmenin ön koşuludur.
    """),
    (title: "İntegral", text: """
    Belirli integral, bir eğrinin altında kalan alanı verir. Antitürev, türevi verilen fonksiyona eşit olan fonksiyondur.
    Analizin temel teoremi türev ile integralin birbirinin tersi olduğunu söyler. İntegral alan ve hacim hesaplarında kullanılır.
    """),
]
let englishParts = [
    (title: "Cells", text: """
    A cell is the smallest unit of life that can replicate independently. Mitochondria are called the powerhouse of the cell.
    Photosynthesis refers to the process by which plants turn light into chemical energy. The nucleus contains the genetic material of the cell.
    Ribosome: a small structure that builds proteins from amino acids. Membranes control what enters and leaves the cell.
    """),
]
let trCards = StudyOffline.flashcards(parts: turkishParts, english: false, count: 8)
check(trCards.contains { $0.front == "Türev nedir?" && $0.back.contains("anlık değişim oranıdır") }, "study: turkish definition card \(trCards.map(\.front))")
check(trCards.contains { $0.front.hasPrefix("Antitürev") || $0.front.contains("Antitürev") }, "study: second turkish definition")
check(trCards.count >= 4 && trCards.count <= 8 && Set(trCards.map(\.front)).count == trCards.count, "study: card count and no repeats (\(trCards.count))")
let enCards = StudyOffline.flashcards(parts: englishParts, english: true, count: 8)
check(enCards.contains { $0.front == "What is a cell?" } && enCards.contains { $0.front == "What is ribosome?" || $0.front == "What is a ribosome?" },
      "study: english definition cards \(enCards.map(\.front))")
check(enCards.contains { $0.front.lowercased().contains("photosynthesis") }, "study: 'refers to' card")
let quiz = StudyOffline.quiz(parts: turkishParts, english: false, count: 5)
check(!quiz.isEmpty && quiz.allSatisfy { $0.choices.count == 4 && Set($0.choices).count == 4 && $0.choices.indices.contains($0.answer) },
      "study: quiz has four different choices (\(quiz.count))")
check(quiz.allSatisfy { q in q.question.contains("_____") && !q.question.lowercased().contains(q.choices[q.answer].lowercased()) },
      "study: the answer is blanked out of the question")
let map = StudyOffline.mindMap(title: "Kalkülüs", parts: turkishParts, english: false)
check(map.title == "Kalkülüs" && map.children.map(\.title) == ["Türev", "İntegral"] && map.children.allSatisfy { !$0.children.isEmpty },
      "study: mind map branches")
let guide = StudyOffline.guide(parts: turkishParts, english: false)
check(guide.sections.map(\.heading) == ["Türev", "İntegral"] && !guide.summary.isEmpty && guide.terms.contains { $0.term == "Türev" } && !guide.questions.isEmpty,
      "study: guide")

func tree(_ title: String, _ children: [MindNode] = []) -> MindNode { MindNode(title: title, children: children) }
let mapRoot = tree("Root", [tree("A", [tree("A1"), tree("A2"), tree("A3")]), tree("B"), tree("C", [tree("C1")])])
let placed = MindMapLayout.layout(mapRoot, collapsed: [], size: { node, _ in CGSize(width: 40 + CGFloat(node.title.count) * 8, height: 30) },
                                  columnGap: 50, rowGap: 12)
check(placed.count == 8, "mindmap: every node placed")
var overlap = false
for i in placed.indices {
    for j in placed.indices where j > i && placed[i].frame.intersects(placed[j].frame) { overlap = true }
}
check(!overlap, "mindmap: no overlap")
let byID = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0) })
check(placed.allSatisfy { p in p.parent.map { byID[$0]!.frame.maxX < p.frame.minX } ?? true }, "mindmap: children right of their parent")
let aNode = placed.first { $0.title == "A" }!
let aKids = placed.filter { $0.parent == aNode.id }
check(abs(aNode.frame.midY - (aKids.map(\.frame.midY).min()! + aKids.map(\.frame.midY).max()!) / 2) < 0.5, "mindmap: parent centred on its children")
let folded = MindMapLayout.layout(mapRoot, collapsed: [mapRoot.children[0].id], size: { _, _ in CGSize(width: 60, height: 30) }, columnGap: 50, rowGap: 12)
check(folded.count == 5 && !folded.contains { $0.title == "A1" }, "mindmap: a folded branch hides its children")

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
