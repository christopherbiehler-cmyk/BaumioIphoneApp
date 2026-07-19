import Foundation
import SwiftUI

enum ProjectStatus: String, CaseIterable, Identifiable {
    case planned = "Geplant"
    case active = "Aktiv"
    case completed = "Abgeschlossen"
    case paused = "Pausiert"

    var id: String { rawValue }
}

enum WorkStatus: String, CaseIterable, Identifiable {
    case planned = "Geplant"
    case active = "Aktiv"
    case done = "Erledigt"
    case blocked = "Blockiert"

    var id: String { rawValue }
}

enum Priority: String, CaseIterable, Identifiable {
    case low = "Niedrig"
    case medium = "Mittel"
    case high = "Hoch"

    var id: String { rawValue }
}

enum DocumentCategory: String, CaseIterable, Identifiable {
    case offers = "Angebote"
    case invoices = "Rechnungen"
    case plans = "Pläne"
    case contracts = "Verträge"
    case photos = "Fotos"
    case proofs = "Nachweise"

    var id: String { rawValue }
}

enum BaumioSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case projects = "Projekte"
    case trades = "Firmen"
    case schedule = "Termine"
    case diary = "Bautagebuch"
    case tasks = "Aufgaben"
    case materials = "Materialliste"
    case timeTracking = "Zeiterfassung"
    case handover = "Übergabe"
    case documents = "Dokumente"
    case costs = "Kosten"
    case offers = "Angebote"
    case defects = "Mängel"
    case funding = "Fördertracker"
    case taxes = "§35a Export"
    case reviews = "Bewertungen"
    case pricing = "Abo"
    case settings = "Einstellungen"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .projects: "building.2"
        case .trades: "hammer"
        case .schedule: "calendar"
        case .diary: "book.pages"
        case .tasks: "checklist"
        case .materials: "shippingbox"
        case .timeTracking: "clock"
        case .handover: "checkmark.seal"
        case .documents: "doc.text"
        case .costs: "eurosign.circle"
        case .offers: "doc.badge.clock"
        case .defects: "exclamationmark.triangle"
        case .funding: "leaf"
        case .taxes: "tray.and.arrow.down"
        case .reviews: "star"
        case .pricing: "crown"
        case .settings: "gearshape"
        }
    }

    /// Bereiche, die nur im Pro-Abo verfügbar sind (entsprechend der Preisliste).
    var requiresPro: Bool {
        switch self {
        case .defects, .funding, .taxes, .reviews, .offers, .timeTracking, .handover: true
        default: false
        }
    }
}

struct Project: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var address: String
    var startDate: Date
    var plannedEndDate: Date
    var budget: Decimal
    var description: String
    var status: ProjectStatus
    var progress: Double
    /// Vom Backend berechneter Kosten-Fortschritt (bezahlt/geplant in %).
    var progressByCosts: Int = 0
    /// Finanzierungsübersicht – Eigenkapital und Baudarlehen (separat von Budget).
    var eigenkapital: Decimal = 0
    var kredit: Decimal = 0
    /// Supabase user_id des Projektbesitzers – nil bedeutet eigenes Projekt (Demo-Modus).
    var ownerUserID: UUID? = nil
    var floorPlanPath: String? = nil
    /// Zeitpunkt der finalen Protokoll-Unterschrift. Wenn gesetzt → Protokoll ist gesperrt.
    var handoverSignedAt: Date? = nil
    var handoverSig1Path: String? = nil
    var handoverSig2Path: String? = nil
}

struct Trade: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var company: String
    var tradeType: String = ""
    var address: String = ""
    var phone: String = ""
    var email: String = ""
    var status: WorkStatus
    var costs: Decimal
    var budget: Decimal = 0
    var notes: String
    var rating: Int
    var progress: Int = 0
}

struct ScheduleItem: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var durationDays: Int
    var status: WorkStatus
    var trade: String
    var notes: String
    var dependsOn: UUID? = nil
    var startTime: Date? = nil
    var endTime: Date? = nil
}

struct DiaryEntry: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var weather: String
    var companies: [String]
    var completedWork: String
    var issues: String
    var photosCount: Int
    var notes: String
}

struct TaskItem: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var priority: Priority
    var dueDate: Date
    var trade: String
    var isDone: Bool
}

struct MaterialItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var quantity: Decimal
    var unit: String
    var supplier: String
    var articleNumber: String
    var price: Decimal
    var deliveryStatus: String
    var trade: String
    var notes: String
    var fundingItemID: UUID? = nil
    var url: String = ""
}

struct PhotoRef: Identifiable, Hashable {
    var id = UUID()
    var storagePath: String
}

struct DocumentItem: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var category: DocumentCategory
    var uploadDate: Date
    var fileType: String
    var storagePath: String = ""
    var fileSize: Int = 0
}

struct CostItem: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var planned: Decimal
    var ordered: Decimal
    var paid: Decimal
    var category: String
    var status: String
    var trade: String
    var invoiceReference: String
    var notes: String = ""
    var fundingItemID: UUID? = nil
    var invoiceDate: Date? = nil
    var dueDate: Date? = nil
    var laborAmount: Decimal = 0
    var machineAmount: Decimal = 0
    var travelAmount: Decimal = 0
    var warrantyEnd: Date? = nil
    var paymentDate: Date? = nil
    var supplier: String = ""
}

