import Foundation

struct SupabaseConfig {
    let projectURL: URL
    let anonKey: String

    var isConfigured: Bool {
        !anonKey.isEmpty && !anonKey.contains("DEIN_SUPABASE_ANON_KEY")
    }

    static func load() -> SupabaseConfig? {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        else { return nil }

        return SupabaseConfig(projectURL: url, anonKey: anonKey)
    }
}

struct SupabaseSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct SupabaseUser: Codable, Sendable {
    let id: UUID
    let email: String?
}

struct ProjectDetails: Sendable {
    let trades: [Trade]
    let schedule: [ScheduleItem]
    let tasks: [TaskItem]
    let materials: [MaterialItem]
    let costs: [CostItem]
    let offers: [OfferItem]
    let defects: [DefectItem]
    let diary: [DiaryEntry]
    let documents: [DocumentItem]
    let timeLogs: [TimeLogItem]
    let handoverItems: [HandoverItem]
    let funding: [FundingItem]
    let reviews: [ReviewItem]
}

enum AppError: LocalizedError {
    case validation(String)

    var errorDescription: String? {
        switch self { case .validation(let msg): msg }
    }
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidResponse
    case missingSession
    case missingProject
    case requestFailed(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Supabase ist noch nicht konfiguriert."
        case .invalidResponse: "Die Antwort von Supabase konnte nicht verarbeitet werden."
        case .missingSession: "Du bist nicht angemeldet. Bitte logge dich erneut ein."
        case .missingProject: "Bitte lege zuerst ein Projekt an oder wähle ein Projekt aus."
        case .requestFailed(let message): message
        case .unauthorized: "Deine Sitzung ist abgelaufen. Bitte logge dich erneut ein."
        }
    }
}

enum DocumentScanError: LocalizedError {
    case proRequired
    case trialLimitReached
    case wrongDocumentType
    case fileTooLarge
    case networkError(Int)

    var errorDescription: String? {
        switch self {
        case .proRequired: "Rechnungsscan ist eine Pro-Funktion. Starte deinen kostenlosen Testzeitraum."
        case .trialLimitReached: "Du hast deinen Gratis-Scan im Testzeitraum verwendet. Upgrade auf Baumio Pro für unbegrenzte Scans."
        case .wrongDocumentType: "Das Bild konnte nicht als Rechnung oder Angebot erkannt werden. Bitte ein klares Foto verwenden."
        case .fileTooLarge: "Das Bild ist zu groß. Bitte ein kleineres Foto verwenden (max. 4 MB)."
        case .networkError(let code): "Verbindungsfehler (HTTP \(code)). Bitte erneut versuchen."
        }
    }
}

struct RechnungScanResult {
    var betrag: Decimal
    var datum: Date?
    var faelligAm: Date?
    var firma: String
    var rechnungsnummer: String
    var gewerk: String
    var arbeitskosten: Decimal
    var materialkosten: Decimal
    var fahrkosten: Decimal
}

struct AngebotScanResult {
    var betrag: Decimal
    var gueltigBis: Date?
    var firma: String
    var angebotsnummer: String
    var leistung: String
    var gewerk: String
}

struct VisitenkarteScanResult {
    var name: String
    var company: String
    var tradeType: String
    var address: String
    var phone: String
    var email: String
}

// Kodiert/dekodiert Kontaktdaten (Adresse, Telefon, E-Mail) im notes-Feld einer Firma.
// Format: "#CONTACT:addr=<url-encoded>,phone=<url-encoded>,email=<url-encoded>"
enum TradeContactCoder {
    static func encode(address: String, phone: String, email: String, userNotes: String) -> String? {
        guard !address.isEmpty || !phone.isEmpty || !email.isEmpty else {
            let t = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        var parts: [String] = []
        if !address.isEmpty { parts.append("addr=\(urlEncode(address))") }
        if !phone.isEmpty   { parts.append("phone=\(urlEncode(phone))") }
        if !email.isEmpty   { parts.append("email=\(urlEncode(email))") }
        let header = "#CONTACT:" + parts.joined(separator: ",")
        let trimmed = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? header : header + "\n" + trimmed
    }

    static func decode(_ raw: String?) -> (address: String, phone: String, email: String, userNotes: String) {
        guard let raw, !raw.isEmpty else { return ("", "", "", "") }
        let lines = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, first.hasPrefix("#CONTACT:") else { return ("", "", "", raw) }
        let userNotes = lines.count > 1 ? lines[1] : ""
        var address = "", phone = "", email = ""
        for pair in first.dropFirst(9).split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let v = kv[1].removingPercentEncoding ?? kv[1]
            switch kv[0] {
            case "addr":  address = v
            case "phone": phone   = v
            case "email": email   = v
            default: break
            }
        }
        return (address, phone, email, userNotes)
    }

    private static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

struct SupabaseProject: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let name: String
    let status: String
    let budget: Decimal?
    let startDate: String?
    let endDate: String?
    let description: String?
    let progressByCosts: Int?
    let eigenkapital: Decimal?
    let kredit: Decimal?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case status
        case budget
        case startDate = "start_date"
        case endDate = "end_date"
        case description
        case progressByCosts = "progress_by_costs"
        case eigenkapital
        case kredit
    }

    var appProject: Project {
        Project(
            id: id,
            name: name,
            address: "",
            startDate: startDate.flatMap(Self.dateFormatter.date(from:)) ?? Date(),
            plannedEndDate: endDate.flatMap(Self.dateFormatter.date(from:)) ?? Date(),
            budget: budget ?? 0,
            description: description ?? "",
            status: ProjectStatus(supabaseValue: status),
            progress: 0,
            progressByCosts: progressByCosts ?? 0,
            eigenkapital: eigenkapital ?? 0,
            kredit: kredit ?? 0,
            ownerUserID: userID
        )
    }

    private static let dateFormatter = BaumioDateFormatter.shared
}

struct NewSupabaseProject: Encodable, Sendable {
    let userID: UUID
    let name: String
    let status: String
    let budget: Decimal
    let startDate: String?
    let endDate: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name
        case status
        case budget
        case startDate = "start_date"
        case endDate = "end_date"
        case description
    }
}

struct UpdateSupabaseProject: Encodable, Sendable {
    let name: String
    let status: String
    let budget: Decimal
    let startDate: String?
    let endDate: String?
    let description: String?
    let eigenkapital: Decimal
    let kredit: Decimal

    enum CodingKeys: String, CodingKey {
        case name, status, budget
        case startDate = "start_date"
        case endDate = "end_date"
        case description
        case eigenkapital
        case kredit
    }
}

struct NewSupabaseTrade: Encodable, Sendable {
    let projectID: UUID
    let name: String
    let company: String?
    let tradeType: String?
    let status: String
    let budget: Decimal?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case name
        case company
        case tradeType = "trade_type"
        case status
        case budget
        case notes
    }
}

struct NewSupabaseAppointment: Encodable, Sendable {
    let projectID: UUID
    let title: String
    let date: String
    let notes: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case title
        case date
        case notes
        case status
    }
}

struct NewSupabaseTodo: Encodable, Sendable {
    let projectID: UUID
    let userID: UUID
    let title: String
    let priority: String
    let dueDate: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case userID = "user_id"
        case title
        case priority
        case dueDate = "due_date"
    }
}

