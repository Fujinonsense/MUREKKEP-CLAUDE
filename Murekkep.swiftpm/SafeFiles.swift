import Foundation

// Files this build cannot read all of: kept aside before anything is written over them, or read
// one entry at a time. Foundation only (checked by tools/safefilescheck).

/// A copy of a file next to itself, made before the app goes on without it: "ink.mrk" becomes
/// "ink.bak-20261026-141503", dated when the file was last written, so a newer build or a repair
/// can still get at the bytes. The same file keeps the same name, so the copy is made once.
enum FileBackup {
    static let marker = ".bak-"

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// Where the copy of `url` goes, for a file last written at `date`.
    static func backupURL(for url: URL, date: Date) -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent(stem + marker + stamp.string(from: date))
    }

    /// Copies the file aside (unless the copy is there already) and returns the copy's URL; nil when
    /// there is nothing to copy or the copy could not be made.
    @discardableResult
    static func keep(_ url: URL) -> URL? {
        let fm = FileManager.default
        let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let copy = backupURL(for: url, date: modified ?? Date())
        if fm.fileExists(atPath: copy.path) { return copy }
        do {
            try fm.copyItem(at: url, to: copy)
            return copy
        } catch {
            return nil
        }
    }
}

/// A JSON list read one entry at a time, so an entry this build cannot read (written by a newer
/// Mürekkep, or damaged) loses neither the others nor itself: its JSON is kept as it is and
/// written back with the rest.
enum LenientList {
    struct Reading<T> {
        var items: [T]
        /// The entries that did not decode, as `JSONSerialization` values.
        var unreadable: [Any]
    }

    /// nil when `data` is not a JSON list at all (then there is nothing to keep).
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder) -> Reading<T>? {
        if let all = try? decoder.decode([T].self, from: data) {
            return Reading(items: all, unreadable: [])
        }
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
        var reading = Reading<T>(items: [], unreadable: [])
        for entry in list {
            // Only an object can be an entry; anything else is kept as it came.
            if let object = entry as? [String: Any],
               let one = try? JSONSerialization.data(withJSONObject: object),
               let item = try? decoder.decode(T.self, from: one) {
                reading.items.append(item)
            } else {
                reading.unreadable.append(entry)
            }
        }
        return reading
    }

    /// The list for the file: the items, then the unreadable entries as they were.
    static func encode<T: Encodable>(_ items: [T], unreadable: [Any], encoder: JSONEncoder) throws -> Data {
        let data = try encoder.encode(items)
        guard !unreadable.isEmpty, let list = try JSONSerialization.jsonObject(with: data) as? [Any] else { return data }
        return try JSONSerialization.data(withJSONObject: list + unreadable)
    }
}
