import Foundation

/// One recorded take of a lecture: when it started (seconds since the reference date, the same clock
/// as a stroke's birth) and how long it ran. The audio is "rec-<id>.m4a" in the note's folder.
struct Recording: Codable, Identifiable, Equatable {
    var id: UUID
    var start: Double
    var duration: Double
    var title: String
}

/// Which ink a playing take hides, and where tapping ink plays from (twin of
/// tests/ports/recording_sync.py).
///
/// A stroke belongs to a take when its pencil lifted between the take's start and half a second after
/// its end. While that take plays, its strokes whose moment is still ahead of the playhead are hidden,
/// so the page fills in as the lecture goes on; everything else shows. Tapping a stroke of a take plays
/// from 1.5 s before its moment (the pencil lifts at the end of the line, and the words that went with
/// it came a little before).
enum RecordingSync {
    static let grace = 0.5
    static let leadIn = 1.5

    private static func contains(_ r: Recording, _ birth: Double) -> Bool {
        birth >= r.start && birth <= r.start + r.duration + grace
    }

    /// Ids of the strokes (id, birth) still ahead of `time` seconds into `recording`.
    static func hidden(births: [(id: Int, birth: Double)], recording: Recording, time: Double) -> Set<Int> {
        var out = Set<Int>()
        for s in births where contains(recording, s.birth) && s.birth - recording.start > time {
            out.insert(s.id)
        }
        return out
    }

    /// The take a stroke was written in and the seconds into it to play from, or nil.
    static func seek(birth: Double, recordings: [Recording]) -> (id: UUID, time: Double)? {
        for r in recordings where contains(r, birth) {
            return (r.id, max(0, min(birth - r.start, r.duration) - leadIn))
        }
        return nil
    }
}