struct NewSupabaseCost: Encodable, Sendable {
    let projectID: UUID
    let description: String
    let category: String
    let costType: String
    let amount: Decimal
    let status: String
    let invoiceNumber: String?
    let notes: String?
    let invoiceDate: String?
    let dueDate: String?
    let laborAmount: Decimal?
    let machineAmount: Decimal?
    let travelAmount: Decimal?
    let warrantyEnd: String?
    let paymentDate: String?
    let supplier: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case description
        case category
        case costType = "cost_type"
        case amount
        case status
        case invoiceNumber = "invoice_number"
        case notes
        case invoiceDate = "invoice_date"
        case dueDate = "due_date"
        case laborAmount = "labor_amount"
        case machineAmount = "machine_amount"
        case travelAmount = "travel_amount"
        case warrantyEnd = "warranty_end"
        case paymentDate = "payment_date"
        case supplier
    }
}

struct NewSupabaseMaterial: Encodable, Sendable {
    let projectID: UUID
    let name: String
    let quantity: Decimal
    let unit: String
    let supplier: String?
    let articleNumber: String?
    let priceEstimated: Decimal?
    let status: String
    let orderDate: String?
    let deliveryDate: String?
    let notes: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case name
        case quantity
        case unit
        case supplier
        case articleNumber = "article_number"
        case priceEstimated = "price_estimated"
        case status
        case orderDate = "order_date"
        case deliveryDate = "delivery_date"
        case notes
        case url
    }
}

struct NewSupabaseQuote: Encodable, Sendable {
    let projectID: UUID
    let title: String
    let company: String?
    let amount: Decimal?
    let validUntil: String?
    let notes: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case title
        case company
        case amount
        case validUntil = "valid_until"
        case notes
        case scope
    }
}

struct NewSupabaseDefect: Encodable, Sendable {
    let projectID: UUID
    let description: String
    let severity: String?
    let importance: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case description
        case severity
        case importance
        case status
    }
}

struct NewSupabaseDiaryEntry: Encodable, Sendable {
    let projectID: UUID
    let date: String
    let weather: String?
    let temperature: Int?
    let notes: String
    let presentTrades: [String]

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case date
        case weather
        case temperature
        case notes
        case presentTrades = "present_trades"
    }
}

struct UpdateSupabaseStatus: Encodable, Sendable {
    let status: String
}

struct UpdateSupabaseTodoDone: Encodable, Sendable {
    let done: Bool
}

struct UpdateSupabaseQuoteSelection: Encodable, Sendable {
    let isSelected: Bool
    let quoteStatus: String

    enum CodingKeys: String, CodingKey {
        case isSelected = "is_selected"
        case quoteStatus = "quote_status"
    }
}

struct UpdateSupabaseTrade: Encodable, Sendable {
    let name: String
    let company: String?
    let tradeType: String?
    let budget: Decimal?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name
        case company
        case tradeType = "trade_type"
        case budget
        case notes
    }
}

struct UpdateSupabaseAppointment: Encodable, Sendable {
    let title: String
    let date: String
    let notes: String?
    let status: String
}

struct UpdateSupabaseTodo: Encodable, Sendable {
    let title: String
    let priority: String
    let dueDate: String?

    enum CodingKeys: String, CodingKey {
        case title
        case priority
        case dueDate = "due_date"
    }
}

struct UpdateSupabaseMaterial: Encodable, Sendable {
    let name: String
    let quantity: Decimal
    let unit: String
    let supplier: String?
    let articleNumber: String?
    let priceEstimated: Decimal?
    let status: String
    let notes: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case name
        case quantity
        case unit
        case supplier
        case articleNumber = "article_number"
        case priceEstimated = "price_estimated"
        case status
        case notes
        case url
    }
}

struct UpdateSupabaseCost: Encodable, Sendable {
    let description: String
    let category: String
    let amount: Decimal
    let status: String
    let invoiceNumber: String?
    let notes: String?
    let invoiceDate: String?
    let dueDate: String?
    let laborAmount: Decimal?
    let machineAmount: Decimal?
    let travelAmount: Decimal?
    let warrantyEnd: String?
    let paymentDate: String?
    let supplier: String?

    enum CodingKeys: String, CodingKey {
        case description, category, amount, status, notes, supplier
        case invoiceNumber = "invoice_number"
        case invoiceDate = "invoice_date"
        case dueDate = "due_date"
        case laborAmount = "labor_amount"
        case machineAmount = "machine_amount"
        case travelAmount = "travel_amount"
        case warrantyEnd = "warranty_end"
        case paymentDate = "payment_date"
    }
}

struct UpdateSupabaseQuote: Encodable, Sendable {
    let title: String
    let company: String?
    let amount: Decimal?
    let validUntil: String?
    let notes: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case title, company, amount, notes, scope
        case validUntil = "valid_until"
    }
}

struct UpdateSupabaseDefect: Encodable, Sendable {
    let description: String
    let severity: String?
    let importance: String?
    let status: String
}

struct UpdateSupabaseDiary: Encodable, Sendable {
    let date: String
    let weather: String?
    let temperature: Int?
    let notes: String
    let presentTrades: [String]

    enum CodingKeys: String, CodingKey {
        case date
        case weather
        case temperature
        case notes
        case presentTrades = "present_trades"
    }
}

struct SupabaseTradeRow: Decodable, Sendable {
    let id: UUID
    let name: String
    let company: String?
    let tradeType: String?
    let status: String?
    let notes: String?
    let budget: Decimal?

    enum CodingKeys: String, CodingKey {
        case id, name, company, status, notes, budget
        case tradeType = "trade_type"
    }

    var appTrade: Trade {
        let (address, phone, email, cleanNotes) = TradeContactCoder.decode(notes)
        return Trade(id: id, name: name, company: company ?? "", tradeType: tradeType ?? "", address: address, phone: phone, email: email, status: WorkStatus(tradeValue: status), costs: 0, budget: budget ?? 0, notes: cleanNotes, rating: 0)
    }
}

struct SupabaseAppointmentRow: Decodable, Sendable {
    let id: UUID
    let title: String
    let date: String
    let status: String?
    let notes: String?

    var appScheduleItem: ScheduleItem {
        let (startTime, endTime, cleanNotes) = AppointmentTimeCoder.decode(notes)
        return ScheduleItem(id: id, title: title, date: BaumioDateFormatter.shared.date(from: date) ?? Date(), durationDays: 1, status: WorkStatus(appointmentValue: status), trade: "", notes: cleanNotes, startTime: startTime, endTime: endTime)
    }
}

struct SupabaseTodoRow: Decodable, Sendable {
    let id: UUID
    let title: String
    let priority: String?
    let dueDate: String?
    let done: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case priority
        case dueDate = "due_date"
        case done
    }

    var appTask: TaskItem {
        TaskItem(id: id, title: title, priority: Priority(todoValue: priority), dueDate: dueDate.flatMap(BaumioDateFormatter.shared.date(from:)) ?? Date(), trade: "", isDone: done ?? false)
    }
}

struct SupabaseMaterialRow: Decodable, Sendable {
    let id: UUID
    let name: String
    let quantity: Decimal?
    let unit: String?
    let supplier: String?
    let articleNumber: String?
    let priceEstimated: Decimal?
    let priceActual: Decimal?
    let status: String?
    let notes: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case quantity
        case unit
        case supplier
        case articleNumber = "article_number"
        case priceEstimated = "price_estimated"
        case priceActual = "price_actual"
        case status
        case notes
        case url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        quantity = try c.decodeIfPresent(Decimal.self, forKey: .quantity)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        supplier = try c.decodeIfPresent(String.self, forKey: .supplier)
        articleNumber = try c.decodeIfPresent(String.self, forKey: .articleNumber)
        priceEstimated = try c.decodeIfPresent(Decimal.self, forKey: .priceEstimated)
        priceActual = try c.decodeIfPresent(Decimal.self, forKey: .priceActual)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        url = try c.decodeIfPresent(String.self, forKey: .url)
    }

    var appMaterial: MaterialItem {
        let (fundingID, cleanNotes) = FundingLinkCoder.decode(notes)
        // Wie die Website: tatsächlicher Preis bevorzugt, sonst geschätzter Preis (Einzelpreis).
        return MaterialItem(id: id, name: name, quantity: quantity ?? 0, unit: unit ?? "Stück", supplier: supplier ?? "", articleNumber: articleNumber ?? "", price: priceActual ?? priceEstimated ?? 0, deliveryStatus: status?.displayStatus ?? "Geplant", trade: "", notes: cleanNotes, fundingItemID: fundingID, url: url ?? "")
    }
}

