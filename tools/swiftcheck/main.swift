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
check(RecordingSync.skip(time: 10, by: -5, duration: 60) == 5 && RecordingSync.skip(time: 3, by: -5, duration: 60) == 0
      && RecordingSync.skip(time: 58, by: 5, duration: 60) == 60, "recording: arrow keys jump within the take")
check(RecordingSync.volume(1, step: 0.1) == 1 && RecordingSync.volume(1, step: -0.1) == 0.9
      && RecordingSync.volume(0.9, step: -0.1) == 0.8 && RecordingSync.volume(0.05, step: -0.1) == 0, "recording: volume in tenths")

// MARK: Word spaces of typed text (WordSpacing)

// The font's tracking 2.8 with an example space of 5.5 (font units, a tenth of the cap height).
check(WordSpacing.space(tracking: 2.8, fontTracking: 2.8, spaceAdvance: 5.5) == 5.5, "word space: the font's own at its own tracking")
let thick = WordSpacing.space(tracking: 4.0, fontTracking: 2.8, spaceAdvance: 5.5)
check(abs(thick - 8.5) < 0.0001, "word space: a thick 3D ink (tracking 4.0) gets 8.5, not 5.5")
// What the eye sees: the gaps minus the line width (here 2 units for the thick ink).
check((thick - 2) / (4.0 - 2) >= 2.5, "word space: a word gap reads as at least 2.5 letter gaps on thick ink")
check(WordSpacing.space(tracking: 3.4, fontTracking: 2.8, spaceAdvance: 5.5) > 5.5
      && WordSpacing.space(tracking: 3.4, fontTracking: 2.8, spaceAdvance: 5.5) < thick, "word space: grows with the tracking")

// MARK: Letter and word gaps of the typed font (StrokeFont)

/// Ink of each drawn character across the x-height band (0.8…6.2 above the baseline, font units), as
/// typed text lays it out; nil for a space.
func bandSpans(_ text: String, tracking: Float = StrokeFont.tracking) -> [(ch: Character, lo: Float, hi: Float)?] {
    var out: [(ch: Character, lo: Float, hi: Float)?] = []
    for mark in StrokeFont.layout(text, tracking: tracking).marks {
        var xs: [Float] = []
        for path in mark.glyph.paths {
            let pts = path.map { SIMD2<Float>(mark.x + $0.x * mark.k, mark.rise + $0.y * mark.k) }
            for (a, b) in zip(pts, pts.dropFirst()) {
                for s in 0...10 {
                    let p = a + (b - a) * (Float(s) / 10)
                    if p.y >= 0.8 && p.y <= 6.2 { xs.append(p.x) }
                }
            }
            if pts.count == 1, pts[0].y >= 0.8, pts[0].y <= 6.2 { xs.append(pts[0].x) }
        }
        if mark.spaceBefore { out.append(nil) }
        if let lo = xs.min(), let hi = xs.max() { out.append((mark.ch, lo, hi)) }
    }
    return out
}

/// The widest gap between letters of a word and the narrowest gap between words, across the band.
func gaps(_ text: String) -> (letters: Float, words: Float) {
    var letters: Float = 0
    var words: Float = .infinity
    let spans = bandSpans(text)
    var previous: (ch: Character, lo: Float, hi: Float)?
    var spaced = false
    for span in spans {
        guard let span else { spaced = true; continue }
        if let p = previous {
            let gap = span.lo - p.hi
            if spaced { words = min(words, gap) } else { letters = max(letters, gap) }
        }
        previous = span
        spaced = false
    }
    return (letters, words)
}

// Lowercase letters keep their ink near their sides; "r", "t" and "f" left gaps as wide as a word space
// ("der ste", "tekr ar", "no t").
let openSides = "abcçdefgğhkmnoöprsştuüvwxyz".filter { ch in
    let spans = bandSpans("n\(ch)n").compactMap { $0 }
    guard spans.count == 3 else { return true }
    return spans[1].lo - spans[0].hi > 2.0 + StrokeFont.tracking || spans[2].lo - spans[1].hi > 2.0 + StrokeFont.tracking
}
check(openSides.isEmpty, "font: no lowercase letter leaves more than 2 units of air beside its ink (open: \(String(openSides)))")
for sample in ["Bugün derste türev ve integral konusunu tekrar ettik", "artık fırtına ortak birtakım şeyler",
               "Türkiye Test Yarın Tarih fıstık"] {
    let g = gaps(sample)
    check(g.words >= 1.4 * g.letters, "font: words stand apart in \"\(sample)\" (word gap \(g.words), letter gap \(g.letters))")
}
let tu = bandSpans("Tü").compactMap { $0 }
check(tu.count == 2 && tu[1].lo - tu[0].hi <= 4.6, "font: a lowercase letter tucks under the T")
check(abs(StrokeFont.width("ortak birtakım") - StrokeFont.layout("ortak birtakım").width) < 0.0001,
      "font: width and layout agree")

