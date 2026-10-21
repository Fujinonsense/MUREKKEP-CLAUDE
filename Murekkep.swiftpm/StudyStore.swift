import Foundation

/// One study tool being made.
final class StudyJob: ObservableObject, Identifiable {
    let id = UUID()
    let kind: StudyKind
    let sectionID: UUID?
    let title: String
    @Published var phase = Loc.t("Hazırlanıyor…")
    @Published var progress: Double = 0
    @Published var error: String?
    var task: Task<Void, Never>?

    init(kind: StudyKind, sectionID: UUID?, title: String) {
        self.kind = kind
        self.sectionID = sectionID
        self.title = title
    }
}

/// The study tools (flashcards, quizzes, mind maps, guides), kept in Documents/Murekkep/Study.
/// They are made one at a time in the background, like the Studio's overviews.
final class StudyStore: ObservableObject {
    @Published private(set) var sets: [StudySet] = []
    @Published private(set) var jobs: [StudyJob] = []
    /// The set that just got ready (the library opens it).
    @Published var justFinished: UUID?
    private var queueTail: Task<Void, Never>?
    private let root: URL
    private let saveQueue = DispatchQueue(label: "murekkep.study.save", qos: .utility)

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Murekkep", isDirectory: true).appendingPathComponent("Study", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    private var indexURL: URL { root.appendingPathComponent("sets.json") }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: indexURL), let list = try? decoder.decode([StudySet].self, from: data) else { return }
        sets = list.sorted { $0.created > $1.created }
    }

    /// Written off the main thread: a deck saves after every card rated.
    private func persist() {
        let snapshot = sets
        let url = indexURL
        saveQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func set(_ id: UUID) -> StudySet? { sets.first { $0.id == id } }

    func sets(in sectionID: UUID?) -> [StudySet] {
        guard let sectionID else { return sets }
        return sets.filter { $0.sectionID == sectionID }
    }

    func jobs(in sectionID: UUID?) -> [StudyJob] {
        guard let sectionID else { return jobs }
        return jobs.filter { $0.sectionID == sectionID }
    }

    func save(_ set: StudySet) {
        if let i = sets.firstIndex(where: { $0.id == set.id }) {
            sets[i] = set
        } else {
            sets.insert(set, at: 0)
        }
        persist()
    }

    func delete(_ id: UUID) {
        sets.removeAll { $0.id == id }
        persist()
    }

    func rename(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = sets.firstIndex(where: { $0.id == id }) else { return }
        sets[i].title = t
        persist()
    }

    /// A card was rated: its new memory state is kept.
    func rate(card: UUID, in setID: UUID, rating: ReviewRating, now: Date = Date()) {
        guard let s = sets.firstIndex(where: { $0.id == setID }),
              let c = sets[s].cards.firstIndex(where: { $0.id == card }) else { return }
        sets[s].cards[c].review = SpacedRepetition.review(sets[s].cards[c].review, rating: rating, now: now)
        persist()
    }

    func recordScore(_ score: Int, in setID: UUID) {
        guard let s = sets.firstIndex(where: { $0.id == setID }) else { return }
        sets[s].bestScore = max(sets[s].bestScore ?? 0, score)
        persist()
    }

    /// Sets of a deleted course stay, without a course.
    func detachSection(_ sectionID: UUID) {
        for i in sets.indices where sets[i].sectionID == sectionID {
            sets[i].sectionID = nil
        }
        persist()
    }

    func dismiss(_ job: StudyJob) {
        job.task?.cancel()
        jobs.removeAll { $0.id == job.id }
    }

    /// Reads the sources and writes the set in the background; its progress shows as a job.
    @MainActor
    func start(options: StudyOptions, sources: [NoteMeta], sectionID: UUID?, engine: StudioEngine,
               library: LibraryStore, settings: AppSettings, chapter: BookChapter? = nil) {
        let title = chapter.map { Loc.t("Bölüm {0} · {1}", "\($0.number)", $0.title) }
            ?? (sources.count == 1 ? sources[0].title : (library.sections.first { $0.id == sectionID }?.name ?? Loc.t("Kaynaklar")))
        let job = StudyJob(kind: options.kind, sectionID: sectionID, title: title)
        jobs.insert(job, at: 0)
        let previous = queueTail
        if previous != nil { job.phase = Loc.t("Sırada…") }
        job.task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            if Task.isCancelled {
                self.jobs.removeAll { $0.id == job.id }
                return
            }
            do {
                job.phase = Loc.t("Kaynaklar okunuyor…")
                job.progress = 0.03
                let material = await StudioMaterial.gather(sources, library: library, chapter: chapter) { done, total in
                    Task { @MainActor in
                        job.phase = Loc.t("Sayfalar okunuyor ({0}/{1})…", "\(done + 1)", "\(total)")
                        job.progress = 0.03 + 0.2 * Double(done + 1) / Double(max(total, 1))
                    }
                }
                try Task.checkCancellation()
                job.phase = Loc.t("Hazırlanıyor…")
                job.progress = 0.25
                var set = try await StudyWriter.write(options: options, material: material, engine: engine, settings: settings) { fraction, phase in
                    job.progress = 0.25 + 0.73 * fraction
                    if let phase { job.phase = phase }
                }
                set.sectionID = sectionID
                if let chapter { set.title = chapter.title }
                self.save(set)
                self.jobs.removeAll { $0.id == job.id }
                self.justFinished = set.id
            } catch is CancellationError {
                self.jobs.removeAll { $0.id == job.id }
            } catch {
                job.phase = Loc.t("Olmadı")
                job.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        queueTail = job.task
    }
}
