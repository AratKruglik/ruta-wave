import CryptoKit
import Foundation

enum SAPISIDHash {
    static func make(sapisid: String, timestamp: Int, origin: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data("\(timestamp) \(sapisid) \(origin)".utf8))
        return "\(timestamp)_" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
