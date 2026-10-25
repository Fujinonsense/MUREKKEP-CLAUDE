import SwiftUI

/// The downloadable model's row: what this iPad gets, and one button for each state (download,
/// stop, retry, delete). Used in Settings and, compact, at the top of the assistant.
struct BrainCard: View {
    @ObservedObject var brain = DeviceBrain.shared
    var compact = false
    @State private var confirmDelete = false
    /// The App Store edition says the size and asks before the model comes down (guideline 4.2.3).
    @State private var confirmDownload = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.ai)
                        .frame(width: 34, height: 34)
                    Image(systemName: "brain")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                action
            }
            .confirmationDialog(Loc.t("{0} indirilsin mi?", title), isPresented: $confirmDownload, titleVisibility: .visible) {
                Button(Loc.t("İndir")) { brain.startDownload() }
                Button(Loc.t("Şimdi değil"), role: .cancel) {}
            } message: {
                Text(Loc.t("{0} yer kaplar ve bir kez indirilir; sonra yapay zekâ iPad'inde internetsiz çalışır. İndirme arka planda sürer ve Wi‑Fi yoksa mobil veriyi de kullanır.",
                           brain.model.map { BrainModel.sizeText($0.bytes, english: Loc.isEnglish) } ?? ""))
            }
            if let fraction = brain.fraction {
                ProgressView(value: fraction)
                    .tint(Theme.ink)
            }
            if case let .failed(message) = brain.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !compact, BrainRuntime.isCompiledIn, let model = brain.model {
                // Read again every few seconds: what is open in the app changes what is free.
                TimelineView(.periodic(from: .now, by: 3)) { _ in
                    if let memory = DeviceBrain.memory() {
                        memoryRow(memory, model: model)
                    }
                }
            }
        }
        .confirmationDialog(Loc.t("Model silinsin mi?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(Loc.t("Sil"), role: .destructive) { brain.delete() }
        } message: {
            Text(Loc.t("Yer açılır; istediğinde yeniden indirebilirsin."))
        }
    }

    private func download() {
        if ProPlan.sells { confirmDownload = true } else { brain.startDownload() }
    }

    /// What iOS lets the app hold, what is free now, and whether the model loads in it.
    private func memoryRow(_ memory: BrainMemory, model: BrainModel) -> some View {
        let english = Loc.isEnglish
        let fits = memory.fits(weights: model.bytes)
        return VStack(alignment: .leading, spacing: 3) {
            Label(Loc.t("Uygulamaya ayrılan bellek: {0} · şu an boş: {1}",
                        BrainModel.sizeText(memory.limit, english: english), BrainModel.sizeText(memory.free, english: english)),
                  systemImage: "memorychip")
                .foregroundStyle(.secondary)
            Label(fits
                  ? Loc.t("{0} yüklenirken {1} boş bellek ister: sığıyor.", model.title,
                          BrainModel.sizeText(BrainMemory.need(weights: model.bytes), english: english))
                  : Loc.t("{0} yüklenirken {1} boş bellek ister: şu an sığmıyor. Diğer uygulamaları kapat; yine sığmazsa yükleyici büyük bellek iznini almamış olabilir.",
                          model.title, BrainModel.sizeText(BrainMemory.need(weights: model.bytes), english: english)),
                  systemImage: fits ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(fits ? Color.green : Color.orange)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var title: String {
        guard let model = brain.model else { return Loc.t("Güçlü yerel model") }
        return model.title
    }

    private var subtitle: String {
        if !BrainRuntime.isCompiledIn || brain.model == nil {
            return brain.unavailableReason ?? ""
        }
        guard let model = brain.model else { return "" }
        let size = BrainModel.sizeText(model.bytes, english: Loc.isEnglish)
        switch brain.phase {
        case .ready:
            return Loc.t("Hazır. Asistan otomatik olarak bunu kullanıyor; internetsiz çalışır.")
        case let .downloading(done, total):
            return Loc.t("İndiriliyor: {0} / {1}. Arka planda sürer; uygulamayı kapatabilirsin.",
                         BrainModel.sizeText(done, english: Loc.isEnglish), BrainModel.sizeText(total, english: Loc.isEnglish))
        case .absent, .failed:
            return compact
                ? Loc.t("Soruları adım adım düşünerek çözer. Bir kez indir ({0}), sonra internetsiz çalışır.", size)
                : Loc.t("Bu iPad için en güçlü model. Bir kez indirilir ({0}), sonra tamamen cihazda ve internetsiz çalışır.", size)
        }
    }

    @ViewBuilder
    private var action: some View {
        if BrainRuntime.isCompiledIn, brain.model != nil {
            switch brain.phase {
            case .absent:
                Button(Loc.t("İndir")) { download() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ink)
                    .controlSize(compact ? .small : .regular)
            case .failed:
                Button(Loc.t("Yeniden dene")) { download() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ink)
                    .controlSize(compact ? .small : .regular)
            case .downloading:
                Button(Loc.t("Durdur")) { brain.cancelDownload() }
                    .buttonStyle(.bordered)
                    .controlSize(compact ? .small : .regular)
            case .ready:
                if compact {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(Loc.t("Sil"), role: .destructive) { confirmDelete = true }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}
