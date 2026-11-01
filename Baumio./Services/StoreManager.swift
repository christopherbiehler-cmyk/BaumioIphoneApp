import Foundation
import StoreKit

/// Verwaltet das Pro-Abo über StoreKit 2 (In-App-Käufe).
/// Apple verlangt, dass digitale Abos in der App ausschließlich über In-App-Käufe laufen.
@MainActor
@Observable
final class StoreManager {
    /// Produkt-ID des Monats-Abos. Muss exakt mit App Store Connect / der .storekit-Datei übereinstimmen.
    static let proProductID = "de.baumio.pro.monthly.3"

    private(set) var products: [Product] = []
    private(set) var isSubscribed = false
    private(set) var isPurchasing = false
    private(set) var isLoadingProducts = false
    var purchaseError: String?
    /// Neutrale Rückmeldung (z. B. „Abo wiederhergestellt“, „Kauf wartet auf Genehmigung“).
    var infoMessage: String?

    /// Supabase-User-ID des angemeldeten Kontos. Ein Abo zählt nur für das Konto, mit dem es gekauft wurde
    /// (`appAccountToken`). Ältere Käufe ohne Token bleiben für alle Konten gültig.
    var accountToken: UUID?

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

    /// Länge des kostenlosen Testzeitraums in Tagen – direkt aus dem StoreKit-Produkt.
    var trialDays: Int? {
        guard let offer = proProduct?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }

    /// z. B. „14 Tage kostenlos testen“ (Fallback, solange das Produkt nicht geladen ist).
    var trialTitle: String {
        if let days = trialDays { return "\(days) Tage kostenlos testen" }
        return "Kostenlos testen"
    }

    var trialBadge: String {
        if let days = trialDays { return "\(days) Tage gratis" }
        return "Gratis testen"
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
        purchaseError = nil
        infoMessage = nil
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
                switch verification {
                case .unverified(let tx, _):
                    await tx.finish()
                    purchaseError = StoreError.failedVerification.localizedDescription
                    return false
                case .verified(let tx):
                    await tx.finish()
                    await refreshSubscriptionStatus()
                    return isSubscribed
                }
            case .pending:
                infoMessage = "Der Kauf wartet noch auf Genehmigung (z. B. Familienfreigabe). Pro wird nach der Freigabe automatisch aktiviert."
                return false
            case .userCancelled:
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
        purchaseError = nil
        infoMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = error.localizedDescription
            return
        }
        await refreshSubscriptionStatus()
        infoMessage = isSubscribed ? "Dein Abo wurde wiederhergestellt." : "Es wurden keine aktiven Käufe für dieses Konto gefunden."
    }

    /// Gibt den JWS-String der aktuellen Pro-Transaktion zurück (für Trial-Erkennung in der Edge Function).
    func currentTransactionJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil,
               belongsToCurrentAccount(transaction) {
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
            guard belongsToCurrentAccount(transaction) else { continue }
            if let expiration = transaction.expirationDate {
                if expiration > Date() { active = true }
            } else {
                active = true
            }
        }
        isSubscribed = active
    }

    func reset() {
        isSubscribed = false
        accountToken = nil
        infoMessage = nil
        purchaseError = nil
    }

    /// Ohne angemeldetes Konto (Demo-Modus) zählt jede Transaktion; sonst nur Käufe dieses Kontos oder ältere ohne Token.
    private func belongsToCurrentAccount(_ transaction: Transaction) -> Bool {
        guard let accountToken else { return true }
        guard let owner = transaction.appAccountToken else { return true }
        return owner == accountToken
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
