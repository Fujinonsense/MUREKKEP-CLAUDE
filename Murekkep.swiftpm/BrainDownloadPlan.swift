import Foundation

/// The model's download worked out from what is on disk, so it goes on where it stopped after the
/// app was closed, the iPad slept or Wi-Fi went away (checked in tools/swiftcheck). Each file comes
/// into "<file>.part" and is moved into place once whole.
enum BrainDownloadPlan {
    struct File: Codable, Equatable {
        var path: String
        var size: Int64?
    }

    /// Bytes of one file on disk: the finished file and its part file, -1 when absent.
    struct OnDisk: Equatable {
        var whole: Int64
        var part: Int64
    }

    enum Step: Equatable {
        /// The file is in place.
        case done
        /// The part file is whole: it only has to be moved into place.
        case finish
        /// It has to be fetched from this byte on.
        case fetch(from: Int64)
    }

    static func step(_ file: File, _ disk: OnDisk) -> Step {
        if disk.whole >= 0, file.size.map({ disk.whole == $0 }) ?? true { return .done }
        let part = max(0, disk.part)
        if let size = file.size {
            if part == size { return .finish }
            if part > size { return .fetch(from: 0) }
        }
        return .fetch(from: part)
    }

    /// Bytes there (on disk and arriving) and in all, for the progress bar.
    static func progress(_ files: [File], disk: (String) -> OnDisk, inFlight: [String: Int64]) -> (done: Int64, total: Int64) {
        var done: Int64 = 0
        var total: Int64 = 0
        for file in files {
            let d = disk(file.path)
            let size = file.size ?? max(d.whole, 0)
            total += size
            switch step(file, d) {
            case .done, .finish:
                done += size
            case let .fetch(from):
                done += min(size, from + (inFlight[file.path] ?? 0))
            }
        }
        return (done, total)
    }

    enum Merge: Equatable {
        /// The whole file came (HTTP 200): it replaces the part file.
        case replace
        /// The rest of it came (HTTP 206 from where the part ends): it is added to the part file.
        case append
        /// Anything else is thrown away and fetched again.
        case discard
    }

    /// `received`: bytes of the finished download; `expected`: the file's size when known. The sizes
    /// decide first: a download resumed by iOS ends with a response whose Content-Range starts where
    /// it resumed, not where the part file ends.
    static func merge(status: Int, rangeStart: Int64?, partSize: Int64, received: Int64, expected: Int64?) -> Merge {
        guard status == 200 || status == 206 else { return .discard }
        let part = max(partSize, 0)
        if let expected {
            if received == expected { return .replace }
            return part + received == expected ? .append : .discard
        }
        if status == 200 { return .replace }
        return rangeStart == part ? .append : .discard
    }

    /// The first byte of a Content-Range header ("bytes 300-999/1000" is 300).
    static func rangeStart(_ header: String?) -> Int64? {
        guard let header, let r = header.range(of: #"bytes\s+\d+-"#, options: .regularExpression) else { return nil }
        return Int64(header[r].filter(\.isNumber))
    }
}