// Typed text is written like a pen (Lettering): ends ease in and out, downstrokes are fuller than
// crossbars, a dot stays round.
func lettered(_ path: [SIMD2<Float>]) -> [InkPoint] {
    var pts = path.map { InkPoint(x: $0.x, y: $0.y, r: 1.5, ink: 0.55) }
    Lettering.apply(&pts)
    return pts
}
let downstroke = lettered((0...40).map { SIMD2<Float>(0, Float($0)) })
let crossbar = lettered((0...40).map { SIMD2<Float>(Float($0), 0) })
check(downstroke[0].r < downstroke[20].r * 0.7 && downstroke[40].r < downstroke[20].r * 0.7,
      "lettering: a stroke eases in and out")
check(downstroke[20].r > crossbar[20].r * 1.2, "lettering: a downstroke is fuller than a crossbar")
check(lettered([SIMD2<Float>(0, 0), SIMD2<Float>(0, 0.5)]).allSatisfy { $0.r > 1.5 },
      "lettering: a dot stays round and bold")

// MARK: Photos as PDF pages (PhotoPDF)

// A page has the photo's own shape and A4's long side; photos are scaled down, never up.
check(PhotoPDF.pageSize(for: CGSize(width: 3024, height: 4032)) == CGSize(width: 632, height: 842),
      "photo pdf: a portrait phone photo gets a portrait page as tall as A4")
check(PhotoPDF.pageSize(for: CGSize(width: 2732, height: 2048)) == CGSize(width: 842, height: 631),
      "photo pdf: an iPad screenshot gets a landscape page as wide as A4")
check(PhotoPDF.scaledPixels(for: CGSize(width: 4032, height: 3024)) == CGSize(width: 2400, height: 1800),
      "photo pdf: a 12 MP photo is scaled down to 2400 px")
check(PhotoPDF.scaledPixels(for: CGSize(width: 800, height: 600)) == CGSize(width: 800, height: 600),
      "photo pdf: a small photo keeps its size")
check(PhotoPDF.fileName("Ders: 3/4") == "Ders- 3-4" && PhotoPDF.fileName("  ") == "Photos",
      "photo pdf: titles become safe file names")

// MARK: Typing from a keyboard (KeyboardSpot)

// Page lines 28 apart; the view shows y 0…600; the margin is at 60.
let notes = [CGRect(x: 60, y: 90, width: 300, height: 20), CGRect(x: 60, y: 118, width: 200, height: 22)]
let underNotes = KeyboardSpot.start(lastTyped: nil, ink: notes, viewTop: 0, viewBottom: 600, left: 60, spacing: 28)
check(underNotes.x == 60 && abs(underNotes.y - (140 + 0.2 * 28)) < 0.001, "keyboard: typing starts under the notes in view")
let typed = CGRect(x: 120, y: 118, width: 200, height: 22)
let underTyped = KeyboardSpot.start(lastTyped: typed, ink: [notes[0], typed], viewTop: 0, viewBottom: 600, left: 60, spacing: 28)
check(underTyped.x == 120 && abs(underTyped.y - (140 + 0.2 * 28)) < 0.001, "keyboard: typing goes on under the last typed text, at its left")
let inkBelow = [typed, CGRect(x: 60, y: 200, width: 300, height: 20)]
check(KeyboardSpot.start(lastTyped: typed, ink: inkBelow, viewTop: 0, viewBottom: 600, left: 60, spacing: 28).x == 60,
      "keyboard: handwriting under the typed text comes first")
check(KeyboardSpot.start(lastTyped: nil, ink: [], viewTop: 300, viewBottom: 900, left: 60, spacing: 28) == CGPoint(x: 60, y: 328),
      "keyboard: an empty view starts a line under its top")
// Ink down to the bottom of the view: the first free line in view.
let full = [CGRect(x: 60, y: 300, width: 400, height: 60), CGRect(x: 60, y: 420, width: 400, height: 200)]
let free = KeyboardSpot.start(lastTyped: nil, ink: full, viewTop: 300, viewBottom: 600, left: 60, spacing: 28)
check(free.y > 360 && free.y + 28 <= 420, "keyboard: ink to the bottom of the view: the first free line")

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
var lowEase = mature
lowEase.ease = 1.35
check(abs(SpacedRepetition.review(lowEase, rating: .again, now: t0).ease - 1.3) < 1e-9, "srs: ease never below 1.3")
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

// MARK: Finding the computer's AI (LocalServerFinder)

let home = LocalServerFinder.candidates(ip: "192.168.1.37", mask: "255.255.255.0")
check(home.count == 253 && !home.contains("192.168.1.37") && home.contains("192.168.1.1") && home.contains("192.168.1.254")
      && !home.contains("192.168.1.0") && !home.contains("192.168.1.255"), "finder: a /24 home network (\(home.count))")
check(home.first == "192.168.1.36" || home.first == "192.168.1.38", "finder: neighbours first (\(home.first ?? "-"))")
let wide = LocalServerFinder.candidates(ip: "10.20.30.40", mask: "255.255.0.0")
check(wide.count == 253 && wide.allSatisfy { $0.hasPrefix("10.20.30.") }, "finder: a wide network is scanned around the iPad only")
check(LocalServerFinder.candidates(ip: "10.0.0.5", mask: "255.255.255.252") == ["10.0.0.6"], "finder: a tiny network")
check(LocalServerFinder.candidates(ip: "bad", mask: "255.255.255.0").isEmpty, "finder: no address, nothing to scan")

