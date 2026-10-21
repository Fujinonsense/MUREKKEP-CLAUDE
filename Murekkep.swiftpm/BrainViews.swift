import SwiftUI

/// The downloadable model's row: what this iPad gets, and one button for each state (download,
/// stop, retry, delete). Used in Settings and, compact, at the top of the assistant.
struct BrainCard: View {
    @ObservedObject var brain = DeviceBrain.shared
    var compact = false
    @State private var confirmDelete = false

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
            if let fraction = brain.fraction {
                ProgressView(value: fraction)
                    .tint(Theme.ink)
            }
            if case let .failed(message) = brain.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .confirmationDialog(Loc.t("Model silinsin mi?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(Loc.t("Sil"), role: .destructive) { brain.delete() }
        } message: {
            Text(Loc.t("Yer açılır; istediğinde yeniden indirebilirsin."))
        }
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
            return Loc.t("İndiriliyor: {0} / {1}. Uygulama açık kalsın; kapanırsa kaldığı yerden sürer.",
                         BrainModel.sizeText(done, english: Loc.isEnglish), BrainModel.sizeText(total, english: Loc.isEnglish))
        case .absent, .failed:
            return compact
                ? Loc.t("Soruları adım adım düşünerek çözer. Bir kez indir ({0}), sonra internetsiz çalışır.", size)
                : Loc.t("Bu iPad için en güçlü model. Bir kez indirilir ({0}, Wi‑Fi önerilir), sonra tamamen cihazda ve internetsiz çalışır.", size)
        }
    }

    @ViewBuilder
    private var action: some View {
        if BrainRuntime.isCompiledIn, brain.model != nil {
            switch brain.phase {
            case .absent:
                Button(Loc.t("İndir")) { brain.startDownload() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ink)
                    .controlSize(compact ? .small : .regular)
            case .failed:
                Button(Loc.t("Yeniden dene")) { brain.startDownload() }
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