struct SupabaseCostRow: Decodable, Sendable {
    let id: UUID
    let description: String
    let category: String?
    let amount: Decimal
    let plannedAmount: Decimal?
    let status: String?
    let invoiceNumber: String?
    let notes: String?
    let invoiceDate: String?
    let dueDate: String?
    let laborAmount: Decimal?
    let machineAmount: Decimal?
    let travelAmount: Decimal?
    let warrantyEnd: String?
    let paymentDate: String?
    let supplier: String?

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case category
        case amount
        case plannedAmount = "planned_amount"
        case status
        case invoiceNumber = "invoice_number"
        case notes
        case invoiceDate = "invoice_date"
        case dueDate = "due_date"
        case laborAmount = "labor_amount"
        case machineAmount = "machine_amount"
        case travelAmount = "travel_amount"
        case warrantyEnd = "warranty_end"
        case paymentDate = "payment_date"
        case supplier
    }

    var appCost: CostItem {
        let normalizedStatus = status ?? CostStatusValue.open
        let ordered = CostStatusValue.isOrdered(normalizedStatus) ? amount : 0
        let paid = CostStatusValue.isPaid(normalizedStatus) ? amount : 0
        let (fundingID, cleanNotes) = FundingLinkCoder.decode(notes)
        // Geplant = planned_amount falls gesetzt, sonst der Betrag (wie die Website).
        return CostItem(
            id: id,
            title: description,
            planned: plannedAmount ?? amount,
            ordered: ordered,
            paid: paid,
            category: category?.displayStatus ?? "Sonstiges",
            status: normalizedStatus.displayStatus,
            trade: "",
            invoiceReference: invoiceNumber ?? "",
            notes: cleanNotes,
            fundingItemID: fundingID,
            invoiceDate: invoiceDate.flatMap { BaumioDateFormatter.shared.date(from: $0) },
            dueDate: dueDate.flatMap { BaumioDateFormatter.shared.date(from: $0) },
            laborAmount: laborAmount ?? 0,
            machineAmount: machineAmount ?? 0,
            travelAmount: travelAmount ?? 0,
            warrantyEnd: warrantyEnd.flatMap { BaumioDateFormatter.shared.date(from: $0) },
            paymentDate: paymentDate.flatMap { BaumioDateFormatter.shared.date(from: $0) },
            supplier: supplier ?? ""
        )
    }
}

struct SupabaseQuoteRow: Decodable, Sendable {
    let id: UUID
    let title: String
    let company: String?
    let amount: Decimal?
    let validUntil: String?
    let notes: String?
    let isSelected: Bool?
    let scope: String?
    let quoteStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, title, company, amount, notes, scope
        case validUntil = "valid_until"
        case isSelected = "is_selected"
        case quoteStatus = "quote_status"
    }

    var appOffer: OfferItem {
        let (fundingID, cleanNotes) = FundingLinkCoder.decode(notes)
        return OfferItem(
            id: id,
            provider: company ?? title,
            amount: amount ?? 0,
            trade: "",
            status: quoteStatus ?? (isSelected == true ? "Angenommen" : "Erhalten"),
            title: title,
            validUntil: validUntil.flatMap(BaumioDateFormatter.shared.date(from:)),
            notes: cleanNotes,
            fundingItemID: fundingID,
            scope: scope ?? ""
        )
    }
}

struct SupabaseDefectRow: Decodable, Sendable {
    let id: UUID
    let description: String
    let status: String?
    let severity: String?
    let importance: String?

    var appDefect: DefectItem {
        let (trade, responsible, deadline, cleanDescription) = DefectMetaCoder.decode(description)
        let rawTitle = cleanDescription.split(separator: "\n", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let defectTitle = rawTitle.isEmpty ? "Mangel" : (rawTitle.count > 60 ? String(rawTitle.prefix(60)) + "…" : rawTitle)
        return DefectItem(
            id: id,
            title: defectTitle,
            description: cleanDescription,
            trade: trade,
            responsible: responsible,
            deadline: deadline ?? Date(),
            status: status?.displayStatus ?? "Offen",
            priority: Priority(defectSeverity: severity),
            severity: severity ?? "mäßig",
            importance: importance ?? "wichtig"
        )
    }
}

struct SupabaseTimeLogRow: Decodable, Sendable {
    let id: UUID
    let title: String
    let category: String?
    let logDate: String?
    let durationMinutes: Int?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case logDate = "log_date"
        case durationMinutes = "duration_minutes"
        case description
    }

    var appTimeLog: TimeLogItem {
        TimeLogItem(
            id: id,
            title: title,
            category: TimeLogCategory(supabaseValue: category),
            date: logDate.flatMap(BaumioDateFormatter.shared.date(from:)) ?? Date(),
            durationMinutes: durationMinutes ?? 0,
            notes: description ?? ""
        )
    }
}

struct SupabaseHandoverRow: Decodable, Sendable {
    let id: UUID
    let item: String
    let room: String?
    let tradeType: String?
    let status: String?
    let isDone: Bool?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case item
        case room
        case tradeType = "trade_type"
        case status
        case isDone = "is_done"
        case notes
    }

    var appHandoverItem: HandoverItem {
        HandoverItem(
            id: id,
            item: item,
            room: room ?? "",
            tradeType: tradeType ?? "",
            status: HandoverStatus(supabaseValue: status),
            isDone: isDone ?? false,
            notes: notes ?? ""
        )
    }
}

struct NewSupabaseHandover: Encodable, Sendable {
    let projectID: UUID
    let item: String
    let room: String?
    let tradeType: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case item
        case room
        case tradeType = "trade_type"
        case status
    }
}

struct UpdateSupabaseHandover: Encodable, Sendable {
    let status: String
    let isDone: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case isDone = "is_done"
    }
}

struct UpdateSupabaseHandoverItem: Encodable, Sendable {
    let item: String
    let room: String?
    let tradeType: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case item, room, notes
        case tradeType = "trade_type"
    }
}

struct UpdateSupabaseTimeLog: Encodable, Sendable {
    let title: String
    let category: String
    let logDate: String
    let durationMinutes: Int
    let description: String?

    enum CodingKeys: String, CodingKey {
        case title, category, description
        case logDate = "log_date"
        case durationMinutes = "duration_minutes"
    }
}

struct UpdateSupabaseTradeRating: Encodable, Sendable {
    let quality: Int
    let punctuality: Int
    let communication: Int
    let pricePerformance: Int
    let wouldRecommend: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case quality, punctuality, communication
        case pricePerformance = "price_performance"
        case wouldRecommend = "would_recommend"
        case notes
    }
}

struct NewSupabaseTimeLog: Encodable, Sendable {
    let projectID: UUID
    let title: String
    let category: String
    let logDate: String
    let durationMinutes: Int
    let description: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case title
        case category
        case logDate = "log_date"
        case durationMinutes = "duration_minutes"
        case description
    }
}

struct SupabaseDiaryRow: Decodable, Sendable {
    let id: UUID
    let date: String
    let weather: String?
    let notes: String
    let presentTrades: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case weather
        case notes
        case presentTrades = "present_trades"
    }

    var appDiaryEntry: DiaryEntry {
        DiaryEntry(id: id, date: BaumioDateFormatter.shared.date(from: date) ?? Date(), weather: weather?.displayStatus ?? "", companies: presentTrades ?? [], completedWork: notes, issues: "", photosCount: 0, notes: "")
    }
}

