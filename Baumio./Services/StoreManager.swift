import Foundation
import StoreKit

/// Verwaltet das Pro-Abo über StoreKit 2 (In-App-Käufe).
/// Apple verlangt, dass digitale Abos in der App ausschließlich über In-App-Käufe laufen.
@MainActor
@Observable
final class StoreManager {
    /// Produkt-ID des Monats-Abos. Muss exakt mit App Store Connect / der .storekit-Datei übereinstimmen.
    static let proProductID = "de.baumio.pro.monthly"

    private(set) var products: [Product] = []
    private(set) var isSubscribed = false
    private(set) var isPurchasing = false
    private(set) var isLoadingProducts = false
    var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactionUpdates()
        Task {
            await loadProducts()
            await refreshSubscriptionStatus()
        }
    }

    var proProduct: Product? {
        products.first { $0.id == Self.proProductID }
    }

    /// Anzeigepreis des Abos, z. B. "8,99 €". Fällt auf den Platzhalter zurück, wenn das Produkt noch nicht geladen ist.
    var proDisplayPrice: String {
        proProduct?.displayPrice ?? "8,99 €"
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: [Self.proProductID])
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// Startet den Kauf des Pro-Abos. `appAccountToken` (Supabase-User-ID) wird mit der
    /// Transaktion verknüpft, damit die Server-Benachrichtigung den Kauf dem Nutzer zuordnen kann.
    @discardableResult
    func purchasePro(appAccountToken: UUID? = nil) async -> Bool {
        if proProduct == nil {
            await loadProducts()
        }
        guard let product = proProduct else {
            purchaseError = "Das Abo ist aktuell nicht verfügbar. Bitte versuche es später erneut."
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            var options: Set<Product.PurchaseOption> = []
            if let appAccountToken {
                options.insert(.appAccountToken(appAccountToken))
            }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshSubscriptionStatus()
                return isSubscribed
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    /// Stellt frühere Käufe wieder her (z. B. nach Neuinstallation oder Gerätewechsel).
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = error.localizedDescription
        }
        await refreshSubscriptionStatus()
    }

    /// Gibt den JWS-String der aktuellen Pro-Transaktion zurück (für Trial-Erkennung in der Edge Function).
    func currentTransactionJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID {
                return result.jwsRepresentation
            }
        }
        return nil
    }

    /// Prüft die aktuell gültigen Berechtigungen und setzt `isSubscribed`.
    func refreshSubscriptionStatus() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard transaction.productID == Self.proProductID, transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate {
                if expiration > Date() { active = true }
            } else {
                active = true
            }
        }
        isSubscribed = active
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshSubscriptionStatus()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: LocalizedError {
        case failedVerification

        var errorDescription: String? {
            switch self {
            case .failedVerification: "Der Kauf konnte nicht verifiziert werden."
            }
        }
    }
}
