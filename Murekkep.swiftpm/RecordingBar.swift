import SwiftUI

/// The lecture bar over the bottom of the page: record and stop, then the takes with play, a
/// scrubber, speed and "ink follows the sound". While it is open, a finger tap on ink plays from the
/// moment it was written.
struct LectureBar: View {
    @ObservedObject var lecture: LectureAudio
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            recordButton
            if lecture.isRecording {
                recordingStatus
            } else if let take = lecture.current {
                player(take)
            } else {
                Text(Loc.t("Dersi kaydet: yazdıkların sesle eşleşir; sonra mürekkebe dokununca o ana gidersin."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Loc.t("Kayıt çubuğunu kapat"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassCapsule()
        .alert(Loc.t("Ders kaydı"), isPresented: Binding(get: { lecture.message != nil }, set: { if !$0 { lecture.message = nil } })) {
            Button(Loc.t("Tamam"), role: .cancel) { lecture.message = nil }
        } message: {
            Text(lecture.message ?? "")
        }
    }

    private var recordButton: some View {
        Button {
            lecture.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.red.opacity(0.85), lineWidth: 2)
                    .frame(width: 34, height: 34)
                if lecture.isRecording {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red)
                        .frame(width: 13, height: 13)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lecture.isRecording ? Loc.t("Kaydı durdur") : Loc.t("Kaydetmeye başla"))
    }

    private var recordingStatus: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.6)) { context in
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(Int(context.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0 ? 1 : 0.35)
            }
            Text(Self.clock(lecture.elapsed))
                .font(.subheadline.monospacedDigit().weight(.semibold))
            Text(Loc.t("Kaydediliyor"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func player(_ take: Recording) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(lecture.takes) { t in
                    Button {
                        lecture.select(t)
                    } label: {
                        Label("\(t.title) · \(Self.clock(t.duration))", systemImage: t.id == take.id ? "checkmark" : "waveform")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    lecture.delete(take)
                } label: {
                    Label(Loc.t("Bu kaydı sil"), systemImage: "trash")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(take.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.primary)
            }
            Button {
                lecture.togglePlay()
            } label: {
                Image(systemName: lecture.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lecture.isPlaying ? Loc.t("Duraklat") : Loc.t("Oynat"))
            Slider(value: Binding(get: { lecture.time }, set: { lecture.seek(to: $0) }), in: 0...max(take.duration, 0.1))
                .tint(Theme.ink)
                .frame(minWidth: 140, maxWidth: 300)
            Text("\(Self.clock(lecture.time)) / \(Self.clock(take.duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            Menu {
                ForEach([Float(1), 1.25, 1.5, 2], id: \.self) { r in
                    Button {
                        lecture.rate = r
                    } label: {
                        if r == lecture.rate {
                            Label(Self.rateText(r), systemImage: "checkmark")
                        } else {
                            Text(Self.rateText(r))
                        }
                    }
                }
            } label: {
                Text(Self.rateText(lecture.rate))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .accessibilityLabel(Loc.t("Oynatma hızı"))
            Button {
                lecture.replayInk.toggle()
            } label: {
                Image(systemName: "pencil.and.scribble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(lecture.replayInk ? Theme.ink : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(lecture.replayInk ? Theme.ink.opacity(0.14) : Color.clear))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lecture.replayInk ? Loc.t("Mürekkep sesle birlikte görünüyor") : Loc.t("Mürekkebi sesle birlikte göster"))
        }
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    private static func rateText(_ r: Float) -> String {
        r == r.rounded() ? "\(Int(r))×" : String(format: "%.2g×", r)
    }
}
