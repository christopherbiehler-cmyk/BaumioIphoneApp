import Foundation
import Network

/// Schlanker, threadsicherer Fehler-Logger. Schreibt technische Fehlerdaten per INSERT in `public.error_logs`.
/// Fire-and-forget: wirft nie, blockiert nie und loggt sich bei eigenem Scheitern nicht selbst erneut.
actor ErrorLogger {
    static let shared = ErrorLogger()

    enum Level: String, Sendable {
        case error, warn, info
    }

    private struct Entry: Encodable, Sendable {
        let level: String
        let context: String
        let message: String
        let details: String?
        var userID: String?
        let platform: String
        let appVersion: String
        let url: String?

        enum CodingKeys: String, CodingKey {
            case level, context, message, details
            case userID = "user_id"
            case platform
            case appVersion = "app_version"
            case url
        }
    }

    private enum SendResult {
        case sent
        case rejected   // Server lehnt ab → verwerfen
        case offline    // Netzwerkproblem → später erneut versuchen
    }

    private static let maxBuffered = 50
    private static let maxPerMinute = 20
    private static let dedupeWindow: TimeInterval = 60

    private var userID: String?
    private var accessToken: String?
    private var buffer: [Entry] = []
    private var recentKeys: [String: Date] = [:]
    private var sentTimes: [Date] = []
    private var isFlushing = false
    private var retryTask: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private init() {
        // Bei Wiederverbindung gepufferte Einträge nachsenden.
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { await self?.flush() }
        }
        monitor.start(queue: DispatchQueue(label: "eu.baumio.errorlogger.path"))
    }

    // MARK: - Sitzung

    func setSession(userID: UUID?, accessToken: String?) {
        self.userID = userID?.uuidString.lowercased()
        self.accessToken = accessToken
    }

    func clearSession() {
        userID = nil
        accessToken = nil
    }

    // MARK: - Logging

    func log(_ level: Level, context: String, message: String, details: String? = nil, url: String? = nil) {
        let cleanContext = Self.clean(context, limit: 200)
        let cleanMessage = Self.clean(message, limit: 2000)
        guard !cleanContext.isEmpty, !cleanMessage.isEmpty else { return }

        // Identische Meldungen innerhalb von 60 s nur einmal senden.
        let now = Date()
        recentKeys = recentKeys.filter { now.timeIntervalSince($0.value) < Self.dedupeWindow }
        let key = cleanContext + "|" + cleanMessage
        guard recentKeys[key] == nil else { return }
        recentKeys[key] = now

        let entry = Entry(
            level: level.rawValue,
            context: cleanContext,
            message: cleanMessage,
            details: details.map { Self.clean($0, limit: 10_000) },
            userID: userID,
            platform: "ios",
            appVersion: Self.appVersion,
            url: url.map { Self.clean($0, limit: 2000) }
        )
        if buffer.count >= Self.maxBuffered { buffer.removeFirst() }
        buffer.append(entry)
        Task { await flush() }
    }

    /// Bequemer Einstieg aus beliebigem Kontext (nicht-async). Filtert reine Abbrüche und Offline-Fehler heraus.
    nonisolated static func report(_ error: Error, context: String, level: Level = .error, url: String? = nil) {
        guard shouldLog(error) else { return }
        let ns = error as NSError
        let message = "\(ns.domain) \(ns.code): \(error.localizedDescription)"
        let details = error is DecodingError ? String(describing: error) : nil
        Task { await shared.log(level, context: context, message: message, details: details, url: url) }
    }

    nonisolated static func report(_ level: Level, context: String, message: String, details: String? = nil, url: String? = nil) {
        Task { await shared.log(level, context: context, message: message, details: details, url: url) }
    }

    nonisolated static func shouldLog(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled && urlError.code != .notConnectedToInternet
        }
        if let supabaseError = error as? SupabaseError {
            switch supabaseError {
            case .unauthorized, .missingSession, .missingProject, .emailConfirmationRequired, .notConfigured:
                return false
            default:
                return true
            }
        }
        return true
    }

    // MARK: - Senden

    private func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !buffer.isEmpty {
            let now = Date()
            sentTimes.removeAll { now.timeIntervalSince($0) >= 60 }
            if sentTimes.count >= Self.maxPerMinute, let oldest = sentTimes.first {
                scheduleRetry(after: 60 - now.timeIntervalSince(oldest) + 1)
                return
            }
            // Eintrag vor dem Senden entnehmen, damit paralleles Puffern den Index nicht verschiebt.
            let entry = buffer.removeFirst()
            switch await send(entry) {
            case .sent, .rejected:
                sentTimes.append(Date())
            case .offline:
                if buffer.count < Self.maxBuffered { buffer.insert(entry, at: 0) }
                return
            }
        }
    }

    private func scheduleRetry(after delay: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 1)))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func send(_ entry: Entry) async -> SendResult {
        guard let config = SupabaseConfig.load(), config.isConfigured else { return .rejected }

        // user_id muss die eigene ID sein – bei Nutzerwechsel anonym senden.
        var row = entry
        if row.userID != userID { row.userID = nil }

        if let accessToken, row.userID != nil {
            let result = await post(row, config: config, bearer: accessToken)
            if case .rejected = result {
                // Evtl. abgelaufenes Token → anonym ohne user_id erneut versuchen.
                row.userID = nil
                return await post(row, config: config, bearer: config.anonKey)
            }
            return result
        }
        row.userID = nil
        return await post(row, config: config, bearer: config.anonKey)
    }

    private func post(_ row: Entry, config: SupabaseConfig, bearer: String) async -> SendResult {
        guard let body = try? JSONEncoder().encode(row) else { return .rejected }
        var request = URLRequest(url: config.projectURL.appending(path: "rest/v1/error_logs"))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return .rejected }
            return 200..<300 ~= status ? .sent : .rejected
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                 .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            default:
                return .rejected
            }
        } catch {
            return .rejected
        }
    }

    // MARK: - Bereinigung

    nonisolated static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String("\(short) (\(build))".prefix(50))
    }

    /// Entfernt personenbezogene Daten und Geheimnisse und kürzt auf das Limit.
    nonisolated static func clean(_ text: String, limit: Int) -> String {
        var result = text
        let rules: [(pattern: String, replacement: String)] = [
            (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "[email]"),
            (#"(?i)bearer\s+[A-Za-z0-9._~+/=\-]+"#, "Bearer [token]"),
            (#"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.?[A-Za-z0-9_\-]*"#, "[token]"),
            (#"(?i)(password|passwort|passwd|token|apikey|api_key|secret)(["'\s:=]+)[^\s,;"']+"#, "$1$2[redacted]"),
            (#"[A-Za-z0-9_+/=\-]{40,}"#, "[token]")
        ]
        for rule in rules {
            result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement, options: .regularExpression)
        }
        return String(result.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    /// URL ohne Query; UUIDs werden maskiert, Storage-Pfade auf den Bucket gekürzt.
    nonisolated static func safeURL(_ url: URL?) -> String? {
        guard let url, let host = url.host() else { return nil }
        var components = url.pathComponents.filter { $0 != "/" }
        if components.first == "storage" { components = Array(components.prefix(4)) }
        let path = components.joined(separator: "/")
            .replacingOccurrences(of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#, with: ":id", options: .regularExpression)
        return "https://\(host)/\(path)"
    }
}