// Kodiert/dekodiert KfW-Metadaten als erste Zeile des notes-Feldes.
// Format: "#KFW:prog=beg_em,max=50000.00,rate=70,dd=2025-12-31,g=1,k=0,e=1,f=0"
enum FundingKfWCoder {
    static func encode(programType: FundingProgramType = .sonstige, maxAmount: Decimal, rate: Int? = nil, documentDeadline: Date?, g: Bool, k: Bool, e: Bool, f: Bool, userNotes: String) -> String {
        guard maxAmount > 0 || g || k || e || f || programType != .sonstige || rate != nil else { return userNotes }
        var header = "#KFW:"
        if programType != .sonstige { header += "prog=\(programType.rawValue)," }
        header += "max=\(maxAmount)"
        if let r = rate { header += ",rate=\(r)" }
        if let dd = documentDeadline { header += ",dd=\(BaumioDateFormatter.string(from: dd))" }
        header += ",g=\(g ? 1 : 0),k=\(k ? 1 : 0),e=\(e ? 1 : 0),f=\(f ? 1 : 0)"
        return userNotes.isEmpty ? header : header + "\n" + userNotes
    }

    static func decode(_ raw: String) -> (programType: FundingProgramType, maxAmount: Decimal, rate: Int?, docDeadline: Date?, g: Bool, k: Bool, e: Bool, f: Bool, userNotes: String) {
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, first.hasPrefix("#KFW:") else {
            return (.sonstige, 0, nil, nil, false, false, false, false, raw)
        }
        let userNotes = parts.count > 1 ? parts[1] : ""
        var programType = FundingProgramType.sonstige
        var maxAmount: Decimal = 0; var rate: Int? = nil; var docDeadline: Date? = nil
        var g = false, k = false, e = false, f = false
        for pair in first.dropFirst(5).split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "prog": programType = FundingProgramType(stored: kv[1])
            case "max":  maxAmount = Decimal(string: kv[1]) ?? 0
            case "rate": rate = Int(kv[1])
            case "dd":   docDeadline = BaumioDateFormatter.shared.date(from: kv[1])
            case "g":    g = kv[1] == "1"
            case "k":    k = kv[1] == "1"
            case "e":    e = kv[1] == "1"
            case "f":    f = kv[1] == "1"
            default: break
            }
        }
        return (programType, maxAmount, rate, docDeadline, g, k, e, f, userNotes)
    }
}

// Kodiert/dekodiert die Verknüpfung zu einer Förderung als erste Zeile des notes-Felds.
// Format: "#FUND:id=<UUID>"
// Kodiert/dekodiert Terminzeiten (Start/Ende) im notes-Feld.
// Format: "#TIME:start=09:00,end=10:30\nNutzernotizen"
enum AppointmentTimeCoder {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func encode(startTime: Date?, endTime: Date?, userNotes: String) -> String? {
        guard startTime != nil || endTime != nil else {
            let trimmed = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var parts: [String] = []
        if let s = startTime { parts.append("start=\(timeFormatter.string(from: s))") }
        if let e = endTime { parts.append("end=\(timeFormatter.string(from: e))") }
        let header = "#TIME:" + parts.joined(separator: ",")
        let trimmed = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? header : header + "\n" + trimmed
    }

    static func decode(_ raw: String?) -> (startTime: Date?, endTime: Date?, userNotes: String) {
        guard let raw, !raw.isEmpty else { return (nil, nil, "") }
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, first.hasPrefix("#TIME:") else { return (nil, nil, raw) }
        let userNotes = parts.count > 1 ? parts[1] : ""
        var startTime: Date? = nil
        var endTime: Date? = nil
        for pair in first.dropFirst(6).split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "start": startTime = timeFormatter.date(from: kv[1])
            case "end":   endTime   = timeFormatter.date(from: kv[1])
            default: break
            }
        }
        return (startTime, endTime, userNotes)
    }
}

enum FundingLinkCoder {
    static func encode(fundingID: UUID?, userNotes: String) -> String? {
        guard let fundingID else {
            let trimmed = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let header = "#FUND:id=\(fundingID.uuidString)"
        let trimmed = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? header : header + "\n" + trimmed
    }

    static func decode(_ raw: String?) -> (fundingID: UUID?, userNotes: String) {
        guard let raw, !raw.isEmpty else { return (nil, "") }
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, first.hasPrefix("#FUND:") else { return (nil, raw) }
        let userNotes = parts.count > 1 ? parts[1] : ""
        var fundingID: UUID? = nil
        for pair in first.dropFirst(6).split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, kv[0] == "id" else { continue }
            fundingID = UUID(uuidString: kv[1])
        }
        return (fundingID, userNotes)
    }
}

// Kodiert/dekodiert Mangel-Metadaten (Gewerk, Verantwortlicher, Frist) im description-Feld.
// Format: "#DEF:trade=Elektriker,resp=Müller,dead=2025-12-31\nBeschreibung"
enum DefectMetaCoder {
    static func encode(trade: String, responsible: String, deadline: Date?, userNotes: String) -> String {
        guard !trade.isEmpty || !responsible.isEmpty || deadline != nil else { return userNotes }
        var parts: [String] = []
        if !trade.isEmpty { parts.append("trade=\(trade.replacingOccurrences(of: ",", with: ";"))") }
        if !responsible.isEmpty { parts.append("resp=\(responsible.replacingOccurrences(of: ",", with: ";"))") }
        if let deadline { parts.append("dead=\(BaumioDateFormatter.string(from: deadline))") }
        let header = "#DEF:" + parts.joined(separator: ",")
        return userNotes.isEmpty ? header : header + "\n" + userNotes
    }

    static func decode(_ raw: String) -> (trade: String, responsible: String, deadline: Date?, description: String) {
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, first.hasPrefix("#DEF:") else {
            return ("", "", nil, raw)
        }
        let description = parts.count > 1 ? parts[1] : ""
        var trade = "", responsible = ""
        var deadline: Date? = nil
        for pair in first.dropFirst(5).split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "trade": trade = kv[1].replacingOccurrences(of: ";", with: ",")
            case "resp":  responsible = kv[1].replacingOccurrences(of: ";", with: ",")
            case "dead":  deadline = BaumioDateFormatter.shared.date(from: kv[1])
            default: break
            }
        }
        return (trade, responsible, deadline, description)
    }
}

struct SupabaseSubsidyRow: Decodable, Sendable {
    let id: UUID
    let name: String
    let provider: String?
    let amount: Decimal?
    let status: String?
    let deadline: String?
    let referenceNumber: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, provider, amount, status, deadline
        case referenceNumber = "reference_number"
        case notes
    }

    var appFunding: FundingItem {
        let (prog, maxAmt, rate, docDead, g, k, e, f, cleanNotes) = FundingKfWCoder.decode(notes ?? "")
        return FundingItem(
            id: id,
            name: name,
            provider: provider ?? "",
            amount: amount ?? 0,
            status: (status ?? "geplant").displayStatus,
            deadline: deadline.flatMap(BaumioDateFormatter.shared.date(from:)),
            referenceNumber: referenceNumber ?? "",
            notes: cleanNotes,
            maxAmount: maxAmt,
            documentDeadline: docDead,
            kfwGrundfoerderung: g,
            kfwKlimabonus: k,
            kfwEinkommensbonus: e,
            kfwEffizienzbonus: f,
            programType: prog,
            manualGrantRate: rate
        )
    }
}

