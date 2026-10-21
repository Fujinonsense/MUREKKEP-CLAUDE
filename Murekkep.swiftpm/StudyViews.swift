import SwiftUI

extension StudyKind {
    var title: String {
        switch self {
        case .flashcards: return Loc.t("Bilgi kartları")
        case .quiz: return Loc.t("Test")
        case .mindMap: return Loc.t("Zihin haritası")
        case .guide: return Loc.t("Çalışma rehberi")
        }
    }

    var blurb: String {
        switch self {
        case .flashcards: return Loc.t("Aralıklı tekrarla: zor kartlar sık, bildiklerin seyrek gelir.")
        case .quiz: return Loc.t("Dört şıklı sorular, açıklamalarıyla; yanlışlarını yeniden çöz.")
        case .mindMap: return Loc.t("Konunun dalları bir bakışta; dokununca katlanır.")
        case .guide: return Loc.t("Özet, bölüm bölüm ana fikirler, terimler ve sorular.")
        }
    }

    /// Cards and questions come in a number; maps and guides do not.
    var hasCount: Bool { self == .flashcards || self == .quiz }
}

struct StudyRequest: Identifiable {
    let id = UUID()
    let sectionID: UUID?
    let kind: StudyKind
}

/// "1 dk", "10 dk", "3 g": how long until a card comes back.
func studyWaitLabel(_ seconds: TimeInterval) -> String {
    if seconds < 3600 { return Loc.t("{0} dk", "\(max(1, Int((seconds / 60).rounded())))") }
    if seconds < 86_400 { return Loc.t("{0} sa", "\(Int((seconds / 3600).rounded()))") }
    let days = seconds / 86_400
    if days < 30 { return Loc.t("{0} g", "\(Int(days.rounded()))") }
    return Loc.t("{0} ay", "\(Int((days / 30).rounded()))")
}

// MARK: - Library pieces

