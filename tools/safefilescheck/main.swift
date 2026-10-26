import Foundation

// The checks of InkCodec.swift's version reading and SafeFiles.swift (FileBackup, LenientList), run
// with the Windows Swift toolchain (tools/safefilescheck/run.ps1). Prints every failure and a count.

var failures = 0
var total = 0

func check(_ ok: Bool, _ name: String, got: String = "") {
    total += 1
    if !ok {
        failures += 1
        print("FAIL \(name)" + (got.isEmpty ? "" : " — got: \(got)"))
    }
}

func le32(_ v: UInt32) -> Data {
    var w = ByteWriter()
    w.u32(v)
    return w.data
}

// MARK: Ink files: good, truncated, newer, not ink

let stroke = Stroke(brush: .pencil, color: InkColor(0.1, 0.2, 0.3, 0.9), width: 2.5, birth: 123.5, seed: 7,
                    points: [InkPoint(x: 1, y: 2, r: 0.8, ink: 0.5), InkPoint(x: 3, y: 4, r: 1.2, ink: 0.7)])
let good = InkCodec.encode([[stroke], []])
check((try? InkCodec.decode(good)) == [[stroke], []], "round trip")
check(InkCodec.formatVersion(of: good) == 1, "version of a current file", got: "\(String(describing: InkCodec.formatVersion(of: good)))")
check(!InkCodec.isNewerFormat(good), "a current file is not newer")

let truncated = good.prefix(good.count - 5)
check((try? InkCodec.decode(truncated)) == nil, "a truncated file does not decode")
check(!InkCodec.isNewerFormat(truncated), "a truncated file is damaged, not newer")

var newer = Data()
newer.append(good.prefix(4))
newer.append(le32(2))
newer.append(good.suffix(from: 8))
var newerError: InkCodec.CodecError?
do { _ = try InkCodec.decode(newer) } catch let e as InkCodec.CodecError { newerError = e } catch {}
check(newerError == .unsupportedVersion, "a newer file is refused as unsupported", got: "\(String(describing: newerError))")
check(InkCodec.formatVersion(of: newer) == 2, "the newer file's version is read")
check(InkCodec.isNewerFormat(newer), "a newer file is told apart from a damaged one")

let garbage = Data("hello ink".utf8)
check(InkCodec.formatVersion(of: garbage) == nil, "not an ink file: no version")
check(!InkCodec.isNewerFormat(garbage), "not an ink file: not newer")
check(InkCodec.formatVersion(of: Data()) == nil, "an empty file: no version")
check(!InkCodec.isNewerFormat(good.prefix(6)), "a file cut inside the version: not newer")

// MARK: FileBackup: named by the file's date, made once, the original untouched

var parts = DateComponents()
parts.year = 2026
parts.month = 10
parts.day = 26
parts.hour = 14
parts.minute = 15
parts.second = 3
let fixed = Calendar(identifier: .gregorian).date(from: parts)!
let inkName = FileBackup.backupURL(for: URL(fileURLWithPath: "/notes/abc/ink.mrk"), date: fixed).lastPathComponent
check(inkName == "ink.bak-20261026-141503", "ink.mrk's backup name", got: inkName)
let indexName = FileBackup.backupURL(for: URL(fileURLWithPath: "/notes/index.json"), date: fixed).lastPathComponent
check(indexName == "index.bak-20261026-141503", "index.json's backup name", got: indexName)
check(FileBackup.backupURL(for: URL(fileURLWithPath: "/notes/abc/ink.mrk"), date: fixed).deletingLastPathComponent().path
        == URL(fileURLWithPath: "/notes/abc").path, "the backup sits next to the file")

