import Foundation

/// Which addresses to try when looking for the user's computer running Ollama or LM Studio on the
/// same Wi-Fi: the iPad's own /24 (a wider network is narrowed to the /24 around the iPad, so a
/// search takes seconds), without the iPad itself, nearest addresses first.
enum LocalServerFinder {
    /// Ollama and LM Studio's default ports.
    static let ports = [11434, 1234]

    private static func parse(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return parts.reduce(0) { $0 << 8 | $1 }
    }

    private static func format(_ v: UInt32) -> String {
        "\(v >> 24 & 255).\(v >> 16 & 255).\(v >> 8 & 255).\(v & 255)"
    }

    static func candidates(ip: String, mask: String) -> [String] {
        guard let address = parse(ip), var netmask = parse(mask) else { return [] }
        // Wider than a /24: only the /24 the iPad is in.
        netmask = max(netmask, 0xFFFF_FF00)
        let network = address & netmask
        let broadcast = network | ~netmask
        guard broadcast > network + 1 else { return [] }
        let hosts = (network + 1)..<broadcast
        return hosts.filter { $0 != address }
            .sorted { a, b in
                let da = a > address ? a - address : address - a
                let db = b > address ? b - address : address - b
                return da != db ? da < db : a < b
            }
            .map(format)
    }
}
