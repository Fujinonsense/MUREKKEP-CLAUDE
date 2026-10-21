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

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
