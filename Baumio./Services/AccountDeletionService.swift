import Foundation

/// Konfiguration des Web-Endpunkts zum Löschen des Kontos – einzige Stelle, an der die URL steht.
enum AccountDeletionConfig {
    static let endpoint = URL(string: "https://baumio.eu/api/account/delete")!
}

enum AccountDeletionError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Das Löschen hat nicht geklappt. Bitte versuche es später erneut oder schreibe uns."
    }
}

/// Ruft den Web-Endpunkt auf, der Storage-Dateien löscht, ein Stripe-Abo kündigt und danach den Account entfernt.
enum AccountDeletionService {
    static func deleteAccount(accessToken: String, session: URLSession = .shared) async throws {
        var request = URLRequest(url: AccountDeletionConfig.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120   // Der Endpunkt löscht zuerst alle Dateien
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let status: Int
        do {
            let (_, response) = try await session.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            ErrorLogger.report(error, context: "account.delete", url: ErrorLogger.safeURL(AccountDeletionConfig.endpoint))
            throw AccountDeletionError.failed
        }

        guard status == 200 else {
            ErrorLogger.report(.error, context: "account.delete", message: "Löschen fehlgeschlagen: HTTP \(status)", url: ErrorLogger.safeURL(AccountDeletionConfig.endpoint))
            throw AccountDeletionError.failed
        }
    }
}
