import Foundation
import CryptoKit

/// Hilfsfunktionen für Sign in with Apple. Apple verlangt einen einmaligen Nonce:
/// Der App-Request sendet den SHA256-Hash, an Supabase wird der Klartext-Nonce übergeben.
enum AppleSignInSupport {
    /// Erzeugt einen zufälligen Nonce-String (Klartext), der lokal gemerkt wird.
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else {
                // Fallback, falls die sichere Quelle fehlschlägt.
                for _ in 0..<remaining {
                    result.append(charset[Int(arc4random_uniform(UInt32(charset.count)))])
                }
                return result
            }

            for random in randoms where remaining > 0 {
                if Int(random) < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }

        return result
    }

    /// SHA256-Hash des Nonce als Hex-String – wird im Apple-Request gesetzt.
    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
