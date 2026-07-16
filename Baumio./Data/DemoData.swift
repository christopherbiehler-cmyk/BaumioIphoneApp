import Foundation

enum DemoData {
    static let projects: [Project] = []
    static let trades: [Trade] = []
    static let schedule: [ScheduleItem] = []
    static let diary: [DiaryEntry] = []
    static let tasks: [TaskItem] = []
    static let materials: [MaterialItem] = []
    static let documents: [DocumentItem] = []
    static let costs: [CostItem] = []
    static let offers: [OfferItem] = []
    static let defects: [DefectItem] = []
    static let funding: [FundingItem] = []
    static let reviews: [ReviewItem] = []

    static let pricingPlans: [PricingPlan] = [
        PricingPlan(
            name: "Starter",
            price: "0 €",
            subtitle: "Für den Einstieg mit einem Projekt.",
            features: [
                PricingFeature(title: "1 Projekt", isIncluded: true),
                PricingFeature(title: "Bis zu 5 Firmen", isIncluded: true),
                PricingFeature(title: "Termine & Zeitstrahl", isIncluded: true),
                PricingFeature(title: "Bautagebuch & Materialliste", isIncluded: true),
                PricingFeature(title: "Dokumente hochladen", isIncluded: true),
                PricingFeature(title: "Mängel-Matrix", isIncluded: false),
                PricingFeature(title: "KfW Fördertracker", isIncluded: false),
                PricingFeature(title: "§35a EStG Export", isIncluded: false)
            ],
            buttonTitle: "Kostenlos starten",
            isHighlighted: false
        ),
        PricingPlan(
            name: "Pro",
            planType: "pro",
            price: "8,99 € / Monat",
            subtitle: "14 Tage kostenlos testen, danach monatlich kündbar über Apple-Abos.",
            features: [
                PricingFeature(title: "§35a: Bis zu 1.200 € Steuern sparen (PDF-Export)", isIncluded: true),
                PricingFeature(title: "KfW 261 / 455 & BAFA BEG EM: Förderungen bis 28.000 € nicht verpassen", isIncluded: true),
                PricingFeature(title: "Baumängel-Matrix (Berliner Standard) + PDF", isIncluded: true),
                PricingFeature(title: "Bauzeitenplan als PDF für Behörden & Architekten", isIncluded: true),
                PricingFeature(title: "Angebots-Vergleich – günstigsten Handwerker finden", isIncluded: true),
                PricingFeature(title: "Handwerker bewerten & Übergabeprotokoll", isIncluded: true),
                PricingFeature(title: "2 Projektmitglieder einladen (Architekten, Partner)", isIncluded: true),
                PricingFeature(title: "Unbegrenzte Projekte & Gewerke · 5 GB Speicher", isIncluded: true)
            ],
            buttonTitle: "14 Tage kostenlos testen",
            isHighlighted: true
        ),
        PricingPlan(
            name: "Business",
            planType: "business",
            price: "24,99 € / Monat",
            subtitle: "Für Vermieter & Gewerbetreibende mit Teams und mehreren Objekten.",
            features: [
                PricingFeature(title: "Alles aus Pro", isIncluded: true),
                PricingFeature(title: "Unbegrenzte Projektmitglieder", isIncluded: true),
                PricingFeature(title: "Team-Übersicht aller Projekte", isIncluded: true),
                PricingFeature(title: "Architekten, Bauleiter & Partner einladen", isIncluded: true),
                PricingFeature(title: "Prioritäts-Support", isIncluded: true)
            ],
            buttonTitle: "Kontakt aufnehmen",
            buttonSystemImage: "envelope.fill",
            isHighlighted: false
        )
    ]
}