// MARK: Content search (TextSearch)

let searchPage = "Ders notları: Öğrenci İSTANBUL'da türevin tanımını öğrendi. Sonra integral geldi; türev ile integral birbirinin tersidir."
check(TextSearch.normalize("İSTANBUL Işık ÖĞRENCİ") == "istanbul isik ogrenci", "search: turkish letters fold (\(TextSearch.normalize("İSTANBUL Işık ÖĞRENCİ")))")
let hits = TextSearch.hits(query: "ogrenci", in: searchPage, limit: 5)
check(hits.count == 1 && hits[0].match == "Öğrenci", "search: diacritics and case do not matter (\(hits.map(\.match)))")
let many = TextSearch.hits(query: "integral", in: searchPage, limit: 5)
check(many.count == 2 && many[0].before.hasSuffix("Sonra ") && many[0].after.hasPrefix(" geldi"), "search: every match with its context")
let short = TextSearch.hits(query: "integral", in: searchPage, limit: 1)
check(short.count == 1, "search: limit")
check(TextSearch.hits(query: "  ", in: searchPage, limit: 5).isEmpty && TextSearch.hits(query: "kimya", in: searchPage, limit: 5).isEmpty, "search: nothing to find")
let longText = String(repeating: "lorem ipsum ", count: 30) + "hedef kelime" + String(repeating: " dolor sit", count: 30)
let ctx = TextSearch.hits(query: "hedef", in: longText, limit: 1)[0]
check(ctx.before.count <= 48 && ctx.after.count <= 72 && ctx.before.hasPrefix("…") && ctx.after.hasSuffix("…"), "search: context is trimmed")

// MARK: Downloadable model (BrainCatalog, tests/test_brain.py)

let gib: UInt64 = 1_073_741_824
check(BrainModel.best(physicalMemory: 16 * gib, available: 9_000_000_000) == .qwen9B, "brain: 16 GB gets the 9B")
check(BrainModel.best(physicalMemory: 16 * gib, available: 5_000_000_000) == .qwen4B, "brain: little free memory gets the 4B")
check(BrainModel.best(physicalMemory: 12 * gib, available: nil) == .qwen9B, "brain: unknown free memory keeps the 9B")
check(BrainModel.best(physicalMemory: UInt64(7.6 * Double(gib)), available: 4_500_000_000) == .qwen4B, "brain: 8 GB gets the 4B")
check(BrainModel.best(physicalMemory: 6 * gib, available: nil) == .qwen2B && BrainModel.best(physicalMemory: 4 * gib, available: nil) == nil,
      "brain: 6 GB gets the 2B, 4 GB none")
check(BrainMemory.need(weights: 3_061_000_000) == 3_761_000_000, "brain memory: the weights and 0.7 GB to answer")
let roomy = BrainMemory(used: 1_200_000_000, free: 4_900_000_000)
check(roomy.limit == 6_100_000_000 && roomy.fits(weights: BrainModel.qwen4B.bytes) && !roomy.fits(weights: BrainModel.qwen9B.bytes),
      "brain memory: the limit is used plus free; the 4B fits in 4.9 GB free, the 9B not")
check(["config.json", "model.safetensors", "tokenizer.json", "chat_template.jinja", "vocab.json"].allSatisfy(BrainModel.wanted)
      && !["README.md", ".gitattributes", "images/demo.png", "onnx/model.json"].contains(where: BrainModel.wanted), "brain: model files only")
let thought = ThinkingText.split("Önce şıkları tartalım. 12+3=15.\n</think>\n\nB şıkkı doğrudur.\nCevap: B", thinking: true)
check(thought.thinking == "Önce şıkları tartalım. 12+3=15." && thought.answer.hasSuffix("Cevap: B") && thought.answering, "brain: thinking and answer split")
check(ThinkingText.split("Önce şıklar", thinking: true) == .init(thinking: "Önce şıklar", answer: "", answering: false)
      && ThinkingText.split("<think>düşünce</think>Cevap: A", thinking: true) == .init(thinking: "düşünce", answer: "Cevap: A", answering: true)
      && ThinkingText.split("Kısa cevap.", thinking: false) == .init(thinking: "", answer: "Kısa cevap.", answering: true), "brain: thinking in progress, tags, no thinking")