/// The four study tools next to the video and audio cards.
struct StudyCreateRow: View {
    let sectionID: UUID?
    let actions: LibraryActions

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            ForEach(StudyKind.allCases) { kind in
                Button {
                    actions.makeStudy(sectionID, kind)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 40, height: 40)
                            .background(Theme.ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(kind.blurb)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(radius: 16)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

struct StudySetCard: View {
    let set: StudySet

    private var detail: String {
        switch set.kind {
        case .flashcards:
            let due = set.dueCards(now: Date()).count
            return due > 0 ? Loc.t("{0} kart · {1} çalışılacak", "\(set.cards.count)", "\(due)") : Loc.t("{0} kart · bugünlük bitti", "\(set.cards.count)")
        case .quiz:
            if let best = set.bestScore { return Loc.t("{0} soru · en iyi {1}", "\(set.questions.count)", "\(best)") }
            return Loc.t("{0} soru", "\(set.questions.count)")
        case .mindMap:
            return Loc.t("{0} dal", "\(set.map?.children.count ?? 0)")
        case .guide:
            return Loc.t("{0} bölüm · {1} terim", "\(set.guide?.sections.count ?? 0)", "\(set.guide?.terms.count ?? 0)")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: set.kind.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.ai, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(set.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(set.kind.title) · \(detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .glassCard(radius: 16)
    }
}

struct StudyJobRow: View {
    @ObservedObject var job: StudyJob
    @EnvironmentObject private var study: StudyStore

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: max(0.02, job.progress))
                .progressViewStyle(.circular)
                .tint(Theme.aiStart)
                .opacity(job.error == nil ? 1 : 0)
                .overlay {
                    if job.error != nil {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(job.kind.title) · \(job.title)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(job.error ?? job.phase)
                    .font(.caption)
                    .foregroundStyle(job.error == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button {
                study.dismiss(job)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(job.error == nil ? Loc.t("İptal et") : Loc.t("Kapat"))
        }
        .padding(14)
        .glassCard(radius: 18)
    }
}

/// The study tools of a course (or all of them), with the ones being made.
struct StudyShelf: View {
    @EnvironmentObject private var study: StudyStore
    let sectionID: UUID?
    let actions: LibraryActions

    var body: some View {
        let sets = study.sets(in: sectionID)
        let jobs = study.jobs(in: sectionID)
        if !sets.isEmpty || !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: Loc.t("Çalışma araçları"))
                ForEach(jobs) { job in
                    StudyJobRow(job: job)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(sets) { set in
                        Button {
                            actions.openStudy(set)
                        } label: {
                            StudySetCard(set: set)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                study.delete(set.id)
                            } label: {
                                Label(Loc.t("Sil"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Create

struct StudyCreateSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var study: StudyStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let request: StudyRequest
    @State private var kind: StudyKind
    @State private var selected: Set<UUID> = []
    @State private var english = Loc.isEnglish
    @State private var count = 20
    @State private var engine: StudioEngine
    @State private var showAllSources = false

    init(request: StudyRequest, engine: StudioEngine) {
        self.request = request
        _kind = State(initialValue: request.kind)
        _engine = State(initialValue: engine)
    }

    private var candidates: [NoteMeta] {
        let notes = request.sectionID.map { id in library.notes.filter { $0.sectionID == id } } ?? library.notes
        return notes.sorted { a, b in
            if a.kind != b.kind { return a.kind == .pdf }
            return a.modified > b.modified
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(StudyKind.allCases) { k in
                            let on = k == kind
                            Button {
                                kind = k
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: k.symbol)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(on ? Theme.ink : Color.secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(k.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(k.blurb)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Theme.ink.opacity(0.1) : Color.primary.opacity(0.04)))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.ink : Color.clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Loc.t("Dil"))
                            .font(.subheadline.weight(.semibold))
                        Picker(Loc.t("Dil"), selection: $english) {
                            Text("Türkçe").tag(false)
                            Text("English").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 6)
                    if kind.hasCount {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(kind == .flashcards ? Loc.t("Kart sayısı") : Loc.t("Soru sayısı"))
                                .font(.subheadline.weight(.semibold))
                            Picker(Loc.t("Sayı"), selection: $count) {
                                ForEach([10, 20, 30, 50], id: \.self) { n in
                                    Text("\(n)").tag(n)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text(Loc.t("Temel ayarlar"))
                }
                Section {
                    ForEach(candidates.filter { selected.contains($0.id) }) { note in
                        sourceRow(note)
                    }
                    let others = candidates.filter { !selected.contains($0.id) }
                    if !others.isEmpty {
                        DisclosureGroup(isExpanded: $showAllSources) {
                            ForEach(others) { note in
                                sourceRow(note)
                            }
                        } label: {
                            Label(Loc.t("Başka kaynak ekle ({0})", "\(others.count)"), systemImage: "plus.circle")
                                .foregroundStyle(Theme.ink)
                        }
                    }
                } header: {
                    Text(Loc.t("Kaynaklar · {0} seçili", "\(selected.count)"))
                }
                Section {
                    Picker(Loc.t("Hazırlayan"), selection: $engine) {
                        ForEach(StudioEngine.allCases) { e in
                            Label(e.title + (e.isAvailable(settings: settings) ? "" : Loc.t(" (kullanılamıyor)")), systemImage: e.symbol).tag(e)
                        }
                    }
                } header: {
                    Text(Loc.t("Yapay zekâ"))
                } footer: {
                    Text(engine.detail)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Loc.t("Vazgeç")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Loc.t("Oluştur")) { create() }
                        .fontWeight(.bold)
                        .disabled(selected.isEmpty || !engine.isAvailable(settings: settings))
                }
            }
            .onAppear {
                if selected.isEmpty {
                    let pdfs = candidates.filter { $0.kind == .pdf }
                    let pick = pdfs.isEmpty ? Array(candidates.prefix(3)) : Array(pdfs.prefix(request.sectionID == nil ? 1 : 6))
                    selected = Set(pick.map(\.id))
                }
            }
        }
    }

    private func sourceRow(_ note: NoteMeta) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selected.contains(note.id) { selected.remove(note.id) } else if selected.count < 10 { selected.insert(note.id) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected.contains(note.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected.contains(note.id) ? Theme.ink : Color.secondary)
                Image(systemName: note.kind == .pdf ? "doc.richtext" : "book.closed")
                    .foregroundStyle(.secondary)
                Text(note.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func create() {
        let chosen = candidates.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        study.start(options: StudyOptions(kind: kind, english: english, count: count), sources: chosen,
                    sectionID: request.sectionID, engine: engine, library: library, settings: settings)
        dismiss()
    }
}

// MARK: - Open a set

struct StudySetView: View {
    @EnvironmentObject private var study: StudyStore
    @Environment(\.dismiss) private var dismiss
    let setID: UUID

    var body: some View {
        NavigationStack {
            Group {
                if let set = study.set(setID) {
                    switch set.kind {
                    case .flashcards: FlashcardSession(set: set)
                    case .quiz: QuizSession(set: set)
                    case .mindMap: MindMapScreen(set: set)
                    case .guide: GuideScreen(set: set)
                    }
                } else {
                    Text(Loc.t("Bu çalışma aracı silinmiş."))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(study.set(setID)?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Loc.t("Kapat")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Flashcards

struct FlashcardSession: View {
    @EnvironmentObject private var study: StudyStore
    let set: StudySet
    @State private var queue: [UUID] = []
    @State private var flipped = false
    @State private var reviewed = 0
    @State private var loaded = false

    private var current: Flashcard? {
        guard let id = queue.first else { return nil }
        return study.set(set.id)?.cards.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Label(Loc.t("{0} kart kaldı", "\(queue.count)"), systemImage: "rectangle.stack")
                Spacer()
                Label(Loc.t("{0} çalışıldı", "\(reviewed)"), systemImage: "checkmark.circle")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            if let card = current {
                cardView(card)
                    .padding(.horizontal, 24)
                    .onTapGesture { withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { flipped.toggle() } }
                if flipped {
                    ratingButtons(card)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { flipped = true }
                    } label: {
                        Text(Loc.t("Cevabı göster"))
                            .font(.headline)
                            .frame(maxWidth: 360)
                            .padding(.vertical, 14)
                            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                finished
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            queue = (study.set(set.id) ?? set).dueCards(now: Date()).map(\.id)
        }
    }

    private func cardView(_ card: Flashcard) -> some View {
        ZStack {
            face(card.front, caption: Loc.t("Soru"), tint: Theme.ink)
                .opacity(flipped ? 0 : 1)
            face(card.back, caption: Loc.t("Cevap"), tint: Theme.aiStart)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .frame(maxWidth: 640)
        .frame(height: 340)
    }

    private func face(_ text: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            // The header line of an index card.
            Rectangle()
                .fill(tint.opacity(0.35))
                .frame(height: 1)
            ScrollView {
                Text(text)
                    .font(Theme.display(.title2, weight: .regular))
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1.5))
        .shadow(color: Theme.shadow.opacity(0.08), radius: 12, y: 6)
    }

    private func ratingButtons(_ card: Flashcard) -> some View {
        let now = Date()
        return HStack(spacing: 10) {
            ForEach(ReviewRating.allCases, id: \.self) { rating in
                Button {
                    rate(card, rating)
                } label: {
                    VStack(spacing: 3) {
                        Text(Self.title(rating))
                            .font(.subheadline.weight(.semibold))
                        Text(studyWaitLabel(SpacedRepetition.wait(after: rating, for: card.review, now: now)))
                            .font(.caption.monospacedDigit())
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Self.tint(rating).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Self.tint(rating))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 24)
    }

    private func rate(_ card: Flashcard, _ rating: ReviewRating) {
        study.rate(card: card.id, in: set.id, rating: rating)
        reviewed += 1
        withAnimation(.easeInOut(duration: 0.2)) {
            flipped = false
            queue.removeFirst()
            // Cards in their short learning steps come back in this session.
            if let due = study.set(set.id)?.cards.first(where: { $0.id == card.id })?.review.due,
               due.timeIntervalSinceNow < 15 * 60 {
                queue.append(card.id)
            }
        }
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.ai)
            Text(reviewed == 0 ? Loc.t("Bugün çalışılacak kart yok") : Loc.t("Bugünlük bu kadar"))
                .font(Theme.display(.title2))
            Text(Loc.t("Kartlar, hatırlama durumuna göre yeniden gelir. Yarın tekrar bak."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    static func title(_ r: ReviewRating) -> String {
        switch r {
        case .again: return Loc.t("Tekrar")
        case .hard: return Loc.t("Zor")
        case .good: return Loc.t("İyi")
        case .easy: return Loc.t("Kolay")
        }
    }

    static func tint(_ r: ReviewRating) -> Color {
        switch r {
        case .again: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return Theme.ink
        }
    }
}

// MARK: - Quiz

struct QuizSession: View {
    @EnvironmentObject private var study: StudyStore
    let set: StudySet
    /// The questions of this round (all, or the ones answered wrong last time).
    @State private var round: [Int] = []
    @State private var position = 0
    @State private var chosen: Int?
    @State private var right = 0
    @State private var wrong: [Int] = []
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 18) {
            if position < round.count {
                let q = set.questions[round[position]]
                HStack {
                    Text(Loc.t("Soru {0}/{1}", "\(position + 1)", "\(round.count)"))
                    Spacer()
                    Text(Loc.t("{0} doğru", "\(right)"))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                Text(q.question)
                    .font(Theme.display(.title3, weight: .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 10) {
                    ForEach(q.choices.indices, id: \.self) { i in
                        choice(q, i)
                    }
                }
                if chosen != nil {
                    if !q.explanation.isEmpty {
                        Text(q.explanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            chosen = nil
                            position += 1
                            if position == round.count, round.count == set.questions.count {
                                study.recordScore(right, in: set.id)
                            }
                        }
                    } label: {
                        Text(position + 1 < round.count ? Loc.t("Sonraki soru") : Loc.t("Sonucu gör"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                result
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            round = Array(set.questions.indices)
        }
    }

    private func choice(_ q: QuizQuestion, _ i: Int) -> some View {
        let answered = chosen != nil
        let isRight = i == q.answer
        let isChosen = i == chosen
        let tint: Color = answered ? (isRight ? .green : (isChosen ? .red : .secondary)) : Theme.ink
        return Button {
            guard chosen == nil else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                chosen = i
                if isRight { right += 1 } else { wrong.append(round[position]) }
            }
        } label: {
            HStack(spacing: 12) {
                Text(String(Character(UnicodeScalar(UInt8(65 + i)))))
                    .font(.subheadline.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint.opacity(0.15)))
                Text(q.choices[i])
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if answered && (isRight || isChosen) {
                    Image(systemName: isRight ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isRight ? .green : .red)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(answered && (isRight || isChosen) ? tint.opacity(0.1) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(answered && (isRight || isChosen) ? tint : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var result: some View {
        VStack(spacing: 14) {
            Image(systemName: right == round.count ? "trophy.fill" : "chart.bar.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.ai)
            Text(Loc.t("{0}/{1} doğru", "\(right)", "\(round.count)"))
                .font(Theme.display(.largeTitle).monospacedDigit())
            if !wrong.isEmpty {
                Button {
                    withAnimation {
                        round = wrong
                        wrong = []
                        right = 0
                        position = 0
                        chosen = nil
                    }
                } label: {
                    Label(Loc.t("Yanlışları yeniden çöz ({0})", "\(wrong.count)"), systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.ink, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            Button(Loc.t("Baştan başla")) {
                withAnimation {
                    round = Array(set.questions.indices)
                    wrong = []
                    right = 0
                    position = 0
                    chosen = nil
                }
            }
        }
        .padding(.top, 40)
    }
}

// MARK: - Mind map

struct MindMapScreen: View {
    let set: StudySet
    @State private var collapsed: Set<UUID> = []
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    private static let palette: [Color] = [.blue, .purple, .teal, .orange, .pink, .green, .indigo, .brown]

    var body: some View {
        if let root = set.map {
            let placed = MindMapLayout.layout(root, collapsed: collapsed, size: Self.size, columnGap: 56, rowGap: 14)
            let bounds = placed.reduce(CGRect.null) { $0.union($1.frame) }
            let size = CGSize(width: bounds.maxX + 2, height: bounds.maxY + 2)
            let zoom = scale * pinch
            ScrollView([.horizontal, .vertical]) {
                map(placed, colors: Self.branchColors(root), size: size)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(width: size.width * zoom + 80, height: size.height * zoom + 80, alignment: .topLeading)
                    .padding(40)
            }
            .simultaneousGesture(magnify)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        withAnimation { collapsed = Set(root.children.map(\.id)) }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .accessibilityLabel(Loc.t("Dalları kapat"))
                    Button {
                        withAnimation { collapsed = [] }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(Loc.t("Dalları aç"))
                }
            }
        }
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in scale = min(max(scale * value, 0.35), 3) }
    }

    /// The connectors and the nodes, at full size.
    private func map(_ placed: [MindMapLayout.Placed], colors: [UUID: Color], size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            connectors(placed, colors: colors)
                .frame(width: size.width, height: size.height)
            ForEach(placed, id: \.id) { p in
                node(p, color: colors[p.id] ?? Theme.ink)
                    .frame(width: p.frame.width, height: p.frame.height)
                    .position(x: p.frame.midX, y: p.frame.midY)
                    .onTapGesture { toggle(p) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func connectors(_ placed: [MindMapLayout.Placed], colors: [UUID: Color]) -> some View {
        let byID = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0) })
        return Canvas { ctx, _ in
            for p in placed {
                guard let parentID = p.parent, let parent = byID[parentID] else { continue }
                let a = CGPoint(x: parent.frame.maxX, y: parent.frame.midY)
                let b = CGPoint(x: p.frame.minX, y: p.frame.midY)
                let mid = (a.x + b.x) / 2
                var path = Path()
                path.move(to: a)
                path.addCurve(to: b, control1: CGPoint(x: mid, y: a.y), control2: CGPoint(x: mid, y: b.y))
                let color = (colors[p.id] ?? Color.gray).opacity(0.55)
                ctx.stroke(path, with: .color(color), lineWidth: p.depth == 1 ? 2.5 : 1.6)
            }
        }
    }

    private func toggle(_ p: MindMapLayout.Placed) {
        guard p.hasChildren else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if collapsed.contains(p.id) {
                collapsed.remove(p.id)
            } else {
                collapsed.insert(p.id)
            }
        }
    }

    private func node(_ p: MindMapLayout.Placed, color: Color) -> some View {
        let font: Font = p.depth == 0 ? .title3.weight(.bold) : (p.depth == 1 ? .callout.weight(.semibold) : .footnote)
        return HStack(spacing: 6) {
            Text(p.title)
                .font(font)
                .multilineTextAlignment(.leading)
                .foregroundStyle(p.depth == 0 ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if p.hasChildren && p.depth > 0 {
                Image(systemName: p.folded ? "plus.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: p.depth == 0 ? 16 : 11, style: .continuous)
                .fill(p.depth == 0 ? AnyShapeStyle(Theme.ai) : AnyShapeStyle(color.opacity(p.depth == 1 ? 0.18 : 0.08)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: p.depth == 0 ? 16 : 11, style: .continuous)
                .strokeBorder(p.depth == 0 ? Color.clear : color.opacity(p.depth == 1 ? 0.7 : 0.35), lineWidth: p.depth == 1 ? 1.5 : 1)
        }
    }

    /// Every node takes its main branch's color.
    private static func branchColors(_ root: MindNode) -> [UUID: Color] {
        var out: [UUID: Color] = [root.id: Theme.ink]
        func paint(_ n: MindNode, _ c: Color) {
            out[n.id] = c
            for child in n.children { paint(child, c) }
        }
        for (i, branch) in root.children.enumerated() {
            paint(branch, palette[i % palette.count])
        }
        return out
    }

    /// A node's box from its text (wrapped within a width per level).
    static func size(_ node: MindNode, _ depth: Int) -> CGSize {
        let fontSize: CGFloat = depth == 0 ? 20 : (depth == 1 ? 16 : 13)
        let maxWidth: CGFloat = depth == 0 ? 260 : (depth == 1 ? 230 : 210)
        let textWidth = CGFloat(node.title.count) * fontSize * 0.56
        let inner = maxWidth - 24 - (depth > 0 ? 20 : 0)
        let lines = max(1, (textWidth / inner).rounded(.up))
        let width = min(maxWidth, textWidth + 24 + (depth > 0 ? 20 : 0))
        return CGSize(width: max(width, 60), height: lines * fontSize * 1.3 + 16)
    }
}

// MARK: - Guide

struct GuideScreen: View {
    let set: StudySet

    var body: some View {
        if let guide = set.guide {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !guide.summary.isEmpty {
                        block(Loc.t("Özet")) {
                            Text(guide.summary.joined(separator: " "))
                                .font(.body)
                        }
                    }
                    ForEach(Array(guide.sections.enumerated()), id: \.offset) { _, section in
                        block(section.heading) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(section.points, id: \.self) { point in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Circle().fill(Theme.ink).frame(width: 6, height: 6)
                                        Text(point)
                                    }
                                }
                            }
                        }
                    }
                    if !guide.terms.isEmpty {
                        block(Loc.t("Terimler")) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(guide.terms, id: \.term) { t in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(t.term).font(.headline)
                                        Text(t.definition).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !guide.questions.isEmpty {
                        block(Loc.t("Düşünmek için sorular")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(guide.questions.enumerated()), id: \.offset) { i, q in
                                    Text("\(i + 1). \(q)")
                                }
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: Self.plainText(set.title, guide)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.display(.title3))
            content()
        }
    }

    static func plainText(_ title: String, _ g: StudyGuide) -> String {
        var s = title + "\n\n"
        if !g.summary.isEmpty { s += g.summary.joined(separator: " ") + "\n\n" }
        for section in g.sections {
            s += section.heading + "\n" + section.points.map { "• " + $0 }.joined(separator: "\n") + "\n\n"
        }
        if !g.terms.isEmpty { s += g.terms.map { "\($0.term): \($0.definition)" }.joined(separator: "\n") + "\n\n" }
        if !g.questions.isEmpty { s += g.questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") }
        return s
    }
}
