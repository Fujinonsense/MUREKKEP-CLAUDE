import Foundation

/// A language model the iPad downloads once and then runs itself (MLX on its GPU): no account, no
/// key, no computer. Qwen3.5 reads Turkish and English and thinks step by step before it answers.
struct BrainModel: Identifiable, Equatable, Sendable {
    /// The Hugging Face repository, e.g. "mlx-community/Qwen3.5-4B-4bit".
    let id: String
    let title: String
    /// Download size in bytes (the files the app takes).
    let bytes: Int64
    /// Physical memory the iPad needs, in GiB.
    let minimumMemoryGiB: Double
    /// Memory that must be free for the app while the model answers: the weights and the context.
    let workingSet: Int64

    static let qwen9B = BrainModel(id: "mlx-community/Qwen3.5-9B-4bit", title: "Qwen3.5 9B",
                                   bytes: 5_977_000_000, minimumMemoryGiB: 11.5, workingSet: 7_200_000_000)
    static let qwen4B = BrainModel(id: "mlx-community/Qwen3.5-4B-4bit", title: "Qwen3.5 4B",
                                   bytes: 3_061_000_000, minimumMemoryGiB: 7.0, workingSet: 3_900_000_000)
    static let qwen2B = BrainModel(id: "mlx-community/Qwen3.5-2B-4bit", title: "Qwen3.5 2B",
                                   bytes: 1_749_000_000, minimumMemoryGiB: 5.0, workingSet: 2_400_000_000)

    /// Strongest first.
    static let all = [qwen9B, qwen4B, qwen2B]

    /// The strongest model this iPad can run. The physical memory decides; the largest model also
    /// needs `available` (the memory free for the app now, nil when unknown) to hold it.
    static func best(physicalMemory: UInt64, available: Int64?) -> BrainModel? {
        let gib = Double(physicalMemory) / 1_073_741_824
        for model in all where gib >= model.minimumMemoryGiB {
            if model == qwen9B, let available, available < model.workingSet { continue }
            return model
        }
        return nil
    }

    /// The model's folder on disk.
    var folder: String { id.replacingOccurrences(of: "/", with: "--") }

    /// "3,1 GB" / "3.1 GB".
    static func sizeText(_ bytes: Int64, english: Bool) -> String {
        let gb = Double(bytes) / 1_000_000_000
        let text = gb >= 10 ? String(format: "%.0f", gb) : String(format: "%.1f", gb)
        return (english ? text : text.replacingOccurrences(of: ".", with: ",")) + " GB"
    }

    /// A file of the repository the model needs: weights, configuration, tokenizer, chat template.
    static func wanted(_ path: String) -> Bool {
        let name = path.lowercased()
        guard !name.contains("/"), !name.hasPrefix(".") else { return false }
        if name.hasSuffix(".safetensors") || name.hasSuffix(".json") || name.hasSuffix(".jinja") { return true }
        return name == "tokenizer.model" || name == "merges.txt"
    }
}

/// The app's memory as iOS allows it (Settings shows it under the model). The larger memory limit
/// raises `limit`; what is open in the app takes from `free`.
struct BrainMemory: Equatable {
    /// What the app holds now (its footprint), bytes.
    let used: Int64
    /// What the app may still take now.
    let free: Int64

    /// Room to answer beside the weights: the context and the work of each step.
    static let headroom: Int64 = 700_000_000

    /// Everything iOS lets the app hold.
    var limit: Int64 { used + free }

    /// Free memory a model of `weights` bytes needs to load (BrainRuntime refuses below it).
    static func need(weights: Int64) -> Int64 { weights + headroom }

    func fits(weights: Int64) -> Bool { free >= Self.need(weights: weights) }
}

/// A reply of a thinking model: "<think>…</think>" and then the answer.
enum ThinkingText {
    struct Parts: Equatable {
        var thinking: String
        var answer: String
        /// The thinking has ended (or there was none), so `answer` is the answer so far.
        var answering: Bool
    }