let abcde: [Character] = ["A", "B", "C", "D", "E"]
let choices: [(String, Character?)] = [
    ("Gerekçe...\nCevap: C", "C"), ("**Cevap: B**", "B"), ("Doğru cevap **D) 12** çünkü toplam 12 eder.", "D"),
    ("Answer: (a)", "A"), ("The correct answer is E.", "E"), ("Doğru şık C'dir.", "C"), ("YANIT: D", "D"),
    ("Cevap A olamaz, çünkü fiil yok.\nCevap: D", "D"), ("Cevap açık değil; cevap edilebilir bir soru.", nil), ("Bence **B** çünkü...", "B"),
    ("**Şıkların Değerlendirilmesi:**\nA) 8: Yanlış.\nB) 0: Yanlış.\nC) Tanımsızdır: Yanlış, limit var.\nD) 4: Doğru.\nE) 2: Yanlış.", "D"),
    ("A) went: incorrect\nB) has gone — Correct, present perfect.\nC) go: wrong", "B"), ("* **C)** 3/4: **Doğru**", "C"),
    ("A) 1: Doğru\nB) 2: Doğru", nil), ("C) x − 2: Doğru değil.", nil), ("A) 8: Doğru gibi görünüyor ama değil.\nCevap: D", "D"),
]
for (text, want) in choices {
    let got = ThinkingText.choice(in: text, letters: abcde)
    check(got == want, "brain: choice of \"\(text.prefix(28))\" = \(got.map(String.init) ?? "nil")")
}
check(ThinkingText.choice(in: "Cevap: E", letters: ["A", "B", "C", "D"]) == nil, "brain: only the question's letters")
check(ThinkingText.explanation("Metinde yazar umudu anlatıyor.\nBu yüzden B.\nCevap: B") == "Metinde yazar umudu anlatıyor.\nBu yüzden B."
      && ThinkingText.explanation("**Cevap: B**, çünkü metnin tamamı umudu anlatıyor.") == "**Cevap: B**, çünkü metnin tamamı umudu anlatıyor.",
      "brain: the choice line leaves the explanation")
check(BrainBudget.thinking(for: "3x + 5 = 20 ise x kaçtır?") == 1_024 && BrainBudget.thinking(for: "√16 + 2² − 3 = ?") == 1_024
      && BrainBudget.thinking(for: "Parçada asıl anlatılmak istenen nedir?") == 512 && BrainBudget.thinking(for: "1923 yılında ne oldu?") == 512,
      "brain: arithmetic thinks longer")
// Half the old budgets: Qwen3.5 4B got 39 of 40 test questions right at 2,048/768 and at 1,024/384, and
// always spends its whole budget, so the wait halves.
check(BrainBudget.exercise == 512 && BrainBudget.deep == 768, "brain: exercises and checks think half as long as before")
check(BrainModel.sizeText(3_061_000_000, english: false) == "3,1 GB" && BrainModel.sizeText(5_977_000_000, english: true) == "6.0 GB", "brain: sizes")

// The text pen reads a line again when the writing goes on (tests/test_textpen_batch.py).
let aga = CGRect(x: 100, y: 200, width: 60, height: 40)
func box(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect { CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) }
let batchCases: [(CGRect, TimeInterval, Bool, String)] = [
    (box(180, 205, 260, 236), 2, true, "next word"), (box(175, 196, 230, 238), 1, true, "ascender"),
    (box(175, 212, 230, 248), 1, true, "descender"), (box(100, 262, 200, 300), 2, false, "next line"),
    (box(160 + 4 * 40 + 5, 205, 400, 236), 2, false, "far right"), (box(20, 205, 80, 236), 2, false, "back at the start"),
    (box(148, 190, 152, 194), 3, true, "dot"), (box(163, 234, 166, 238), 3, true, "full stop"),
    (box(165, 196, 171, 206), 3, true, "closing quote"), (box(180, 205, 260, 236), 14.9, true, "within the window"),
    (box(180, 205, 260, 236), 15.1, false, "after the window"), (box(180, 205, 260, 236), -1, false, "negative time"),
]
for (next, elapsed, want, name) in batchCases {
    check(TextPenBatch.continues(last: aga, next: next, elapsed: elapsed) == want, "text pen batch: \(name)")
}

// The model's background download picks up where it stopped (BrainDownloadPlan).
let weights = BrainDownloadPlan.File(path: "model.safetensors", size: 1_000)
let none = BrainDownloadPlan.OnDisk(whole: -1, part: -1)
check(BrainDownloadPlan.step(weights, none) == .fetch(from: 0), "brain download: nothing yet starts at 0")
check(BrainDownloadPlan.step(weights, .init(whole: -1, part: 400)) == .fetch(from: 400), "brain download: a part goes on")
check(BrainDownloadPlan.step(weights, .init(whole: -1, part: 1_000)) == .finish, "brain download: a full part is finished")
check(BrainDownloadPlan.step(weights, .init(whole: -1, part: 1_200)) == .fetch(from: 0), "brain download: a part too big starts over")
check(BrainDownloadPlan.step(weights, .init(whole: 1_000, part: -1)) == .done, "brain download: the whole file is done")
check(BrainDownloadPlan.step(weights, .init(whole: 900, part: -1)) == .fetch(from: 0), "brain download: a short file is fetched again")
check(BrainDownloadPlan.step(.init(path: "config.json", size: nil), .init(whole: 12, part: -1)) == .done,
      "brain download: a file of unknown size is done once there")
