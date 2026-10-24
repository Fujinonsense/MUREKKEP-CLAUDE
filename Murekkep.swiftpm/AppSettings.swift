import Combine
import Foundation
import Security

/// What an Apple Pencil double tap or squeeze does in Mürekkep.
enum PencilAction: String, CaseIterable, Identifiable {
    /// Squeeze and hold (or double tap) to erase; when the erasing is done the previous tool returns.
    case holdToErase
    case system
    case palette
    case eraser
    case previous
    case colors
    case nothing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdToErase: return Loc.t("Geçici silgi (bitince önceki araca dön)")
        case .system: return Loc.t("Sistem ayarını kullan")
        case .palette: return Loc.t("Araç menüsünü aç (cetvel, seçim, silgi, renkler)")
        case .eraser: return Loc.t("Silgiye geç / geri dön")
        case .previous: return Loc.t("Önceki araca dön")
        case .colors: return Loc.t("Renk paletini aç")
        case .nothing: return Loc.t("Hiçbir şey yapma")
        }
    }
}

/// User preferences, persisted in UserDefaults. The optional Claude key lives in the Keychain.
final class AppSettings: ObservableObject {
    private static let keyAccount = "claude-api-key"
    private static let fallbackKey = "claudeKeyFallback"

    /// The language of the whole app (the root view is rebuilt when it changes).
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
            Loc.reload()
        }
    }

    // MARK: Assistant

    @Published var engine: AIEngine {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: "engine") }
    }
    @Published var webSearch: Bool {
        didSet { UserDefaults.standard.set(webSearch, forKey: "webSearch") }
    }
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    @Published var serverModel: String {
        didSet { UserDefaults.standard.set(serverModel, forKey: "serverModel") }
    }
    @Published var serverSendsImages: Bool {
        didSet { UserDefaults.standard.set(serverSendsImages, forKey: "serverSendsImages") }
    }
    @Published var model: ClaudeModel {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: "model") }
    }
    @Published var effort: ThinkingEffort {
        didSet { UserDefaults.standard.set(effort.rawValue, forKey: "effort") }
    }
    @Published var textOnlyPDF: Bool {
        didSet { UserDefaults.standard.set(textOnlyPDF, forKey: "textOnlyPDF") }
    }

    // MARK: Pencil

    @Published var pencilOnly: Bool {
        didSet { UserDefaults.standard.set(pencilOnly, forKey: "pencilOnly") }
    }
    @Published var straightLine: Bool {
        didSet { UserDefaults.standard.set(straightLine, forKey: "straightLine") }
    }
    @Published var hoverPreview: Bool {
        didSet { UserDefaults.standard.set(hoverPreview, forKey: "hoverPreview") }
    }
    @Published var tapAction: PencilAction {
        didSet { UserDefaults.standard.set(tapAction.rawValue, forKey: "tapAction") }
    }
    @Published var squeezeAction: PencilAction {
        didSet { UserDefaults.standard.set(squeezeAction.rawValue, forKey: "squeezeAction") }
    }
    @Published var rollRotatesNib: Bool {
        didSet { UserDefaults.standard.set(rollRotatesNib, forKey: "rollRotatesNib") }
    }
    /// Calligraphy nib angle in degrees (0 = horizontal).
    @Published var nibAngle: Double {
        didSet { UserDefaults.standard.set(nibAngle, forKey: "nibAngle") }
    }
    /// Page rotation in degrees, so the hand can rest at a comfortable angle.
    @Published var pageAngle: Double {
        didSet { UserDefaults.standard.set(pageAngle, forKey: "pageAngle") }
    }
    /// While locked, two fingers cannot turn the page by accident.
    @Published var pageAngleLocked: Bool {
        didSet { UserDefaults.standard.set(pageAngleLocked, forKey: "pageAngleLocked") }
    }
    /// Two-finger tap undoes, three-finger tap redoes.
    @Published var fingerTapUndo: Bool {
        didSet { UserDefaults.standard.set(fingerTapUndo, forKey: "fingerTapUndo") }
    }
    /// After holding the pencil still, drawings like a heart or a smiley offer stickers.
    @Published var sketchSuggestions: Bool {
        didSet { UserDefaults.standard.set(sketchSuggestions, forKey: "sketchSuggestions") }
    }
    /// A faint paper sound while writing; it mixes with music instead of pausing it.
    @Published var paperSound: Bool {
        didSet { UserDefaults.standard.set(paperSound, forKey: "paperSound") }
    }
    /// 0…1, scaled down to a whisper by the sound engine.
    @Published var paperSoundLevel: Double {
        didSet { UserDefaults.standard.set(paperSoundLevel, forKey: "paperSoundLevel") }
    }
    /// Seconds of rest after which the text pen's writing becomes text.
    @Published var textPenDelay: Double {
        didSet { UserDefaults.standard.set(textPenDelay, forKey: "textPenDelay") }
    }
    /// Size of the text pen's and the Aa tool's letters, as a share of the template's: 0.8, 1, 1.25
    /// or 1.5 (never taller than the ruled lines allow).
    @Published var textPenScale: Double {
        didSet { UserDefaults.standard.set(textPenScale, forKey: "textPenScale") }
    }
    /// Read handwriting (text pen, "convert to text") with Claude when a key is saved: far more
    /// accurate on fast writing and on math. Without a key, or offline, the device reads it.
    @Published var handwritingAI: Bool {
        didSet { UserDefaults.standard.set(handwritingAI, forKey: "handwritingAI") }
    }

    // MARK: Ink

    @Published var animations: Bool {
        didSet { UserDefaults.standard.set(animations, forKey: "animations") }
    }
    @Published var batterySaver: Bool {
        didSet { UserDefaults.standard.set(batterySaver, forKey: "batterySaver") }
    }
    @Published var dryDuration: Double {
        didSet { UserDefaults.standard.set(dryDuration, forKey: "dryDuration") }
    }
    /// Seconds until lava has cooled into a crust with glowing embers.
    @Published var lavaCoolDuration: Double {
        didSet { UserDefaults.standard.set(lavaCoolDuration, forKey: "lavaCoolDuration") }
    }
    /// Flowers in new grass strokes: 0 none, 1 some, 2 lots.
    @Published var flowerLevel: Int {
        didSet { UserDefaults.standard.set(flowerLevel, forKey: "flowerLevel") }
    }

    @Published private(set) var hasAPIKey: Bool

    /// The AI model (Qwen3.5) downloads by itself on any internet, in the background.
    @Published var autoBrainDownload: Bool {
        didSet { UserDefaults.standard.set(autoBrainDownload, forKey: "autoBrainDownload") }
    }

    /// The background behind the library (AppBackgrounds); a Pro one shows only with Pro.
    @Published var appBackground: AppBackground {
        didSet { UserDefaults.standard.set(appBackground.rawValue, forKey: "appBackground") }
    }

    /// Pens given a heart in the pen panel: they always stand in the notebook's pen bar.
    @Published var favoriteBrushes: [Brush] {
        didSet { UserDefaults.standard.set(favoriteBrushes.map { Int($0.rawValue) }, forKey: "favoriteBrushes") }
    }

    /// Where the notebook's pen bar stands: along the top, along the bottom or down the right side.
    @Published var paletteEdge: PaletteEdge {
        didSet { UserDefaults.standard.set(paletteEdge.rawValue, forKey: "paletteEdge") }
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "engine": AIEngine.deviceBrain.rawValue,
            "webSearch": true,
            "serverURL": "",
            "serverModel": "",
            "serverSendsImages": false,
            "pencilOnly": true,
            "straightLine": true,
            "hoverPreview": true,
            "tapAction": PencilAction.palette.rawValue,
            "squeezeAction": PencilAction.holdToErase.rawValue,
            "rollRotatesNib": true,
            "nibAngle": 38.0,
            "pageAngle": 0.0,
            "pageAngleLocked": true,
            "fingerTapUndo": true,
            "sketchSuggestions": true,
            "paperSound": false,
            "paperSoundLevel": 0.4,
            "textPenDelay": 1.3,
            "textPenScale": 1.0,
            "handwritingAI": true,
            "animations": true,
            "batterySaver": false,
            "dryDuration": 4.0,
            "lavaCoolDuration": 6.0,
            "flowerLevel": 1,
            "textOnlyPDF": false,
            "autoBrainDownload": true,
            "appBackground": (ProPlan.sells ? AppBackground.paper : AppBackground.ruled).rawValue,
        ])
        language = AppLanguage.stored
        engine = AIEngine.migrated(AIEngine(rawValue: d.string(forKey: "engine") ?? ""))
        webSearch = d.bool(forKey: "webSearch")
        serverURL = d.string(forKey: "serverURL") ?? ""
        serverModel = d.string(forKey: "serverModel") ?? ""
        serverSendsImages = d.bool(forKey: "serverSendsImages")
        model = ClaudeModel(rawValue: d.string(forKey: "model") ?? "") ?? .sonnet
        effort = ThinkingEffort(rawValue: d.string(forKey: "effort") ?? "") ?? .medium
        textOnlyPDF = d.bool(forKey: "textOnlyPDF")
        autoBrainDownload = d.bool(forKey: "autoBrainDownload")
        pencilOnly = d.bool(forKey: "pencilOnly")
        straightLine = d.bool(forKey: "straightLine")
        hoverPreview = d.bool(forKey: "hoverPreview")
        // 2.3: squeeze-and-hold borrows the eraser. Earlier installs had stored the palette (or the
        // plain eraser switch), so they move over once.
        if !d.bool(forKey: "pencilActions.v2") {
            d.set(true, forKey: "pencilActions.v2")
            d.set(PencilAction.holdToErase.rawValue, forKey: "squeezeAction")
            let tap = d.string(forKey: "tapAction")
            if tap == nil || tap == PencilAction.eraser.rawValue || tap == PencilAction.system.rawValue {
                d.set(PencilAction.holdToErase.rawValue, forKey: "tapAction")
            }
        }
        // 2.5: double tap opens the tool ring (ruler, lasso, eraser…); squeeze keeps the borrowed eraser.
        if !d.bool(forKey: "pencilActions.v3") {
            d.set(true, forKey: "pencilActions.v3")
            let tap = d.string(forKey: "tapAction")
            if tap == nil || tap == PencilAction.holdToErase.rawValue {
                d.set(PencilAction.palette.rawValue, forKey: "tapAction")
            }
        }
        tapAction = PencilAction(rawValue: d.string(forKey: "tapAction") ?? "") ?? .palette
        squeezeAction = PencilAction(rawValue: d.string(forKey: "squeezeAction") ?? "") ?? .holdToErase
        rollRotatesNib = d.bool(forKey: "rollRotatesNib")
        nibAngle = min(max(d.double(forKey: "nibAngle"), 0), 180)
        pageAngle = min(max(d.double(forKey: "pageAngle"), -90), 90)
        pageAngleLocked = d.bool(forKey: "pageAngleLocked")
        fingerTapUndo = d.bool(forKey: "fingerTapUndo")
        sketchSuggestions = d.bool(forKey: "sketchSuggestions")
        // 3.0: the writing sound starts switched off (its switch moved to a corner of the page).
        if !d.bool(forKey: "paperSound.v2") {
            d.set(true, forKey: "paperSound.v2")
            d.set(false, forKey: "paperSound")
        }
        paperSound = d.bool(forKey: "paperSound")
        handwritingAI = d.bool(forKey: "handwritingAI")
        paperSoundLevel = min(max(d.double(forKey: "paperSoundLevel"), 0), 1)
        textPenDelay = min(max(d.double(forKey: "textPenDelay"), 0.6), 3)
        let scale = d.double(forKey: "textPenScale")
        textPenScale = scale >= 0.8 && scale <= 1.5 ? scale : 1.0
        animations = d.bool(forKey: "animations")
        batterySaver = d.bool(forKey: "batterySaver")
        dryDuration = min(max(d.double(forKey: "dryDuration"), 1), 20)
        lavaCoolDuration = min(max(d.double(forKey: "lavaCoolDuration"), 2), 20)
        flowerLevel = min(max(d.integer(forKey: "flowerLevel"), 0), 2)
        appBackground = AppBackground.migrated(d.string(forKey: "appBackground") ?? "") ?? .paper
        favoriteBrushes = (d.array(forKey: "favoriteBrushes") as? [Int] ?? []).compactMap { Brush(rawValue: UInt8(clamping: $0)) }
        paletteEdge = PaletteEdge(rawValue: d.string(forKey: "paletteEdge") ?? "") ?? .top
        hasAPIKey = (Keychain.read(account: Self.keyAccount) ?? d.string(forKey: Self.fallbackKey)) != nil
    }

    func toggleFavorite(_ brush: Brush) {
        favoriteBrushes = PenStrip.toggled(brush, in: favoriteBrushes)
    }

    /// The background to draw: a Pro one falls back to paper while Pro is locked.
    func shownBackground(locked: Bool) -> AppBackground {
        appBackground.isPremium && locked ? .paper : appBackground
    }

    var apiKey: String? {
        if let k = Keychain.read(account: Self.keyAccount), !k.isEmpty { return k }
        if let k = UserDefaults.standard.string(forKey: Self.fallbackKey), !k.isEmpty { return k }
        return nil
    }

    func saveAPIKey(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if Keychain.save(key, account: Self.keyAccount) {
            UserDefaults.standard.removeObject(forKey: Self.fallbackKey)
        } else {
            // Some sandboxes (for example certain Playgrounds builds) have no keychain access.
            UserDefaults.standard.set(key, forKey: Self.fallbackKey)
        }
        hasAPIKey = true
    }

    func deleteAPIKey() {
        Keychain.delete(account: Self.keyAccount)
        UserDefaults.standard.removeObject(forKey: Self.fallbackKey)
        hasAPIKey = false
    }

    // Last used color and width per brush.

    func color(for brush: Brush) -> InkColor? {
        guard let arr = UserDefaults.standard.array(forKey: "color.\(brush.rawValue)") as? [Double], arr.count == 4 else {
            return nil
        }
        return InkColor(Float(arr[0]), Float(arr[1]), Float(arr[2]), Float(arr[3]))
    }

    func setColor(_ c: InkColor, for brush: Brush) {
        UserDefaults.standard.set([Double(c.r), Double(c.g), Double(c.b), Double(c.a)], forKey: "color.\(brush.rawValue)")
    }

    func width(for brush: Brush) -> Float? {
        let v = UserDefaults.standard.double(forKey: "width.\(brush.rawValue)")
        return v > 0 ? Float(v) : nil
    }

    func setWidth(_ w: Float, for brush: Brush) {
        UserDefaults.standard.set(Double(w), forKey: "width.\(brush.rawValue)")
    }

    /// Pens picked most recently (newest first); a new user starts with the writing pens (in the App
    /// Store edition the free ones).
    var recentBrushes: [Brush] {
        let raw = UserDefaults.standard.array(forKey: "recentBrushes") as? [Int] ?? []
        let list = raw.compactMap { Brush(rawValue: UInt8(clamping: $0)) }
        guard list.isEmpty else { return list }
        return ProPlan.sells ? [.pen, .pencil, .calligraphy, .highlighter] : [.pen, .pencil, .fountain, .highlighter]
    }

    func rememberBrush(_ brush: Brush) {
        var list = recentBrushes.filter { $0 != brush }
        list.insert(brush, at: 0)
        UserDefaults.standard.set(list.prefix(6).map { Int($0.rawValue) }, forKey: "recentBrushes")
        objectWillChange.send()
    }

    /// Recently picked custom colors (newest first).
    var recentColors: [InkColor] {
        guard let arr = UserDefaults.standard.array(forKey: "recentColors") as? [[Double]] else { return [] }
        return arr.compactMap { v in
            v.count == 4 ? InkColor(Float(v[0]), Float(v[1]), Float(v[2]), Float(v[3])) : nil
        }
    }

    func rememberColor(_ c: InkColor) {
        var list = recentColors.filter { $0 != c }
        list.insert(c, at: 0)
        let stored = list.prefix(8).map { [Double($0.r), Double($0.g), Double($0.b), Double($0.a)] }
        UserDefaults.standard.set(Array(stored), forKey: "recentColors")
        objectWillChange.send()
    }
}

enum Keychain {
    private static let service = "com.murekkep.app.claude"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        SecItemDelete(baseQuery(account) as CFDictionary)
        var add = baseQuery(account)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
