import SwiftUI

/// The Mürekkep Pro page: what Pro adds beside the free plan, the three plans and the purchase.
/// It opens when a free allowance runs out or a Pro-only thing is touched, and from Settings. The
/// artwork at the top is one of the Pro library backgrounds.
struct PaywallView: View {
    let reason: ProPlan.Feature?
    let close: () -> Void
    @ObservedObject private var store = ProStore.shared
    @State private var plan: ProPlan.Product.Kind = .yearly

    /// The plans in the order shown; the first one the App Store gave is chosen when the chosen one is missing.
    private static let shown: [ProPlan.Product.Kind] = [.yearly, .monthly, .lifetime]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 22) {
                    if let reason {
                        reasonLine(reason)
                    }
                    perks
                    if store.isPro {
                        active
                    } else if store.pricesFailed {
                        unavailable
                    } else if store.products.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        plans
                        // Only a plan with its App Store price can be bought (the chosen one always has it).
                        if let price = store.price(ProPlan.product(plan)) {
                            purchase(price)
                        }
                    }
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel(Loc.t("Kapat"))
        }
        .task { await store.refresh() }
        .onChange(of: store.products, initial: true) { _, _ in keepPlanSellable() }
    }

    /// When the chosen plan is one the App Store did not give, the first one it did is chosen instead.
    private func keepPlanSellable() {
        guard store.price(ProPlan.product(plan)) == nil,
              let first = Self.shown.first(where: { store.price(ProPlan.product($0)) != nil }) else { return }
        plan = first
    }

    // MARK: Parts

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AppBackgroundView(kind: .holo)
            LinearGradient(colors: [.clear, Theme.paper], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "Mürekkep Pro")
                    .font(Theme.display(.largeTitle, weight: .bold))
                Text(Loc.t("Sınırsız yapay zekâ, 3D mürekkepler ve yaratıcı arka planlar."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .frame(height: 220)
        .clipped()
    }

    private func reasonLine(_ reason: ProPlan.Feature) -> some View {
        Label(Self.reasonText(reason), systemImage: "info.circle")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    static func reasonText(_ reason: ProPlan.Feature) -> String {
        switch reason {
        case .aiAnswer:
            return Loc.t("Bugünkü {0} ücretsiz yapay zekâ cevabını kullandın. Yarın yenilenir.", "\(ProPlan.dailyAnswers)")
        case .overview:
            return Loc.t("Bu haftanın ücretsiz video ya da sesli özetini kullandın. Pazartesi yenilenir.")
        case .studySet:
            return Loc.t("Bu haftanın {0} ücretsiz çalışma setini kullandın. Pazartesi yenilenir.", "\(ProPlan.weeklyStudySets)")
        case .premiumInk:
            return Loc.t("3D mürekkepler Mürekkep Pro'da.")
        case .premiumTemplate:
            return Loc.t("Bu şablon Mürekkep Pro'da.")
        case .premiumBackground:
            return Loc.t("Bu arka plan Mürekkep Pro'da.")
        case .trialInk:
            return Loc.t("Doğa kalemlerinin deneme mürekkebi bitti. Pro ile sınırsız çizersin.")
        }
    }

    private var perks: some View {
        VStack(alignment: .leading, spacing: 14) {
            perk("sparkles", Loc.t("Sınırsız yapay zekâ"),
                 Loc.t("Ücretsiz planda günde {0} cevap", "\(ProPlan.dailyAnswers)"))
            perk("play.rectangle", Loc.t("Sınırsız video ve sesli özet"),
                 Loc.t("Ücretsiz planda haftada {0}", "\(ProPlan.weeklyOverviews)"))
            perk("rectangle.stack", Loc.t("Sınırsız çalışma seti"),
                 Loc.t("Ücretsiz planda haftada {0}", "\(ProPlan.weeklyStudySets)"))
            perk("leaf", Loc.t("Sınırsız doğa kalemleri"),
                 Loc.t("Ücretsiz planda deneme mürekkebi kadar"))
            perk("paintbrush.pointed", Loc.t("10 adet 3D mürekkep"),
                 Loc.t("Lav, altın, krom, galaksi, yıldırım, inci ve fazlası"))
            perk("photo.artframe", Loc.t("10 sanat arka planı: sıvı cam, ipek, erimiş altın ve fazlası"),
                 Loc.t("Ücretsiz planda düz renkler"))
            perk("doc.richtext", Loc.t("Planlayıcı, CV ve özel şablonlar"),
                 Loc.t("Haftalık, aylık, toplantı, nota kâğıdı ve fazlası"))
            Text(Loc.t("Defterler, PDF'ler, kalemler, metin kalemi ve öğrenci şablonları her zaman ücretsiz."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func perk(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var plans: some View {
        VStack(spacing: 10) {
            ForEach(Self.shown, id: \.self) { kind in
                planRow(kind)
            }
        }
    }

    private func planRow(_ kind: ProPlan.Product.Kind) -> some View {
        let price = store.price(ProPlan.product(kind))
        let chosen = plan == kind && price != nil
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            plan = kind
        } label: {
            HStack(spacing: 14) {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(chosen ? Theme.ink : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(Self.title(kind))
                            .font(.headline)
                        if kind == .yearly && store.trialEligible {
                            Chip(text: Loc.t("{0} gün ücretsiz", "\(store.trialDays)"), symbol: "gift", tint: Theme.aiEnd)
                        }
                    }
                    Text(detail(kind))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let price {
                    // The amount that is billed, with its period, is the largest price on the page (3.1.2).
                    Text(Self.billed(kind, price))
                        .font(.headline.monospacedDigit())
                } else {
                    // The App Store did not give this plan (say, not attached to the version yet):
                    // no planned price stands in for it, and it cannot be chosen.
                    Text(Loc.t("Şu anda alınamıyor"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
            .overlay(shape.strokeBorder(chosen ? Theme.ink : Theme.hairline, lineWidth: chosen ? 2 : 0.6))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(price == nil)
        .opacity(price == nil ? 0.6 : 1)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private static func title(_ kind: ProPlan.Product.Kind) -> String {
        switch kind {
        case .yearly: return Loc.t("Yıllık")
        case .monthly: return Loc.t("Aylık")
        case .lifetime: return Loc.t("Ömür boyu")
        }
    }

    private static func billed(_ kind: ProPlan.Product.Kind, _ price: String) -> String {
        switch kind {
        case .yearly: return Loc.t("{0}/yıl", price)
        case .monthly: return Loc.t("{0}/ay", price)
        case .lifetime: return price
        }
    }

    private func detail(_ kind: ProPlan.Product.Kind) -> String {
        switch kind {
        case .yearly:
            // The saving is only claimed from the App Store's own prices, never the planned ones.
            if let saving = store.yearlySaving, saving > 0 {
                return Loc.t("Aylık plana göre %{0} daha ucuz", "\(saving)")
            }
            return Loc.t("İstediğin zaman iptal et")
        case .monthly: return Loc.t("İstediğin zaman iptal et")
        case .lifetime: return Loc.t("Tek ödeme, abonelik yok")
        }
    }

    /// The button, what the chosen plan costs in plain words, and the last purchase's message.
    private func purchase(_ price: String) -> some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await store.purchase(ProPlan.product(plan).id)
                    if store.isPro { close() }
                }
            } label: {
                ZStack {
                    Text(callToAction)
                        .font(.headline)
                        .opacity(store.purchasing ? 0 : 1)
                    if store.purchasing {
                        ProgressView()
                            .tint(Color.white)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .tint(Theme.ink)
            .disabled(store.purchasing)
            if plan == .yearly && store.trialEligible {
                // What the trial turns into, in readable type right under the button.
                Text(Loc.t("{0} gün ücretsiz, sonra yılda {1}", "\(store.trialDays)", price))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            Text(terms(price))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let message = store.message {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var callToAction: String {
        switch plan {
        case .yearly:
            return store.trialEligible ? Loc.t("{0} gün ücretsiz dene", "\(store.trialDays)") : Loc.t("Yıllık Pro'yu başlat")
        case .monthly: return Loc.t("Aylık Pro'yu başlat")
        case .lifetime: return Loc.t("Ömür boyu Pro'yu al")
        }
    }

    /// What the purchase means, said before it (App Store guideline 3.1.2).
    private func terms(_ price: String) -> String {
        let manage = Loc.t("Ödeme Apple hesabından alınır. Aboneliği Ayarlar > Apple Hesabı > Abonelikler'den yönetebilir ve iptal edebilirsin.")
        switch plan {
        case .yearly where store.trialEligible:
            return Loc.t("{0} gün ücretsiz, sonra yılda {1}. Deneme bitmeden en az 24 saat önce iptal etmezsen abonelik başlar ve her yıl kendiliğinden yenilenir.",
                         "\(store.trialDays)", price) + " " + manage
        case .yearly:
            return Loc.t("Yılda {0}. Dönem bitmeden en az 24 saat önce iptal etmezsen her yıl kendiliğinden yenilenir.", price) + " " + manage
        case .monthly:
            return Loc.t("Ayda {0}. Dönem bitmeden en az 24 saat önce iptal etmezsen her ay kendiliğinden yenilenir.", price) + " " + manage
        case .lifetime:
            return Loc.t("{0}, tek seferlik ödeme. Abonelik değildir, yenilenmez.", price)
        }
    }

    /// No prices from the App Store (no connection, or the store not ready): nothing to buy yet.
    private var unavailable: some View {
        VStack(spacing: 12) {
            Label(Loc.t("Fiyatlar yüklenemedi."), systemImage: "wifi.exclamationmark")
                .font(.headline)
            Text(Loc.t("İnternet bağlantını kontrol edip yeniden dene."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(Loc.t("Tekrar dene")) {
                Task { await store.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var active: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Loc.t("Mürekkep Pro açık"), systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(Loc.t("Bütün sınırlar kalktı; 3D mürekkepler, özel şablonlar ve arka planlar senin."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(Loc.t("Aboneliği yönet")) {
                Task { await store.manageSubscription() }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Button(Loc.t("Satın alımları geri yükle")) {
                Task { await store.restore() }
            }
            Link(Loc.t("Kullanım koşulları"), destination: ProPlan.termsURL)
            Link(Loc.t("Gizlilik politikası"), destination: ProPlan.privacyURL)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .tint(Color.secondary)
        .frame(maxWidth: .infinity)
    }
}

/// The small mark on Pro-only pens, templates and backgrounds: "Pro" in the app's ink gradient.
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "Pro")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Theme.ai, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: Theme.aiStart.opacity(0.35), radius: 3, y: 1)
            .accessibilityLabel(Text(verbatim: "Mürekkep Pro"))
    }
}

/// The quiet way to Mürekkep Pro at the top right of the library (App Store edition, until Pro is on).
struct ProCornerButton: View {
    @ObservedObject private var pro = ProStore.shared

    var body: some View {
        if pro.locks {
            Button {
                Paywall.present()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(verbatim: "Pro")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ai)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.aiStart.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(Loc.t("Mürekkep Pro'ya geç"))
        }
    }
}

/// What Mürekkep does with the user's data, in plain words (also reachable from Settings).
struct PrivacyNote: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Self.paragraphs, id: \.self) { text in
                        Text(text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .navigationTitle(Loc.t("Gizlilik"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Loc.t("Tamam")) { dismiss() }
                }
            }
        }
    }

    static var paragraphs: [String] {
        var all = [
            Loc.t("Defterlerin, PDF'lerin, el yazın ve ses kayıtların iPad'inde durur; iPad yedeklemesi açıksa kendi iCloud yedeğine de girer. Mürekkep'in sunucusu, hesabı, reklamı ya da izleme aracı yoktur."),
            Loc.t("Yapay zekâ (Qwen3.5) iPad'in üzerinde çalışır; notların ve soruların bir sunucuya gönderilmez."),
            Loc.t("Model ilk kez indirilirken dosyalar Hugging Face'ten alınır. İnternet araması açıksa, aranan kelimeler Wikipedia'ya ve DuckDuckGo'ya gider. Bu sırada o sitelere yalnızca olağan bağlantı bilgileri (IP adresi gibi) ulaşır."),
            Loc.t("Ayarlar'da kendi bilgisayarındaki yapay zekâyı seçersen, sorular yalnızca aynı Wi‑Fi'deki o bilgisayara gider."),
        ]
        if !ProPlan.sells {
            all.append(Loc.t("Ayarlar'da kendi anahtarınla Claude'u seçersen, o sorular ve gönderdiğin sayfalar Anthropic'e gider."))
        }
        all.append(Loc.t("Satın almaları Apple yapar; ödeme bilgilerin Mürekkep'e hiç gelmez. Ücretsiz plandaki günlük ve haftalık hakların yalnızca bu iPad'de sayılır."))
        all.append(Loc.t("Notlarını silmek için defteri ya da PDF'i sil; uygulamayı silince her şey iPad'den kalkar. Sorular için: {0}", ProPlan.supportEmail))
        return all
    }
}