let files = [weights, BrainDownloadPlan.File(path: "config.json", size: 100)]
let disk: (String) -> BrainDownloadPlan.OnDisk = { $0 == "config.json" ? .init(whole: 100, part: -1) : .init(whole: -1, part: 300) }
let shown = BrainDownloadPlan.progress(files, disk: disk, inFlight: ["model.safetensors": 200])
check(shown.done == 600 && shown.total == 1_100, "brain download: progress \(shown)")
check(BrainDownloadPlan.merge(status: 200, rangeStart: nil, partSize: 300, received: 1_000, expected: 1_000) == .replace
      && BrainDownloadPlan.merge(status: 206, rangeStart: 300, partSize: 300, received: 700, expected: 1_000) == .append
      && BrainDownloadPlan.merge(status: 206, rangeStart: 0, partSize: 300, received: 500, expected: 1_000) == .discard
      && BrainDownloadPlan.merge(status: 404, rangeStart: nil, partSize: 0, received: 1_000, expected: 1_000) == .discard,
      "brain download: merging a finished download")
// Resumed downloads: the last response's Content-Range starts where iOS resumed, not where the part
// ends, so the sizes decide.
check(BrainDownloadPlan.merge(status: 206, rangeStart: 650, partSize: 300, received: 700, expected: 1_000) == .append
      && BrainDownloadPlan.merge(status: 206, rangeStart: 650, partSize: 0, received: 1_000, expected: 1_000) == .replace,
      "brain download: a resumed download is merged by its size")
check(BrainDownloadPlan.merge(status: 200, rangeStart: nil, partSize: 0, received: 12, expected: nil) == .replace
      && BrainDownloadPlan.merge(status: 206, rangeStart: 5, partSize: 5, received: 7, expected: nil) == .append,
      "brain download: unknown sizes go by the response")
check(BrainDownloadPlan.rangeStart("bytes 300-999/1000") == 300 && BrainDownloadPlan.rangeStart(nil) == nil
      && BrainDownloadPlan.rangeStart("bytes */1000") == nil, "brain download: Content-Range")

// Mürekkep Pro: what the free plan allows (ProPlan).
var proCalendar = Calendar(identifier: .iso8601)
proCalendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
func day(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "T12:00:00+03:00")! }
var usage = ProPlan.Usage()
let wednesday = day("2026-10-21")
for _ in 0..<ProPlan.dailyAnswers { check(usage.consume(.aiAnswer, isPro: false, on: wednesday, calendar: proCalendar), "pro: free answers") }
check(!usage.consume(.aiAnswer, isPro: false, on: wednesday, calendar: proCalendar), "pro: the 16th answer of a day waits")
check(usage.remaining(.aiAnswer, on: wednesday, calendar: proCalendar) == 0
      && usage.remaining(.aiAnswer, on: day("2026-10-22"), calendar: proCalendar) == ProPlan.dailyAnswers,
      "pro: answers come back the next day")
check(usage.consume(.aiAnswer, isPro: true, on: wednesday, calendar: proCalendar), "pro: Pro answers without a limit")
check(usage.consume(.overview, isPro: false, on: wednesday, calendar: proCalendar)
      && !usage.consume(.overview, isPro: false, on: day("2026-10-25"), calendar: proCalendar)
      && usage.consume(.overview, isPro: false, on: day("2026-10-26"), calendar: proCalendar),
      "pro: one overview a week (ISO weeks start on Monday)")
var sets = ProPlan.Usage()
for _ in 0..<ProPlan.weeklyStudySets { _ = sets.consume(.studySet, isPro: false, on: wednesday, calendar: proCalendar) }
check(!sets.consume(.studySet, isPro: false, on: wednesday, calendar: proCalendar), "pro: three study sets a week")
check(!ProPlan.Usage().allows(.premiumInk, isPro: false, on: wednesday, calendar: proCalendar)
      && ProPlan.Usage().allows(.premiumInk, isPro: true, on: wednesday, calendar: proCalendar),
      "pro: premium inks only with Pro")
check(ProPlan.products.map(\.id) == ["murekkep.pro.monthly", "murekkep.pro.yearly", "murekkep.pro.lifetime"]
      && ProPlan.products.allSatisfy { !$0.fallbackPriceTR.isEmpty && !$0.fallbackPriceUS.isEmpty },
      "pro: the three plans")
check(ProPlan.isPremium(template: "resume") && !ProPlan.isPremium(template: "cornell") && !ProPlan.isPremium(template: "lined"),
      "pro: templates")
check(ProPlan.yearlySaving(monthly: 129.99, yearly: 899.99) == 42 && ProPlan.yearlySaving(monthly: 3.99, yearly: 24.99) == 47
      && ProPlan.yearlySaving(monthly: 0, yearly: 10) == 0 && ProPlan.yearlySaving(monthly: 1, yearly: 20) == 0,
      "pro: the yearly plan's saving")
check(ProPlan.products.allSatisfy { $0.fallbackAmountTR > 0 && $0.fallbackAmountUS > 0 }, "pro: planned amounts")
check(ProPlan.product(.lifetime).fallbackAmountTR >= 3 * ProPlan.product(.yearly).fallbackAmountTR
      && ProPlan.product(.lifetime).fallbackAmountUS >= 3 * ProPlan.product(.yearly).fallbackAmountUS,
      "pro: lifetime costs more than three years of the yearly plan")