struct NewSupabaseSubsidy: Encodable, Sendable {
    let projectID: UUID
    let name: String
    let provider: String?
    let amount: Decimal?
    let status: String
    let deadline: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case name, provider, amount, status, deadline, notes
    }
}

struct UpdateSupabaseSubsidy: Encodable, Sendable {
    let name: String
    let provider: String?
    let amount: Decimal?
    let status: String
    let deadline: String?
    let notes: String?
}

struct SupabaseTradeRatingRow: Decodable, Sendable {
    let id: UUID
    let tradeID: UUID?
    let quality: Int?
    let punctuality: Int?
    let communication: Int?
    let pricePerformance: Int?
    let wouldRecommend: Bool?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tradeID = "trade_id"
        case quality, punctuality, communication
        case pricePerformance = "price_performance"
        case wouldRecommend = "would_recommend"
        case notes
    }

    func appReview(trade: SupabaseTradeRow?) -> ReviewItem {
        let values = [quality, punctuality, communication, pricePerformance].compactMap { $0 }
        let stars = values.isEmpty ? 0 : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        return ReviewItem(
            id: id,
            company: (trade?.company.flatMap { $0.isEmpty ? nil : $0 }) ?? trade?.name ?? "Gewerk",
            trade: trade?.name ?? "",
            stars: stars,
            notes: notes ?? "",
            recommended: wouldRecommend ?? true,
            quality: quality ?? 3,
            punctuality: punctuality ?? 3,
            communication: communication ?? 3,
            pricePerformance: pricePerformance ?? 3
        )
    }
}

struct NewSupabaseTradeRating: Encodable, Sendable {
    let projectID: UUID
    let tradeID: UUID
    let quality: Int
    let punctuality: Int
    let communication: Int
    let pricePerformance: Int
    let wouldRecommend: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case tradeID = "trade_id"
        case quality, punctuality, communication
        case pricePerformance = "price_performance"
        case wouldRecommend = "would_recommend"
        case notes
    }
}

struct SupabaseDocumentRow: Decodable, Sendable {
    let id: UUID
    let name: String
    let docType: String?
    let storagePath: String?
    let fileSize: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case docType = "doc_type"
        case storagePath = "storage_path"
        case fileSize = "file_size"
        case createdAt = "created_at"
    }

    private static let isoFormatter = ISO8601DateFormatter()

    var appDocument: DocumentItem {
        DocumentItem(
            id: id,
            title: name,
            category: DocumentCategory(supabaseValue: docType),
            uploadDate: createdAt.flatMap { Self.isoFormatter.date(from: $0) } ?? Date(),
            fileType: docType?.uppercased() ?? "DATEI",
            storagePath: storagePath ?? "",
            fileSize: fileSize ?? 0
        )
    }
}

struct NewSupabaseDocument: Encodable, Sendable {
    let projectID: UUID
    let name: String
    let docType: String
    let storagePath: String
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case name
        case docType = "doc_type"
        case storagePath = "storage_path"
        case fileSize = "file_size"
    }
}

struct SupabaseStorageUsageRow: Decodable, Sendable {
    let totalBytes: Int?

    enum CodingKeys: String, CodingKey {
        case totalBytes = "total_bytes"
    }
}

struct SupabasePhotoRow: Decodable, Sendable {
    let id: UUID
    let storagePath: String
    let parent: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case storagePath = "storage_path"
        case parent
    }
}

struct NewSupabaseDefectPhoto: Encodable, Sendable {
    let defectID: UUID
    let storagePath: String
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case defectID = "defect_id"
        case storagePath = "storage_path"
        case fileSize = "file_size"
    }
}

struct NewSupabaseDiaryPhoto: Encodable, Sendable {
    let diaryEntryID: UUID
    let storagePath: String
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case diaryEntryID = "diary_entry_id"
        case storagePath = "storage_path"
        case fileSize = "file_size"
    }
}

struct NewSupabaseCostPhoto: Encodable, Sendable {
    let costID: UUID
    let storagePath: String
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case costID = "cost_id"
        case storagePath = "storage_path"
        case fileSize = "file_size"
    }
}

struct NewSupabaseTaskPhoto: Encodable, Sendable {
    let taskID: UUID
    let storagePath: String
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case storagePath = "storage_path"
        case fileSize = "file_size"
    }
}

struct SupabaseService: Sendable {
    private let config: SupabaseConfig?
    private let session: URLSession

    init(config: SupabaseConfig? = SupabaseConfig.load(), session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    var isConfigured: Bool { config?.isConfigured == true }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let endpoint = try endpoint(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")])
        return try await sendAuth(endpoint: endpoint, body: AuthRequest(email: email, password: password))
    }

    func signUp(email: String, password: String) async throws -> SupabaseSession? {
        let endpoint = try endpoint(path: "auth/v1/signup")
        do {
            return try await sendAuth(endpoint: endpoint, body: AuthRequest(email: email, password: password))
        } catch SupabaseError.invalidResponse {
            // Supabase gibt ein User-Objekt (kein access_token) zurück wenn E-Mail-Bestätigung erforderlich ist.
            return nil
        }
    }

    func resetPassword(email: String) async throws {
        let endpoint = try endpoint(path: "auth/v1/recover")
        let _: EmptySupabaseResponse = try await sendAuth(endpoint: endpoint, body: EmailRequest(email: email))
    }

    /// Erneuert die Sitzung anhand des Refresh-Tokens (für „angemeldet bleiben").
    func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        let endpoint = try endpoint(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        return try await sendAuth(endpoint: endpoint, body: RefreshRequest(refreshToken: refreshToken))
    }

    /// Sendet ein Bild an die `process-document` Edge Function und gibt das geparste Ergebnis zurück.
    /// Das Bild wird NICHT in Supabase gespeichert – nur der Extrakt kommt zurück.
    func scanRechnung(imageData: Data, mimeType: String, accessToken: String, transactionJWS: String?) async throws -> RechnungScanResult {
        let raw = try await invokeProcessDocument(imageData: imageData, mimeType: mimeType, documentType: "rechnung", accessToken: accessToken, transactionJWS: transactionJWS)
        return RechnungScanResult(
            betrag: (raw["betrag"] as? Double).map { Decimal($0) } ?? 0,
            datum: (raw["datum"] as? String).flatMap(BaumioDateFormatter.shared.date(from:)),
            faelligAm: (raw["faellig_am"] as? String).flatMap(BaumioDateFormatter.shared.date(from:)),
            firma: raw["firma"] as? String ?? "",
            rechnungsnummer: raw["rechnungsnummer"] as? String ?? "",
            gewerk: raw["gewerk"] as? String ?? "",
            arbeitskosten: (raw["arbeitskosten"] as? Double).map { Decimal($0) } ?? 0,
            materialkosten: (raw["materialkosten"] as? Double).map { Decimal($0) } ?? 0,
            fahrkosten: (raw["fahrkosten"] as? Double).map { Decimal($0) } ?? 0
        )
    }

    func scanVisitenkarte(imageData: Data, mimeType: String, accessToken: String) async throws -> VisitenkarteScanResult {
        let raw = try await invokeProcessDocument(imageData: imageData, mimeType: mimeType, documentType: "visitenkarte", accessToken: accessToken, transactionJWS: nil)
        return VisitenkarteScanResult(
            name:      raw["name"]      as? String ?? "",
            company:   raw["company"]   as? String ?? "",
            tradeType: raw["trade_type"] as? String ?? "",
            address:   raw["address"]   as? String ?? "",
            phone:     raw["phone"]     as? String ?? "",
            email:     raw["email"]     as? String ?? ""
        )
    }

    func scanAngebot(imageData: Data, mimeType: String, accessToken: String, transactionJWS: String?) async throws -> AngebotScanResult {
        let raw = try await invokeProcessDocument(imageData: imageData, mimeType: mimeType, documentType: "angebot", accessToken: accessToken, transactionJWS: transactionJWS)
        return AngebotScanResult(
            betrag: (raw["betrag"] as? Double).map { Decimal($0) } ?? 0,
            gueltigBis: (raw["gueltig_bis"] as? String).flatMap(BaumioDateFormatter.shared.date(from:)),
            firma: raw["firma"] as? String ?? "",
            angebotsnummer: raw["angebotsnummer"] as? String ?? "",
            leistung: raw["leistung"] as? String ?? "",
            gewerk: raw["gewerk"] as? String ?? ""
        )
    }

    private func invokeProcessDocument(imageData: Data, mimeType: String, documentType: String, accessToken: String, transactionJWS: String?) async throws -> [String: Any] {
        guard let config, config.isConfigured else { throw SupabaseError.notConfigured }
        let endpoint = try endpoint(path: "functions/v1/process-document")

        var bodyDict: [String: Any] = [
            "imageBase64": imageData.base64EncodedString(),
            "mimeType": mimeType,
            "documentType": documentType,
        ]
        if let jws = transactionJWS { bodyDict["transactionJWS"] = jws }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200:
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let result = json?["result"] as? [String: Any] else { throw SupabaseError.invalidResponse }
            return result
        case 403: throw DocumentScanError.proRequired
        case 413: throw DocumentScanError.fileTooLarge
        case 422: throw DocumentScanError.wrongDocumentType
        case 429: throw DocumentScanError.trialLimitReached
        default:  throw DocumentScanError.networkError(status)
        }
    }

