import Foundation

// The text pen's reading path in the app's own Swift (InkDeskew, InkLine, HandwritingModel, CTC),
// run on the cases of gen_cases.py and compared with the Python twins number by number, then scored.
// usage: textpen.exe <cases.json> <hwmodel.bin> [limit]

let args = CommandLine.arguments
let root = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: Any]
let model = HandwritingModel(data: try! Data(contentsOf: URL(fileURLWithPath: args[2])))!
let limit = args.count > 3 ? Int(args[3])! : Int.max
let pythonCharset = Array(root["charset"] as! String)
var failures = 0

func check(_ ok: Bool, _ what: String) {
    if !ok {
        failures += 1
        if failures <= 40 { print("FAIL \(what)") }
    }
}

func number(_ v: Any) -> Double { (v as? NSNumber)?.doubleValue ?? .nan }

check(model.charset == pythonCharset, "charset in hwmodel.bin matches python's")

struct PenReading {
    var degrees: Double
    var lines: [(members: [Int], base: [Int], text: String, image: InkLineImage, logProbs: [[Float]])]
}

/// What readWithModel does with a batch, without Vision and the dictionary.
func read(_ strokes: [[CGPoint]], radius: Float) -> PenReading {
    let degrees = InkDeskew.angle(strokes)
    let pivot = InkDeskew.centre(strokes)
    let levelled = strokes.enumerated().map { k, s in
        Stroke(id: k, points: s.map { p in
            let q = degrees == 0 ? p : InkDeskew.level(p, degrees: degrees, centre: pivot)
            return InkPoint(x: Float(q.x), y: Float(q.y), r: radius)
        })
    }
    var out: [(members: [Int], base: [Int], text: String, image: InkLineImage, logProbs: [[Float]])] = []
    for line in InkLine.lines(levelled) {
        let (base, _) = InkLine.splitRaised(line)
        guard let image = InkLine.render(base) else { continue }
        let lp = model.logProbs(image)
        let text = CTC.beam(lp, charset: model.charset).first?.text ?? ""
        out.append((line.map(\.id).sorted(), base.map(\.id).sorted(), text, image, lp))
    }
    return PenReading(degrees: degrees, lines: out)
}

var exact = 0, lineCount = 0, total = 0, parityCases = 0
var worstImage: Float = 0, worstLogProb: Float = 0, meanImage: Double = 0, imagesCompared = 0
var textAgree = 0, textCompared = 0
let started = Date()
for (n, item) in (root["cases"] as! [[String: Any]]).enumerated() {
    guard n < limit else { break }
    let radius = Float(number(item["radius"]!))
    guard radius == 0 else { continue }  // the line finder and the renderer ignore the pen's radius
    let texts = item["texts"] as! [String]
    let strokes = (item["strokes"] as! [[[Any]]]).map { s in s.map { CGPoint(x: number($0[0]), y: number($0[1])) } }
    let got = read(strokes, radius: radius)
    total += 1
    exact += got.lines.map(\.text) == texts ? 1 : 0
    lineCount += got.lines.count == texts.count ? 1 : 0
    // The same strokes with a thick 3D pen's radius must be read exactly the same.
    if n % 7 == 0 {
        let thick = read(strokes, radius: 2.6)
        check(thick.lines.map(\.members) == got.lines.map(\.members) && thick.lines.map(\.text) == got.lines.map(\.text),
              "case \(n): a thick pen changes the reading")
    }
    guard let py = item["python"] as? [String: Any] else { continue }
    parityCases += 1
    check(abs(got.degrees - number(py["angle"]!)) < 1e-6, "case \(n): deskew \(got.degrees) vs \(number(py["angle"]!))")
    let pyLines = py["lines"] as! [[String: Any]]
    let members = pyLines.map { ($0["members"] as! [Any]).map { Int(number($0)) } }
    check(got.lines.map(\.members) == members, "case \(n) \(texts): lines \(got.lines.map(\.members.count)) vs python \(members.map(\.count))")
    guard got.lines.map(\.members) == members else { continue }
    for (k, pl) in pyLines.enumerated() {
        let line = got.lines[k]
        check(line.base == (pl["base"] as! [Any]).map { Int(number($0)) }, "case \(n) line \(k): exponents split differently")
        check(line.image.width == Int(number(pl["width"]!)), "case \(n) line \(k): width \(line.image.width) vs \(number(pl["width"]!))")
        let inkSum = line.image.pixels.reduce(Float(0), +)
        check(abs(Double(inkSum) - number(pl["inkSum"]!)) / max(number(pl["inkSum"]!), 1) < 0.12,
              "case \(n) line \(k): ink \(inkSum) vs python \(number(pl["inkSum"]!))")
        textCompared += 1
        textAgree += line.text == pl["text"] as! String ? 1 : 0
        if let image = pl["image"] as? [Any], image.count == line.image.pixels.count {
            var worst: Float = 0, sum: Double = 0
            for (a, b) in zip(line.image.pixels, image) {
                let d = abs(a - Float(number(b)))
                worst = max(worst, d)
                sum += Double(d)
            }
            worstImage = max(worstImage, worst)
            meanImage += sum / Double(image.count)
            imagesCompared += 1
            // The model on python's own image: the Swift network must give python's numbers.
            let pyImage = InkLineImage(width: line.image.width, pixels: image.map { Float(number($0)) },
                                       scale: line.image.scale, origin: line.image.origin)
            let lp = model.logProbs(pyImage)
            let ref = pl["logProbs"] as! [[Any]]
            check(lp.count == ref.count, "case \(n) line \(k): \(lp.count) columns vs \(ref.count)")
            var w: Float = 0
            for (row, refRow) in zip(lp, ref) {
                for (a, b) in zip(row, refRow) { w = max(w, abs(a - Float(number(b)))) }
            }
            worstLogProb = max(worstLogProb, w)
            check(w < 0.02, "case \(n) line \(k): log-probabilities differ by \(w)")
            let text = CTC.beam(lp, charset: model.charset).first?.text ?? ""
            check(text == pl["text"] as! String, "case \(n) line \(k): beam on python's image \"\(text)\" vs \"\(pl["text"] as! String)\"")
        }
    }
    if parityCases % 50 == 0 {
        print("… \(parityCases) cases, \(Int(Date().timeIntervalSince(started))) s")
    }
}
print("cases read: \(total); exact \(exact) (\(100 * exact / max(total, 1)) %), right line count \(lineCount)")
print("parity with python on \(parityCases) cases: same text on \(textAgree)/\(textCompared) lines; "
      + "images: worst pixel difference \(worstImage), mean \(imagesCompared > 0 ? meanImage / Double(imagesCompared) : 0) over \(imagesCompared); "
      + "model on python's images: worst log-probability difference \(worstLogProb)")
print(failures == 0 ? "all checks passed" : "\(failures) checks failed")
exit(failures == 0 ? 0 : 1)