let fm = FileManager.default
let dir = fm.temporaryDirectory.appendingPathComponent("safefilescheck-" + UUID().uuidString, isDirectory: true)
try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: dir) }
let ink = dir.appendingPathComponent("ink.mrk")
try! truncated.write(to: ink)
let first = FileBackup.keep(ink)
check(first != nil, "the copy is made")
check(first?.lastPathComponent.hasPrefix("ink.bak-") == true, "the copy's name", got: first?.lastPathComponent ?? "nil")
check(first.flatMap { try? Data(contentsOf: $0) } == truncated, "the copy holds the same bytes")
check((try? Data(contentsOf: ink)) == truncated, "the original is untouched")
let second = FileBackup.keep(ink)
check(second == first, "kept again: the same copy", got: second?.lastPathComponent ?? "nil")
let listing = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
check(listing.filter { $0.hasPrefix("ink.bak-") }.count == 1, "one copy, not two", got: listing.joined(separator: ","))
check(FileBackup.keep(dir.appendingPathComponent("missing.mrk")) == nil, "nothing to copy: nil")

// MARK: LenientList: one entry at a time, the unreadable ones kept as they were

struct Item: Codable, Equatable {
    var id: Int
    var name: String
    var when: Date
}

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601

let mixed = Data("""
[{"id": 1, "name": "first", "when": "2026-10-26T10:00:00Z"},
 {"id": "two", "name": "from a newer build", "when": "2026-10-26T11:00:00Z", "extra": {"deep": [1, 2]}},
 {"id": 3, "name": "third", "when": "2026-10-26T12:00:00Z"},
 "not even an object"]
""".utf8)
let read = LenientList.decode(Item.self, from: mixed, decoder: decoder)
check(read != nil, "a list with bad entries is read")
check(read?.items.map(\.id) == [1, 3], "the good entries", got: "\(read?.items.map(\.id) ?? [])")
check(read?.unreadable.count == 2, "the bad entries are kept", got: "\(read?.unreadable.count ?? -1)")
check((read?.unreadable.first as? [String: Any])?["name"] as? String == "from a newer build", "a bad entry keeps its JSON")
check(read?.unreadable.last as? String == "not even an object", "a non-object entry is kept too")

if let read {
    let written = try! LenientList.encode(read.items, unreadable: read.unreadable, encoder: encoder)
    let back = (try? JSONSerialization.jsonObject(with: written)) as? [Any]
    check(back?.count == 4, "written back: all four entries", got: "\(back?.count ?? -1)")
    let again = LenientList.decode(Item.self, from: written, decoder: decoder)
    check(again?.items == read.items, "written back: the good entries decode again")
    check(again?.unreadable.count == 2, "written back: the bad entries are still there")
    let kept = (back?[2] as? [String: Any])
    check(((kept?["extra"] as? [String: Any])?["deep"] as? [Int]) == [1, 2], "written back: a bad entry's unknown fields survive",
          got: "\(String(describing: kept))")
    check(back?.last as? String == "not even an object", "written back: the non-object entry survives")
}

let five = [Item(id: 5, name: "five", when: Date(timeIntervalSince1970: 1_700_000_000))]
let allGood = try! encoder.encode(five)
let fast = LenientList.decode(Item.self, from: allGood, decoder: decoder)
check(fast?.items == five && fast?.unreadable.isEmpty == true, "a good list: nothing unreadable")
// With nothing unreadable the file is the encoder's own (the keys' order is the encoder's business).
let rewritten = try! LenientList.encode(five, unreadable: [], encoder: encoder)
check(rewritten == (try! encoder.encode(five)), "a good list is written as before",
      got: String(decoding: rewritten, as: UTF8.self) + " vs " + String(decoding: allGood, as: UTF8.self))

check(LenientList.decode(Item.self, from: Data("{\"a\": 1}".utf8), decoder: decoder) == nil, "an object is not a list")
check(LenientList.decode(Item.self, from: Data("[1, 2".utf8), decoder: decoder) == nil, "a cut file is not a list")
check(LenientList.decode(Item.self, from: Data(), decoder: decoder) == nil, "an empty file is not a list")
check(LenientList.decode(Item.self, from: Data("[]".utf8), decoder: decoder)?.items.isEmpty == true, "an empty list is a list")

print(failures == 0 ? "safefilescheck: \(total) checks passed" : "safefilescheck: \(failures) of \(total) checks failed")
exit(failures == 0 ? 0 : 1)
