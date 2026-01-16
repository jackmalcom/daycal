import Foundation
import CryptoKit

extension Data {
    func sha256() -> Data {
        let digest = SHA256.hash(data: self)
        return Data(digest)
    }

    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
