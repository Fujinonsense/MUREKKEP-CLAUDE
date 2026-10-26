import SwiftUI
import UIKit

struct AssistantPanel: View {
    @ObservedObject var assistant: AssistantModel
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings
    var onClose: () -> Void

    @State private var keyInput = ""
    @FocusState private var inputFocused: Bool
    @State private var askWebSearch = false

    init(assistant: AssistantModel, editor: EditorModel, onClose: @escaping () -> Void) {
        self.assistant = assistant
        self.editor = editor
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if settings.engine == .claude && !settings.hasAPIKey {
                keyPrompt
                Divider()
            }
            messagesList
            controls
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            assistant.warmUp()
            // The only question the assistant asks: whether its searches may go to the web.
            if !settings.askedWebSearch && settings.engine != .claude { askWebSearch = true }
        }
        .alert(Loc.t("İnternette arama açılsın mı?"), isPresented: $askWebSearch) {
            Button(Loc.t("Aç")) { answerWebSearch(true) }
            Button(Loc.t("Kapalı kalsın"), role: .cancel) { answerWebSearch(false) }
        } message: {
            Text(Loc.t("Açıksa yalnızca aranan kelimeler Wikipedia ve DuckDuckGo'ya gider; notların gönderilmez."))
        }
    }

    private func answerWebSearch(_ on: Bool) {
        settings.webSearch = on
        settings.askedWebSearch = true
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.ai)
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: assistant.isBusy)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(Loc.t("Asistan"))
                    .font(.headline)
                Menu {
                    Picker(Loc.t("Motor"), selection: $settings.engine) {
                        ForEach(AIEngine.listed(current: settings.engine, hasKey: settings.hasAPIKey)) { engine in
                            Label(engine.title, systemImage: engine.symbol).tag(engine)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: assistant.engineBadge.symbol)
                        Text(assistant.engineBadge.title)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                assistant.reset()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
            }
            .disabled(assistant.messages.isEmpty)
            .accessibilityLabel(Loc.t("Yeni sohbet"))
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
            }
            .accessibilityLabel(Loc.t("Kapat"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var keyPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Loc.t("Claude motoru seçili. API anahtarı ekle ya da anahtarsız bir motora geç."))
                .font(.subheadline.weight(.medium))
            HStack {
                SecureField("sk-ant-…", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button(Loc.t("Kaydet")) {
                    settings.saveAPIKey(keyInput)
                    keyInput = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button(Loc.t("Anahtarsız motora geç (Otomatik)")) {
                settings.engine = .auto
            }
            .font(.caption.weight(.semibold))
        }
        .padding(16)
        .background(Theme.ink.opacity(0.06))
    }

    // MARK: Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if assistant.messages.isEmpty {
                        intro
                    }
                    ForEach(assistant.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if let status = assistant.status {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 4)
                        .transition(.opacity)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: assistant.messages.last?.text) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: assistant.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editor.isPDF ? Loc.t("Bu PDF hakkında sor.") : Loc.t("El yazısı notların hakkında sor."))
                .font(Theme.display(.title2))
            Text(introDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if showsBrainOffer {
                BrainCard(compact: true)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(spacing: 8) {
                Chip(text: Loc.t("API anahtarı gerekmez"), symbol: "key.slash", tint: .green)
                if settings.webSearch && settings.engine != .claude {
                    Chip(text: Loc.t("İnternet açık"), symbol: "globe", tint: Theme.ink)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(QuickAction.allCases) { action in
                    Button {
                        assistant.run(action)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: action.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.ai)
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(assistant.isBusy)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var introDetail: String {
        switch settings.engine {
        case .claude:
            return Loc.t("Claude seçtiğin sayfaları okur; istersen üzerine yazdığın notları da görür.")
        default:
            return editor.isPDF
                ? Loc.t("Sayfaların metnini ve el yazını okur, yanıtı tamamen iPad'de üretir. İstersen internete de bakar.")
                : Loc.t("El yazını metne çevirir, yanıtı tamamen iPad'de üretir. İstersen internete de bakar.")
        }
    }

    /// The stronger model is offered where answers are written, until it is on the iPad.
    private var showsBrainOffer: Bool {
        guard settings.engine == .auto || settings.engine == .deviceBrain else { return false }
        let brain = DeviceBrain.shared
        return BrainRuntime.isCompiledIn && brain.model != nil && brain.phase != .ready
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(Loc.t("Kapsam"), selection: $assistant.scope) {
                ForEach(AIScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                if settings.engine != .claude {
                    Toggle(isOn: $settings.webSearch) {
                        Label(Loc.t("İnternet"), systemImage: "globe")
                            .font(.footnote.weight(.medium))
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
                if editor.isPDF {
                    Toggle(isOn: $assistant.includeHandwriting) {
                        Label(Loc.t("Notlarım"), systemImage: "pencil.and.scribble")
                            .font(.footnote.weight(.medium))
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
                Spacer()
                Text(scopeHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !assistant.messages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(QuickAction.allCases) { action in
                            Button {
                                assistant.run(action)
                            } label: {
                                Label(action.title, systemImage: action.symbol)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(assistant.isBusy)
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(Loc.t("Bir soru yaz ya da Pencil ile karala…"), text: $assistant.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onSubmit { assistant.send() }
                if assistant.isBusy {
                    Button {
                        assistant.cancel()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Loc.t("Durdur"))
                } else {
                    Button {
                        assistant.send()
                        inputFocused = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Theme.ai)
                                .frame(width: 34, height: 34)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(sendDisabled ? 0.4 : 1)
                    .disabled(sendDisabled)
                    .accessibilityLabel(Loc.t("Gönder"))
                }
            }
        }
        .padding(14)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var sendDisabled: Bool {
        assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (settings.engine == .claude && !settings.hasAPIKey)
    }

    private var scopeHint: String {
        let current = editor.currentPage + 1
        switch assistant.scope {
        case .page:
            return Loc.t("Sayfa {0}", "\(current)")
        case .nearby:
            let r = editor.pageRange(around: editor.currentPage, radius: 2)
            return Loc.t("Sayfa {0}–{1}", "\(r.lowerBound + 1)", "\(r.upperBound + 1)")
        case .document:
            return Loc.t("{0} sayfa", "\(editor.pageCount)")
        case .section:
            if let id = editor.store.note(editor.meta.id)?.sectionID,
               let section = editor.store.sections.first(where: { $0.id == id }) {
                let count = editor.store.notes.filter { $0.sectionID == id }.count
                return Loc.t("{0} · {1} not", "\(section.name)", "\(count)")
            }
            return Loc.t("Not bir bölümde değil")
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.text)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    // The student's own words in their wet ink.
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .textSelection(.enabled)
                if let note = message.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        } else if message.text.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let engine = message.engine {
                    Label(engine, systemImage: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(MarkdownLite.render(message.text))
                    .font(.callout)
                    .foregroundStyle(message.isError ? Color.red : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !message.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Loc.t("Kaynaklar"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(message.sources.enumerated()), id: \.offset) { i, source in
                            Link(destination: source.url) {
                                HStack(spacing: 6) {
                                    Text("\(i + 1)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Theme.ink, in: Circle())
                                    Text(source.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text(source.url.host ?? "")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(14)
            .padding(.leading, 6)
            // The answer reads like a teacher's note on paper, marked in the margin.
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(message.isError ? AnyShapeStyle(Color.red) : AnyShapeStyle(Theme.ai))
                    .frame(width: 3)
                    .padding(.vertical, 14)
                    .padding(.leading, 7)
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = MathText.plain(message.text)
                } label: {
                    Label(Loc.t("Kopyala"), systemImage: "doc.on.doc")
                }
                // A wrong or harmful AI answer can be sent to us (App Store guideline 1.2).
                Link(destination: ProPlan.supportMail(subject: Loc.t("Yapay zekâ cevabını bildir"),
                                                      body: Loc.t("Bu cevapta sorun var:") + "\n\n" + MathText.plain(message.text))) {
                    Label(Loc.t("Bildir"), systemImage: "exclamationmark.bubble")
                }
            }
        }
    }
}

/// Small Markdown renderer: headings, bullets and code blocks per line, inline styles via Foundation.
/// Any LaTeX a model slipped in is shown as text (MathText), code blocks aside.
enum MarkdownLite {
    static func render(_ text: String) -> AttributedString {
        var result = AttributedString()
        let lines = MathText.plain(text).components(separatedBy: "\n")
        var inCode = false
        for (index, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                continue
            }
            var line: AttributedString
            if inCode {
                line = AttributedString(raw)
                line.font = .system(.callout, design: .monospaced)
            } else if let heading = headingText(trimmed) {
                line = inline(heading)
                line.font = .headline
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = String(repeating: "   ", count: min(raw.prefix(while: { $0 == " " }).count / 2, 4))
                line = AttributedString(indent + "•  ") + inline(String(trimmed.dropFirst(2)))
            } else {
                line = inline(raw)
            }
            result += line
            if index < lines.count - 1 {
                result += AttributedString("\n")
            }
        }
        return result
    }

    private static func headingText(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.hasPrefix(" ") else { return nil }
        return String(rest.dropFirst())
    }

    private static func inline(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }
}
