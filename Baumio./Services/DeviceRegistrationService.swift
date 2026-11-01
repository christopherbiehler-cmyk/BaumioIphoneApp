import Foundation
import Security
import UIKit

struct DeviceRegistrationResult: Decodable, Sendable {
    let activeDevices: Int?
    let limit: Int?
    let overLimit: Bool?

    enum CodingKeys: String, CodingKey {
        case activeDevices = "active_devices"
        case limit
        case overLimit = "over_limit"
    }
}

/// Meldet die Installation per RPC `register_device` an (Plattform- und Geräte-Tracking).
/// Läuft komplett im Hintergrund; Fehler werden nur über den ErrorLogger gemeldet.
actor DeviceRegistrationService {
    static let shared = DeviceRegistrationService()

    private static let keychainService = "eu.baumio.app"
    private static let keychainAccount = "device.id"
    private static let lastSuccessKey = "deviceRegistration.lastSuccess"
    private static let minInterval: TimeInterval = 6 * 60 * 60

    private var isRegistering = false

    private init() {}

    /// Registriert das Gerät; ohne `force` höchstens alle 6 Stunden.
    func register(accessToken: String, force: Bool) async {
        guard !isRegistering else { return }
        let supabase = await MainActor.run { SupabaseService() }
        guard await supabase.isConfigured else { return }
        if !force,
           let last = UserDefaults.standard.object(forKey: Self.lastSuccessKey) as? Date,
           Date().timeIntervalSince(last) < Self.minInterval {
            return
        }
        isRegistering = true
        defer { isRegistering = false }

        let deviceID = Self.deviceID()
        let label = await Self.deviceLabel()
        do {
            let result = try await supabase.registerDevice(deviceID: deviceID, label: label, accessToken: accessToken)
            UserDefaults.standard.set(Date(), forKey: Self.lastSuccessKey)
            if result.overLimit == true {
                await ErrorLogger.shared.log(
                    .info,
                    context: "device.over_limit",
                    message: "Geräte-Limit überschritten: \(result.activeDevices ?? -1) von \(result.limit ?? -1)"
                )
            }
        } catch {
            // Fehler wurden bereits im Service-Layer als warn geloggt – Registrierung darf die App nie stören.
        }
    }

    /// Bei Logout: Zeitstempel zurücksetzen, damit der nächste Login sofort registriert.
    func resetThrottle() {
        UserDefaults.standard.removeObject(forKey: Self.lastSuccessKey)
    }

    /// Bei Kontolöschung: auch die Geräte-ID entfernen.
    func wipe() {
        resetThrottle()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Geräte-ID & Label

    /// App-eigene Geräte-ID, nur in diesem Gerät im Keychain (nicht iCloud-synchronisiert).
    private static func deviceID() -> String {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let id = String(data: data, encoding: .utf8), id.count >= 8 {
            return id
        }

        let id = UUID().uuidString.lowercased()
        var attributes = base
        attributes[kSecValueData as String] = Data(id.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        SecItemDelete(base as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
        return id
    }

    /// Label ohne persönliche Daten, z. B. „iPhone · iOS 18.2".
    @MainActor
    private static func deviceLabel() -> String {
        "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
    }
}