// The notebook's pen bar: favourites first, then the pens used last.
let order = ["pen", "pencil", "fountain", "marker", "highlighter", "lava", "gold", "brush"]
let noFavourites = PenStrip.pens(favorites: [String](), recent: ["gold", "pen", "brush", "pencil", "lava", "marker"], order: order)
check(noFavourites.favorites.isEmpty && noFavourites.recent == ["pen", "pencil", "lava", "gold", "brush"],
      "pen bar: without favourites, the five used last in the panel's order")
let withFavourites = PenStrip.pens(favorites: ["gold", "pencil"], recent: ["gold", "pen", "brush", "pencil", "lava"], order: order)
check(withFavourites.favorites == ["pencil", "gold"] && withFavourites.recent == ["pen", "lava", "brush"],
      "pen bar: favourites stay, recent pens fill up to five")
let manyFavourites = PenStrip.pens(favorites: ["pen", "pencil", "fountain", "marker", "highlighter", "lava"],
                                   recent: ["brush", "gold", "pen"], order: order)
check(manyFavourites.favorites.count == 6 && manyFavourites.recent == ["gold", "brush"],
      "pen bar: two recent pens stay beside many favourites")
check(PenStrip.toggled("gold", in: ["pen"]) == ["pen", "gold"] && PenStrip.toggled("pen", in: ["pen", "gold"]) == ["gold"],
      "pen bar: starring and unstarring")

// Trial ink: the nature pens draw a fixed amount for free, once; Pro draws without a limit.
var ink = ProPlan.Usage()
check(ink.inkLeft() == ProPlan.trialInk && ProPlan.trialInk == 3_000, "trial ink: a full trial to start (about 5 lines)")
check(ink.spendInk(2_000, isPro: false) && ink.inkLeft() == 1_000, "trial ink: a stroke spends its length")
check(ink.spendInk(1_500, isPro: false) && ink.inkLeft() == 0, "trial ink: the last stroke may run past the end")
check(!ink.spendInk(10, isPro: false) && ink.inkLeft() == 0, "trial ink: none left, nothing drawn")
check(ink.spendInk(10, isPro: true) && ink.inkLeft() == 0, "trial ink: Pro draws on")
check(ink.consume(.aiAnswer, isPro: false, on: wednesday, calendar: proCalendar) && ink.inkLeft() == 0,
      "trial ink: daily allowances do not reset it")
check(PenShelf.nature.brushes(favorites: []).allSatisfy(\.isTrialInk)
      && Brush.allCases.filter(\.isTrialInk).allSatisfy { PenShelf.shelf(of: $0) == .nature }
      && ProPlan.limit(.trialInk) == nil,
      "trial ink: exactly the nature shelf's pens")

// The pen panel's shelves (PenShelf): each pen on exactly one shelf, the 3D inks together.
let shelved = PenShelf.allCases.filter { $0 != .favorites }.flatMap { $0.brushes(favorites: []) }
check(shelved.count == Brush.allCases.count && Set(shelved) == Set(Brush.allCases), "pen shelves: every pen once")
check(PenShelf.threeD.brushes(favorites: []).allSatisfy(\.isPremium)
      && PenShelf.allCases.filter { $0 != .threeD && $0 != .favorites }.allSatisfy { $0.brushes(favorites: []).allSatisfy { !$0.isPremium } },
      "pen shelves: the 3D inks have their own shelf")
check(PenShelf.favorites.brushes(favorites: [.lava, .pen]) == [.pen, .lava], "pen shelves: favourites in the panel's order")
check(PenShelf.shelf(of: .gold) == .threeD && PenShelf.shelf(of: .pencil) == .writing && PenShelf.shelf(of: .grass) == .nature
      && PenShelf.shelf(of: .neon) == .paint, "pen shelves: a pen's own shelf")
check(PenShelf.opening(saved: "", favorites: [], current: .neon) == .paint
      && PenShelf.opening(saved: "", favorites: [.pen], current: .neon) == .favorites
      && PenShelf.opening(saved: "nature", favorites: [.pen], current: .neon) == .nature
      && PenShelf.opening(saved: "favorites", favorites: [], current: .lava) == .threeD,
      "pen shelves: which shelf the panel opens on")

// MARK: Math inside a worded question (MathEngine)

/// The equation the engine solved on a line and its roots; nil when it solved none.
func solved(_ line: String) -> (String, [Double])? {
    if case let .solved(text, _, roots, _, _)? = MathEngine.analyze(line) { return (text, roots) }
    return nil
}

// The engine's result reaches the model as a certain fact: a worded line gives the right result or none.
check(solved("2x+3=7 ise x kaçtır?").map { $0.0 == "2x+3=7" && $0.1 == [2] } == true,
      "math engine: the x after \"ise\" is what is asked, not part of the equation")
check(solved("x²+3x=10 ise x kaçtır?")?.1 == [-5, 2], "math engine: a worded quadratic has both roots")
check(solved("Soru 3) 2x+1=7 ise x kaçtır?")?.1 == [3] && solved("2x+3=7 ise x'in değeri kaçtır?")?.1 == [2],
      "math engine: a numbered question and \"x'in değeri\"")
