import Foundation

// Runs the on-device model's pure Swift logic on Windows: the GPU gate that keeps the downloaded
// model out of the background (BrainGate.swift) and the scene-by-scene language check of its
// scripts (ScriptLanguage.swift). usage: check.exe

var failures = 0

func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { failures += 1 }
}

// MARK: The gate (BrainGate.swift)

let gate = BrainGate()
try! gate.enter()
gate.leave()
check(gate.runningCount == 0 && !gate.isPaused, "gate: an answer enters and leaves")

var t0 = Date()
gate.pause()
check(gate.isPaused && Date().timeIntervalSince(t0) < 0.2, "gate: pausing an idle gate returns at once")

do {
    try gate.enter()
    check(false, "gate: no answer starts while the app is away")
} catch let error as BrainInterrupted {
    check(error == BrainInterrupted(started: false) && !(error.errorDescription ?? "").isEmpty,
          "gate: an answer that cannot start throws BrainInterrupted(started: false)")
} catch {
    check(false, "gate: a paused gate threw \(error)")
}
check(gate.runningCount == 0, "gate: a refused answer is not counted as running")

gate.resume()
check((try? gate.enter()) != nil && gate.runningCount == 1, "gate: after the app is back an answer starts")

// The answer running now stops in a quarter second: going away waits for it, not the whole stopWait.
let stopper = Thread {
    Thread.sleep(forTimeInterval: 0.25)
    gate.leave()
}
stopper.start()
t0 = Date()
gate.pause()
let waited = Date().timeIntervalSince(t0)
check(waited >= 0.2 && waited < BrainGate.stopWait - 0.1 && gate.runningCount == 0,
      "gate: going away waits for the running answer to stop (\(Int(waited * 1000)) ms)")
gate.resume()

// One that never looks at the gate: going away gives up after stopWait.
try! gate.enter()
t0 = Date()
gate.pause()
let gaveUp = Date().timeIntervalSince(t0)
check(gaveUp >= BrainGate.stopWait - 0.05 && gaveUp < BrainGate.stopWait + 0.4,
      "gate: going away gives up after \(BrainGate.stopWait) s (\(Int(gaveUp * 1000)) ms)")
gate.leave()
gate.resume()

check(BrainInterrupted(started: true).errorDescription != BrainInterrupted(started: false).errorDescription
      && BrainInterrupted(started: true).errorDescription?.isEmpty == false,
      "interrupted: stopped in the middle and refused at the start say different things")

// MARK: The language check (ScriptLanguage.swift)

// A stand-in for StudioWriter.speaks: Turkish when the text has a Turkish letter.
let turkish: (String) -> Bool = { $0.range(of: "[çğıöşüÇĞİÖŞÜ]", options: .regularExpression) != nil }
let script = ["Bugün kalbin iletim sistemine bakacağız.", "The sinoatrial node sets the pace.",
              "Sinoatriyal düğüm kalbin doğal pilidir.", "Then the signal reaches the ventricles."]
check(ScriptLanguage.wrong(script, speaks: turkish) == [1, 3], "language: the scenes in the other language are found by index")
check(ScriptLanguage.wrong([], speaks: turkish).isEmpty, "language: an empty script has no wrong scenes")

check(ScriptLanguage.keeps(total: 10, wrong: 0) && ScriptLanguage.keeps(total: 10, wrong: 4) && ScriptLanguage.keeps(total: 1, wrong: 0),
      "language: a script mostly in its language is kept")
check(!ScriptLanguage.keeps(total: 10, wrong: 5) && !ScriptLanguage.keeps(total: 2, wrong: 1) && !ScriptLanguage.keeps(total: 0, wrong: 0),
      "language: half or more in the other language hands the script to the next writer")

let prompt = ScriptLanguage.rewritePrompt(["The sinoatrial node sets the pace.", "Then the signal reaches the ventricles."], english: false)
check(prompt.contains("2 metni yalnızca Türkçe") && prompt.contains("JSON") && prompt.contains("\"The sinoatrial node sets the pace.\""),
      "language: the rewrite asks for the texts in Turkish as a JSON list")
check(ScriptLanguage.rewritePrompt(["Kalp bir pompadır."], english: true).contains("1 texts in English only"),
      "language: the rewrite asks for English for an English overview")

check(ScriptLanguage.rewritten("[\"Sinoatriyal düğüm tempoyu belirler.\", \"Sonra sinyal karıncıklara ulaşır.\"]", count: 2)
      == ["Sinoatriyal düğüm tempoyu belirler.", "Sonra sinyal karıncıklara ulaşır."],
      "language: the rewrite's JSON list is read")
check(ScriptLanguage.rewritten("İşte çeviri:\n```json\n[ \" Sinoatriyal düğüm tempoyu belirler. \" ]\n```", count: 1)
      == ["Sinoatriyal düğüm tempoyu belirler."],
      "language: a list wrapped in words or a code fence is read and trimmed")
check(ScriptLanguage.rewritten("[\"bir\"]", count: 2) == nil, "language: too few texts are not used")
check(ScriptLanguage.rewritten("[\"bir\", \"\"]", count: 2) == nil, "language: an empty text is not used")
check(ScriptLanguage.rewritten("[1, 2]", count: 2) == nil && ScriptLanguage.rewritten("no list here", count: 1) == nil,
      "language: numbers or no list are not used")

print(failures == 0 ? "all ok" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
