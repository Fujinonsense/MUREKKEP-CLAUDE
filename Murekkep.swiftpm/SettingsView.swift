import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = ""
    @State private var testResult: String?
    @State private var testing = false
    @State private var serverModels: [String] = []
    @State private var serverStatus: String?
    @State private var checkingServer = false
    /// 0…1 while the Wi-Fi is searched for the computer's AI.
    @State private var findProgress: Double?
    @State private var showClaude = false

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                engineSection
                internetSection
                serverSection
                pencilSection
                inkSection
                claudeSection
            }
            .navigationTitle(Loc.t("Ayarlar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Loc.t("Bitti")) { dismiss() }
                }
            }
        }
    }

    // MARK: Language

    private var languageSection: some View {
        Section {
            Picker(selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            } label: {
                Label(Loc.t("Dil"), systemImage: "globe")
            }
            .pickerStyle(.menu)
        } footer: {
            Text(Loc.t("Uygulamanın tüm metinleri bu dilde gösterilir. Değiştirince ana sayfaya dönülür; açık not kaydedilir."))
        }
    }

    // MARK: Assistant

    private var engineSection: some View {
        Section {
            ForEach(AIEngine.allCases) { engine in
                Button {
                    settings.engine = engine
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: engine.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(engine == .claude ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Theme.ai))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(engine.title)
                                .foregroundStyle(.primary)
                            Text(engine.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if settings.engine == engine {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            HStack {
                Label("Apple Intelligence", systemImage: "cpu")
                Spacer()
                if let reason = OnDeviceAI.unavailableReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } else {
                    Label(Loc.t("Hazır"), systemImage: "checkmark.seal.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                }
            }
        } header: {
            Text(Loc.t("Yapay zekâ motoru"))
        } footer: {
            Text(Loc.t("Claude dışındaki hiçbir motor API anahtarı istemez. El yazısı ve taranmış sayfalar her zaman cihazda metne çevrilir."))
        }
    }

    private var internetSection: some View {
        Section {
            Toggle(isOn: $settings.webSearch) {
                Label(Loc.t("İnternetten araştır"), systemImage: "globe")
            }
        } header: {
            Text(Loc.t("İnternet"))
        } footer: {
            Text(Loc.t("Serbest sorularda ve \"Açıkla\"da Vikipedi ile DuckDuckGo'ya bakar; hesap ya da anahtar gerekmez. Yalnızca arama sözcükleri gönderilir, notların gönderilmez."))
        }
    }

    private var serverSection: some View {
        Section {
            Button {
                findServer()
            } label: {
                HStack {
                    Label(Loc.t("Bilgisayarımı ağda bul"), systemImage: "wifi")
                    if let findProgress {
                        Spacer()
                        ProgressView(value: findProgress)
                            .frame(width: 80)
                    }
                }
            }
            .disabled(findProgress != nil || checkingServer)
            TextField(Loc.t("ör. 192.168.1.20:11434"), text: $settings.serverURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                TextField(Loc.t("Model (boşsa ilk model)"), text: $settings.serverModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !serverModels.isEmpty {
                    Menu {
                        ForEach(serverModels, id: \.self) { model in
                            Button(model) { settings.serverModel = model }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                }
            }
            Toggle(Loc.t("Sayfa görüntüsünü de gönder (görsel modeller)"), isOn: $settings.serverSendsImages)
            Button {
                checkServer()
            } label: {
                HStack {
                    Text(Loc.t("Bağlantıyı test et ve modelleri getir"))
                    if checkingServer {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(checkingServer || LocalServerClient.normalizedBase(settings.serverURL) == nil)
            if let serverStatus {
                Text(serverStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(Loc.t("Yerel sunucu"))
        } footer: {
            Text(Loc.t("Bilgisayarında Ollama (ollama.com) ya da LM Studio çalıştır. Ollama'yı ağdan erişilebilir başlat: OLLAMA_HOST=0.0.0.0 ollama serve. LM Studio'da \"Serve on Local Network\"ü aç. Adresi IP numarasıyla yaz. Görsel model (ör. llama3.2-vision, gemma3, qwen2.5vl) el yazısını doğrudan okuyabilir."))
        }
    }

    // MARK: Pencil

    private var pencilSection: some View {
        Section {
            Toggle(isOn: $settings.pencilOnly) {
                Label(Loc.t("Yalnızca Apple Pencil ile çiz"), systemImage: "applepencil")
            }
            Picker(selection: $settings.tapAction) {
                ForEach(PencilAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            } label: {
                Label(Loc.t("Çift dokunma"), systemImage: "hand.tap")
            }
            Picker(selection: $settings.squeezeAction) {
                ForEach(PencilAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            } label: {
                Label(Loc.t("Sıkma (Pencil Pro)"), systemImage: "hand.pinch")
            }
            Toggle(isOn: $settings.rollRotatesNib) {
                Label(Loc.t("Gövdeyi döndürünce hat ucu dönsün (Pencil Pro)"), systemImage: "arrow.triangle.2.circlepath")
            }
            Toggle(isOn: $settings.hoverPreview) {
                Label(Loc.t("Havada önizleme ve kalem gölgesi"), systemImage: "scope")
            }
            Toggle(isOn: $settings.straightLine) {
                Label(Loc.t("Bekleyince şekli düzelt (doğru, daire, elips, parabol, yay, çokgen)"), systemImage: "scribble.variable")
            }
            Toggle(isOn: $settings.sketchSuggestions) {
                Label(Loc.t("Bekleyince çizim öner (kalp → gerçekçi kalp, yüz → emoji)"), systemImage: "heart.text.square")
            }
            .disabled(!settings.straightLine)
            Toggle(isOn: $settings.fingerTapUndo) {
                Label(Loc.t("İki parmakla dokununca geri al, üç parmakla yinele"), systemImage: "hand.tap")
            }
            Toggle(isOn: $settings.handwritingAI) {
                Label(settings.hasAPIKey
                      ? Loc.t("El yazısını ve matematiği Claude ile oku (en doğru)")
                      : Loc.t("El yazısını Claude ile oku (aşağıya Claude anahtarı ekleyince açılır)"),
                      systemImage: "text.viewfinder")
            }
            Toggle(isOn: $settings.paperSound) {
                Label(Loc.t("Yazı sesi (müziği durdurmaz; sayfanın sol alt köşesinden de açılır)"), systemImage: "speaker.wave.1")
            }
            if settings.paperSound {
                HStack {
                    Image(systemName: "speaker")
                        .foregroundStyle(.secondary)
                    Slider(value: $settings.paperSoundLevel, in: 0.1...1)
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Loc.t("Kağıt sesi düzeyi"))
            }
        } header: {
            Text("Apple Pencil")
        } footer: {
            Text(Loc.t("Basınç, eğim ve yön her kalemde kullanılır. Kaleme çift dokununca araç menüsü açılır: kalem, fosforlu, metin kalemi, seçim, cetvel, şekil, pergel ve silgi; altında kalemin kalınlığı ayarlanır, bir kalem seçince renkleri gelir. \"Geçici silgi\" seçiliyken Pencil Pro'yu sıkınca silgiye geçilir, tekrar sıkınca kaleme dönülür; silip kalemi kaldırınca da kaldığın araca kendiliğinden dönülür. Gövdeyi döndürmek hat kaleminin ucunu çevirir ve seçimler kalemde titreşimle onaylanır. Yalnızca Pencil ile çizerken de şekil tutamaçları ve çıkartma kutusu parmakla sürüklenebilir. Parmakla iki dokunuş geri alır, üç dokunuş yineler."))
        }
    }

    private var inkSection: some View {
        Section {
            Toggle(isOn: $settings.animations) {
                Label(Loc.t("Animasyonlar (dalga, sim, rüzgâr)"), systemImage: "sparkles")
            }
            Toggle(isOn: $settings.batterySaver) {
                Label(Loc.t("Pil tasarrufu (30 fps)"), systemImage: "battery.50")
            }
            VStack(alignment: .leading) {
                Text(Loc.t("Islak mürekkebin kuruma süresi: {0} sn", "\(Int(settings.dryDuration))"))
                Slider(value: $settings.dryDuration, in: 1...15, step: 1)
            }
            VStack(alignment: .leading) {
                Text(Loc.t("Lavın soğuyup kora dönme süresi: {0} sn", "\(Int(settings.lavaCoolDuration))"))
                Slider(value: $settings.lavaCoolDuration, in: 2...20, step: 1)
            }
            Picker(Loc.t("Çimde çiçek"), selection: $settings.flowerLevel) {
                Text(Loc.t("Yok")).tag(0)
                Text(Loc.t("Az")).tag(1)
                Text(Loc.t("Bol")).tag(2)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(Loc.t("3B mürekkep"))
        } footer: {
            Text(Loc.t("Ekranda hareket eden bir şey yoksa çizim motoru tamamen durur ve pil harcamaz."))
        }
    }

    // MARK: Claude (optional)

    private var claudeSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showClaude) {
                if settings.hasAPIKey {
                    Label(Loc.t("API anahtarı kayıtlı"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Button(Loc.t("Anahtarı sil"), role: .destructive) {
                        settings.deleteAPIKey()
                        testResult = nil
                    }
                } else {
                    SecureField("sk-ant-…", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(Loc.t("Kaydet")) {
                        settings.saveAPIKey(keyInput)
                        keyInput = ""
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button {
                    guard let key = settings.apiKey else { return }
                    testing = true
                    testResult = nil
                    let model = settings.model
                    Task {
                        let result = await ClaudeClient.ping(apiKey: key, model: model)
                        testResult = result
                        testing = false
                    }
                } label: {
                    HStack {
                        Text(Loc.t("Bağlantıyı test et"))
                        if testing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!settings.hasAPIKey || testing)
                if let testResult {
                    Text(testResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Picker(Loc.t("Model"), selection: $settings.model) {
                    ForEach(ClaudeModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                Picker(Loc.t("Düşünme"), selection: $settings.effort) {
                    ForEach(ThinkingEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(Loc.t("PDF'i yalnızca metin olarak gönder"), isOn: $settings.textOnlyPDF)
            } label: {
                Label("Claude API", systemImage: "cloud")
            }
        } header: {
            Text(Loc.t("İsteğe bağlı bulut"))
        } footer: {
            Text(Loc.t("Yalnızca motor olarak Claude'u seçersen kullanılır. Anahtar bu cihazda saklanır; ücreti API hesabından düşülür."))
        }
    }

    /// Searches the Wi-Fi for Ollama or LM Studio and takes the first one found.
    private func findServer() {
        findProgress = 0
        serverStatus = nil
        Task { @MainActor in
            let found = await LocalServerFinder.search { fraction in findProgress = fraction }
            findProgress = nil
            guard let first = found.first, let host = first.host else {
                serverStatus = LocalServerFinder.wifiAddress() == nil
                    ? Loc.t("iPad Wi-Fi'ye bağlı değil. Bilgisayarınla aynı ağa bağlan.")
                    : Loc.t("Ağda yapay zekâ sunucusu bulunamadı. Bilgisayarda Ollama'yı ağa açık başlat (OLLAMA_HOST=0.0.0.0) ya da LM Studio'da \"Serve on Local Network\"ü aç; yerel ağ izni sorulduysa onayla ve yeniden dene.")
                return
            }
            settings.serverURL = first.port.map { "\(host):\($0)" } ?? host
            // Looking for the computer means wanting its brain: the assistant answers with it now.
            settings.engine = .localServer
            checkServer()
        }
    }

    private func checkServer() {
        guard let base = LocalServerClient.normalizedBase(settings.serverURL) else { return }
        checkingServer = true
        serverStatus = nil
        Task { @MainActor in
            do {
                let models = try await LocalServerClient.listModels(base: base)
                serverModels = models
                if settings.serverModel.isEmpty, let first = models.first {
                    settings.serverModel = first
                }
                serverStatus = models.isEmpty
                    ? Loc.t("Bağlandı ama sunucuda model yok. Bilgisayarda bir model indir (ör. ollama pull llama3.2).")
                    : Loc.t("Bağlandı. {0} model bulundu.", "\(models.count)")
            } catch {
                serverStatus = LocalServerClient.friendly(error)
            }
            checkingServer = false
        }
    }
}