check(solved("2x+3=7 ise x=?")?.1 == [2], "math engine: \"x=?\" after the equation")
check(MathEngine.analyze("2x+3=7 ise 4x kaçtır?") == nil && MathEngine.analyze("2x+3=7 ise y kaçtır?") == nil,
      "math engine: a question about something other than the unknown gets no fact")
check(MathEngine.analyze("f(x)=3x+2 ise f(4) kaçtır?") == nil, "math engine: function notation gets no fact")
if case let .value(text, v)? = MathEngine.analyze("3+4×2 işleminin sonucu kaçtır?") {
    check(text == "3+4×2" && v == 11, "math engine: the sum inside a worded question")
} else {
    check(false, "math engine: the sum inside a worded question")
}

// MARK: Handwritten math the engine settles alone (PageMath)

check(PageMath.engineSettles(["3+3=33"]), "page math: a lone calculation needs no model")
check(PageMath.engineSettles(["Soru 1", "3+3=33", "-"]), "page math: a label and a stray mark do not count")
check(PageMath.engineSettles(["2x+3=7", "2x=4", "x=2"]), "page math: equation steps are the engine's")
check(!PageMath.engineSettles(["Ali'nin 3 elması var, 2 tane daha alırsa kaç elması olur?"]), "page math: a word problem needs the model")
check(!PageMath.engineSettles(["3+3=33", "Buna göre sonuç neden yanlış"]), "page math: a sentence next to the sum needs the model")
check(!PageMath.engineSettles(["Bugün hava çok güzel"]) && !PageMath.engineSettles([]), "page math: no calculation, no engine answer")
// The engine pulls the sum out of a worded question ("3+4×2 işleminin…" → 11, "2x+3=7 ise x kaçtır?"
// → x = 2), but a question in words is the model's, with its options.
check(!PageMath.engineSettles(["3+4×2 işleminin sonucu kaçtır?", "A) 12", "B) 11"])
      && !PageMath.engineSettles(["2x+3=7 ise x kaçtır?"]), "page math: a worded question goes to the model")
check(PageMath.engineSettles(["3+3=?"]), "page math: a bare question mark is still the engine's")
// The text pen's reading (the user's own readers with Vision's readings among its candidates) wins
// on a math line when the engine can work it out; otherwise Vision's line stays.
check(PageMath.reading(vision: "343=33", pen: "3+3=33") == "3+3=33", "page math: the text pen's reading of a sum wins")
check(PageMath.reading(vision: "3+3=33", pen: nil) == "3+3=33", "page math: without the text pen Vision's line stays")
check(PageMath.reading(vision: "3+3=33", pen: "3+3=3)") == "3+3=33", "page math: a reading the engine cannot work out loses")
check(PageMath.reading(vision: "3+3=33", pen: "  ") == "3+3=33", "page math: an empty reading loses")
// A calculation typed into the chat with only question words around it is the engine's, at once.
for q in ["3+3=33 doğru mu?", "3+4×2 kaç eder?", "2x+3=7 ise x kaçtır?", "√49 nedir", "Is 12*12=144 correct?"] {
    check(PageMath.question(q) != nil, "page math: \"\(q)\" is answered by the engine")
}
for q in ["Ali'nin 3 elması var, 2 tane daha alırsa kaç elması olur?", "türev nedir?", "f(x)=3x+2 ise f(4) kaçtır?",
          "Bu sayfadaki 3. soruyu çöz", "2023 yılında ne oldu?"] {
    check(PageMath.question(q) == nil, "page math: \"\(q)\" goes to the model")
}
if case let .claim(_, holds, left, _, _)? = PageMath.question("3+3=33 doğru mu?") {
    check(!holds && left == 6, "page math: the engine finds 3+3=33 wrong (left side 6)")
} else {
    check(false, "page math: the engine finds 3+3=33 wrong (left side 6)")
}

// The flowering water pen (as in the ad's hook): a glossy turquoise line that grows glass flowers on
// thin turquoise stems once the pen lifts; no grass. Some stems stand in pairs or threes, some carry
// a small leaf or two, and the flowers come in several sizes.
let waterLine = (0...40).map { InkPoint(x: Float($0) * 5, y: 300, r: 4, ink: 0) }
let blooms = GrassGenerator.blooms(points: waterLine, width: 8, color: InkColor(hex: 0x22B8CF), seed: 0.37)
let stems = blooms.blades.filter { $0.kind == .glassStem }
let leaves = blooms.blades.filter { $0.kind == .glassLeaf }
check(blooms.flowers.count >= 8 && stems.count == blooms.flowers.count && stems.allSatisfy(\.isStem)
      && stems.count + leaves.count == blooms.blades.count,
      "flowering water: a flower on every stem, leaves on some, no grass blades")
check(blooms.flowers.allSatisfy { $0.style == GrassGenerator.glassStyle }
      && GrassGenerator.field(points: waterLine, width: 8, color: InkColor(hex: 0x3BA55D), seed: 1.5).flowers.allSatisfy { $0.style < 2.5 },
      "flowering water: glass flowers (style 3), which the grass pen never grows")
