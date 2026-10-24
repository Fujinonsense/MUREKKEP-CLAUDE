import SwiftUI

/// The lecture player over the bottom of the page: play, a scrubber and the time; the rest (other
/// takes, speed, ink that follows the sound, delete) waits in one menu. Recording is the mic button in
/// the top bar: one tap starts, one tap stops. While the player is open, a finger tap on ink plays from
/// the moment it was written.
struct LectureBar: View {
    @ObservedObject var lecture: LectureAudio
    /// Off while the page takes typing (the Aa tool, the text pen): space and the arrows write there.
    var keyboard = true
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let take = lecture.current {
                Button {
                    lecture.togglePlay()
                } label: {
                    Image(systemName: lecture.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(keyboard ? KeyboardShortcut(.space, modifiers: []) : nil)
                .accessibilityLabel(lecture.isPlaying ? Loc.t("Duraklat") : Loc.t("Oynat"))
                Slider(value: Binding(get: { lecture.time }, set: { lecture.seek(to: $0) }), in: 0...max(take.duration, 0.1))
                    .tint(Theme.ink)
                    .frame(minWidth: 160, maxWidth: 340)
                Text("\(Self.clock(lecture.time)) / \(Self.clock(take.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                if lecture.rate != 1 {
                    Text(Self.rateText(lecture.rate))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .fixedSize()
                }
                if lecture.volume < 1 {
                    Label(Loc.t("Ses %{0}", "\(Int((lecture.volume * 100).rounded()))"),
                          systemImage: lecture.volume == 0 ? "speaker.slash.fill" : "speaker.wave.1.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Loc.t("%{0}", "\(Int((lecture.volume * 100).rounded()))"))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                options(take)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Loc.t("Oynatıcıyı kapat"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .glassCapsule()
        .background {
            // The keyboard case: space plays and pauses (the play button), the arrows jump and set the volume.
            if lecture.current != nil, keyboard {
                Group {
                    Button(Loc.t("5 sn geri")) { lecture.skip(by: -5) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button(Loc.t("5 sn ileri")) { lecture.skip(by: 5) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    Button(Loc.t("Sesi aç")) { lecture.nudgeVolume(by: 0.1) }
                        .keyboardShortcut(.upArrow, modifiers: [])
                    Button(Loc.t("Sesi kıs")) { lecture.nudgeVolume(by: -0.1) }
                        .keyboardShortcut(.downArrow, modifiers: [])
                }
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func options(_ take: Recording) -> some View {
        Menu {
            if lecture.takes.count > 1 {
                Section(Loc.t("Kayıtlar")) {
                    ForEach(lecture.takes) { t in
                        Button {
                            lecture.select(t)
                        } label: {
                            Label("\(t.title) · \(Self.clock(t.duration))", systemImage: t.id == take.id ? "checkmark" : "waveform")
                        }
                    }
                }
            }
            Picker(Loc.t("Oynatma hızı"), selection: $lecture.rate) {
                ForEach([Float(1), 1.25, 1.5, 2], id: \.self) { r in
                    Text(Self.rateText(r)).tag(r)
                }
            }
            .pickerStyle(.menu)
            Toggle(Loc.t("Mürekkep sesle birlikte gelsin"), isOn: $lecture.replayInk)
            Divider()
            Button(role: .destructive) {
                lecture.delete(take)
            } label: {
                Label(Loc.t("Bu kaydı sil"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Loc.t("Kayıt seçenekleri"))
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    private static func rateText(_ r: Float) -> String {
        r == r.rounded() ? "\(Int(r))×" : String(format: "%.2g×", r)
    }
}