extension CostItem {
    /// Material-Anteil = Gesamtbetrag minus explizit erfasste Dienstleistungskosten.
    var materialAmount: Decimal {
        let explicit = laborAmount + machineAmount + travelAmount
        return explicit > 0 ? max(planned - explicit, 0) : planned
    }
    /// §35a-relevanter Betrag: explizite Arbeits-/Maschinen-/Fahrtkosten, oder bei Kategorie "Lohn" der Gesamtbetrag.
    var taxRelevantAmount: Decimal {
        let explicit = laborAmount + machineAmount + travelAmount
        if explicit > 0 { return explicit }
        return category == "Lohn" ? planned : 0
    }
    var isInvoice: Bool { invoiceDate != nil || laborAmount > 0 || machineAmount > 0 || travelAmount > 0 }
}

struct OfferItem: Identifiable, Hashable {
    var id = UUID()
    var provider: String
    var amount: Decimal
    var trade: String
    var status: String
    var title: String = ""
    var validUntil: Date? = nil
    var notes: String = ""
    var fundingItemID: UUID? = nil
    var scope: String = ""
}

struct FloorPlan: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var projectID: UUID
    var label: String
    var storagePath: String
    var sortOrder: Int = 0
}

struct DefectItem: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var description: String
    var trade: String
    var responsible: String
    var deadline: Date
    var status: String
    var priority: Priority
    var severity: String = "mäßig"
    var importance: String = "wichtig"
    var pinX: Double? = nil
    var pinY: Double? = nil
    var floorPlanID: UUID? = nil
}

enum TimeLogCategory: String, CaseIterable, Identifiable {
    case planung = "Planung"
    case software = "Software"
    case termin = "Vor-Ort-Termin"
    case behoerde = "Behörde"
    case handwerk = "Handwerk"
    case sonstiges = "Sonstiges"

    var id: String { rawValue }

    /// Supabase-Rohwert der Kategorie.
    var supabaseValue: String {
        switch self {
        case .planung: "planung"
        case .software: "software"
        case .termin: "termin"
        case .behoerde: "behoerde"
        case .handwerk: "handwerk"
        case .sonstiges: "sonstiges"
        }
    }

    init(supabaseValue: String?) {
        switch supabaseValue {
        case "planung": self = .planung
        case "software": self = .software
        case "termin": self = .termin
        case "behoerde": self = .behoerde
        case "handwerk": self = .handwerk
        default: self = .sonstiges
        }
    }
}

enum HandoverStatus: String, CaseIterable, Identifiable {
    case offen = "Offen"
    case akzeptiert = "Akzeptiert"
    case vorbehalt = "Unter Vorbehalt"
    case abgelehnt = "Abgelehnt"

    var id: String { rawValue }

    var supabaseValue: String {
        switch self {
        case .offen: "offen"
        case .akzeptiert: "akzeptiert"
        case .vorbehalt: "vorbehalt"
        case .abgelehnt: "abgelehnt"
        }
    }

    init(supabaseValue: String?) {
        switch supabaseValue {
        case "akzeptiert": self = .akzeptiert
        case "vorbehalt": self = .vorbehalt
        case "abgelehnt": self = .abgelehnt
        default: self = .offen
        }
    }
}

struct HandoverItem: Identifiable, Hashable {
    var id = UUID()
    var item: String
    var room: String
    var tradeType: String
    var status: HandoverStatus
    var isDone: Bool
    var notes: String
    var signatureURL: String? = nil
}

struct DefectComment: Identifiable, Hashable {
    var id = UUID()
    var defectID: UUID
    var text: String
    var author: String
    var createdAt: Date
}

struct TimeLogItem: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var category: TimeLogCategory
    var date: Date
    var durationMinutes: Int
    var notes: String
}