check(blooms.flowers.allSatisfy { $0.petal.z >= $0.petal.x && $0.petal.z >= $0.petal.y && $0.core.min() > 0.85 },
      "flowering water: the petals are blue and violet around a pale centre")
check(blooms.flowers.allSatisfy { (0.5...1.6).contains($0.delay) }, "flowering water: the flowers open after the pen lifts")
check(stems.allSatisfy { $0.height >= 8 && abs($0.base.y - 300) <= 4 },
      "flowering water: the stems rise from the line itself")
check(stems.allSatisfy { $0.color.y > $0.color.x + 0.3 && $0.color.z > $0.color.x + 0.3 },
      "flowering water: the stems are turquoise-blue glass, not the ink darkened")
check(!leaves.isEmpty && leaves.allSatisfy { leaf in
    stems.contains { stem in
        let t = (stem.base.y - leaf.base.y) / stem.height
        return (0.2...0.55).contains(t) && abs(stem.base.x + stem.lean * t * t - leaf.base.x) < 0.01
            && leaf.height < stem.height * 0.5 && abs(leaf.lean) >= leaf.height
    }
}, "flowering water: small leaves sit low on their stems and bend away from them")
let stemHeights = stems.map(\.height)
let flowerRadii = blooms.flowers.map(\.radius)
check((stemHeights.max() ?? 0) > (stemHeights.min() ?? 0) * 1.6 && (flowerRadii.max() ?? 0) > (flowerRadii.min() ?? 0) * 1.5,
      "flowering water: stems of different heights carry flowers of different sizes")
let stemX = stems.map(\.base.x).sorted()
check(zip(stemX, stemX.dropFirst()).contains { $1 - $0 < 8 * 0.7 }, "flowering water: some stems stand in pairs or threes")
let bloomsAgain = GrassGenerator.blooms(points: waterLine, width: 8, color: InkColor(hex: 0x22B8CF), seed: 0.37)
check(bloomsAgain.flowers.map(\.radius) == blooms.flowers.map(\.radius) && bloomsAgain.blades.map(\.base) == blooms.blades.map(\.base),
      "flowering water: the same stroke always grows the same flowers")
let longLine = (0...4000).map { InkPoint(x: Float($0) * 5, y: 300, r: 4, ink: 0) }
let longBlooms = GrassGenerator.blooms(points: longLine, width: 8, color: InkColor(hex: 0x22B8CF), seed: 0.37)
check(longBlooms.flowers.count <= 420 && longBlooms.blades.count <= 420 * 3 && longBlooms.flowers.count > 300,
      "flowering water: a very long line stays bounded")
// The live stroke's flowers are made again every frame from the growing line: a stem must stay where
// the pen passed, not slide along as the line gets longer.
let halfway = GrassGenerator.blooms(points: Array(waterLine.prefix(24)), width: 8, color: InkColor(hex: 0x22B8CF), seed: 0.37)
check(!halfway.blades.isEmpty && Set(halfway.blades.map(\.base)).isSubset(of: Set(blooms.blades.map(\.base))),
      "flowering water: stems stay put while the line grows")
let dot = GrassGenerator.blooms(points: [InkPoint(x: 50, y: 50, r: 4, ink: 0)], width: 8, color: InkColor(hex: 0x22B8CF), seed: 0.5)
check(!dot.flowers.isEmpty, "flowering water: a dot grows a flower too")
check(Brush.bloom.group == .nature && Brush.bloom.isTrialInk && !Brush.bloom.isPremium && Brush.bloom.growsFlowers
      && Brush.grass.growsFlowers && !Brush.sea.growsFlowers,
      "flowering water: a nature pen with trial ink, growing flowers like the grass")
check(Brush.bloom.shading == Brush.jelly.rawValue && Brush.sea.shading == Brush.sea.rawValue,
      "flowering water: drawn with the glossy gel shading")

// The pen bar moves to the top, the bottom or the right side, wherever the finger lets go of its grip;
// never to the left, which holds the drafting rail.
check(PaletteEdge.nearest(x: 600, y: 900, width: 1_200, height: 1_000, current: .top) == .bottom, "pen bar dock: let go low, it goes to the bottom")
check(PaletteEdge.nearest(x: 1_150, y: 500, width: 1_200, height: 1_000, current: .top) == .trailing, "pen bar dock: let go on the right, it goes right")
check(PaletteEdge.nearest(x: 600, y: 80, width: 1_200, height: 1_000, current: .bottom) == .top, "pen bar dock: let go high, it goes to the top")
check(PaletteEdge.nearest(x: 30, y: 300, width: 1_200, height: 1_000, current: .trailing) == .top
      && PaletteEdge.nearest(x: 30, y: 700, width: 1_200, height: 1_000, current: .top) == .bottom,
      "pen bar dock: let go on the left, it goes to the nearer of top and bottom")
check(PaletteEdge.nearest(x: 30, y: 500, width: 1_200, height: 1_000, current: .bottom) == .bottom,
      "pen bar dock: a tie keeps the edge it stands on")
check(!PaletteEdge.allCases.contains { "\($0)".contains("leading") || "\($0)".contains("left") }, "pen bar dock: no left edge")

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