    // MARK: - Projektmitglieder

    func fetchProjectMembers(projectID: UUID, accessToken: String) async throws -> [ProjectMember] {
        let endpoint = try endpoint(path: "rest/v1/project_members", query: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "project_id", value: "eq.\(projectID.uuidString)")
        ])
        let rows: [SupabaseProjectMember] = try await sendRest(endpoint: endpoint, method: "GET", accessToken: accessToken)
        return rows.map(\.appMember)
    }

    func fetchPendingInvites(email: String, accessToken: String) async throws -> [ProjectMember] {
        // URLComponents kodiert query-Werte automatisch — kein manuelles Encoding nötig
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = try endpoint(path: "rest/v1/project_members", query: [
            URLQueryItem(name: "select", value: "*,projects(name)"),
            URLQueryItem(name: "invited_email", value: "eq.\(normalizedEmail)"),
            URLQueryItem(name: "status", value: "eq.pending")
        ])
        let rows: [SupabaseProjectMember] = try await sendRest(endpoint: endpoint, method: "GET", accessToken: accessToken)
        return rows.map(\.appMember)
    }

    func acceptInvite(id: UUID, accessToken: String) async throws {
        struct Patch: Encodable { let status: String }
        let endpoint = try endpoint(path: "rest/v1/project_members", query: [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
        ])
        let _: EmptySupabaseResponse = try await sendRest(endpoint: endpoint, method: "PATCH", accessToken: accessToken, body: Patch(status: "accepted"), prefer: "return=minimal")
    }

    /// Löscht das Konto samt Daten über die Edge Function `delete-account` (nutzt den User-JWT).
    func deleteAccount(accessToken: String) async throws {
        guard let config else { throw SupabaseError.notConfigured }
        let endpoint = try endpoint(path: "functions/v1/delete-account")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let _: EmptySupabaseResponse = try await decode(request: request)
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseSession {
        let endpoint = try endpoint(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "id_token")])
        return try await sendAuth(endpoint: endpoint, body: AppleTokenRequest(idToken: idToken, nonce: nonce))
    }

    /// Liest den Plan aus `profiles.plan` und gibt ihn als String zurück ("free", "pro", "business").
    func fetchPlan(userID: UUID, accessToken: String) async throws -> String {
        let endpoint = try endpoint(path: "rest/v1/profiles", query: [
            URLQueryItem(name: "select", value: "plan"),
            URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")
        ])
        let rows: [SupabaseProfileRow] = try await sendRest(endpoint: endpoint, method: "GET", accessToken: accessToken)
        return rows.first?.plan ?? "free"
    }

    /// Lädt alle Projektmitglieder, die dieser Nutzer eingeladen hat (projektübergreifend, für Business-Team-Übersicht).
    func fetchAllMembersInvitedBy(userID: UUID, accessToken: String) async throws -> [ProjectMember] {
        let endpoint = try endpoint(path: "rest/v1/project_members", query: [
            URLQueryItem(name: "select", value: "*,projects(name)"),
            URLQueryItem(name: "invited_by", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ])
        let rows: [SupabaseProjectMember] = try await sendRest(endpoint: endpoint, method: "GET", accessToken: accessToken)
        return rows.map(\.appMember)
    }

    /// Setzt `profiles.plan` (nach erfolgreichem App-Kauf) – dieselbe Spalte wie die Website.
    func setPlan(userID: UUID, plan: String, accessToken: String) async throws {
        let endpoint = try endpoint(path: "rest/v1/profiles", query: [
            URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")
        ])
        let _: EmptySupabaseResponse = try await sendRest(endpoint: endpoint, method: "PATCH", accessToken: accessToken, body: UpdateSupabaseProfilePlan(plan: plan), prefer: "return=minimal")
    }

    func fetchProjects(accessToken: String) async throws -> [Project] {
        let endpoint = try endpoint(path: "rest/v1/projects", query: [
            URLQueryItem(name: "select", value: "id,user_id,name,status,budget,start_date,end_date,description,progress_by_costs,eigenkapital,kredit"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ])
        let rows: [SupabaseProject] = try await sendRest(endpoint: endpoint, method: "GET", accessToken: accessToken)
        return rows.map(\.appProject)
    }

    func createProject(_ project: NewSupabaseProject, accessToken: String) async throws -> Project {
        let endpoint = try endpoint(path: "rest/v1/projects")
        let rows: [SupabaseProject] = try await sendRest(endpoint: endpoint, method: "POST", accessToken: accessToken, body: project, prefer: "return=representation")
        guard let createdProject = rows.first else { throw SupabaseError.invalidResponse }
        return createdProject.appProject
    }

    func fetchProjectDetails(projectID: UUID, accessToken: String) async throws -> ProjectDetails {
        async let trades: [SupabaseTradeRow] = fetchRows("trades", projectID: projectID, accessToken: accessToken, select: "id,name,company,trade_type,status,notes,budget")
        async let appointments: [SupabaseAppointmentRow] = fetchRows("appointments", projectID: projectID, accessToken: accessToken, select: "id,title,date,status,notes")
        async let todos: [SupabaseTodoRow] = fetchRows("project_todos", projectID: projectID, accessToken: accessToken, select: "id,title,priority,due_date,done")
        async let materials: [SupabaseMaterialRow] = fetchRows("materials", projectID: projectID, accessToken: accessToken, select: "id,name,quantity,unit,supplier,article_number,price_estimated,price_actual,status,notes")
        async let costs: [SupabaseCostRow] = fetchRows("costs", projectID: projectID, accessToken: accessToken, select: "id,description,category,amount,planned_amount,status,invoice_number,notes,invoice_date,due_date,labor_amount,machine_amount,travel_amount,warranty_end,payment_date,supplier")
        async let quotes: [SupabaseQuoteRow] = fetchRows("quotes", projectID: projectID, accessToken: accessToken, select: "id,title,company,amount,valid_until,notes,is_selected,scope,quote_status")
        async let defects: [SupabaseDefectRow] = fetchRows("defects", projectID: projectID, accessToken: accessToken, select: "id,description,status,severity,importance")
        async let diary: [SupabaseDiaryRow] = fetchRows("diary_entries", projectID: projectID, accessToken: accessToken, select: "id,date,weather,notes,present_trades")
        async let documents: [SupabaseDocumentRow] = fetchRows("documents", projectID: projectID, accessToken: accessToken, select: "id,name,doc_type,storage_path,file_size,created_at")
        async let timeLogs: [SupabaseTimeLogRow] = fetchRows("time_logs", projectID: projectID, accessToken: accessToken, select: "id,title,category,log_date,duration_minutes,description")
        async let handover: [SupabaseHandoverRow] = fetchRows("handover_items", projectID: projectID, accessToken: accessToken, select: "id,item,room,trade_type,status,is_done,notes")
        async let subsidies: [SupabaseSubsidyRow] = fetchRows("subsidies", projectID: projectID, accessToken: accessToken, select: "id,name,provider,amount,status,deadline,reference_number,notes")
        async let ratings: [SupabaseTradeRatingRow] = fetchRows("trade_ratings", projectID: projectID, accessToken: accessToken, select: "id,trade_id,quality,punctuality,communication,price_performance,would_recommend,notes")

        let tradeRows = try await trades
        let tradeLookup = Dictionary(tradeRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Zusatz-Tabellen tolerant behandeln: fehlt eine, bleibt der Bereich leer,
        // statt den ganzen Login/Datenladevorgang scheitern zu lassen.
        let subsidyRows = (try? await subsidies) ?? []
        let ratingRows = (try? await ratings) ?? []

        return try await ProjectDetails(
            trades: tradeRows.map(\.appTrade),
            schedule: appointments.map(\.appScheduleItem),
            tasks: todos.map(\.appTask),
            materials: materials.map(\.appMaterial),
            costs: costs.map(\.appCost),
            offers: quotes.map(\.appOffer),
            defects: defects.map(\.appDefect),
            diary: diary.map(\.appDiaryEntry),
            documents: documents.map(\.appDocument),
            timeLogs: timeLogs.map(\.appTimeLog),
            handoverItems: handover.map(\.appHandoverItem),
            funding: subsidyRows.map(\.appFunding),
            reviews: ratingRows.map { $0.appReview(trade: tradeLookup[$0.tradeID ?? UUID()]) }
        )
    }

    private func fetchRows<ResponseBody: Decodable>(_ table: String, projectID: UUID, accessToken: String, select: String) async throws -> ResponseBody {
        let endpoint = try endpoint(path: "rest/v1/\(table)", query: [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "project_id", value: "eq.\(projectID.uuidString)")
        ])
        return try await sendRest(endpoint: endpoint, method: "GET", accessToken: accessToken)
    }

    func insert<TableRow: Encodable>(_ row: TableRow, into table: String, accessToken: String) async throws {
        let endpoint = try endpoint(path: "rest/v1/\(table)")
        let _: EmptySupabaseResponse = try await sendRest(endpoint: endpoint, method: "POST", accessToken: accessToken, body: row, prefer: "return=minimal")
    }

    /// Fügt einen Datensatz ein und gibt die erzeugte Zeile zurück (für lokales Einfügen ohne Voll-Reload).
    func insertReturning<TableRow: Encodable, ResponseRow: Decodable>(_ row: TableRow, into table: String, accessToken: String) async throws -> [ResponseRow] {
        let endpoint = try endpoint(path: "rest/v1/\(table)")
        return try await sendRest(endpoint: endpoint, method: "POST", accessToken: accessToken, body: row, prefer: "return=representation")
    }

    func update<TableRow: Encodable>(_ row: TableRow, in table: String, id: UUID, accessToken: String) async throws {
        let endpoint = try endpoint(path: "rest/v1/\(table)", query: [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
        ])
        let _: EmptySupabaseResponse = try await sendRest(endpoint: endpoint, method: "PATCH", accessToken: accessToken, body: row, prefer: "return=minimal")
    }

    func delete(from table: String, id: UUID, accessToken: String) async throws {
        let endpoint = try endpoint(path: "rest/v1/\(table)", query: [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
        ])
        let _: EmptySupabaseResponse = try await sendRest(endpoint: endpoint, method: "DELETE", accessToken: accessToken)
    }

    // MARK: - Storage

    /// Lädt eine Datei in den privaten Bucket. `path` beginnt mit der User-ID (Storage-RLS).
    func uploadToStorage(bucket: String, path: String, data: Data, contentType: String, accessToken: String) async throws {
        guard let config else { throw SupabaseError.notConfigured }
        let endpoint = try endpoint(path: "storage/v1/object/\(bucket)/\(path)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        let _: EmptySupabaseResponse = try await decode(request: request)
    }

    /// Erstellt eine zeitlich begrenzte, signierte URL zum Öffnen einer privaten Datei.
    func createSignedURL(bucket: String, path: String, expiresIn: Int = 3600, accessToken: String) async throws -> URL {
        guard let config else { throw SupabaseError.notConfigured }
        let endpoint = try endpoint(path: "storage/v1/object/sign/\(bucket)/\(path)")
        var request = try restRequest(endpoint: endpoint, method: "POST", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(SignedURLRequest(expiresIn: expiresIn))
        let response: SignedURLResponse = try await decode(request: request)
        // Antwort ist relativ ("/object/sign/..."), an die Storage-Basis-URL anhängen.
        let relative = response.signedURL.hasPrefix("/") ? String(response.signedURL.dropFirst()) : response.signedURL
        guard let url = URL(string: "storage/v1/\(relative)", relativeTo: config.projectURL) else {
            throw SupabaseError.invalidResponse
        }
        return url.absoluteURL
    }

    func deleteFromStorage(bucket: String, path: String, accessToken: String) async throws {
        let endpoint = try endpoint(path: "storage/v1/object/\(bucket)/\(path)")
        let _: EmptySupabaseResponse = try await sendRest(endpoint: endpoint, method: "DELETE", accessToken: accessToken)
    }

    /// Lädt Foto-Verweise (id, Pfad, Eltern-ID) einer Foto-Tabelle für mehrere Eltern-Einträge.
    func fetchPhotos(table: String, parentColumn: String, parentIDs: [UUID], accessToken: String) async throws -> [SupabasePhotoRow] {
        guard !parentIDs.isEmpty else { return [] }
        let list = parentIDs.map(\.uuidString).joined(separator: ",")
        let endpoint = try endpoint(path: "rest/v1/\(table)", query: [
            URLQueryItem(name: "select", value: "id,storage_path,parent:\(parentColumn)"),
            URLQueryItem(name: parentColumn, value: "in.(\(list))")
        ])
        return try await sendRest(endpoint: endpoint, method: "GET", accessToken: accessToken)
    }

    /// Liest den aktuellen Speicherverbrauch des Nutzers (Bytes) aus der View.
    func fetchStorageUsage(userID: UUID, accessToken: String) async throws -> Int {
        let endpoint = try endpoint(path: "rest/v1/storage_usage_per_user", query: [
            URLQueryItem(name: "select", value: "total_bytes"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ])
        let rows: [SupabaseStorageUsageRow] = try await sendRest(endpoint: endpoint, method: "GET", accessToken: accessToken)
        return rows.first?.totalBytes ?? 0
    }

    private func endpoint(path: String, query: [URLQueryItem] = []) throws -> URL {
        guard let config, config.isConfigured else { throw SupabaseError.notConfigured }
        var components = URLComponents(url: config.projectURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw SupabaseError.invalidResponse }
        return url
    }

    private func sendAuth<RequestBody: Encodable, ResponseBody: Decodable>(endpoint: URL, body: RequestBody) async throws -> ResponseBody {
        guard let config else { throw SupabaseError.notConfigured }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await decode(request: request)
    }

    private func sendRest<ResponseBody: Decodable>(endpoint: URL, method: String, accessToken: String) async throws -> ResponseBody {
        var request = try restRequest(endpoint: endpoint, method: method, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await decode(request: request)
    }

    private func sendRest<RequestBody: Encodable, ResponseBody: Decodable>(endpoint: URL, method: String, accessToken: String, body: RequestBody, prefer: String? = nil) async throws -> ResponseBody {
        var request = try restRequest(endpoint: endpoint, method: method, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = try JSONEncoder().encode(body)
        return try await decode(request: request)
    }

    private func restRequest(endpoint: URL, method: String, accessToken: String) throws -> URLRequest {
        guard let config else { throw SupabaseError.notConfigured }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func decode<ResponseBody: Decodable>(request: URLRequest) async throws -> ResponseBody {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard 200..<300 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 401 { throw SupabaseError.unauthorized }
            let errResponse = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data)
            let message = errResponse?.bestMessage ?? "Supabase-Fehler: HTTP \(httpResponse.statusCode)"
            // Klare deutsche Fehlermeldung für häufige Auth-Fehler
            let friendlyMessage: String
            switch message.lowercased() {
            case let m where m.contains("invalid login credentials") || m.contains("invalid_credentials"):
                friendlyMessage = "E-Mail oder Passwort ist falsch."
            case let m where m.contains("email not confirmed"):
                friendlyMessage = "Bitte bestätige zuerst deine E-Mail-Adresse."
            case let m where m.contains("user not found"):
                friendlyMessage = "Kein Konto mit dieser E-Mail gefunden."
            case let m where m.contains("too many requests") || m.contains("rate limit"):
                friendlyMessage = "Zu viele Versuche. Bitte warte kurz und versuche es erneut."
            default:
                friendlyMessage = message
            }
            throw SupabaseError.requestFailed(friendlyMessage)
        }
        if ResponseBody.self == EmptySupabaseResponse.self, data.isEmpty { return EmptySupabaseResponse() as! ResponseBody }
        do { return try JSONDecoder().decode(ResponseBody.self, from: data) } catch {
            if ResponseBody.self == EmptySupabaseResponse.self { return EmptySupabaseResponse() as! ResponseBody }
            throw SupabaseError.invalidResponse
        }
    }
}

struct SupabaseProjectMember: Decodable, Sendable {
    let id: UUID
    let projectID: UUID
    let invitedEmail: String
    let role: String
    let status: String
    let invitedBy: UUID?
    let projects: EmbeddedProject?

    struct EmbeddedProject: Decodable, Sendable { let name: String }

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case invitedEmail = "invited_email"
        case role, status
        case invitedBy = "invited_by"
        case projects
    }

    var appMember: ProjectMember {
        ProjectMember(
            id: id,
            projectID: projectID,
            invitedEmail: invitedEmail,
            role: MemberRole(rawValue: role) ?? .viewer,
            status: MemberStatus(rawValue: status) ?? .pending,
            invitedBy: invitedBy,
            projectName: projects?.name ?? ""
        )
    }
}

struct NewSupabaseProjectMember: Encodable, Sendable {
    let projectID: UUID
    let invitedEmail: String
    let role: String
    let invitedBy: UUID

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case invitedEmail = "invited_email"
        case role
        case invitedBy = "invited_by"
    }
}

private struct AuthRequest: Encodable { let email: String; let password: String }
private struct EmailRequest: Encodable { let email: String }
private struct RefreshRequest: Encodable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}
private struct SignedURLRequest: Encodable { let expiresIn: Int }
private struct SignedURLResponse: Decodable { let signedURL: String }

private struct AppleTokenRequest: Encodable {
    let provider = "apple"
    let idToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case nonce
    }
}

struct SupabaseProfileRow: Decodable, Sendable {
    let plan: String?
}

struct UpdateSupabaseProfilePlan: Encodable, Sendable {
    let plan: String
}
private struct SupabaseErrorResponse: Decodable {
    let message: String?
    let errorDescription: String?   // Auth-Endpunkte nutzen "error_description"
    let error: String?              // Fallback: "error"-Feld
    enum CodingKeys: String, CodingKey {
        case message
        case errorDescription = "error_description"
        case error
    }
    var bestMessage: String? { message ?? errorDescription ?? error }
}
private struct EmptySupabaseResponse: Decodable {}

enum BaumioDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from date: Date) -> String { shared.string(from: date) }
}

