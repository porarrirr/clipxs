import CryptoKit
import Foundation

/// Shared content hashing so capture-time and edit-time hashes stay comparable
/// for dedup.
enum ContentHash {
    static func sha256(_ value: String) -> String {
        sha256(Data(value.utf8))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
