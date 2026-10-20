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