extension ProjectStatus {
    init(supabaseValue: String) {
        switch supabaseValue {
        case "aktiv": self = .active
        case "abgeschlossen": self = .completed
        case "pausiert": self = .paused
        default: self = .planned
        }
    }

    var supabaseValue: String {
        switch self {
        case .planned: "planung"
        case .active: "aktiv"
        case .completed: "abgeschlossen"
        case .paused: "pausiert"
        }
    }
}

/// Typsichere Konstanten für Kostenpositions-Status (Supabase-Rohwerte).
enum CostStatusValue {
    static let open         = "offen"
    static let commissioned = "beauftragt"
    static let paid         = "bezahlt"
    static let rejected     = "abgelehnt"

    /// true wenn Betrag als beauftragt gilt (beauftragt oder bezahlt)
    static func isOrdered(_ raw: String) -> Bool { raw == commissioned || raw == paid }
    static func isPaid(_ raw: String) -> Bool    { raw == paid }
}

extension WorkStatus {
    init(tradeValue: String?) {
        switch tradeValue {
        case "beauftragt": self = .active
        case "abgeschlossen": self = .done
        case "angefragt": self = .planned
        default: self = .planned
        }
    }

    init(appointmentValue: String?) {
        switch appointmentValue {
        case "bestaetigt": self = .active
        case "abgeschlossen": self = .done
        case "abgesagt": self = .blocked
        default: self = .planned
        }
    }