    /// With thinking on, the prompt already opens the thinking, so the reply may start inside it
    /// without "<think>"; everything up to "</think>" is thinking. With thinking off any stray block
    /// is dropped and the rest is the answer.
    static func split(_ raw: String, thinking: Bool) -> Parts {
        if let close = raw.range(of: "</think>") {
            var head = String(raw[..<close.lowerBound])
            if let open = head.range(of: "<think>") { head = String(head[open.upperBound...]) }
            let tail = String(raw[close.upperBound...])
            return Parts(thinking: head.trimmingCharacters(in: .whitespacesAndNewlines),
                         answer: tail.trimmingCharacters(in: .whitespacesAndNewlines), answering: true)
        }
        if let open = raw.range(of: "<think>") {
            let before = String(raw[..<open.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return Parts(thinking: String(raw[open.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines),
                         answer: before, answering: false)
        }
        if thinking {
            return Parts(thinking: raw.trimmingCharacters(in: .whitespacesAndNewlines), answer: "", answering: false)
        }
        return Parts(thinking: "", answer: raw.trimmingCharacters(in: .whitespacesAndNewlines), answering: true)
    }

    private static let finalLine = try! NSRegularExpression(
        pattern: "(?:cevap|yan[ıi]t|doğru (?:cevap|şık|seçenek)|answer|correct (?:answer|option))(?:\\s+is)?\\s*[:：]?\\s*\\**\\s*\\(?([A-Ea-e])\\)?(?![A-Za-zÇĞİÖŞÜçğıöşü])",
        options: [.caseInsensitive])
    private static let boldLetter = try! NSRegularExpression(pattern: "\\*\\*\\s*\\(?([A-Ea-e])\\)?\\s*\\*\\*")
    /// "D) 4: Doğru." — an option-by-option verdict, when the answer ran out before its "Cevap:" line.
    private static let verdictLine = try! NSRegularExpression(
        pattern: "^[\\s*\\-•]*\\(?([A-Ea-e])\\)[^\\n]*?[:：—–\\-]\\s*\\**\\s*(?:doğru|correct)\\b(?!\\s*değil)",
        options: [.caseInsensitive, .anchorsMatchLines])

    /// The option an answer chose. The last "Cevap: C" / "Answer: (B)" wins (models restate their
    /// final choice at the end); then the one option a verdict list calls right; otherwise the
    /// first bold letter. Only letters the question has.
    static func choice(in answer: String, letters: [Character]) -> Character? {
        let allowed = Set(letters.map { Character($0.uppercased()) })
        let ns = answer as NSString
        let range = NSRange(location: 0, length: ns.length)
        func letter(_ m: NSTextCheckingResult) -> Character? {
            guard let c = ns.substring(with: m.range(at: 1)).uppercased().first, allowed.contains(c) else { return nil }
            return c
        }
        if let found = finalLine.matches(in: answer, range: range).reversed().lazy.compactMap(letter).first {
            return found
        }
        let marked = Set(verdictLine.matches(in: answer, range: range).compactMap(letter))
        if marked.count == 1 { return marked.first }
        return boldLetter.matches(in: answer, range: range).lazy.compactMap(letter).first
    }

    /// The answer without its closing "Cevap: X" line, for the reasoning under the chosen option.
    static func explanation(_ answer: String) -> String {
        let lines = answer.components(separatedBy: "\n")
        let kept = lines.filter { line in
            let ns = line as NSString
            let all = NSRange(location: 0, length: ns.length)
            guard let m = finalLine.firstMatch(in: line, range: all) else { return true }
            // A line that only states the choice goes; a sentence that mentions it stays.
            return ns.length - m.range.length > 12
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// How long the downloaded model may think before it must answer. Qwen3.5 4B always spends its whole
/// budget, so the wait follows these numbers; at half the earlier ones (2,048 / 768) it still got 39 of
/// 40 test questions right (mrk-ml/textpen/brain_eval), and the answers came twice as fast.
enum BrainBudget {
    /// Thinking tokens for one question: working out numbers needs room, a reading question less.
    static func thinking(for text: String) -> Int {
        isMath(text) ? 1_024 : 512
    }

    /// A textbook exercise, answered whole.
    static let exercise = 512

    /// Checking a solution, solving a page, or a free question with arithmetic.
    static let deep = 768

    /// A worded math question solved on its own (an inequality, an equation, blanks to fill): one
    /// line of working, not five options to try, so less than a test question's 1,024; at the iPad's
    /// ~20 tokens a second about 40 seconds. With the page solved one question at a time, a budget
    /// that runs out no longer spills half a page of reasoning into the answer.
    static let mathQuestion = 768

    /// The steps under a result the math engine already fixed: nothing to work out, only to lay out,
    /// so a third of a worded question's budget (about 13 seconds on the iPad).
    static let mathSteps = 256

    static func isMath(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber).count
        let operators = text.filter { "+−×÷*/=^√<>≤≥∫∑π%²³".contains($0) }.count
        return operators >= 3 || (digits >= 3 && operators >= 1)
    }
}