enum FundingProgramType: String, CaseIterable, Identifiable {
    case heizungsfoerderungBEG = "beg_em"
    case kfwKredit261 = "kfw_261"
    case kfwZuschuss455 = "kfw_455"
    case sonstige = ""

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heizungsfoerderungBEG: "Heizungsförderung BEG EM"
        case .kfwKredit261: "KfW Kredit 261"
        case .kfwZuschuss455: "KfW Zuschuss 455"
        case .sonstige: "Sonstige / Eigene"
        }
    }

    var shortName: String {
        switch self {
        case .heizungsfoerderungBEG: "BEG EM"
        case .kfwKredit261: "KfW 261"
        case .kfwZuschuss455: "KfW 455"
        case .sonstige: "Sonstige"
        }
    }

    var programDescription: String {
        switch self {
        case .heizungsfoerderungBEG: "Klimafreundliche Heizungen (Wärmepumpe, Biomasse, Wärmenetz) – ab 21.07.2026: Grundförderung 30 %, Klimabonus +16 %, Einkommensbonus +10–40 %, max. 28.000 € Zuschuss (BAFA/KfW)"
        case .kfwKredit261: "Sanierung zum KfW-Effizienzhaus – Kredit bis 150.000 €, Tilgungszuschuss bis 45 % (max. 67.500 €)"
        case .kfwZuschuss455: "Energetische Einzelmaßnahmen (Fenster, Fassade, Dach, Heizung) – Zuschuss bis 20 % der förderfähigen Kosten"
        case .sonstige: "Eigenes Förderprogramm oder Zuschuss frei eintragen"
        }
    }

    var defaultProvider: String {
        switch self {
        case .heizungsfoerderungBEG: "BAFA / KfW"
        case .kfwKredit261: "KfW"
        case .kfwZuschuss455: "KfW"
        case .sonstige: ""
        }
    }

    var defaultMaxAmount: Decimal {
        switch self {
        case .heizungsfoerderungBEG: 28000
        case .kfwKredit261: 150000
        case .kfwZuschuss455: 0
        case .sonstige: 0
        }
    }

    var defaultGrantRate: Int {
        switch self {
        case .heizungsfoerderungBEG: 30
        case .kfwKredit261: 45
        case .kfwZuschuss455: 20
        case .sonstige: 0
        }
    }

    /// Ob dieses Programm die 4 KfW-BEG-Boni-Toggles verwendet.
    var usesBEGBoni: Bool { self == .heizungsfoerderungBEG }

    init(stored: String?) {
        switch stored {
        case "beg_em": self = .heizungsfoerderungBEG
        case "kfw_261": self = .kfwKredit261
        case "kfw_455": self = .kfwZuschuss455
        default: self = .sonstige
        }
    }
}

struct FundingItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var provider: String
    var amount: Decimal          // berechneter Förderbetrag (wird in Supabase gespeichert)
    var status: String
    var deadline: Date?          // Antragsfrist
    var referenceNumber: String
    var notes: String            // reine Nutzernotizen
    var maxAmount: Decimal = 0
    var documentDeadline: Date? = nil
    var kfwGrundfoerderung: Bool = false
    var kfwKlimabonus: Bool = false
    var kfwEinkommensbonus: Bool = false
    var kfwEffizienzbonus: Bool = false
    var programType: FundingProgramType = .sonstige
    var manualGrantRate: Int? = nil  // für KfW 261 und 455 (kein BEG-Boni-System)
}

extension FundingItem {
    // Neue BEG-Konditionen ab 21.07.2026 (KfW-Pressemitteilung 08.07.2026).
    // Einkommensbonus wird als 2-Bit im Paar (kfwEinkommensbonus, kfwEffizienzbonus) kodiert:
    //   (false, false) = 0 %  |  (false, true) = +10 % (≤ 50.000 €)
    //   (true, false)  = +30 % (≤ 40.000 €)  |  (true, true) = +40 % (≤ 30.000 €)
    var kfwFoerdersatz: Int {
        if let r = manualGrantRate, r > 0 { return min(r, 100) }
        var pct = 0
        if kfwGrundfoerderung { pct += 30 }
        if kfwKlimabonus      { pct += 16 }  // Klimageschwindigkeitsbonus (ab 01.02.2027 sinkend)
        if kfwEinkommensbonus && kfwEffizienzbonus  { pct += 40 }   // ≤ 30.000 €
        else if kfwEinkommensbonus                  { pct += 30 }   // ≤ 40.000 €
        else if kfwEffizienzbonus                   { pct += 10 }   // ≤ 50.000 €
        return pct  // kein pauschaler 70 %-Deckel mehr
    }
    var estimatedRefund: Decimal {
        guard maxAmount > 0, kfwFoerdersatz > 0 else { return amount }
        return maxAmount * Decimal(kfwFoerdersatz) / 100
    }
    var hasKfWData: Bool { maxAmount > 0 || kfwGrundfoerderung || kfwKlimabonus || kfwEinkommensbonus || kfwEffizienzbonus || manualGrantRate != nil }
}

struct ReviewItem: Identifiable, Hashable {
    var id = UUID()
    var company: String
    var trade: String
    var stars: Int
    var notes: String
    var recommended: Bool
    var quality: Int = 0
    var punctuality: Int = 0
    var communication: Int = 0
    var pricePerformance: Int = 0
}

enum MemberRole: String, CaseIterable, Identifiable {
    case viewer = "viewer"
    case editor = "editor"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .viewer: "Leserecht"
        case .editor: "Vollzugriff"
        }
    }
}

enum MemberStatus: String {
    case pending = "pending"
    case accepted = "accepted"
}

struct ProjectMember: Identifiable, Hashable {
    var id: UUID
    var projectID: UUID
    var invitedEmail: String
    var role: MemberRole
    var status: MemberStatus
    var invitedBy: UUID?
    var projectName: String = ""
}

struct PricingPlan: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var planType: String = ""
    var price: String
    var subtitle: String
    var features: [PricingFeature]
    var buttonTitle: String
    var buttonSystemImage: String = "person.fill.checkmark"
    var isHighlighted: Bool
}

struct PricingFeature: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var isIncluded: Bool
}