    var appointmentStatusValue: String {
        switch self {
        case .planned: "geplant"
        case .active: "bestaetigt"
        case .done: "abgeschlossen"
        case .blocked: "abgesagt"
        }
    }
}

extension Priority {
    init(todoValue: String?) {
        switch todoValue {
        case "high": self = .high
        case "low": self = .low
        default: self = .medium
        }
    }

    init(defectSeverity: String?) {
        switch defectSeverity {
        case "sehr stark", "deutlich": self = .high
        case "geringfügig": self = .low
        default: self = .medium
        }
    }
}

extension DocumentCategory {
    init(supabaseValue: String?) {
        switch supabaseValue {
        case "angebot": self = .offers
        case "rechnung": self = .invoices
        case "plan": self = .plans
        case "vertrag": self = .contracts
        case "genehmigung", "protokoll": self = .proofs
        default: self = .proofs
        }
    }
}

extension String {
    var displayStatus: String {
        switch self {
        case "in_bearbeitung": "In Bearbeitung"
        case "offen": "Offen"
        case "gemeldet": "Gemeldet"
        case "behoben": "Behoben"
        case "geplant": "Geplant"
        case "bestellt": "Bestellt"
        case "geliefert": "Geliefert"
        case "verbaut": "Verbaut"
        case "retour": "Retour"
        case "lohn": "Lohn"
        case "material": "Material"
        case "nebenkosten": "Nebenkosten"
        case "planung": "Planung"
        case "foerderung": "Förderung"
        case "sonstiges": "Sonstiges"
        case "bewölkt": "Bewölkt"
        case "sonnig": "Sonnig"
        case "regnerisch": "Regnerisch"
        case "schnee": "Schnee"
        case "sturm": "Sturm"
        case "beantragt": "Beantragt"
        case "bewilligt": "Bewilligt"
        case "ausgezahlt": "Ausgezahlt"
        case "abgelehnt": "Abgelehnt"
        default: self
        }
    }
}
