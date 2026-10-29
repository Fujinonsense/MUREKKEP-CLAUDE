import SwiftUI
import UIKit

/// The engineering toolbox: a scientific calculator that also solves equations, a unit converter,
/// constants and formulas, and function plots. Every result can be written onto the page.
struct EngineeringPanel: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("engineering.tab") private var tab: Tab = .calculator

    enum Tab: String, CaseIterable, Identifiable {
        case calculator
        case units
        case reference
        case plot

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calculator: return Loc.t("Hesap")
            case .units: return Loc.t("Birimler")
            case .reference: return Loc.t("Formüller")
            case .plot: return Loc.t("Grafik")
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(Loc.t("Bölüm"), selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
                switch tab {
                case .calculator:
                    CalculatorView(editor: editor)
                case .units:
                    UnitConverterView(editor: editor)
                case .reference:
                    ReferenceView(editor: editor)
                case .plot:
                    PlotView(editor: editor) { dismiss() }
                }
            }
            .navigationTitle(Loc.t("Mühendislik"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Loc.t("Kapat")) { dismiss() }
                }
            }
        }
    }
}

/// "Sayfaya yaz" button shared by the tabs.
private struct WriteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(Loc.t("Sayfaya yaz"), systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.ink)
    }
}

// MARK: - Calculator

struct CalculatorView: View {
    @ObservedObject var editor: EditorModel
    @AppStorage("calculator.degrees") private var degrees = true
    @State private var expression = ""
    @State private var history: [Entry] = []
    @State private var lastValue: Double?

    struct Entry: Identifiable {
        let id = UUID()
        let expression: String
        let result: String
    }

    private let keys: [[String]] = [
        ["sin", "cos", "tan", "√", "^"],
        ["asin", "acos", "atan", "ln", "log"],
        ["7", "8", "9", "(", ")"],
        ["4", "5", "6", "×", "÷"],
        ["1", "2", "3", "+", "−"],
        ["0", ",", "π", "e", "!"],
        ["x", "=", "²", "Ans", "⌫"],
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .trailing, spacing: 6) {
                    TextField(Loc.t("Örn. 3,2 × sin 30 + √2 ya da 2x + 3 = 11"), text: $expression)
                        .font(.title2.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(commit)
                    Text(preview ?? " ")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(preview == nil ? Color.secondary : Theme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack {
                    Picker(Loc.t("Açı"), selection: $degrees) {
                        Text(Loc.t("Derece")).tag(true)
                        Text(Loc.t("Radyan")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    Spacer()
                    Button(Loc.t("Temizle"), role: .destructive) { expression = "" }
                        .buttonStyle(.bordered)
                    WriteButton { write() }
                        .disabled(preview == nil)
                }

                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(keys, id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { key in
                                Button {
                                    press(key)
                                } label: {
                                    Text(key)
                                        .font(.system(size: key.count > 2 ? 16 : 20, weight: .medium).monospacedDigit())
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(key == "=" ? Color.white : Color.primary)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(keyFill(key)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !history.isEmpty {
                    Text(Loc.t("Geçmiş"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(history) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.expression).font(.subheadline.monospacedDigit())
                                Text(entry.result).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.ink)
                            }
                            Spacer()
                            Button {
                                editor.writeAtViewCenter("\(entry.expression) → \(entry.result)")
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Loc.t("Sayfaya yaz"))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
        }
    }

    private func keyFill(_ key: String) -> AnyShapeStyle {
        if key == "=" { return AnyShapeStyle(Theme.ink) }
        if key.first?.isNumber == true || key == "," { return AnyShapeStyle(Color.primary.opacity(0.10)) }
        return AnyShapeStyle(Color.primary.opacity(0.05))
    }

    private func press(_ key: String) {
        switch key {
        case "⌫":
            if !expression.isEmpty { expression.removeLast() }
        case "Ans":
            if let lastValue { expression += MathFormat.decimal(lastValue) }
        case "sin", "cos", "tan", "asin", "acos", "atan", "ln", "log":
            expression += key + "("
        case "√":
            expression += "√("
        case "=":
            // "2x + 3" then "=" starts the right side of an equation; a second "=" solves it.
            if !expression.contains("=") && expression.contains("x") {
                expression += "="
            } else {
                commit()
            }
        default:
            expression += key
        }
    }

    /// The live answer under the expression.
    private var preview: String? {
        let text = expression.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return Calculator.answer(text, degrees: degrees)?.text
    }

    private func commit() {
        let text = expression.trimmingCharacters(in: .whitespaces)
        guard let answer = Calculator.answer(text, degrees: degrees) else { return }
        history.insert(Entry(expression: text, result: answer.text), at: 0)
        if history.count > 30 { history.removeLast(history.count - 30) }
        if let v = answer.value { lastValue = v }
    }

    private func write() {
        let text = expression.trimmingCharacters(in: .whitespaces)
        guard let answer = Calculator.answer(text, degrees: degrees) else { return }
        commit()
        if answer.value != nil {
            editor.writeAtViewCenter("\(text) = \(answer.text)")
        } else {
            editor.writeAtViewCenter("\(text) → \(answer.text)")
        }
    }
}

/// Evaluates calculator input with the same engine the assistant uses to read handwriting.
enum Calculator {
    struct Answer {
        let text: String
        let value: Double?
    }

    private static let inverseTrig: Set<String> = ["asin", "arcsin", "acos", "arccos", "atan", "arctan"]

    static func answer(_ raw: String, degrees: Bool) -> Answer? {
        let text = raw.hasSuffix("=") ? String(raw.dropLast()) : raw
        if text.contains("=") {
            guard let finding = MathEngine.analyze(text) else { return nil }
            return Answer(text: plain(finding), value: nil)
        }
        guard let e = MathParser.parse(text) else { return nil }
        if !e.variables.isEmpty {
            return nil
        }
        guard let v = angleMode(e, degrees: degrees).evaluate([:]) else {
            return Answer(text: Loc.t("tanımsız"), value: nil)
        }
        let tidy = MathEngine.tidy(v)
        return Answer(text: MathFormat.number(tidy), value: tidy)
    }

    /// Applies the degree/radian switch. In radians a literal like "sin 30" is wrapped so the
    /// handwriting heuristic (which reads it as degrees) stays out.
    static func angleMode(_ e: MathExpr, degrees: Bool) -> MathExpr {
        switch e {
        case .number, .variable:
            return e
        case let .negate(a):
            return .negate(angleMode(a, degrees: degrees))
        case let .add(a, b):
            return .add(angleMode(a, degrees: degrees), angleMode(b, degrees: degrees))
        case let .subtract(a, b):
            return .subtract(angleMode(a, degrees: degrees), angleMode(b, degrees: degrees))
        case let .multiply(a, b):
            return .multiply(angleMode(a, degrees: degrees), angleMode(b, degrees: degrees))
        case let .divide(a, b):
            return .divide(angleMode(a, degrees: degrees), angleMode(b, degrees: degrees))
        case let .power(a, b):
            return .power(angleMode(a, degrees: degrees), angleMode(b, degrees: degrees))
        case let .factorial(a):
            return .factorial(angleMode(a, degrees: degrees))
        case let .degrees(a):
            return .degrees(angleMode(a, degrees: degrees))
        case let .call(name, arg):
            let inner = angleMode(arg, degrees: degrees)
            if MathExpr.trigNames.contains(name) {
                if case .degrees = inner { return .call(name, inner) }
                return .call(name, degrees ? .degrees(inner) : .multiply(inner, .number(1)))
            }
            if inverseTrig.contains(name), degrees {
                return .multiply(.call(name, inner), .number(180 / .pi))
            }
            return .call(name, inner)
        }
    }

    /// Plain-text version of a finding, short enough to write on the page.
    static func plain(_ finding: MathFinding) -> String {
        switch finding {
        case let .value(_, v):
            return MathFormat.number(v)
        case let .claim(_, holds, left, _, _):
            return holds ? Loc.t("doğru") : Loc.t("yanlış: sol taraf {0} eder", "\(MathFormat.number(left))")
        case let .solved(_, variable, roots, _, trig):
            return MathFormat.roots(roots, variable: variable, trig: trig)
        case let .noRealSolution(_, variable):
            return Loc.t("gerçek sayılarda {0} için çözüm yok", "\(variable)")
        case let .identity(_, variable):
            return Loc.t("her {0} için doğru", "\(variable)")
        case .contradiction:
            return Loc.t("çözüm yok (çelişki)")
        }
    }
}

// MARK: - Units

struct UnitDef: Hashable {
    let name: String
    let symbol: String
    /// Value in the category's base unit = value × factor + offset.
    let factor: Double
    var offset: Double = 0
}

struct UnitCategory: Identifiable, Hashable {
    let title: String
    let symbol: String
    let units: [UnitDef]

    var id: String { title }

    static var all: [UnitCategory] { [
        UnitCategory(title: Loc.t("Uzunluk"), symbol: "ruler", units: [
            UnitDef(name: Loc.t("milimetre"), symbol: "mm", factor: 0.001),
            UnitDef(name: Loc.t("santimetre"), symbol: "cm", factor: 0.01),
            UnitDef(name: Loc.t("metre"), symbol: "m", factor: 1),
            UnitDef(name: Loc.t("kilometre"), symbol: "km", factor: 1000),
            UnitDef(name: Loc.t("mikrometre"), symbol: "μm", factor: 1e-6),
            UnitDef(name: Loc.t("inç"), symbol: "in", factor: 0.0254),
            UnitDef(name: Loc.t("fit"), symbol: "ft", factor: 0.3048),
            UnitDef(name: Loc.t("yarda"), symbol: "yd", factor: 0.9144),
            UnitDef(name: Loc.t("mil"), symbol: "mi", factor: 1609.344),
            UnitDef(name: Loc.t("deniz mili"), symbol: "nmi", factor: 1852),
        ]),
        UnitCategory(title: Loc.t("Alan"), symbol: "square.dashed", units: [
            UnitDef(name: Loc.t("milimetrekare"), symbol: "mm²", factor: 1e-6),
            UnitDef(name: Loc.t("santimetrekare"), symbol: "cm²", factor: 1e-4),
            UnitDef(name: Loc.t("metrekare"), symbol: "m²", factor: 1),
            UnitDef(name: Loc.t("dönüm"), symbol: Loc.t("dönüm"), factor: 1000),
            UnitDef(name: Loc.t("hektar"), symbol: "ha", factor: 1e4),
            UnitDef(name: Loc.t("kilometrekare"), symbol: "km²", factor: 1e6),
            UnitDef(name: Loc.t("inçkare"), symbol: "in²", factor: 0.00064516),
            UnitDef(name: Loc.t("fitkare"), symbol: "ft²", factor: 0.09290304),
        ]),
        UnitCategory(title: Loc.t("Hacim"), symbol: "cube", units: [
            UnitDef(name: Loc.t("mililitre"), symbol: "mL", factor: 1e-6),
            UnitDef(name: Loc.t("litre"), symbol: "L", factor: 1e-3),
            UnitDef(name: Loc.t("santimetreküp"), symbol: "cm³", factor: 1e-6),
            UnitDef(name: Loc.t("metreküp"), symbol: "m³", factor: 1),
            UnitDef(name: Loc.t("inçküp"), symbol: "in³", factor: 1.6387064e-5),
            UnitDef(name: Loc.t("fitküp"), symbol: "ft³", factor: 0.028316846592),
            UnitDef(name: Loc.t("galon (ABD)"), symbol: "gal", factor: 0.003785411784),
        ]),
        UnitCategory(title: Loc.t("Kütle"), symbol: "scalemass", units: [
            UnitDef(name: Loc.t("miligram"), symbol: "mg", factor: 1e-6),
            UnitDef(name: "gram", symbol: "g", factor: 1e-3),
            UnitDef(name: "kilogram", symbol: "kg", factor: 1),
            UnitDef(name: Loc.t("ton"), symbol: "t", factor: 1000),
            UnitDef(name: "pound", symbol: "lb", factor: 0.45359237),
            UnitDef(name: Loc.t("ons"), symbol: "oz", factor: 0.028349523125),
            UnitDef(name: "slug", symbol: "slug", factor: 14.59390294),
        ]),
        UnitCategory(title: Loc.t("Kuvvet"), symbol: "arrow.down.to.line", units: [
            UnitDef(name: "newton", symbol: "N", factor: 1),
            UnitDef(name: "kilonewton", symbol: "kN", factor: 1e3),
            UnitDef(name: "meganewton", symbol: "MN", factor: 1e6),
            UnitDef(name: Loc.t("kilogram-kuvvet"), symbol: "kgf", factor: 9.80665),
            UnitDef(name: Loc.t("pound-kuvvet"), symbol: "lbf", factor: 4.4482216152605),
            UnitDef(name: "kip", symbol: "kip", factor: 4448.2216152605),
            UnitDef(name: Loc.t("din"), symbol: "dyn", factor: 1e-5),
        ]),
        UnitCategory(title: Loc.t("Basınç / Gerilme"), symbol: "gauge.with.dots.needle.50percent", units: [
            UnitDef(name: "pascal", symbol: "Pa", factor: 1),
            UnitDef(name: "kilopascal", symbol: "kPa", factor: 1e3),
            UnitDef(name: "megapascal", symbol: "MPa", factor: 1e6),
            UnitDef(name: "gigapascal", symbol: "GPa", factor: 1e9),
            UnitDef(name: "N/mm²", symbol: "N/mm²", factor: 1e6),
            UnitDef(name: "bar", symbol: "bar", factor: 1e5),
            UnitDef(name: Loc.t("atmosfer"), symbol: "atm", factor: 101_325),
            UnitDef(name: "psi", symbol: "psi", factor: 6894.757293168),
            UnitDef(name: "ksi", symbol: "ksi", factor: 6_894_757.293168),
            UnitDef(name: "kgf/cm²", symbol: "kgf/cm²", factor: 98_066.5),
            UnitDef(name: Loc.t("milimetre cıva"), symbol: "mmHg", factor: 133.322387415),
        ]),
        UnitCategory(title: Loc.t("Enerji / İş"), symbol: "bolt", units: [
            UnitDef(name: "joule", symbol: "J", factor: 1),
            UnitDef(name: "kilojoule", symbol: "kJ", factor: 1e3),
            UnitDef(name: "megajoule", symbol: "MJ", factor: 1e6),
            UnitDef(name: Loc.t("watt-saat"), symbol: "Wh", factor: 3600),
            UnitDef(name: Loc.t("kilowatt-saat"), symbol: "kWh", factor: 3.6e6),
            UnitDef(name: Loc.t("kalori"), symbol: "cal", factor: 4.184),
            UnitDef(name: Loc.t("kilokalori"), symbol: "kcal", factor: 4184),
            UnitDef(name: "BTU", symbol: "BTU", factor: 1055.05585262),
            UnitDef(name: Loc.t("elektronvolt"), symbol: "eV", factor: 1.602176634e-19),
            UnitDef(name: Loc.t("fit-pound"), symbol: "ft·lbf", factor: 1.3558179483314),
        ]),
        UnitCategory(title: Loc.t("Güç"), symbol: "powerplug", units: [
            UnitDef(name: "watt", symbol: "W", factor: 1),
            UnitDef(name: "kilowatt", symbol: "kW", factor: 1e3),
            UnitDef(name: "megawatt", symbol: "MW", factor: 1e6),
            UnitDef(name: Loc.t("beygir gücü (metrik)"), symbol: Loc.t("BG"), factor: 735.49875),
            UnitDef(name: "horsepower", symbol: "hp", factor: 745.69987158227),
            UnitDef(name: Loc.t("BTU/saat"), symbol: "BTU/h", factor: 0.29307107017),
        ]),
        UnitCategory(title: Loc.t("Tork / Moment"), symbol: "arrow.clockwise", units: [
            UnitDef(name: Loc.t("newton-metre"), symbol: "N·m", factor: 1),
            UnitDef(name: Loc.t("kilonewton-metre"), symbol: "kN·m", factor: 1e3),
            UnitDef(name: Loc.t("newton-milimetre"), symbol: "N·mm", factor: 1e-3),
            UnitDef(name: Loc.t("kgf-metre"), symbol: "kgf·m", factor: 9.80665),
            UnitDef(name: Loc.t("pound-fit"), symbol: "lbf·ft", factor: 1.3558179483314),
            UnitDef(name: Loc.t("pound-inç"), symbol: "lbf·in", factor: 0.1129848290276),
        ]),
        UnitCategory(title: Loc.t("Hız"), symbol: "speedometer", units: [
            UnitDef(name: Loc.t("metre/saniye"), symbol: "m/s", factor: 1),
            UnitDef(name: Loc.t("kilometre/saat"), symbol: "km/h", factor: 1 / 3.6),
            UnitDef(name: Loc.t("mil/saat"), symbol: "mph", factor: 0.44704),
            UnitDef(name: "knot", symbol: "kn", factor: 1852.0 / 3600.0),
            UnitDef(name: Loc.t("fit/saniye"), symbol: "ft/s", factor: 0.3048),
        ]),
        UnitCategory(title: Loc.t("Sıcaklık"), symbol: "thermometer.medium", units: [
            UnitDef(name: "Celsius", symbol: "°C", factor: 1, offset: 273.15),
            UnitDef(name: "Kelvin", symbol: "K", factor: 1),
            UnitDef(name: "Fahrenheit", symbol: "°F", factor: 5.0 / 9.0, offset: 273.15 - 32.0 * 5.0 / 9.0),
            UnitDef(name: "Rankine", symbol: "°R", factor: 5.0 / 9.0),
        ]),
        UnitCategory(title: Loc.t("Açı"), symbol: "angle", units: [
            UnitDef(name: Loc.t("derece"), symbol: "°", factor: .pi / 180),
            UnitDef(name: Loc.t("radyan"), symbol: "rad", factor: 1),
            UnitDef(name: Loc.t("grad"), symbol: Loc.t("grad"), factor: .pi / 200),
            UnitDef(name: Loc.t("dakika"), symbol: "'", factor: .pi / 10_800),
            UnitDef(name: Loc.t("tur"), symbol: Loc.t("tur"), factor: 2 * .pi),
        ]),
        UnitCategory(title: Loc.t("Debi"), symbol: "drop", units: [
            UnitDef(name: Loc.t("metreküp/saniye"), symbol: "m³/s", factor: 1),
            UnitDef(name: Loc.t("litre/saniye"), symbol: "L/s", factor: 1e-3),
            UnitDef(name: Loc.t("litre/dakika"), symbol: Loc.t("L/dk"), factor: 1.0 / 60_000),
            UnitDef(name: Loc.t("metreküp/saat"), symbol: "m³/h", factor: 1.0 / 3600),
            UnitDef(name: Loc.t("galon/dakika"), symbol: "gpm", factor: 6.30901964e-5),
        ]),
        UnitCategory(title: Loc.t("Yoğunluk"), symbol: "circle.grid.cross", units: [
            UnitDef(name: "kg/m³", symbol: "kg/m³", factor: 1),
            UnitDef(name: "g/cm³", symbol: "g/cm³", factor: 1000),
            UnitDef(name: "lb/ft³", symbol: "lb/ft³", factor: 16.01846337),
        ]),
    ] }
}

struct UnitConverterView: View {
    @ObservedObject var editor: EditorModel
    @State private var category = UnitCategory.all[0]
    @State private var from = UnitCategory.all[0].units[2]
    @State private var to = UnitCategory.all[0].units[1]
    @State private var input = "1"

    var body: some View {
        Form {
            Section {
                Picker(Loc.t("Büyüklük"), selection: $category) {
                    ForEach(UnitCategory.all) { c in
                        Label(c.title, systemImage: c.symbol).tag(c)
                    }
                }
                .onChange(of: category) { _, c in
                    from = c.units[0]
                    to = c.units[min(1, c.units.count - 1)]
                }
                HStack {
                    TextField(Loc.t("Değer"), text: $input)
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                    Picker(Loc.t("Birim"), selection: $from) {
                        ForEach(category.units, id: \.self) { u in
                            Text("\(u.symbol) · \(u.name)").tag(u)
                        }
                    }
                    .labelsHidden()
                }
                HStack {
                    Button {
                        let f = from
                        from = to
                        to = f
                    } label: {
                        Label(Loc.t("Yer değiştir"), systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Picker(Loc.t("Hedef"), selection: $to) {
                        ForEach(category.units, id: \.self) { u in
                            Text("\(u.symbol) · \(u.name)").tag(u)
                        }
                    }
                    .labelsHidden()
                }
            }
            Section {
                if let line = resultLine {
                    Text(line)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    HStack {
                        Spacer()
                        WriteButton { editor.writeAtViewCenter(line) }
                    }
                } else {
                    Text(Loc.t("Bir sayı yaz (ondalık için virgül kullanabilirsin)."))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(Loc.t("Sonuç"))
            }
            Section {
                ForEach(category.units.filter { $0 != from }, id: \.self) { u in
                    if let v = value, let out = convert(v, from: from, to: u) {
                        HStack {
                            Text(u.name)
                            Spacer()
                            Text("\(MathFormat.decimal(out)) \(u.symbol)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(Loc.t("Diğer birimlerde"))
            }
        }
    }

    private var value: Double? {
        // "1.250,5" (Turkish) and "1250.5" both work.
        let t = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "−", with: "-")
        let s = t.contains(",") ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : t
        return Double(s)
    }

    private var resultLine: String? {
        guard let v = value, let out = convert(v, from: from, to: to) else { return nil }
        return "\(MathFormat.decimal(v)) \(from.symbol) = \(MathFormat.decimal(out)) \(to.symbol)"
    }

    private func convert(_ v: Double, from a: UnitDef, to b: UnitDef) -> Double? {
        let base = v * a.factor + a.offset
        let out = (base - b.offset) / b.factor
        return out.isFinite ? MathEngine.tidy(out) : nil
    }
}

// MARK: - Constants and formulas

struct ReferenceItem: Identifiable {
    let title: String
    let text: String
    var id: String { title + text }
}

struct ReferenceSection: Identifiable {
    let title: String
    let items: [ReferenceItem]
    var id: String { title }

    // Only characters the page font can draw: Latin and Turkish letters, digits, superscripts,
    // · × ± √ π Δ Σ and the Greek letters α β γ δ ε η θ λ μ ρ σ τ φ ω Ω.
    static var all: [ReferenceSection] { [
        ReferenceSection(title: Loc.t("Fiziksel sabitler"), items: [
            ReferenceItem(title: Loc.t("Yerçekimi ivmesi"), text: "g = 9,80665 m/s²"),
            ReferenceItem(title: Loc.t("Işık hızı"), text: "c = 2,998 × 10⁸ m/s"),
            ReferenceItem(title: Loc.t("Evrensel çekim sabiti"), text: "G = 6,674 × 10⁻¹¹ N·m²/kg²"),
            ReferenceItem(title: Loc.t("Planck sabiti"), text: "h = 6,626 × 10⁻³⁴ J·s"),
            ReferenceItem(title: Loc.t("Boltzmann sabiti"), text: "k = 1,381 × 10⁻²³ J/K"),
            ReferenceItem(title: Loc.t("Avogadro sayısı"), text: "NA = 6,022 × 10²³ 1/mol"),
            ReferenceItem(title: Loc.t("Gaz sabiti"), text: "R = 8,314 J/(mol·K)"),
            ReferenceItem(title: Loc.t("Temel yük"), text: "e = 1,602 × 10⁻¹⁹ C"),
            ReferenceItem(title: Loc.t("Boşluğun geçirgenliği"), text: "ε0 = 8,854 × 10⁻¹² F/m"),
            ReferenceItem(title: Loc.t("Boşluğun manyetik geçirgenliği"), text: "μ0 = 4π × 10⁻⁷ H/m"),
            ReferenceItem(title: "Stefan-Boltzmann", text: "σ = 5,670 × 10⁻⁸ W/(m²·K⁴)"),
            ReferenceItem(title: Loc.t("Elektron kütlesi"), text: "me = 9,109 × 10⁻³¹ kg"),
            ReferenceItem(title: Loc.t("Standart atmosfer"), text: "p0 = 101325 Pa"),
        ]),
        ReferenceSection(title: Loc.t("Malzeme ve akışkan değerleri"), items: [
            ReferenceItem(title: Loc.t("Çelik elastisite modülü"), text: Loc.t("E çelik ≈ 200 GPa")),
            ReferenceItem(title: Loc.t("Alüminyum elastisite modülü"), text: Loc.t("E alüminyum ≈ 69 GPa")),
            ReferenceItem(title: Loc.t("Beton elastisite modülü"), text: Loc.t("E beton ≈ 30 GPa")),
            ReferenceItem(title: Loc.t("Çelik yoğunluğu"), text: Loc.t("ρ çelik ≈ 7850 kg/m³")),
            ReferenceItem(title: Loc.t("Suyun yoğunluğu (4 °C)"), text: Loc.t("ρ su = 1000 kg/m³")),
            ReferenceItem(title: Loc.t("Havanın yoğunluğu (15 °C)"), text: Loc.t("ρ hava = 1,225 kg/m³")),
            ReferenceItem(title: Loc.t("Suyun dinamik viskozitesi (20 °C)"), text: Loc.t("μ su ≈ 1,002 × 10⁻³ Pa·s")),
            ReferenceItem(title: Loc.t("Suyun özgül ısısı"), text: Loc.t("c su = 4186 J/(kg·K)")),
            ReferenceItem(title: Loc.t("Çelik Poisson oranı"), text: Loc.t("Poisson oranı (çelik) ≈ 0,3")),
        ]),
        ReferenceSection(title: Loc.t("Statik ve mukavemet"), items: [
            ReferenceItem(title: Loc.t("Normal gerilme"), text: "σ = F / A"),
            ReferenceItem(title: Loc.t("Kayma gerilmesi"), text: "τ = V / A"),
            ReferenceItem(title: Loc.t("Birim uzama"), text: "ε = ΔL / L0"),
            ReferenceItem(title: Loc.t("Hooke yasası"), text: "σ = E · ε"),
            ReferenceItem(title: Loc.t("Eksenel uzama"), text: "δ = F · L / (A · E)"),
            ReferenceItem(title: Loc.t("Eğilme gerilmesi"), text: "σ = M · y / I"),
            ReferenceItem(title: Loc.t("Burulma gerilmesi"), text: "τ = T · r / J"),
            ReferenceItem(title: Loc.t("Dikdörtgen kesit atalet momenti"), text: "I = b · h³ / 12"),
            ReferenceItem(title: Loc.t("Dairesel kesit atalet momenti"), text: "I = π · d⁴ / 64"),
            ReferenceItem(title: Loc.t("Dolu mil kutupsal atalet momenti"), text: "J = π · d⁴ / 32"),
            ReferenceItem(title: Loc.t("Euler burkulma yükü"), text: "Pkr = π² · E · I / (K · L)²"),
            ReferenceItem(title: Loc.t("Basit kiriş, ortada tekil yük"), text: "Mmax = P · L / 4,  δmax = P · L³ / (48 · E · I)"),
            ReferenceItem(title: Loc.t("Basit kiriş, yayılı yük"), text: "Mmax = q · L² / 8,  δmax = 5 · q · L⁴ / (384 · E · I)"),
            ReferenceItem(title: Loc.t("Konsol, uçta tekil yük"), text: "Mmax = P · L,  δmax = P · L³ / (3 · E · I)"),
            ReferenceItem(title: Loc.t("Denge koşulları"), text: "ΣFx = 0,  ΣFy = 0,  ΣM = 0"),
        ]),
        ReferenceSection(title: Loc.t("Dinamik"), items: [
            ReferenceItem(title: Loc.t("Newton'un 2. yasası"), text: "ΣF = m · a"),
            ReferenceItem(title: Loc.t("Hız"), text: "v = v0 + a · t"),
            ReferenceItem(title: Loc.t("Konum"), text: "x = x0 + v0 · t + a · t² / 2"),
            ReferenceItem(title: Loc.t("Zamansız hız"), text: "v² = v0² + 2 · a · Δx"),
            ReferenceItem(title: Loc.t("İş"), text: "W = F · d · cos θ"),
            ReferenceItem(title: Loc.t("Kinetik enerji"), text: "Ek = m · v² / 2"),
            ReferenceItem(title: Loc.t("Potansiyel enerji"), text: "Ep = m · g · h"),
            ReferenceItem(title: Loc.t("Yay enerjisi"), text: "Ey = k · x² / 2"),
            ReferenceItem(title: Loc.t("Güç"), text: "P = W / t = F · v"),
            ReferenceItem(title: "Momentum", text: "p = m · v"),
            ReferenceItem(title: Loc.t("Açısal hız"), text: "ω = 2π · f = v / r"),
            ReferenceItem(title: Loc.t("Merkezcil ivme"), text: "a = v² / r = ω² · r"),
            ReferenceItem(title: Loc.t("Dönme hareketi"), text: "ΣM = I · α"),
            ReferenceItem(title: Loc.t("Dönme güç"), text: "P = T · ω"),
        ]),
        ReferenceSection(title: Loc.t("Akışkanlar ve ısı"), items: [
            ReferenceItem(title: Loc.t("Hidrostatik basınç"), text: "p = ρ · g · h"),
            ReferenceItem(title: Loc.t("Süreklilik"), text: "Q = A1 · v1 = A2 · v2"),
            ReferenceItem(title: "Bernoulli", text: Loc.t("p + ρ · v² / 2 + ρ · g · h = sabit")),
            ReferenceItem(title: Loc.t("Reynolds sayısı"), text: "Re = ρ · v · D / μ"),
            ReferenceItem(title: Loc.t("Kaldırma kuvveti"), text: "Fk = ρ · g · V"),
            ReferenceItem(title: Loc.t("İdeal gaz"), text: "p · V = n · R · T"),
            ReferenceItem(title: Loc.t("Isı"), text: "Q = m · c · ΔT"),
            ReferenceItem(title: Loc.t("Termodinamiğin 1. yasası"), text: "ΔU = Q - W"),
            ReferenceItem(title: Loc.t("Carnot verimi"), text: "η = 1 - Tc / Th"),
            ReferenceItem(title: Loc.t("Isı iletimi (Fourier)"), text: "q = k · A · ΔT / L"),
        ]),
        ReferenceSection(title: Loc.t("Elektrik"), items: [
            ReferenceItem(title: Loc.t("Ohm yasası"), text: "V = I · R"),
            ReferenceItem(title: Loc.t("Elektrik gücü"), text: "P = V · I = I² · R"),
            ReferenceItem(title: Loc.t("Seri direnç"), text: "R = R1 + R2 + R3"),
            ReferenceItem(title: Loc.t("Paralel direnç"), text: "1/R = 1/R1 + 1/R2"),
            ReferenceItem(title: Loc.t("Kondansatör"), text: "Q = C · V,  E = C · V² / 2"),
            ReferenceItem(title: Loc.t("Bobin reaktansı"), text: "XL = 2π · f · L"),
            ReferenceItem(title: Loc.t("Kondansatör reaktansı"), text: "XC = 1 / (2π · f · C)"),
            ReferenceItem(title: Loc.t("Üç fazlı güç"), text: "P = √3 · V · I · cos φ"),
        ]),
        ReferenceSection(title: Loc.t("Matematik"), items: [
            ReferenceItem(title: Loc.t("Pisagor"), text: "a² + b² = c²"),
            ReferenceItem(title: Loc.t("İkinci derece denklem"), text: "x = (-b ± √(b² - 4ac)) / 2a"),
            ReferenceItem(title: Loc.t("Diskriminant"), text: "Δ = b² - 4ac"),
            ReferenceItem(title: Loc.t("Trigonometri"), text: "sin²x + cos²x = 1"),
            ReferenceItem(title: Loc.t("Toplam formülü"), text: "sin(a ± b) = sin a · cos b ± cos a · sin b"),
            ReferenceItem(title: Loc.t("Kosinüs teoremi"), text: "c² = a² + b² - 2ab · cos θ"),
            ReferenceItem(title: Loc.t("Türev"), text: "d/dx xⁿ = n · xⁿ⁻¹"),
            ReferenceItem(title: Loc.t("İntegral"), text: "∫ xⁿ dx = xⁿ⁺¹ / (n + 1) + C"),
            ReferenceItem(title: Loc.t("Daire"), text: Loc.t("A = π · r²,  Ç = 2π · r")),
            ReferenceItem(title: Loc.t("Küre"), text: "V = 4 · π · r³ / 3,  A = 4 · π · r²"),
            ReferenceItem(title: Loc.t("Silindir"), text: "V = π · r² · h"),
            ReferenceItem(title: Loc.t("Sabitler"), text: "π ≈ 3,14159,  e ≈ 2,71828,  φ ≈ 1,61803"),
        ]),
    ] }
}

struct ReferenceView: View {
    @ObservedObject var editor: EditorModel
    @State private var query = ""

    var body: some View {
        List {
            TextField(Loc.t("Ara (ör. burulma, Reynolds, Ohm)"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        Button {
                            editor.writeAtViewCenter(item.text)
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.text)
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(.primary)
                                }
                                Spacer()
                                Image(systemName: "square.and.pencil")
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        .accessibilityHint(Loc.t("Sayfaya yazar"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var sections: [ReferenceSection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased(with: MathFormat.locale)
        guard !q.isEmpty else { return ReferenceSection.all }
        return ReferenceSection.all.compactMap { s in
            let items = s.items.filter {
                $0.title.lowercased(with: MathFormat.locale).contains(q) || $0.text.lowercased(with: MathFormat.locale).contains(q)
            }
            return items.isEmpty ? nil : ReferenceSection(title: s.title, items: items)
        }
    }
}

// MARK: - Plot

struct PlotView: View {
    @ObservedObject var editor: EditorModel
    let onDone: () -> Void
    @AppStorage("plot.expression") private var expression = "x^2 - 3x + 1"
    @AppStorage("plot.xMin") private var xMin = "-4"
    @AppStorage("plot.xMax") private var xMax = "4"
    @State private var message: String?

    private let examples = ["sin(x)", "x^2", "x^3 - 3x", "1/x", "e^(-x) · cos(3x)", "√x", "ln(x)", "abs(x)"]

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("f(x) =")
                        .foregroundStyle(.secondary)
                    TextField("x^2 - 3x + 1", text: $expression)
                        .font(.title3.monospacedDigit())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                HStack {
                    Text(Loc.t("x en az"))
                    TextField("-4", text: $xMin)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                    Divider()
                    Text(Loc.t("en çok"))
                    TextField("4", text: $xMax)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                }
                .monospacedDigit()
            } footer: {
                Text(Loc.t("Grafik eksenleri ve ölçekleriyle, ekranın ortasına son seçtiğin kalemle çizilir. Trigonometrik fonksiyonlar radyan kullanır."))
            }
            Section(Loc.t("Örnekler")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(examples, id: \.self) { e in
                            Button(e) { expression = e }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            Section {
                Button {
                    draw()
                } label: {
                    Label(Loc.t("Grafiği sayfaya çiz"), systemImage: "chart.xyaxis.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                if let message {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func number(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: ".")
        if t.lowercased().contains("pi") || t.contains("π") {
            return MathParser.parse(t).flatMap { $0.evaluate([:]) }
        }
        return Double(t)
    }

    private func draw() {
        guard let a = number(xMin), let b = number(xMax), a < b else {
            message = Loc.t("x aralığını kontrol et (en az, en çoktan küçük olmalı).")
            return
        }
        if let error = editor.plot(expression, xMin: a, xMax: b) {
            message = error
        } else {
            message = nil
            onDone()
        }
    }
}
