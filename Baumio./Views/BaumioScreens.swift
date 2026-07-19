import SwiftUI
import Charts
import AuthenticationServices
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import StoreKit
import EventKit
import CoreLocation
import Contacts
import ContactsUI
import Combine
import PencilKit

// MARK: – CSV-Export-Hilfsfunktion

private func csvURL(_ rows: [[String]], fileName: String) -> URL? {
    let escaped: [[String]] = rows.map { row in
        row.map { cell in
            let clean = cell.replacingOccurrences(of: "\"", with: "\"\"")
            return (clean.contains(";") || clean.contains("\"") || clean.contains("\n")) ? "\"\(clean)\"" : clean
        }
    }
    let body = escaped.map { $0.joined(separator: ";") }.joined(separator: "\n")
    let content = "sep=;\n" + body
    guard let data = content.data(using: .utf8) else { return nil }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    try? data.write(to: url)
    return url
}

// MARK: – Wetter-Hilfsfunktionen (Open-Meteo, kein API-Key nötig)

private final class LocationFetcher: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func fetchLocation() async -> CLLocation? {
        manager.requestWhenInUseAuthorization()
        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.first)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

private func wmoCodeToGerman(_ code: Int) -> String {
    switch code {
    case 0:            return "sonnig"
    case 1, 2:         return "leicht bewölkt"
    case 3:            return "bewölkt"
    case 45, 48:       return "nebelig"
    case 51...65:      return "regnerisch"
    case 80...82:      return "regnerisch"
    case 71...77:      return "schnee"
    case 85, 86:       return "schnee"
    case 95, 96, 99:   return "sturm"
    default:           return "bewölkt"
    }
}

private func fetchCurrentWeather() async -> (weather: String, temp: String)? {
    let fetcher = LocationFetcher()
    guard let location = await fetcher.fetchLocation() else { return nil }
    let lat = location.coordinate.latitude, lon = location.coordinate.longitude
    guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current_weather=true"),
          let (data, _) = try? await URLSession.shared.data(from: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cw = json["current_weather"] as? [String: Any],
          let code = cw["weathercode"] as? Int,
          let temp = cw["temperature"] as? Double else { return nil }
    return (wmoCodeToGerman(code), "\(Int(temp.rounded()))")
}

// MARK: – Kontakt-Import

private struct ContactPickerView: UIViewControllerRepresentable {
    let onSelect: (CNContact) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerView
        init(_ parent: ContactPickerView) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onSelect(contact)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}
    }
}

struct ContactImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: BaumioAppViewModel
    @State private var showingContactPicker = false
    @State private var name = ""
    @State private var company = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var tradeType = ""
    private let tradeTypes = ["", "Elektriker", "Sanitär", "Maler", "Zimmermann", "Dachdecker",
                              "Fliesenleger", "Heizung", "Statiker", "Architekt", "Sonstiges"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingContactPicker = true
                    } label: {
                        Label("Kontakt aus Adressbuch wählen", systemImage: "person.crop.circle.badge.plus")
                    }
                    .foregroundStyle(BaumioTheme.accent)
                }
                Section("Firmendetails") {
                    TextField("Ansprechpartner", text: $name)
                    TextField("Firma / Unternehmen", text: $company)
                    Picker("Gewerk", selection: $tradeType) {
                        ForEach(tradeTypes, id: \.self) {
                            Text($0.isEmpty ? "Kein Gewerk" : $0).tag($0)
                        }
                    }
                }
                if !phone.isEmpty || !email.isEmpty || !address.isEmpty {
                    Section("Importierte Kontaktdaten") {
                        if !phone.isEmpty { Label(phone, systemImage: "phone").foregroundStyle(BaumioTheme.secondaryText) }
                        if !email.isEmpty { Label(email, systemImage: "envelope").foregroundStyle(BaumioTheme.secondaryText) }
                        if !address.isEmpty { Label(address, systemImage: "mappin").foregroundStyle(BaumioTheme.secondaryText) }
                    }
                }
            }
            .navigationTitle("Kontakt importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        model.handle { try await model.createTrade(name: name, company: company, tradeType: tradeType, address: address, phone: phone, email: email, notes: "") }
                        dismiss()
                    }
                    .disabled(name.isEmpty && company.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingContactPicker) {
            ContactPickerView { contact in
                name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                company = contact.organizationName
                phone = contact.phoneNumbers.first?.value.stringValue ?? ""
                email = contact.emailAddresses.first?.value as String? ?? ""
                if let addr = contact.postalAddresses.first?.value {
                    address = [addr.street, addr.postalCode, addr.city].filter { !$0.isEmpty }.joined(separator: " ")
                }
            }
        }
    }
}

// MARK: – App-Tour (nach erstem Login, einmalig)

private struct TourSlide {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let bullets: [String]
}

struct ProjectSetupWizardView: View {
    @Bindable var model: BaumioAppViewModel
    @Binding var isPresented: Bool
    @State private var step = 0
    @State private var projectName = ""
    @State private var address = ""
    @State private var budgetText = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
    @State private var isCreating = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 3)
                    .progressViewStyle(.linear)
                    .tint(BaumioTheme.accent)
                    .padding(.horizontal)
                    .padding(.top, 8)

                TabView(selection: $step) {
                    step1.tag(0)
                    step2.tag(1)
                    step3.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: step)
                .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Projekt einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Überspringen") { isPresented = false }
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
            }
            .background(BaumioTheme.background)
        }
        .preferredColorScheme(.dark)
    }

    private var step1: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(BaumioTheme.accent)
                    Text("Wie heißt dein Bauprojekt?")
                        .font(.title2.bold())
                        .foregroundStyle(BaumioTheme.primaryText)
                    Text("Gib deinem Projekt einen Namen — z. B. \"Dachgeschossausbau\" oder \"Sanierung EG\".")
                        .font(.subheadline)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 12) {
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Projektname", systemImage: "pencil")
                                .font(.caption.bold())
                                .foregroundStyle(BaumioTheme.secondaryText)
                            TextField("z. B. Umbau Erdgeschoss", text: $projectName)
                                .foregroundStyle(BaumioTheme.primaryText)
                        }
                    }
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Adresse (optional)", systemImage: "mappin")
                                .font(.caption.bold())
                                .foregroundStyle(BaumioTheme.secondaryText)
                            TextField("Musterstraße 1, 12345 Stadt", text: $address)
                                .foregroundStyle(BaumioTheme.primaryText)
                        }
                    }
                }

                PrimaryButton(title: "Weiter", systemImage: "arrow.right") {
                    withAnimation { step = 1 }
                }
                .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }

    private var step2: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "eurosign.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(BaumioTheme.accent)
                    Text("Budget & Zeitrahmen")
                        .font(.title2.bold())
                        .foregroundStyle(BaumioTheme.primaryText)
                    Text("Wie viel planst du auszugeben, und wann soll es fertig sein?")
                        .font(.subheadline)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 12) {
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Geplantes Budget (€)", systemImage: "eurosign")
                                .font(.caption.bold())
                                .foregroundStyle(BaumioTheme.secondaryText)
                            TextField("z. B. 50000", text: $budgetText)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(BaumioTheme.primaryText)
                        }
                    }
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Startdatum", systemImage: "calendar")
                                .font(.caption.bold())
                                .foregroundStyle(BaumioTheme.secondaryText)
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }
                    }
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Geplantes Ende", systemImage: "flag.checkered")
                                .font(.caption.bold())
                                .foregroundStyle(BaumioTheme.secondaryText)
                            DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }
                    }
                }

                HStack(spacing: 12) {
                    SecondaryButton(title: "Zurück", systemImage: "arrow.left") {
                        withAnimation { step = 0 }
                    }
                    PrimaryButton(title: "Weiter", systemImage: "arrow.right") {
                        withAnimation { step = 2 }
                    }
                }
            }
            .padding()
        }
    }

    private var step3: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(BaumioTheme.success)
                    Text("Alles bereit!")
                        .font(.title2.bold())
                        .foregroundStyle(BaumioTheme.primaryText)
                    Text("Hier eine Übersicht deines neuen Projekts.")
                        .font(.subheadline)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
                .padding(.top, 24)

                BaumioCard {
                    VStack(alignment: .leading, spacing: 10) {
                        summaryRow(icon: "building.2", label: "Projekt", value: projectName)
                        if !address.isEmpty {
                            summaryRow(icon: "mappin", label: "Adresse", value: address)
                        }
                        if let budget = Decimal(string: budgetText.replacingOccurrences(of: ",", with: ".")) {
                            summaryRow(icon: "eurosign", label: "Budget", value: budget.formatted(.currency(code: "EUR")))
                        }
                        summaryRow(icon: "calendar", label: "Start", value: startDate.formatted(date: .abbreviated, time: .omitted))
                        summaryRow(icon: "flag.checkered", label: "Geplantes Ende", value: endDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }

                HStack(spacing: 12) {
                    SecondaryButton(title: "Zurück", systemImage: "arrow.left") {
                        withAnimation { step = 1 }
                    }
                    PrimaryButton(title: isCreating ? "Erstelle …" : "Projekt erstellen", systemImage: "plus.circle.fill") {
                        Task {
                            isCreating = true
                            let budget = Decimal(string: budgetText.replacingOccurrences(of: ",", with: ".")) ?? 0
                            try? await model.createProject(name: projectName, budget: budget, status: .active, description: address.isEmpty ? nil : address)
                            isCreating = false
                            isPresented = false
                        }
                    }
                    .disabled(isCreating)
                }
            }
            .padding()
        }
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(BaumioTheme.accent)
            Text(label)
                .foregroundStyle(BaumioTheme.secondaryText)
                .font(.subheadline)
            Spacer()
            Text(value)
                .foregroundStyle(BaumioTheme.primaryText)
                .font(.subheadline.bold())
                .multilineTextAlignment(.trailing)
        }
    }
}

struct AppTourView: View {
    @AppStorage("hasSeenAppTour") private var hasSeenAppTour = false
    @Binding var isPresented: Bool
    @State private var page = 0

    private let slides: [TourSlide] = [
        TourSlide(
            icon: "building.2.crop.circle.fill",
            iconColor: BaumioTheme.accent,
            title: "Willkommen bei Baumio",
            subtitle: "Dein digitaler Bauhelfer – von der ersten Planung bis zur Abnahme.",
            bullets: [
                "Projekte, Kosten und Termine zentral verwalten",
                "Bautagebuch und Dokumente immer dabei",
                "Deutsch, datenschutzfreundlich, kein Tracking"
            ]
        ),
        TourSlide(
            icon: "checklist.checked",
            iconColor: BaumioTheme.info,
            title: "So startest du",
            subtitle: "In drei Schritten bist du startklar:",
            bullets: [
                "1. Projekt anlegen – unter ‹Projekte› oben rechts",
                "2. Gewerke und Termine eintragen",
                "3. Kosten, Rechnungen und Dokumente erfassen"
            ]
        ),
        TourSlide(
            icon: "star.circle.fill",
            iconColor: .orange,
            title: "Pro-Features",
            subtitle: "Mit Baumio Pro holst du noch mehr raus:",
            bullets: [
                "KfW & BAFA Fördertracker – bis 28.000 €",
                "§35a Export – bis 1.200 € Steuern sparen",
                "Mängelverwaltung & Übergabeprotokoll",
                "Angebotsvergleich & Bauleiter einladen"
            ]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Überspringen") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(BaumioTheme.secondaryText)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { i in
                    tourSlide(slides[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.easeInOut, value: page)

            VStack(spacing: 12) {
                if page < slides.count - 1 {
                    PrimaryButton(title: "Weiter", systemImage: "arrow.right") {
                        withAnimation { page += 1 }
                    }
                } else {
                    PrimaryButton(title: "Los geht's!", systemImage: "checkmark") {
                        finish()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .baumioBackground()
    }

    private func tourSlide(_ slide: TourSlide) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: slide.icon)
                    .font(.system(size: 72))
                    .foregroundStyle(slide.iconColor)
                    .padding(.top, 32)

                VStack(spacing: 8) {
                    Text(slide.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(BaumioTheme.primaryText)
                        .multilineTextAlignment(.center)
                    Text(slide.subtitle)
                        .font(.body)
                        .foregroundStyle(BaumioTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                BaumioCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(slide.bullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(BaumioTheme.success)
                                    .font(.body)
                                Text(bullet)
                                    .font(.subheadline)
                                    .foregroundStyle(BaumioTheme.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func finish() {
        hasSeenAppTour = true
        isPresented = false
    }
}

struct OnboardingView: View {
    @Bindable var model: BaumioAppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                BrandHeader()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Willkommen bei Baumio")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(BaumioTheme.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text("Dein digitaler Bauhelfer für Projekte, Kosten, Termine und Dokumente.")
                        .font(.title3)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }

                BaumioCard {
                    VStack(alignment: .leading, spacing: 12) {
                        FeatureRow(title: "Alle Bauprojekte strukturiert verwalten")
                        FeatureRow(title: "Dokumente, Kosten und Mängel an einem Ort")
                        FeatureRow(title: "Deutsch, datenschutzfreundlich und ohne Tracking")
                    }
                }

                VStack(spacing: 12) {
                    PrimaryButton(title: "Kostenlos starten", systemImage: "arrow.right", action: model.startFree)
                    SecondaryButton(title: "Einloggen", systemImage: "person.crop.circle", action: model.showLogin)
                    AppleSignInButton(model: model)
                }

                Text("Baumio ist vollständig auf Deutsch vorbereitet. Personenbezogene Daten werden erst verarbeitet, wenn du dich aktiv anmeldest oder später ein Backend verbindest.")
                    .font(.footnote)
                    .foregroundStyle(BaumioTheme.secondaryText)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .baumioBackground()
    }
}

/// Wiederverwendbarer „Sign in with Apple"-Button inkl. Nonce-Handling.
struct AppleSignInButton: View {
    @Bindable var model: BaumioAppViewModel
    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            let raw = AppleSignInSupport.randomNonceString()
            nonce = raw
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInSupport.sha256(raw)
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 48)
        .accessibilityLabel("Mit Apple anmelden")
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                model.authError = "Apple-Anmeldung fehlgeschlagen: Es wurde kein gültiges Token empfangen."
                return
            }
            Task { await model.signInWithApple(idToken: token, nonce: nonce) }
        case .failure(let error):
            let code = (error as? ASAuthorizationError)?.code
            // Abbruch durch den Nutzer nicht als Fehler anzeigen.
            if code == .canceled { return }
            // Error 1000 (unknown): Sign in with Apple nicht für diese App aktiviert,
            // oder kein Apple-Account im Simulator. Auf echten Geräten zeigt das OS selbst einen Hinweis.
            if code == .unknown { return }
            model.authError = "Apple-Anmeldung fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

struct AuthView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var mode: AuthMode = .login

    enum AuthMode: String, CaseIterable, Identifiable {
        case login = "Einloggen"
        case register = "Registrieren"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    BrandHeader()
                    SectionHeader(
                        title: mode == .login ? "Einloggen" : "Registrierung",
                        subtitle: model.usesSupabase ? "Melde dich an, um deine Projektdaten zu laden." : "Supabase Auth ist vorbereitet. Aktuell nutzt Baumio lokale Demo-Daten."
                    )

                    Picker("Modus", selection: $mode) {
                        ForEach(AuthMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Anmeldeart")

                    BaumioCard {
                        VStack(alignment: .leading, spacing: 14) {
                            TextField("E-Mail", text: $model.email)
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled()
                                .accessibilityLabel("E-Mail-Adresse")
                            SecureField("Passwort", text: $model.password)
                                .textContentType(mode == .login ? .password : .newPassword)
                                .accessibilityLabel("Passwort")

                            if let authError = model.authError {
                                Text(authError)
                                    .font(.footnote)
                                    .foregroundStyle(BaumioTheme.warning)
                            }

                            if let authInfo = model.authInfo {
                                Text(authInfo)
                                    .font(.footnote)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }

                            PrimaryButton(title: mode.rawValue, systemImage: "person.fill") {
                                Task {
                                    if mode == .login {
                                        await model.login()
                                    } else {
                                        await model.register()
                                    }
                                }
                            }

                            Button("Passwort vergessen") {
                                model.resetPassword()
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(BaumioTheme.accent)
                            .frame(minHeight: 44, alignment: .leading)
                            .accessibilityLabel("Passwort vergessen")
                        }
                    }

                    VStack(spacing: 10) {
                        Text("oder")
                            .font(.footnote)
                            .foregroundStyle(BaumioTheme.secondaryText)
                        AppleSignInButton(model: model)
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Baumio")
            .baumioBackground()
        }
    }
}

struct DashboardView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var bauberichtExport: ShareableURL?

    private var projectSelection: Binding<UUID?> {
        Binding(
            get: { model.selectedProject?.id },
            set: { newValue in
                guard let newValue, let project = model.projects.first(where: { $0.id == newValue }) else { return }
                model.selectProject(project)
            }
        )
    }

    var body: some View {
        ScreenScaffold(title: "Dashboard", subtitle: model.selectedProject?.name, onRefresh: { await model.reload() }) {
            if !model.projects.isEmpty {
                BaumioCard {
                    Picker("Projekt", selection: projectSelection) {
                        ForEach(model.projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Projekt auswählen")
                }
            }

            if !model.pendingInvites.isEmpty {
                Button {
                    model.selectedSection = .settings
                } label: {
                    BaumioCard {
                        HStack(spacing: 12) {
                            Image(systemName: "person.badge.plus")
                                .font(.title2)
                                .foregroundStyle(BaumioTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(model.pendingInvites.count) offene Projekteinladung\(model.pendingInvites.count == 1 ? "" : "en")")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(BaumioTheme.primaryText)
                                Text("Tippe um einzuladen oder abzulehnen")
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(BaumioTheme.secondaryText)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: BaumioTheme.cardRadius, style: .continuous)
                            .stroke(BaumioTheme.accent, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
            }

            if let project = model.selectedProject {
                BaumioCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Aktuelles Projekt")
                                    .font(.caption.bold())
                                    .foregroundStyle(BaumioTheme.secondaryText)
                                Text(project.name)
                                    .font(.title2.bold())
                                    .foregroundStyle(BaumioTheme.primaryText)
                                Text(project.address)
                                    .font(.subheadline)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                            Spacer()
                            StatusBadge(title: project.status.rawValue, color: BaumioTheme.success)
                        }
                        ProgressView(value: Double(model.overallProgress) / 100)
                            .tint(BaumioTheme.accent)
                            .accessibilityLabel("Projektfortschritt")
                            .accessibilityValue("\(model.overallProgress) Prozent")
                        Text("\(model.overallProgress) % abgeschlossen")
                            .font(.footnote)
                            .foregroundStyle(BaumioTheme.secondaryText)
                    }
                }

                ProjectProgressCard(model: model)

                if !model.costs.isEmpty {
                    BudgetChartCard(model: model)
                }

                AdaptiveGrid(minimum: 170) {
                    DashboardMetricCard(title: "Projektfortschritt", value: "\(Int(project.progress * 100)) %", subtitle: "Projektwert", systemImage: "chart.line.uptrend.xyaxis")
                    DashboardMetricCard(title: "Kostenübersicht", value: model.orderedCosts.euroString, subtitle: "von \(project.budget.euroString) Budget", systemImage: "eurosign.circle", tint: BaumioTheme.info)
                    DashboardMetricCard(title: "Nächste Termine", value: "\(model.schedule.filter { $0.date >= Date() }.count)", subtitle: "in der Zukunft", systemImage: "calendar", tint: BaumioTheme.accent)
                    DashboardMetricCard(title: "Offene Aufgaben", value: "\(model.openTasks.count)", subtitle: "aus deinen Daten", systemImage: "checklist", tint: BaumioTheme.success)
                    DashboardMetricCard(title: "Mängel", value: "\(model.openDefects.count)", subtitle: "aus deinen Daten", systemImage: "exclamationmark.triangle", tint: BaumioTheme.warning)
                    DashboardMetricCard(title: "Heute fällig", value: "\(model.dueTodayCount)", subtitle: model.dueTodayCount == 0 ? "alles erledigt" : "Aufgaben & Mängel", systemImage: model.dueTodayCount == 0 ? "checkmark.circle" : "bell.badge", tint: model.dueTodayCount == 0 ? BaumioTheme.success : BaumioTheme.danger)
                    DashboardMetricCard(title: "Dokumente", value: "\(model.documents.count)", subtitle: "aus deinen Daten", systemImage: "doc.text", tint: BaumioTheme.secondaryText)
                }
            } else {
                EmptyStateView(
                    title: "Noch kein Projekt angelegt",
                    message: "Erstelle dein erstes Bauprojekt unter \"Projekte\" – dann erscheinen hier alle Kennzahlen auf einen Blick.",
                    systemImage: "tray"
                )
            }

            if !model.documents.isEmpty {
                BaumioCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Zuletzt hochgeladene Dokumente")
                            .font(.headline)
                            .foregroundStyle(BaumioTheme.primaryText)
                        ForEach(model.documents.prefix(3)) { document in
                            ItemLine(icon: "doc.text", title: document.title, subtitle: "\(document.category.rawValue) · \(document.uploadDate.formatted(date: .abbreviated, time: .omitted))", tint: BaumioTheme.accent)
                        }
                    }
                }
            }

            if model.selectedProject != nil {
                QuickDefectCard(model: model)
            }

            if let project = model.selectedProject {
                SecondaryButton(title: "Baubericht exportieren", systemImage: "square.and.arrow.up") {
                    if let url = BauberichtPDFExporter.export(model: model, project: project) {
                        bauberichtExport = ShareableURL(url: url)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image("BaumioLogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 28)
                    .accessibilityHidden(true)
            }
        }
        .sheet(item: $bauberichtExport) { shareable in
            ShareSheet(items: [shareable.url])
        }
    }
}


private struct QuickDefectCard: View {
    @Bindable var model: BaumioAppViewModel
    @State private var title = ""
    @State private var showingFullEditor = false
    @FocusState private var focused: Bool

    var body: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Schnell-Mangel", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(BaumioTheme.warning)
                HStack(spacing: 8) {
                    TextField("Kurzbeschreibung …", text: $title)
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit { sendDefect() }
                    Button(action: sendDefect) {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(title.trimmingCharacters(in: .whitespaces).isEmpty ? BaumioTheme.secondaryText : BaumioTheme.warning)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .background(BaumioTheme.secondaryText.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("Detaillierter Mangel …") { showingFullEditor = true }
                    .font(.caption)
                    .foregroundStyle(BaumioTheme.accent)
            }
        }
        .sheet(isPresented: $showingFullEditor) {
            QuickAddView(kind: .defect, model: model)
        }
    }

    private func sendDefect() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.handle { try await model.createDefect(description: trimmed, severity: "mäßig", importance: "wichtig", status: "offen") }
        title = ""
        focused = false
    }
}

struct ProjectProgressCard: View {
    @Bindable var model: BaumioAppViewModel

    var body: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Projektfortschritt", systemImage: "chart.bar.fill")
                        .font(.headline)
                        .foregroundStyle(BaumioTheme.primaryText)
                    Spacer()
                    Text("\(model.overallProgress) %")
                        .font(.title3.bold())
                        .foregroundStyle(BaumioTheme.primaryText)
                }
                ProgressBarRow(label: "Aufgaben", value: model.progressTasks, color: BaumioTheme.info)
                ProgressBarRow(label: "Kosten", value: model.progressCosts, color: BaumioTheme.success)
                ProgressBarRow(label: "Material", value: model.progressMaterials, color: BaumioTheme.accent)
                ProgressBarRow(label: "Zeitplan", value: model.progressTimeline, color: Color(hex: "A855F7"))

                HStack {
                    Label("Zeit-Erfassung", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(BaumioTheme.secondaryText)
                    Spacer()
                    Text(model.totalTrackedTimeText)
                        .font(.subheadline.bold())
                        .foregroundStyle(BaumioTheme.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Erfasste Zeit gesamt: \(model.totalTrackedTimeText)")
            }
        }
    }
}

struct BudgetChartCard: View {
    @Bindable var model: BaumioAppViewModel

    private struct ChartEntry: Identifiable {
        let id = UUID()
        let label: String
        let value: Decimal
        let color: Color
    }

    private var entries: [ChartEntry] {
        [
            ChartEntry(label: "Budget", value: model.selectedProject?.budget ?? 0, color: BaumioTheme.secondaryText.opacity(0.6)),
            ChartEntry(label: "Geplant", value: model.plannedCosts, color: BaumioTheme.info),
            ChartEntry(label: "Bestellt", value: model.orderedCosts, color: BaumioTheme.accent),
            ChartEntry(label: "Bezahlt", value: model.paidCosts, color: BaumioTheme.success)
        ]
    }

    var body: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Kostenübersicht", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(BaumioTheme.primaryText)

                Chart(entries) { entry in
                    BarMark(
                        x: .value("Kategorie", entry.label),
                        y: .value("Betrag", NSDecimalNumber(decimal: entry.value).doubleValue)
                    )
                    .foregroundStyle(entry.color)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(Decimal(d).euroString)
                                    .font(.caption2)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                        }
                        AxisGridLine().foregroundStyle(BaumioTheme.border)
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel().foregroundStyle(BaumioTheme.secondaryText)
                    }
                }
                .frame(height: 160)
            }
        }
    }
}

struct ProgressBarRow: View {
    var label: String
    var value: Int
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(BaumioTheme.secondaryText)
                Spacer()
                Text("\(value) %")
                    .font(.subheadline.bold())
                    .foregroundStyle(BaumioTheme.primaryText)
            }
            ProgressView(value: Double(min(max(value, 0), 100)) / 100)
                .tint(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) Prozent")
    }
}

struct ProjectsView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingProject: Project?
    @State private var deletingProject: Project?

    var body: some View {
        ScreenScaffold(title: "Projekte", subtitle: "Projekt anlegen, bearbeiten und Status verfolgen") {
            if !model.canCreateProject {
                Button { model.selectedSection = .pricing } label: {
                    BaumioCard {
                        HStack {
                            Image(systemName: "crown.fill").foregroundStyle(BaumioTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unbegrenzte Projekte mit Baumio Pro")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(BaumioTheme.primaryText)
                                Text("Free-Plan: 1 Projekt · \(model.store.proDisplayPrice)/Monat")
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(BaumioTheme.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                PrimaryButton(title: "Projekt anlegen", systemImage: "plus", action: { showingEditor = true })
            }

            if model.projects.isEmpty {
                EmptyStateView(
                    title: "Keine Projekte vorhanden",
                    message: model.usesSupabase ? "Für diesen Supabase-Account wurden noch keine Projekte geladen." : "Lege dein erstes Projekt an.",
                    systemImage: "building.2"
                )
            } else {
                ForEach(model.projects) { project in
                    let isOwned = model.isOwner(of: project)
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 10) {
                            ProjectCoverImage(projectID: project.id)
                            HStack {
                                Text(project.name).font(.headline).foregroundStyle(BaumioTheme.primaryText)
                                Spacer()
                                if !isOwned {
                                    StatusBadge(title: "Geteilt", color: BaumioTheme.info)
                                }
                                if model.selectedProject?.id == project.id {
                                    StatusBadge(title: "Ausgewählt", color: BaumioTheme.accent)
                                }
                                StatusBadge(title: project.status.rawValue, color: project.status == .active ? BaumioTheme.success : BaumioTheme.secondaryText)
                                if isOwned {
                                    Menu {
                                        Button("Bearbeiten") { editingProject = project }
                                        Button("Löschen", role: .destructive) {
                                            deletingProject = project
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Projekt bearbeiten oder löschen")
                                }
                            }
                            Text(project.address).foregroundStyle(BaumioTheme.secondaryText)
                            Text(project.description).font(.subheadline).foregroundStyle(BaumioTheme.secondaryText)
                            LabeledContent("Budget", value: project.budget.euroString)
                                .foregroundStyle(BaumioTheme.primaryText, BaumioTheme.secondaryText)
                        }
                    }
                    .onTapGesture { model.selectProject(project) }
                    .accessibilityLabel("Projekt \(project.name) auswählen")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ProjectEditorView(model: model)
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorView(model: model, editing: project)
        }
        .alert("Projekt löschen?", isPresented: Binding(get: { deletingProject != nil }, set: { if !$0 { deletingProject = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingProject = nil }
            Button("Löschen", role: .destructive) {
                if let p = deletingProject {
                    model.handle { try await model.deleteProject(p) }
                    deletingProject = nil
                }
            }
        } message: {
            Text("Das Projekt \"\(deletingProject?.name ?? "")\" und alle zugehörigen Daten werden unwiderruflich gelöscht.")
        }
    }
}

private let tradeTypeOptions = [
    "Elektriker", "Sanitär / Klempner", "Heizung (HKS)", "Dachdecker", "Zimmerer",
    "Maurer", "Maler & Lackierer", "Fliesenleger", "Schreiner / Tischler",
    "Gerüstbauer", "Tiefbau / Erdarbeiten", "Trockenbau", "Bodenleger",
    "Fenster & Türen", "Abbruch & Entsorgung", "Architekt / Planer",
    "Statik & Gutachter", "Sonstiges"
]

struct TradesView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var showingBizCardScanner = false
    @State private var showingContactImport = false
    @State private var showingFavorites = false
    @State private var editingItem: EditingItem?
    @State private var deletingTrade: Trade?
    @State private var searchText = ""

    @AppStorage("favoriteFirmsData") private var favoriteFirmsData: Data = Data()

    private var favoriteFirms: [FavoriteFirm] {
        (try? JSONDecoder().decode([FavoriteFirm].self, from: favoriteFirmsData)) ?? []
    }

    private func saveFavorite(_ trade: Trade) {
        guard !trade.company.isEmpty || !trade.name.isEmpty else { return }
        var current = favoriteFirms
        let fav = FavoriteFirm(from: trade)
        guard !current.contains(where: { $0.company == fav.company && $0.name == fav.name }) else { return }
        current.append(fav)
        favoriteFirmsData = (try? JSONEncoder().encode(current)) ?? Data()
    }

    private func removeFavorite(_ fav: FavoriteFirm) {
        var current = favoriteFirms
        current.removeAll { $0.id == fav.id }
        favoriteFirmsData = (try? JSONEncoder().encode(current)) ?? Data()
    }

    private var filteredTrades: [Trade] {
        guard !searchText.isEmpty else { return model.trades }
        let q = searchText.lowercased()
        return model.trades.filter {
            $0.company.lowercased().contains(q) ||
            $0.name.lowercased().contains(q) ||
            $0.tradeType.lowercased().contains(q) ||
            $0.notes.lowercased().contains(q)
        }
    }

    var body: some View {
        ListScreen(title: "Firmen", subtitle: "Handwerksbetriebe, Kontaktdaten und Kosten") {
            if !model.canCreateTrade {
                Button { model.selectedSection = .pricing } label: {
                    BaumioCard {
                        HStack {
                            Image(systemName: "crown.fill").foregroundStyle(BaumioTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unbegrenzte Firmen mit Baumio Pro")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(BaumioTheme.primaryText)
                                Text("Free-Plan: 5 Firmen · \(model.store.proDisplayPrice)/Monat")
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(BaumioTheme.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    PrimaryButton(title: "Firma anlegen", systemImage: "plus", action: { showingEditor = true })
                    Button { showingContactImport = true } label: {
                        Label("Kontakte", systemImage: "person.crop.circle.badge.plus")
                            .font(.headline)
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, 12)
                            .foregroundStyle(BaumioTheme.primaryText)
                            .background(BaumioTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous)
                                    .stroke(BaumioTheme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kontakt aus Adressbuch importieren")
                    if !favoriteFirms.isEmpty {
                        Button { showingFavorites = true } label: {
                            Label("Favoriten", systemImage: "star.fill")
                                .font(.headline)
                                .frame(minWidth: 44, minHeight: 44)
                                .padding(.horizontal, 12)
                                .foregroundStyle(BaumioTheme.accent)
                                .background(BaumioTheme.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous)
                                        .stroke(BaumioTheme.border, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Aus Favoriten importieren")
                    }
                    if model.isPro {
                        Button { showingBizCardScanner = true } label: {
                            Label("Visitenkarte", systemImage: "camera.viewfinder")
                                .font(.headline)
                                .frame(minWidth: 44, minHeight: 44)
                                .padding(.horizontal, 12)
                                .foregroundStyle(BaumioTheme.primaryText)
                                .background(BaumioTheme.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous)
                                        .stroke(BaumioTheme.border, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Visitenkarte scannen")
                    }
                }
            }

            if !model.isPro && model.canCreateTrade {
                Button { model.selectedSection = .pricing } label: {
                    BaumioCard {
                        HStack(spacing: 10) {
                            Image(systemName: "camera.viewfinder").foregroundStyle(BaumioTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Visitenkarte mit KI scannen")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(BaumioTheme.primaryText)
                                Text("Pro · Kontaktdaten automatisch erfassen")
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "crown.fill").foregroundStyle(BaumioTheme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if !model.trades.isEmpty && filteredTrades.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
            ForEach(filteredTrades) { trade in
                BaumioCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                if !trade.tradeType.isEmpty {
                                    StatusBadge(title: trade.tradeType, color: BaumioTheme.info)
                                }
                                ItemLine(
                                    icon: "building.2",
                                    title: trade.company.isEmpty ? trade.name : trade.company,
                                    subtitle: (!trade.company.isEmpty && !trade.name.isEmpty) ? trade.name : "",
                                    tint: BaumioTheme.accent
                                )
                            }
                            Spacer()
                            Menu {
                                Button("Bearbeiten") { editingItem = .trade(trade) }
                                let isFav = favoriteFirms.contains { $0.company == trade.company && $0.name == trade.name }
                                if isFav {
                                    Button("Aus Favoriten entfernen") {
                                        if let fav = favoriteFirms.first(where: { $0.company == trade.company && $0.name == trade.name }) {
                                            removeFavorite(fav)
                                        }
                                    }
                                } else {
                                    Button("Als Favorit speichern") { saveFavorite(trade) }
                                }
                                Button("Löschen", role: .destructive) {
                                    deletingTrade = trade
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Firma bearbeiten oder löschen")
                            StatusBadge(title: trade.status.rawValue, color: statusColor(trade.status))
                        }

                        if !trade.phone.isEmpty || !trade.email.isEmpty || !trade.address.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                if !trade.phone.isEmpty {
                                    Label(trade.phone, systemImage: "phone")
                                        .font(.footnote)
                                        .foregroundStyle(BaumioTheme.secondaryText)
                                }
                                if !trade.email.isEmpty {
                                    Label(trade.email, systemImage: "envelope")
                                        .font(.footnote)
                                        .foregroundStyle(BaumioTheme.secondaryText)
                                }
                                if !trade.address.isEmpty {
                                    Label(trade.address, systemImage: "mappin")
                                        .font(.footnote)
                                        .foregroundStyle(BaumioTheme.secondaryText)
                                }
                            }
                        }

                        if trade.budget > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Soll")
                                        .font(.caption.bold())
                                        .foregroundStyle(BaumioTheme.secondaryText)
                                    Spacer()
                                    Text(trade.budget.euroString)
                                        .font(.caption.bold())
                                        .foregroundStyle(BaumioTheme.secondaryText)
                                }
                                HStack {
                                    Text("Ist")
                                        .font(.caption.bold())
                                        .foregroundStyle(trade.costs > trade.budget ? BaumioTheme.danger : BaumioTheme.success)
                                    Spacer()
                                    Text(trade.costs.euroString)
                                        .font(.caption.bold())
                                        .foregroundStyle(trade.costs > trade.budget ? BaumioTheme.danger : BaumioTheme.success)
                                }
                                ProgressView(value: trade.budget > 0 ? min(NSDecimalNumber(decimal: trade.costs / trade.budget).doubleValue, 1) : 0)
                                    .tint(trade.costs > trade.budget ? BaumioTheme.danger : BaumioTheme.success)
                            }
                        } else {
                            HStack {
                                Text(trade.costs.euroString)
                                Spacer()
                                StarRating(value: trade.rating)
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(BaumioTheme.primaryText)
                        }
                        if trade.budget > 0 {
                            StarRating(value: trade.rating)
                        }
                        if !trade.notes.isEmpty {
                            Text(trade.notes).font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("Leistung", systemImage: "gauge.medium")
                                    .font(.caption.bold())
                                    .foregroundStyle(BaumioTheme.secondaryText)
                                Spacer()
                                Text("\(trade.progress) %")
                                    .font(.caption.bold())
                                    .foregroundStyle(trade.progress >= 100 ? BaumioTheme.success : BaumioTheme.primaryText)
                                Stepper("", value: Binding(
                                    get: { trade.progress },
                                    set: { v in model.handle { try await model.updateTradeProgress(trade, progress: v) } }
                                ), in: 0...100, step: 10)
                                .labelsHidden()
                            }
                            ProgressView(value: Double(trade.progress) / 100)
                                .tint(trade.progress >= 100 ? BaumioTheme.success : BaumioTheme.accent)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Firma suchen …")
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .trade, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(isPresented: $showingBizCardScanner) {
            VisitenkarteScannerSheet(model: model)
        }
        .sheet(isPresented: $showingContactImport) {
            ContactImportSheet(model: model)
        }
        .sheet(isPresented: $showingFavorites) {
            FavoriteFirmsSheet(model: model, favoriteFirmsData: $favoriteFirmsData)
        }
        .alert("Firma löschen?", isPresented: Binding(get: { deletingTrade != nil }, set: { if !$0 { deletingTrade = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingTrade = nil }
            Button("Löschen", role: .destructive) {
                if let t = deletingTrade { model.handle { try await model.deleteTrade(t) }; deletingTrade = nil }
            }
        } message: {
            Text("\(deletingTrade.map { $0.company.isEmpty ? $0.name : $0.company } ?? "diese Firma") wird unwiderruflich gelöscht.")
        }
    }
}

// MARK: - Favoriten-Firmen Sheet

struct FavoriteFirmsSheet: View {
    @Bindable var model: BaumioAppViewModel
    @Binding var favoriteFirmsData: Data
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var importError: String?

    private var favoriteFirms: [FavoriteFirm] {
        (try? JSONDecoder().decode([FavoriteFirm].self, from: favoriteFirmsData)) ?? []
    }

    private func removeFavorite(_ fav: FavoriteFirm) {
        var current = favoriteFirms
        current.removeAll { $0.id == fav.id }
        favoriteFirmsData = (try? JSONEncoder().encode(current)) ?? Data()
    }

    var body: some View {
        NavigationStack {
            List {
                if favoriteFirms.isEmpty {
                    ContentUnavailableView(
                        "Keine Favoriten",
                        systemImage: "star",
                        description: Text("Speichere Firmen aus einem Projekt als Favorit, um sie in anderen Projekten wiederzuverwenden.")
                    )
                } else {
                    ForEach(favoriteFirms) { fav in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fav.company.isEmpty ? fav.name : fav.company)
                                .font(.headline)
                                .foregroundStyle(BaumioTheme.primaryText)
                            if !fav.tradeType.isEmpty {
                                Text(fav.tradeType)
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                            if !fav.phone.isEmpty {
                                Label(fav.phone, systemImage: "phone")
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                            if !fav.email.isEmpty {
                                Label(fav.email, systemImage: "envelope")
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing) {
                            Button("Löschen", role: .destructive) { removeFavorite(fav) }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                guard model.canCreateTrade else {
                                    importError = "Free-Plan: maximal 5 Firmen. Upgrade auf Baumio Pro für unbegrenzte Firmen."
                                    return
                                }
                                isImporting = true
                                Task {
                                    do {
                                        try await model.createTrade(
                                            name: fav.name,
                                            company: fav.company,
                                            tradeType: fav.tradeType,
                                            address: fav.address,
                                            phone: fav.phone,
                                            email: fav.email,
                                            budget: 0,
                                            notes: ""
                                        )
                                        dismiss()
                                    } catch {
                                        importError = error.localizedDescription
                                    }
                                    isImporting = false
                                }
                            } label: {
                                Label("Hinzufügen", systemImage: "plus.circle.fill")
                            }
                            .tint(BaumioTheme.success)
                        }
                    }
                }
            }
            .navigationTitle("Favoriten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Fehler", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .overlay {
                if isImporting { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial) }
            }
        }
    }
}

struct ScheduleView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var viewMode = "Liste"
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var deletingAppointment: ScheduleItem?
    @State private var exportSheet: ShareableURL?
    @State private var searchText = ""
    @State private var calendarMessage: String?
    @State private var showingCalendarAlert = false
    private let modes = ["Liste", "Zeitstrahl"]

    private var filteredSchedule: [ScheduleItem] {
        guard !searchText.isEmpty else { return model.schedule }
        let q = searchText.lowercased()
        return model.schedule.filter {
            $0.title.lowercased().contains(q) ||
            $0.trade.lowercased().contains(q) ||
            $0.notes.lowercased().contains(q)
        }
    }

    var body: some View {
        ScreenScaffold(title: "Termine & Zeitstrahl", subtitle: "Terminliste und Bauzeitenplan (Gantt)") {
            PrimaryButton(title: "Termin anlegen", systemImage: "plus", action: { showingEditor = true })

            Picker("Ansicht", selection: $viewMode) {
                ForEach(modes, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

            if viewMode == "Zeitstrahl" {
                BaumioCard {
                    GanttChartView(items: model.schedule)
                }
                if model.isPro {
                    SecondaryButton(title: "Bauzeitenplan als PDF exportieren", systemImage: "square.and.arrow.up") {
                        if let url = GanttPDFExporter.export(items: model.schedule, projectName: model.selectedProject?.name ?? "Projekt", date: Date()) {
                            exportSheet = ShareableURL(url: url)
                        }
                    }
                    .disabled(model.schedule.isEmpty)
                } else {
                    Button { model.selectedSection = .pricing } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(BaumioTheme.accent)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PDF exportieren – Baumio Pro")
                                    .font(.headline)
                                    .foregroundStyle(BaumioTheme.primaryText)
                                Text("Für Architekten, Handwerker und Behörden teilen")
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "crown.fill")
                                .foregroundStyle(BaumioTheme.accent)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 16)
                        .background(BaumioTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous)
                                .stroke(BaumioTheme.accent.opacity(0.5), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("PDF-Export, erfordert Baumio Pro")
                }
            } else {
                if !model.schedule.isEmpty {
                    SecondaryButton(title: "In Kalender exportieren", systemImage: "calendar.badge.plus") {
                        Task { await exportToCalendar() }
                    }
                }
                if model.schedule.isEmpty {
                    EmptyStateView(title: "Keine Termine", message: "Lege deinen ersten Termin an.", systemImage: "calendar")
                } else if filteredSchedule.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
                ForEach(filteredSchedule) { item in
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                ItemLine(icon: "calendar", title: item.title, subtitle: {
                                    var s = item.date.formatted(date: .abbreviated, time: .omitted)
                                    if let start = item.startTime {
                                        s += " · " + start.formatted(date: .omitted, time: .shortened)
                                        if let end = item.endTime { s += "–" + end.formatted(date: .omitted, time: .shortened) }
                                    }
                                    return (item.trade.isEmpty ? "" : item.trade + " · ") + s
                                }(), tint: BaumioTheme.accent)
                                Spacer()
                                Menu {
                                    Button("Bearbeiten") { editingItem = .appointment(item) }
                                    Button("Löschen", role: .destructive) {
                                        deletingAppointment = item
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Termin bearbeiten oder löschen")
                            }
                            HStack {
                                StatusBadge(title: item.status.rawValue, color: statusColor(item.status))
                                Text("\(item.durationDays) Tag(e)")
                                    .font(.footnote.bold())
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                            Text(item.notes).font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Termin suchen …")
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .appointment, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(item: $exportSheet) { shareable in
            ShareSheet(items: [shareable.url])
        }
        .alert("Kalender-Export", isPresented: $showingCalendarAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calendarMessage ?? "")
        }
        .alert("Termin löschen?", isPresented: Binding(get: { deletingAppointment != nil }, set: { if !$0 { deletingAppointment = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingAppointment = nil }
            Button("Löschen", role: .destructive) {
                if let a = deletingAppointment { model.handle { try await model.deleteAppointment(a) }; deletingAppointment = nil }
            }
        } message: {
            Text("\(deletingAppointment?.title ?? "dieser Termin") wird unwiderruflich gelöscht.")
        }
    }

    private func exportToCalendar() async {
        let store = EKEventStore()
        do {
            let granted: Bool
            if #available(iOS 17, *) {
                granted = try await store.requestWriteOnlyAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
            guard granted else {
                calendarMessage = "Bitte erlaube Baumio den Zugriff auf deinen Kalender in den Einstellungen."
                showingCalendarAlert = true
                return
            }
            let calendar = store.defaultCalendarForNewEvents
            var added = 0
            for item in filteredSchedule {
                let marker = "[baumio:\(item.id.uuidString)]"
                let dayStart = Calendar.current.startOfDay(for: item.date)
                let windowEnd = Calendar.current.date(byAdding: .day, value: 2, to: dayStart) ?? dayStart
                let pred = store.predicateForEvents(withStart: dayStart, end: windowEnd, calendars: nil)
                if store.events(matching: pred).contains(where: { ($0.notes ?? "").contains(marker) }) { continue }

                let event = EKEvent(eventStore: store)
                event.title = item.title
                let markerSuffix = item.notes.isEmpty ? marker : "\(item.notes)\n\(marker)"
                event.notes = markerSuffix
                event.calendar = calendar

                let isAllDay = item.startTime == nil
                event.isAllDay = isAllDay

                let startDate: Date
                if let t = item.startTime {
                    startDate = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: t),
                                                      minute: Calendar.current.component(.minute, from: t),
                                                      second: 0, of: item.date) ?? item.date
                } else {
                    startDate = Calendar.current.startOfDay(for: item.date)
                }
                let endDate: Date
                if isAllDay {
                    endDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: item.date)) ?? startDate
                } else if let t = item.endTime {
                    endDate = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: t),
                                                    minute: Calendar.current.component(.minute, from: t),
                                                    second: 0, of: item.date) ?? startDate
                } else {
                    endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
                }
                event.startDate = startDate
                event.endDate = endDate
                try store.save(event, span: .thisEvent)
                added += 1
            }
            calendarMessage = "\(added) Termin\(added == 1 ? "" : "e") in den Kalender exportiert."
        } catch {
            calendarMessage = "Fehler: \(error.localizedDescription)"
        }
        showingCalendarAlert = true
    }
}

struct DiaryView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var deletingEntry: DiaryEntry?
    @State private var autoWeather = ""
    @State private var autoTemperature = ""

    var body: some View {
        ListScreen(title: "Bautagebuch", subtitle: "Tägliche Einträge, Wetter, Firmen, Fotos und Notizen") {
            PrimaryButton(title: "Eintrag anlegen", systemImage: "plus", action: { showingEditor = true })

            ForEach(model.diary) { entry in
                BaumioCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            ItemLine(icon: "book.pages", title: entry.date.formatted(date: .long, time: .omitted), subtitle: entry.weather, tint: BaumioTheme.accent)
                            Spacer()
                            Menu {
                                Button("Bearbeiten") { editingItem = .diary(entry) }
                                Button("Löschen", role: .destructive) {
                                    deletingEntry = entry
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Eintrag bearbeiten oder löschen")
                        }
                        Text(entry.completedWork).foregroundStyle(BaumioTheme.primaryText)
                        if !entry.companies.isEmpty {
                            Text("Firmen: \(entry.companies.joined(separator: ", "))").font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
                        }
                        PhotoSection(model: model, bucket: "diary-photos", photos: model.diaryPhotos[entry.id] ?? []) { data in
                            model.handle { try await model.addDiaryPhoto(entry, imageData: data) }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .diary, model: model, initialWeather: autoWeather, initialTemperature: autoTemperature)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .task {
            if let result = await fetchCurrentWeather() {
                autoWeather = result.weather
                autoTemperature = result.temp
            }
        }
        .alert("Eintrag löschen?", isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingEntry = nil }
            Button("Löschen", role: .destructive) {
                if let e = deletingEntry { model.handle { try await model.deleteDiaryEntry(e) }; deletingEntry = nil }
            }
        } message: {
            Text("Der Tagebucheintrag vom \(deletingEntry.map { $0.date.formatted(date: .long, time: .omitted) } ?? "") wird unwiderruflich gelöscht.")
        }
    }
}

struct TasksView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var deletingTask: TaskItem?
    @State private var searchText = ""

    private var filteredTasks: [TaskItem] {
        guard !searchText.isEmpty else { return model.tasks }
        let q = searchText.lowercased()
        return model.tasks.filter { $0.title.lowercased().contains(q) || $0.trade.lowercased().contains(q) }
    }

    var body: some View {
        ListScreen(title: "Aufgaben", subtitle: "Prioritäten, Fälligkeiten und Filter") {
            PrimaryButton(title: "Aufgabe anlegen", systemImage: "plus", action: { showingEditor = true })

            ForEach(filteredTasks) { task in
                BaumioCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                model.handle { try await model.toggleTask(task) }
                            } label: {
                                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isDone ? BaumioTheme.success : BaumioTheme.secondaryText)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(task.isDone ? "Aufgabe als offen markieren" : "Aufgabe als erledigt markieren")
                            VStack(alignment: .leading, spacing: 6) {
                                Text(task.title).font(.headline).foregroundStyle(BaumioTheme.primaryText)
                                Text("\(task.trade) · fällig am \(task.dueDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                                StatusBadge(title: task.priority.rawValue, color: priorityColor(task.priority))
                            }
                            Spacer()
                            Menu {
                                Button("Bearbeiten") { editingItem = .task(task) }
                                Button("Löschen", role: .destructive) {
                                    deletingTask = task
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Aufgabe bearbeiten oder löschen")
                        }
                        PhotoSection(model: model, bucket: "task-photos", photos: model.taskPhotos[task.id] ?? []) { data in
                            model.handle { try await model.addTaskPhoto(task, imageData: data) }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Aufgabe suchen …")
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .task, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .alert("Aufgabe löschen?", isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingTask = nil }
            Button("Löschen", role: .destructive) {
                if let t = deletingTask { model.handle { try await model.deleteTask(t) }; deletingTask = nil }
            }
        } message: {
            Text("\(deletingTask?.title ?? "diese Aufgabe") wird unwiderruflich gelöscht.")
        }
    }
}

struct MaterialsView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var deletingMaterial: MaterialItem?
    @State private var searchText = ""
    @State private var statusFilter = "Alle"
    @State private var supplierFilter = "Alle"
    @State private var csvMaterialSheet: ShareableURL?

    private let statusOptions = ["Alle", "Geplant", "Bestellt", "Geliefert", "Verbaut", "Retour"]
    private let statusUpdates = [
        ("Geplant", "geplant"),
        ("Bestellt", "bestellt"),
        ("Geliefert", "geliefert"),
        ("Verbaut", "verbaut"),
        ("Retour", "retour")
    ]

    private var suppliers: [String] {
        let values = model.materials.map(\.supplier).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return ["Alle"] + Array(Set(values)).sorted()
    }

    private var filteredMaterials: [MaterialItem] {
        model.materials.filter { material in
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || material.name.localizedCaseInsensitiveContains(searchText)
                || material.supplier.localizedCaseInsensitiveContains(searchText)
                || material.articleNumber.localizedCaseInsensitiveContains(searchText)
                || material.notes.localizedCaseInsensitiveContains(searchText)
            let matchesStatus = statusFilter == "Alle" || material.deliveryStatus == statusFilter
            let matchesSupplier = supplierFilter == "Alle" || material.supplier == supplierFilter
            return matchesSearch && matchesStatus && matchesSupplier
        }
    }

    var body: some View {
        ListScreen(title: "Materialliste", subtitle: "Mengen, Einheiten, Preise und Lieferstatus") {
            PrimaryButton(title: "Material anlegen", systemImage: "plus", action: { showingEditor = true })

            BaumioCard {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Material, Händler oder Artikelnummer suchen", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Materialsuche")

                    HStack {
                        Picker("Status", selection: $statusFilter) {
                            ForEach(statusOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)

                        Picker("Händler", selection: $supplierFilter) {
                            ForEach(suppliers, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            ForEach(filteredMaterials) { material in
                BaumioCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            ItemLine(icon: "shippingbox", title: material.name, subtitle: "\(material.quantity.formatted()) \(material.unit) · \(material.supplier.isEmpty ? "Kein Händler" : material.supplier)", tint: BaumioTheme.accent)
                            Spacer()
                            Menu {
                                Button("Bearbeiten") { editingItem = .material(material) }
                                Button("Löschen", role: .destructive) {
                                    deletingMaterial = material
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Material bearbeiten oder löschen")
                        }
                        HStack {
                            Text(material.price.euroString).font(.headline)
                            Spacer()
                            Menu {
                                ForEach(statusUpdates, id: \.0) { title, value in
                                    Button(title) {
                                        model.handle { try await model.updateMaterialStatus(material, status: value) }
                                    }
                                }
                            } label: {
                                StatusBadge(title: material.deliveryStatus, color: material.deliveryStatus == "Geliefert" || material.deliveryStatus == "Verbaut" ? BaumioTheme.success : BaumioTheme.warning)
                            }
                            .accessibilityLabel("Materialstatus ändern")
                        }
                        .foregroundStyle(BaumioTheme.primaryText)
                        if !material.articleNumber.isEmpty {
                            Text("Artikelnummer: \(material.articleNumber)").font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
                        }
                        if !material.url.isEmpty, let url = URL(string: material.url) {
                            Link(destination: url) {
                                Label("Produktlink öffnen", systemImage: "link")
                                    .font(.footnote.bold())
                                    .foregroundStyle(BaumioTheme.accent)
                            }
                        }
                        Text(material.notes).font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    var rows: [[String]] = [["Name", "Menge", "Einheit", "Preis (€)", "Lieferant", "Artikelnummer", "Status"]]
                    for m in model.materials {
                        rows.append([m.name, "\(m.quantity)", m.unit, "\(m.price)", m.supplier, m.articleNumber, m.deliveryStatus])
                    }
                    if let url = csvURL(rows, fileName: "Baumio_Material.csv") { csvMaterialSheet = ShareableURL(url: url) }
                } label: {
                    Label("Als CSV exportieren", systemImage: "tablecells")
                }
                .disabled(model.materials.isEmpty)
            }
        }
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .material, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(item: $csvMaterialSheet) { shareable in
            ShareSheet(items: [shareable.url])
        }
        .alert("Material löschen?", isPresented: Binding(get: { deletingMaterial != nil }, set: { if !$0 { deletingMaterial = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingMaterial = nil }
            Button("Löschen", role: .destructive) {
                if let m = deletingMaterial { model.handle { try await model.deleteMaterial(m) }; deletingMaterial = nil }
            }
        } message: {
            Text("\(deletingMaterial?.name ?? "dieses Material") wird unwiderruflich gelöscht.")
        }
    }
}

struct TimeLogsView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @AppStorage("baumioTimerStart") private var timerStartTimestamp: Double = 0
    @State private var elapsedSeconds = 0
    @State private var showingTimerSheet = false
    @State private var timerElapsedMinutes = 0
    @State private var csvTimeSheet: ShareableURL?

    private var isTimerRunning: Bool { timerStartTimestamp > 0 }

    private var timerDisplayText: String {
        let s = elapsedSeconds
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScreenScaffold(title: "Zeiterfassung", subtitle: "Arbeitszeiten erfassen und auswerten") {
            PrimaryButton(title: "Zeit erfassen", systemImage: "plus", action: { showingEditor = true })

            BaumioCard {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundStyle(isTimerRunning ? BaumioTheme.danger : BaumioTheme.accent)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stoppuhr").font(.headline).foregroundStyle(BaumioTheme.primaryText)
                            Text(isTimerRunning
                                 ? "Läuft seit \(Date(timeIntervalSince1970: timerStartTimestamp).formatted(date: .omitted, time: .shortened))"
                                 : "Starten → automatisch als Zeiteintrag erfassen")
                                .font(.caption).foregroundStyle(BaumioTheme.secondaryText)
                        }
                        Spacer()
                        if isTimerRunning {
                            Text(timerDisplayText)
                                .font(.title2.monospacedDigit().bold())
                                .foregroundStyle(BaumioTheme.danger)
                        }
                    }
                    Button {
                        if isTimerRunning {
                            let seconds = Int(Date().timeIntervalSince1970 - timerStartTimestamp)
                            timerElapsedMinutes = max(1, seconds / 60)
                            timerStartTimestamp = 0
                            elapsedSeconds = 0
                            showingTimerSheet = true
                        } else {
                            timerStartTimestamp = Date().timeIntervalSince1970
                        }
                    } label: {
                        Label(isTimerRunning ? "Stopp & Zeiteintrag anlegen" : "Timer starten",
                              systemImage: isTimerRunning ? "stop.circle.fill" : "play.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isTimerRunning ? BaumioTheme.danger : BaumioTheme.success)
                }
            }

            BaumioCard {
                HStack {
                    Label("Gesamt erfasst", systemImage: "clock")
                        .font(.headline)
                        .foregroundStyle(BaumioTheme.primaryText)
                    Spacer()
                    Text(model.totalTrackedTimeText)
                        .font(.title3.bold())
                        .foregroundStyle(BaumioTheme.accent)
                }
            }

            if model.timeLogs.isEmpty {
                EmptyStateView(
                    title: "Noch keine Zeiten erfasst",
                    message: "Erfasse Planungs-, Termin- oder Handwerkszeiten, um deinen Aufwand auszuwerten.",
                    systemImage: "clock"
                )
            } else {
                ForEach(model.timeLogs) { log in
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                ItemLine(icon: "clock", title: log.title, subtitle: "\(log.category.rawValue) · \(log.date.formatted(date: .abbreviated, time: .omitted))", tint: BaumioTheme.accent)
                                Spacer()
                                Text(durationText(log.durationMinutes))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(BaumioTheme.primaryText)
                                Menu {
                                    Button("Bearbeiten") { editingItem = .timeLog(log) }
                                    Button("Löschen", role: .destructive) {
                                        model.handle { try await model.deleteTimeLog(log) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Zeiteintrag bearbeiten oder löschen")
                            }
                            if !log.notes.isEmpty {
                                Text(log.notes)
                                    .font(.footnote)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .timeLog, model: model)
        }
        .sheet(isPresented: $showingTimerSheet) {
            QuickAddView(kind: .timeLog, model: model, initialHours: timerElapsedMinutes / 60, initialMinutes: timerElapsedMinutes % 60)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(item: $csvTimeSheet) { shareable in
            ShareSheet(items: [shareable.url])
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    var rows: [[String]] = [["Titel", "Kategorie", "Datum", "Dauer (min)", "Notizen"]]
                    let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
                    for t in model.timeLogs {
                        rows.append([t.title, t.category.rawValue, fmt.string(from: t.date), "\(t.durationMinutes)", t.notes])
                    }
                    if let url = csvURL(rows, fileName: "Baumio_Zeiten.csv") { csvTimeSheet = ShareableURL(url: url) }
                } label: {
                    Label("Als CSV exportieren", systemImage: "tablecells")
                }
                .disabled(model.timeLogs.isEmpty)
            }
        }
        .onReceive(ticker) { _ in
            guard isTimerRunning else { return }
            elapsedSeconds = Int(Date().timeIntervalSince1970 - timerStartTimestamp)
        }
        .onAppear {
            if isTimerRunning {
                elapsedSeconds = Int(Date().timeIntervalSince1970 - timerStartTimestamp)
            }
        }
    }

    private func durationText(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }
}

private let handoverTemplates: [(name: String, items: [(item: String, room: String, trade: String)])] = [
    ("Wohnungsübergabe", [
        ("Haustür / Klingel funktioniert", "Eingang", ""),
        ("Briefkasten vorhanden & beschriftet", "Eingang", ""),
        ("Schlüsselübergabe vollständig", "Eingang", ""),
        ("Wände / Decke ohne Schäden", "Wohnzimmer", ""),
        ("Böden ohne Kratzer / Beschädigungen", "Wohnzimmer", ""),
        ("Fenster dicht, Griffe funktionieren", "Wohnzimmer", "Fensterbau"),
        ("Heizkörper heizt gleichmäßig", "Wohnzimmer", "Heizung"),
        ("Küche sauber & vollständig", "Küche", ""),
        ("Wasserhahn / Spüle ohne Leckage", "Küche", "Sanitär"),
        ("Dunstabzug funktioniert", "Küche", "Elektro"),
        ("Fliesen ohne Risse", "Bad / WC", "Fliesenleger"),
        ("Dusche / Badewanne dicht", "Bad / WC", "Sanitär"),
        ("WC spült einwandfrei", "Bad / WC", "Sanitär"),
        ("Lüftung / Fenster vorhanden", "Bad / WC", ""),
        ("Stromzählerstand notiert", "Zähler", "Elektro"),
        ("Wasserzählerstand notiert", "Zähler", "Sanitär"),
    ]),
    ("Neubau-Abnahme", [
        ("Zählerschrank / Sicherungen beschriftet", "Elektro", "Elektro"),
        ("Alle Steckdosen & Schalter geprüft", "Elektro", "Elektro"),
        ("Beleuchtung vollständig funktionsfähig", "Elektro", "Elektro"),
        ("Wasserdruck ausreichend (mind. 2 bar)", "Sanitär", "Sanitär"),
        ("Abflüsse funktionieren, kein Rückstau", "Sanitär", "Sanitär"),
        ("Heizung heizt alle Räume", "Heizung", "Heizung"),
        ("Thermostate / Regelung funktioniert", "Heizung", "Heizung"),
        ("Heizkörper entlüftet", "Heizung", "Heizung"),
        ("Fenster & Türen dicht & schließen korrekt", "Fenster & Türen", "Fensterbau"),
        ("Rollläden / Jalousien funktionieren", "Fenster & Türen", "Fensterbau"),
        ("Außenanlage / Gelände abgeschlossen", "Außenanlage", ""),
        ("Pflasterung / Bodenbelag fertig", "Außenanlage", "Pflasterung"),
    ]),
    ("Sanierung", [
        ("Schutt vollständig entfernt", "Abbruch", ""),
        ("Leitungen ordnungsgemäß gesichert", "Abbruch", ""),
        ("Mauerwerk / Decke ohne neue Risse", "Rohbau", "Maurer"),
        ("Innenputz fertig & trocken", "Ausbau", "Putzer"),
        ("Trockenbau abgehängt & verspachtelt", "Ausbau", "Trockenbau"),
        ("Böden verlegt & verklebt", "Ausbau", "Fußbodenleger"),
        ("Elektroinstallation abgenommen", "Technik", "Elektro"),
        ("Sanitär installiert & dicht", "Technik", "Sanitär"),
        ("Heizungsanlage geprüft", "Technik", "Heizung"),
    ]),
]

struct HandoverProtocolSignatureView: View {
    let trade: String
    @Bindable var model: BaumioAppViewModel
    @Binding var isPresented: Bool
    @State private var step = 0
    @State private var canvas1 = PKDrawing()
    @State private var canvas2 = PKDrawing()
    @State private var isSaving = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var canvasHeight: CGFloat { horizontalSizeClass == .regular ? 340 : 200 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 2)
                    .progressViewStyle(.linear)
                    .tint(BaumioTheme.accent)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if step == 0 {
                    signaturePage(
                        title: "Bauherr unterschreiben",
                        subtitle: "Bitte mit dem Finger oder Apple Pencil unterschreiben",
                        icon: "person.fill",
                        canvas: $canvas1,
                        action: { withAnimation { step = 1 } },
                        actionLabel: "Weiter →"
                    )
                } else {
                    signaturePage(
                        title: "Handwerker / Bauleiter unterschreiben",
                        subtitle: "Zweite Partei bestätigt die Abnahme",
                        icon: "hammer.fill",
                        canvas: $canvas2,
                        action: finalize,
                        actionLabel: isSaving ? "Wird gespeichert …" : "Abnahme abschließen"
                    )
                }
            }
            .navigationTitle("Abnahmeprotokoll unterzeichnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 0 ? "Abbrechen" : "Zurück") {
                        if step == 0 { isPresented = false } else { withAnimation { step = 0 } }
                    }
                }
            }
            .background(BaumioTheme.background)
        }
        .preferredColorScheme(.dark)
    }

    private func signaturePage(title: String, subtitle: String, icon: String, canvas: Binding<PKDrawing>, action: @escaping () -> Void, actionLabel: String) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(BaumioTheme.accent)
                Text(title).font(.title3.bold()).foregroundStyle(BaumioTheme.primaryText)
                Text(subtitle).font(.subheadline).foregroundStyle(BaumioTheme.secondaryText)
            }
            .padding(.top, 24)

            BaumioCard {
                PKCanvasRepresentable(drawing: canvas, tool: PKInkingTool(.pen, color: .black, width: 2))
                    .frame(height: canvasHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(BaumioTheme.accent.opacity(0.4), lineWidth: 1)
                    )
            }

            HStack(spacing: 12) {
                SecondaryButton(title: "Löschen", systemImage: "eraser") {
                    canvas.wrappedValue = PKDrawing()
                }
                PrimaryButton(title: actionLabel, systemImage: "checkmark.circle.fill", action: action)
                    .disabled(canvas.wrappedValue.strokes.isEmpty || isSaving)
            }
            Spacer()
        }
        .padding()
    }

    private func finalize() {
        isSaving = true
        Task {
            let renderer1 = PKCanvasView()
            renderer1.drawing = canvas1
            let sig1 = renderer1.drawing.image(from: renderer1.drawing.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 300, height: 200) : renderer1.drawing.bounds, scale: 2).pngData() ?? Data()
            let renderer2 = PKCanvasView()
            renderer2.drawing = canvas2
            let sig2 = renderer2.drawing.image(from: renderer2.drawing.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 300, height: 200) : renderer2.drawing.bounds, scale: 2).pngData() ?? Data()
            do {
                try await model.finalizeAbnahme(trade: trade, sig1Data: sig1, sig2Data: sig2)
                isPresented = false
            } catch {
                model.actionError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

struct HandoverView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var showingTemplates = false
    @State private var editingItem: EditingItem?
    @State private var exportSheet: ShareableURL?
    @State private var jsonExportSheet: ShareableURL?
    @State private var signingItem: HandoverItem?
    @State private var signingTrade = ""
    @State private var showingProtocolSignature = false

    private var groupedByTrade: [(trade: String, items: [HandoverItem])] {
        let groups = Dictionary(grouping: model.handoverItems) { $0.tradeType.isEmpty ? "Allgemein" : $0.tradeType }
        return groups.map { (trade: $0.key, items: $0.value.sorted { $0.item < $1.item }) }
            .sorted { $0.trade < $1.trade }
    }

    private func abnahmeFor(trade: String) -> AbnahmeRecord? {
        model.abnahmen.first { $0.trade.lowercased() == trade.lowercased() }
    }

    private func progressFor(items: [HandoverItem]) -> Int {
        guard !items.isEmpty else { return 0 }
        return Int(Double(items.filter { $0.isDone }.count) / Double(items.count) * 100)
    }

    var body: some View {
        ScreenScaffold(title: "Übergabe & Abnahme", subtitle: "Prüfpunkte je Gewerk abhaken und einzeln unterzeichnen") {
            PrimaryButton(title: "Prüfpunkt anlegen", systemImage: "plus", action: { showingEditor = true })
            SecondaryButton(title: "Vorlage laden / importieren", systemImage: "list.bullet.clipboard") { showingTemplates = true }

            if model.isPro {
                SecondaryButton(title: "Protokoll als PDF exportieren", systemImage: "square.and.arrow.up") {
                    if let url = PDFExporter.export(
                        HandoverPDFPage(items: model.handoverItems, projectName: model.selectedProject?.name ?? "Projekt", exportDate: Date(), project: model.selectedProject),
                        fileName: "Abnahmeprotokoll.pdf"
                    ) { exportSheet = ShareableURL(url: url) }
                }
                .disabled(model.handoverItems.isEmpty)
                SecondaryButton(title: "Checkliste als JSON exportieren", systemImage: "square.and.arrow.up.on.square") {
                    if let url = exportChecklistAsJSON() { jsonExportSheet = ShareableURL(url: url) }
                }
                .disabled(model.handoverItems.isEmpty)
            } else {
                Button { model.selectedSection = .pricing } label: {
                    BaumioCard {
                        HStack {
                            Image(systemName: "lock.fill").foregroundStyle(BaumioTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Abnahmeprotokoll als PDF").font(.subheadline.bold()).foregroundStyle(BaumioTheme.primaryText)
                                Text("Für Architekten und Behörden – nur in Baumio Pro").font(.caption).foregroundStyle(BaumioTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(BaumioTheme.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if model.handoverItems.isEmpty {
                EmptyStateView(
                    title: "Noch keine Prüfpunkte",
                    message: "Lege Prüfpunkte für die Bauabnahme an. Jedes Gewerk wird separat abgenommen.",
                    systemImage: "checkmark.seal"
                )
            } else {
                ForEach(groupedByTrade, id: \.trade) { group in
                    let abnahme = abnahmeFor(trade: group.trade)
                    let isLocked = abnahme?.isSigned == true
                    let progress = progressFor(items: group.items)

                    BaumioCard {
                        VStack(alignment: .leading, spacing: 10) {
                            // Gewerk-Kopfzeile
                            HStack {
                                Label(group.trade, systemImage: isLocked ? "checkmark.seal.fill" : "hammer")
                                    .font(.headline)
                                    .foregroundStyle(isLocked ? BaumioTheme.success : BaumioTheme.primaryText)
                                Spacer()
                                Text("\(progress) %")
                                    .font(.caption.bold())
                                    .foregroundStyle(progress == 100 ? BaumioTheme.success : BaumioTheme.secondaryText)
                            }
                            ProgressView(value: Double(progress) / 100)
                                .tint(progress == 100 ? BaumioTheme.success : BaumioTheme.accent)

                            // Abnahme-Banner wenn unterzeichnet
                            if let abnahme, let date = abnahme.signedAt {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(BaumioTheme.success)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Abgenommen")
                                            .font(.caption.bold())
                                            .foregroundStyle(BaumioTheme.success)
                                        Text(date.formatted(date: .long, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(BaumioTheme.secondaryText)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        model.handle { try await model.deleteAbnahme(abnahme) }
                                    } label: {
                                        Label("Zurücksetzen", systemImage: "arrow.uturn.backward")
                                            .font(.caption)
                                            .foregroundStyle(BaumioTheme.secondaryText)
                                    }
                                }
                                .padding(8)
                                .background(BaumioTheme.success.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            Divider()

                            // Prüfpunkte
                            ForEach(group.items) { entry in
                                HStack(alignment: .top, spacing: 10) {
                                    Button {
                                        guard !isLocked else { return }
                                        let newStatus: HandoverStatus = entry.isDone ? .offen : .akzeptiert
                                        model.handle { try await model.updateHandoverStatus(entry, status: newStatus) }
                                    } label: {
                                        Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(entry.isDone ? BaumioTheme.success : BaumioTheme.secondaryText)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isLocked)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.item)
                                            .font(.subheadline)
                                            .foregroundStyle(BaumioTheme.primaryText)
                                        if !entry.room.isEmpty {
                                            Text(entry.room)
                                                .font(.caption)
                                                .foregroundStyle(BaumioTheme.secondaryText)
                                        }
                                        if !entry.notes.isEmpty {
                                            Text(entry.notes)
                                                .font(.caption)
                                                .foregroundStyle(BaumioTheme.secondaryText)
                                        }
                                    }
                                    Spacer()
                                    StatusBadge(title: entry.status.rawValue, color: handoverColor(entry.status))
                                    if !isLocked {
                                        Menu {
                                            Button("Bearbeiten") { editingItem = .handover(entry) }
                                            Divider()
                                            ForEach(HandoverStatus.allCases) { status in
                                                Button(status.rawValue) {
                                                    model.handle { try await model.updateHandoverStatus(entry, status: status) }
                                                }
                                            }
                                            Divider()
                                            Button { signingItem = entry } label: {
                                                Label("Einzelunterschrift", systemImage: "signature")
                                            }
                                            Divider()
                                            Button("Löschen", role: .destructive) {
                                                model.handle { try await model.deleteHandoverItem(entry) }
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .foregroundStyle(BaumioTheme.secondaryText)
                                                .frame(width: 44, height: 44)
                                        }
                                    }
                                }
                            }

                            if !isLocked {
                                Divider()
                                Button {
                                    signingTrade = group.trade
                                    showingProtocolSignature = true
                                } label: {
                                    Label("Abnahme für \(group.trade) unterzeichnen", systemImage: "signature")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(BaumioTheme.accent)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .handover, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(item: $exportSheet) { shareable in
            ShareSheet(items: [shareable.url])
        }
        .sheet(item: $jsonExportSheet) { shareable in
            ShareSheet(items: [shareable.url])
        }
        .sheet(isPresented: $showingTemplates) {
            HandoverTemplateSheet(model: model)
        }
        .sheet(item: $signingItem) { item in
            SignatureCaptureView(item: item, model: model)
        }
        .sheet(isPresented: $showingProtocolSignature) {
            HandoverProtocolSignatureView(trade: signingTrade, model: model, isPresented: $showingProtocolSignature)
        }
    }

    private func exportChecklistAsJSON() -> URL? {
        let items = model.handoverItems.map { entry -> [String: String] in
            ["item": entry.item, "room": entry.room, "tradeType": entry.tradeType, "notes": entry.notes,
             "status": entry.status.supabaseValue, "isDone": entry.isDone ? "true" : "false"]
        }
        let wrapper: [String: Any] = [
            "name": model.selectedProject?.name ?? "Meine Checkliste",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "items": items
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper, options: .prettyPrinted) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Baumio_Checkliste_\(Int(Date().timeIntervalSince1970)).json")
        do { try data.write(to: url) } catch { return nil }
        return url
    }

    private func handoverColor(_ status: HandoverStatus) -> Color {
        switch status {
        case .offen: BaumioTheme.warning
        case .akzeptiert: BaumioTheme.success
        case .vorbehalt: BaumioTheme.info
        case .abgelehnt: BaumioTheme.danger
        }
    }
}

struct HandoverTemplateSheet: View {
    @Bindable var model: BaumioAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var loadedTemplate: String? = nil
    @State private var showingImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Wähle eine Vorlage oder importiere eine eigene JSON-Datei.")
                        .font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
                }

                Section("Eigene Vorlage") {
                    Button {
                        showingImporter = true
                    } label: {
                        HStack {
                            Label("JSON-Datei importieren", systemImage: "square.and.arrow.down")
                                .foregroundStyle(BaumioTheme.accent)
                            Spacer()
                            if isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoading)
                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(BaumioTheme.danger)
                    }
                    if let loadedTemplate, loadedTemplate.hasPrefix("Import") {
                        Label(loadedTemplate, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(BaumioTheme.success)
                    }
                    Text("Format: JSON-Datei aus Baumio-Export oder mit Feldern \"item\", \"room\", \"tradeType\".")
                        .font(.caption2)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }

                Section("Integrierte Vorlagen") {
                    ForEach(handoverTemplates, id: \.name) { template in
                        Button {
                            loadTemplate(template)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name).font(.headline).foregroundStyle(BaumioTheme.primaryText)
                                    Text("\(template.items.count) Prüfpunkte")
                                        .font(.caption).foregroundStyle(BaumioTheme.secondaryText)
                                }
                                Spacer()
                                if loadedTemplate == template.name {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(BaumioTheme.success)
                                } else if isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right").foregroundStyle(BaumioTheme.secondaryText)
                                }
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .navigationTitle("Vorlage laden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                importFromJSON(result)
            }
        }
    }

    private func importFromJSON(_ result: Result<URL, Error>) {
        importError = nil
        guard model.isPro else {
            importError = "JSON-Import ist ab Baumio Pro verfügbar."
            return
        }
        switch result {
        case .failure:
            importError = "Datei konnte nicht geöffnet werden."
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawItems = json["items"] as? [[String: String]] else {
                importError = "Ungültiges Format. Erwartet: Baumio-JSON mit \"items\"-Array."
                return
            }
            let wasTruncated = rawItems.count > 200
            let limitedItems = Array(rawItems.prefix(200))
            let entries = limitedItems.compactMap { dict -> (item: String, room: String, trade: String, status: String)? in
                guard let item = dict["item"], !item.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return (item: item, room: dict["room"] ?? "", trade: dict["tradeType"] ?? "", status: dict["status"] ?? "offen")
            }
            guard !entries.isEmpty else {
                importError = "Keine gültigen Prüfpunkte gefunden."
                return
            }
            isLoading = true
            Task {
                var created = 0
                var firstError: String?
                for entry in entries {
                    do {
                        try await model.createHandoverItem(item: entry.item, room: entry.room, tradeType: entry.trade)
                        created += 1
                        if entry.status != "offen", let last = model.handoverItems.last {
                            try? await model.updateHandoverStatus(last, status: HandoverStatus(supabaseValue: entry.status))
                        }
                    } catch {
                        if firstError == nil { firstError = error.localizedDescription }
                    }
                }
                if let err = firstError {
                    importError = "\(created) von \(entries.count) Punkten importiert. Fehler: \(err)"
                } else if wasTruncated {
                    loadedTemplate = "\(created) Punkte geladen (Datei hatte \(rawItems.count) Einträge, max. 200)"
                } else {
                    loadedTemplate = "Import (\(created) Punkte geladen)"
                }
                isLoading = false
            }
        }
    }

    private func loadTemplate(_ template: (name: String, items: [(item: String, room: String, trade: String)])) {
        isLoading = true
        Task {
            do {
                for entry in template.items {
                    try await model.createHandoverItem(item: entry.item, room: entry.room, tradeType: entry.trade)
                }
                loadedTemplate = template.name
            } catch {
                model.actionError = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct DocumentsView: View {
    @Bindable var model: BaumioAppViewModel
    @Environment(\.openURL) private var openURL

    @State private var photoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var showingCamera = false
    @State private var docType = "sonstiges"
    @State private var isBusy = false
    @State private var message: String?
    @State private var isError = false

    private let docTypes: [(value: String, label: String)] = [
        ("vertrag", "Vertrag"), ("angebot", "Angebot"), ("rechnung", "Rechnung"),
        ("genehmigung", "Genehmigung"), ("plan", "Plan"), ("protokoll", "Protokoll"), ("sonstiges", "Sonstiges")
    ]

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        ScreenScaffold(title: "Dokumente", subtitle: "Dateien und Fotos sicher im privaten Speicher") {
            storageCard
            uploadCard

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(isError ? BaumioTheme.warning : BaumioTheme.success)
            }

            ForEach(DocumentCategory.allCases) { category in
                let docs = model.documents.filter { $0.category == category }
                if !docs.isEmpty {
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.rawValue).font(.headline).foregroundStyle(BaumioTheme.primaryText)
                            ForEach(docs) { document in
                                documentRow(document)
                            }
                        }
                    }
                }
            }

            if model.documents.isEmpty {
                EmptyStateView(
                    title: "Noch keine Dokumente",
                    message: "Lade dein erstes Dokument oder Foto hoch – es wird komprimiert und privat gespeichert.",
                    systemImage: "doc.text"
                )
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingCamera) {
            CameraCapturePicker { data in
                let compressed = ImageCompression.compressedJPEG(from: data) ?? data
                Task {
                    isBusy = true
                    defer { isBusy = false }
                    do {
                        let stamp = Date().formatted(date: .abbreviated, time: .omitted)
                        try await model.uploadDocument(name: "Foto \(stamp)", docType: docType, data: compressed, contentType: "image/jpeg", fileExtension: "jpg")
                        show("Foto hochgeladen.", isError: false)
                    } catch { model.actionError = error.localizedDescription }
                }
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            handlePhotoSelection(newItem)
        }
    }

    private var storageCard: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Speicher", systemImage: "internaldrive")
                        .font(.headline)
                        .foregroundStyle(BaumioTheme.primaryText)
                    Spacer()
                    Text("\(Self.byteFormatter.string(fromByteCount: Int64(model.storageUsedBytes))) / \(Self.byteFormatter.string(fromByteCount: Int64(model.storageLimitBytes)))")
                        .font(.subheadline.bold())
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
                ProgressView(value: model.storageUsedFraction)
                    .tint(model.storageUsedFraction > 0.9 ? BaumioTheme.danger : BaumioTheme.accent)
                if !model.isPro {
                    Text("Free-Plan: 500 MB · mit Baumio Pro 5 GB")
                        .font(.caption)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
            }
        }
    }

    private var uploadCard: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Kategorie", selection: $docType) {
                    ForEach(docTypes, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.menu)

                HStack(spacing: 8) {
                    if CameraCapturePicker.isAvailable {
                        Button { showingCamera = true } label: {
                            Label("Kamera", systemImage: "camera")
                                .font(.footnote.bold())
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(BaumioTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: BaumioTheme.controlRadius))
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Bibliothek", systemImage: "photo")
                            .font(.footnote.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(BaumioTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: BaumioTheme.controlRadius))
                    }
                    Button { showingFileImporter = true } label: {
                        Label("PDF/Datei", systemImage: "doc.badge.plus")
                            .font(.footnote.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(BaumioTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: BaumioTheme.controlRadius))
                    }
                }
                .foregroundStyle(BaumioTheme.primaryText)
                .disabled(isBusy || model.selectedProject == nil)

                if isBusy {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Wird hochgeladen …").font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
                    }
                }
            }
        }
    }

    private func documentRow(_ document: DocumentItem) -> some View {
        HStack {
            Button {
                openDocument(document)
            } label: {
                ItemLine(icon: "doc.text", title: document.title, subtitle: document.fileSize > 0 ? Self.byteFormatter.string(fromByteCount: Int64(document.fileSize)) : document.fileType, tint: BaumioTheme.accent)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(role: .destructive) {
                model.handle { try await model.deleteDocument(document) }
            } label: {
                Image(systemName: "trash").foregroundStyle(BaumioTheme.danger).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dokument löschen")
        }
    }

    private func openDocument(_ document: DocumentItem) {
        Task {
            do {
                let url = try await model.documentURL(document)
                openURL(url)
            } catch {
                show(error.localizedDescription, isError: true)
            }
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) {
        Task {
            isBusy = true
            defer { isBusy = false; photoItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    model.actionError = "Foto konnte nicht geladen werden."; return
                }
                let compressed = ImageCompression.compressedJPEG(from: data) ?? data
                let stamp = Date().formatted(date: .abbreviated, time: .omitted)
                try await model.uploadDocument(name: "Foto \(stamp)", docType: docType, data: compressed, contentType: "image/jpeg", fileExtension: "jpg")
                show("Foto hochgeladen.", isError: false)
            } catch {
                model.actionError = error.localizedDescription
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            model.actionError = error.localizedDescription
            return
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                isBusy = true
                defer { isBusy = false }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    var data = try Data(contentsOf: url)
                    let ext = url.pathExtension.lowercased()
                    var contentType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
                    if UTType(filenameExtension: ext)?.conforms(to: .image) == true, let c = ImageCompression.compressedJPEG(from: data) {
                        data = c
                        contentType = "image/jpeg"
                    }
                    try await model.uploadDocument(name: url.deletingPathExtension().lastPathComponent, docType: docType, data: data, contentType: contentType, fileExtension: ext)
                    show("Datei hochgeladen.", isError: false)
                } catch {
                    model.actionError = error.localizedDescription
                }
            }
        }
    }

    private func show(_ text: String, isError: Bool) {
        message = text
        self.isError = isError
    }
}

/// Reduziert Bilder vor dem Upload (Auflösung + JPEG-Kompression) für kleinere Dateien.
enum ImageCompression {
    static func compressedJPEG(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}

private struct MonthlyPaidEntry: Identifiable {
    let id = UUID()
    let month: Date
    let amount: Double
}

struct CostsView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var showingScanner = false
    @State private var deletingCost: CostItem?
    @State private var searchText = ""
    @State private var csvExportSheet: ShareableURL?

    private var filteredCosts: [CostItem] {
        guard !searchText.isEmpty else { return model.costs }
        let q = searchText.lowercased()
        return model.costs.filter {
            $0.title.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            $0.trade.lowercased().contains(q) ||
            $0.supplier.lowercased().contains(q) ||
            $0.invoiceReference.lowercased().contains(q)
        }
    }

    var body: some View {
        ScreenScaffold(title: "Kosten", subtitle: "Budgetvergleich und Rechnungen") {
            if model.canCreateCost {
                PrimaryButton(title: "Kosten erfassen", systemImage: "plus", action: { showingEditor = true })
                if model.isPro {
                    SecondaryButton(title: "Rechnung scannen", systemImage: "doc.viewfinder") {
                        showingScanner = true
                    }
                }
            } else {
                Button { model.selectedSection = .pricing } label: {
                    BaumioCard {
                        HStack {
                            Image(systemName: "lock.fill").foregroundStyle(BaumioTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Limit erreicht (\(BaumioAppViewModel.freeCostLimit) Positionen)").font(.subheadline.bold()).foregroundStyle(BaumioTheme.primaryText)
                                Text("Mit Pro: unbegrenzte Kostenpositionen, vollständige Budget-Übersicht").font(.caption).foregroundStyle(BaumioTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(BaumioTheme.secondaryText)
                        }
                    }
                }
            }
            if model.costs.isEmpty && model.materials.isEmpty {
                EmptyStateView(
                    title: "Keine Kosten vorhanden",
                    message: model.usesSupabase ? "Für diesen Supabase-Account wurden noch keine Kosten geladen." : "Erfasse die ersten Kosten für dein Projekt.",
                    systemImage: "eurosign.circle"
                )
            } else {
                AdaptiveGrid(minimum: 170) {
                    DashboardMetricCard(title: "Budget", value: (model.selectedProject?.budget ?? 0).euroString, subtitle: "\(availableBudget.euroString) verfügbar", systemImage: "target")
                    DashboardMetricCard(title: "Geplant", value: model.plannedCosts.euroString, subtitle: "inkl. Materialliste", systemImage: "sum", tint: BaumioTheme.info)
                    DashboardMetricCard(title: "Bestellt", value: model.orderedCosts.euroString, subtitle: "aktuelle Aufträge", systemImage: "cart")
                    DashboardMetricCard(title: "Bezahlt", value: model.paidCosts.euroString, subtitle: "Rechnungen bezahlt", systemImage: "checkmark.seal", tint: BaumioTheme.success)
                }
                if let project = model.selectedProject, project.eigenkapital > 0 || project.kredit > 0 || !model.funding.isEmpty {
                    FinanzierungsCard(project: project, foerderungSumme: model.funding.reduce(0) { $0 + $1.maxAmount }, geplanteSumme: model.plannedCosts)
                }
                if !tradesWithBudget.isEmpty {
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Budget-Ampel").font(.headline).foregroundStyle(BaumioTheme.primaryText)
                            ForEach(tradesWithBudget) { trade in
                                let label = trade.tradeType.isEmpty ? trade.company : trade.tradeType
                                let ratio = trade.budget > 0 ? NSDecimalNumber(decimal: trade.costs / trade.budget).doubleValue : 0
                                VStack(spacing: 4) {
                                    HStack(spacing: 8) {
                                        Circle().fill(ampelColor(trade.costs, budget: trade.budget)).frame(width: 10, height: 10)
                                        Text(label).font(.subheadline).foregroundStyle(BaumioTheme.primaryText)
                                        Spacer()
                                        Text(trade.costs.euroString).font(.subheadline.bold()).foregroundStyle(ampelColor(trade.costs, budget: trade.budget))
                                        Text("/ \(trade.budget.euroString)").font(.caption).foregroundStyle(BaumioTheme.secondaryText)
                                    }
                                    ProgressView(value: min(ratio, 1)).tint(ampelColor(trade.costs, budget: trade.budget))
                                }
                            }
                        }
                    }
                }
                if !monthlyCosts.isEmpty {
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ausgaben pro Monat").font(.headline).foregroundStyle(BaumioTheme.primaryText)
                            Chart(monthlyCosts) { entry in
                                BarMark(
                                    x: .value("Monat", entry.month, unit: .month),
                                    y: .value("Bezahlt", entry.amount)
                                )
                                .foregroundStyle(BaumioTheme.accent)
                                .cornerRadius(4)
                            }
                            .frame(height: 160)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .month)) { _ in
                                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                                }
                            }
                        }
                    }
                }
                if !model.costs.isEmpty && filteredCosts.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
                ForEach(filteredCosts) { cost in
                    let overBudget = cost.paid > cost.planned && cost.planned > 0
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                ItemLine(icon: "eurosign.circle", title: cost.title, subtitle: "\(cost.category) · \(cost.trade)", tint: overBudget ? BaumioTheme.danger : BaumioTheme.accent)
                                Spacer()
                                if overBudget {
                                    StatusBadge(title: "Überschritten", color: BaumioTheme.danger)
                                }
                                Menu {
                                    Button("Bearbeiten") { editingItem = .cost(cost) }
                                    Button("Löschen", role: .destructive) {
                                        deletingCost = cost
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Kosten bearbeiten oder löschen")
                            }
                            HStack {
                                Text("Geplant: \(cost.planned.euroString)")
                                Spacer()
                                Text("Bestellt: \(cost.ordered.euroString)")
                            }
                            .font(.footnote.bold())
                            .foregroundStyle(BaumioTheme.secondaryText)
                            HStack {
                                Text("Bezahlt: \(cost.paid.euroString)")
                                    .foregroundStyle(overBudget ? BaumioTheme.danger : BaumioTheme.secondaryText)
                                Spacer()
                                Menu {
                                    Button("Offen") { model.handle { try await model.updateCostStatus(cost, status: "offen") } }
                                    Button("Beauftragt") { model.handle { try await model.updateCostStatus(cost, status: "beauftragt") } }
                                    Button("Bezahlt") { model.handle { try await model.updateCostStatus(cost, status: "bezahlt") } }
                                    Button("Storniert") { model.handle { try await model.updateCostStatus(cost, status: "storniert") } }
                                } label: {
                                    StatusBadge(title: cost.status, color: cost.status.lowercased() == "bezahlt" ? BaumioTheme.success : BaumioTheme.info)
                                }
                                .accessibilityLabel("Kostenstatus ändern")
                            }
                            .font(.footnote.bold())
                            if !cost.invoiceReference.isEmpty {
                                Text("Rechnung: \(cost.invoiceReference)").font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
                            }
                            if cost.isInvoice {
                                HStack(spacing: 8) {
                                    if cost.laborAmount > 0 {
                                        Label("Arbeit: \(cost.laborAmount.euroString)", systemImage: "person.fill")
                                    }
                                    if cost.machineAmount > 0 {
                                        Label("Maschine: \(cost.machineAmount.euroString)", systemImage: "wrench")
                                    }
                                    if cost.travelAmount > 0 {
                                        Label("Fahrt: \(cost.travelAmount.euroString)", systemImage: "car")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(BaumioTheme.success)
                            }
                            PhotoSection(model: model, bucket: "cost-photos", photos: model.costPhotos[cost.id] ?? []) { data in
                                model.handle { try await model.addCostPhoto(cost, imageData: data) }
                            }
                        }
                    }
                    .overlay(alignment: .leading) {
                        if overBudget {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(BaumioTheme.danger)
                                .frame(width: 3)
                                .padding(.vertical, 4)
                        }
                    }
                }

                if !model.materials.isEmpty {
                    let totals = model.materialCostTotals
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                ItemLine(icon: "shippingbox", title: "Materialliste", subtitle: "\(model.materials.count) Positionen · Summe", tint: BaumioTheme.accent)
                                Spacer()
                                StatusBadge(title: "aus Materialliste", color: BaumioTheme.secondaryText)
                            }
                            HStack {
                                Text("Geplant: \(totals.planned.euroString)")
                                Spacer()
                                Text("Bestellt: \(totals.ordered.euroString)")
                            }
                            .font(.footnote.bold())
                            .foregroundStyle(BaumioTheme.secondaryText)
                            Text("Bezahlt: \(totals.paid.euroString)")
                                .font(.footnote.bold())
                                .foregroundStyle(BaumioTheme.secondaryText)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Kosten suchen …")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    var rows: [[String]] = [["Titel", "Geplant (€)", "Bezahlt (€)", "Kategorie", "Status", "Lieferant", "Rechnungsnummer"]]
                    for c in model.costs {
                        rows.append([c.title, "\(c.planned)", "\(c.paid)", c.category, c.status, c.supplier, c.invoiceReference])
                    }
                    if let url = csvURL(rows, fileName: "Baumio_Kosten.csv") { csvExportSheet = ShareableURL(url: url) }
                } label: {
                    Label("Als CSV exportieren", systemImage: "tablecells")
                }
                .disabled(model.costs.isEmpty)
            }
        }
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .cost, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(isPresented: $showingScanner) {
            DocumentScannerSheet(docType: .rechnung, model: model)
        }
        .sheet(item: $csvExportSheet) { shareable in
            ShareSheet(items: [shareable.url])
        }
        .alert("Kostenposition löschen?", isPresented: Binding(get: { deletingCost != nil }, set: { if !$0 { deletingCost = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingCost = nil }
            Button("Löschen", role: .destructive) {
                if let c = deletingCost { model.handle { try await model.deleteCost(c) }; deletingCost = nil }
            }
        } message: {
            Text("\(deletingCost?.title ?? "diese Position") wird unwiderruflich gelöscht.")
        }
    }

    private var availableBudget: Decimal {
        (model.selectedProject?.budget ?? 0) - model.plannedCosts
    }

    private var tradesWithBudget: [Trade] {
        model.trades.filter { $0.budget > 0 }
    }

    private func ampelColor(_ costs: Decimal, budget: Decimal) -> Color {
        guard budget > 0 else { return BaumioTheme.success }
        let ratio = NSDecimalNumber(decimal: costs / budget).doubleValue
        if ratio >= 1.0 { return BaumioTheme.danger }
        if ratio >= 0.8 { return BaumioTheme.warning }
        return BaumioTheme.success
    }

    private var monthlyCosts: [MonthlyPaidEntry] {
        let calendar = Calendar.current
        var grouped: [Date: Double] = [:]
        for cost in model.costs {
            guard let date = cost.paymentDate ?? cost.invoiceDate, cost.paid > 0 else { continue }
            let comps = calendar.dateComponents([.year, .month], from: date)
            guard let monthStart = calendar.date(from: comps) else { continue }
            grouped[monthStart, default: 0] += NSDecimalNumber(decimal: cost.paid).doubleValue
        }
        return grouped.map { MonthlyPaidEntry(month: $0.key, amount: $0.value) }
            .sorted { $0.month < $1.month }
    }
}

struct OffersView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var showingScanner = false

    private var groupedOffers: [(scope: String, offers: [OfferItem])] {
        var groups: [(scope: String, offers: [OfferItem])] = []
        var usedIDs = Set<UUID>()

        // Zuerst nach expliziter Ausschreibungsbezeichnung (scope) gruppieren
        let byScope = Dictionary(grouping: model.offers.filter { !$0.scope.isEmpty }) { $0.scope }
        for (key, values) in byScope.sorted(by: { $0.key < $1.key }) {
            guard values.count >= 2 else { continue }
            groups.append((scope: key, offers: values.sorted { $0.amount < $1.amount }))
            values.forEach { usedIDs.insert($0.id) }
        }

        // Fallback: verbleibende Angebote nach Gewerk (trade) gruppieren
        let remaining = model.offers.filter { !usedIDs.contains($0.id) && !$0.trade.isEmpty }
        let byTrade = Dictionary(grouping: remaining) { $0.trade }
        for (key, values) in byTrade.sorted(by: { $0.key < $1.key }) {
            guard values.count >= 2 else { continue }
            groups.append((scope: key, offers: values.sorted { $0.amount < $1.amount }))
            values.forEach { usedIDs.insert($0.id) }
        }

        return groups
    }

    private var ungroupedOffers: [OfferItem] {
        let groupedIDs = Set(groupedOffers.flatMap { $0.offers.map { $0.id } })
        return model.offers.filter { !groupedIDs.contains($0.id) }
    }

    var body: some View {
        ListScreen(title: "Angebote", subtitle: "Angebotsvergleich nach Anbieter, Betrag und Gewerk") {
            PrimaryButton(title: "Angebot anlegen", systemImage: "plus", action: { showingEditor = true })
            if model.isPro {
                SecondaryButton(title: "Angebot scannen", systemImage: "doc.viewfinder") {
                    showingScanner = true
                }
            }

            if model.offers.isEmpty {
                EmptyStateView(
                    title: "Keine Angebote vorhanden",
                    message: "Erfasse Angebote von verschiedenen Firmen. Mit einer Ausschreibungsbezeichnung werden sie automatisch verglichen.",
                    systemImage: "doc.badge.clock"
                )
            }

            if !groupedOffers.isEmpty {
                Text("Angebotsvergleiche")
                    .font(.headline)
                    .foregroundStyle(BaumioTheme.primaryText)
                    .padding(.top, 4)

                ForEach(groupedOffers, id: \.scope) { group in
                    OfferComparisonCard(scope: group.scope, offers: group.offers, model: model) { offer in
                        editingItem = .offer(offer)
                    }
                }
            }

            if !ungroupedOffers.isEmpty {
                Text(groupedOffers.isEmpty ? "Angebote" : "Einzelangebote")
                    .font(.headline)
                    .foregroundStyle(BaumioTheme.primaryText)
                    .padding(.top, 4)
                ForEach(ungroupedOffers) { offer in
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                ItemLine(icon: "doc.badge.clock", title: offer.provider, subtitle: offer.title.isEmpty ? offer.amount.euroString : "\(offer.title) · \(offer.amount.euroString)", tint: BaumioTheme.accent)
                                Spacer()
                                Menu {
                                    Button("Bearbeiten") { editingItem = .offer(offer) }
                                    Button("Löschen", role: .destructive) {
                                        model.handle { try await model.deleteOffer(offer) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Angebot bearbeiten oder löschen")
                                Menu {
                                    Button("Erhalten") { model.handle { try await model.updateOfferStatus(offer, status: "Erhalten") } }
                                    Button("Angenommen") { model.handle { try await model.updateOfferStatus(offer, status: "Angenommen") } }
                                    Button("Abgelehnt") { model.handle { try await model.updateOfferStatus(offer, status: "Abgelehnt") } }
                                } label: {
                                    StatusBadge(title: offer.status, color: offer.status == "Angenommen" ? BaumioTheme.success : BaumioTheme.secondaryText)
                                }
                                .accessibilityLabel("Angebotsstatus ändern")
                            }
                            if let validUntil = offer.validUntil {
                                Text("Gültig bis: \(validUntil.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(validUntil < Date() ? BaumioTheme.danger : BaumioTheme.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .offer, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(isPresented: $showingScanner) {
            DocumentScannerSheet(docType: .angebot, model: model)
        }
    }
}

// MARK: - Visitenkarten-Scanner

struct VisitenkarteScannerSheet: View {
    @Bindable var model: BaumioAppViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ocrConsentGiven") private var consentGiven = false

    enum Step { case consent, picking, scanning, confirming }
    @State private var step: Step = .consent
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    @State private var vName = ""
    @State private var vCompany = ""
    @State private var vTradeType = ""
    @State private var vAddress = ""
    @State private var vPhone = ""
    @State private var vEmail = ""
    @State private var vNotes = ""
    @State private var vBudget = ""

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .consent:   consentView
                case .picking:   pickingView
                case .scanning:  scanningView
                case .confirming: confirmingView
                }
            }
            .navigationTitle("Visitenkarte scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                if step == .confirming {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Speichert …" : "Speichern") {
                            Task { await save() }
                        }
                        .disabled(isSaving || (vCompany.trimmingCharacters(in: .whitespaces).isEmpty && vName.trimmingCharacters(in: .whitespaces).isEmpty))
                    }
                }
            }
        }
        .onAppear { if consentGiven { step = .picking } }
        .sheet(isPresented: $showingCamera) {
            CameraCapturePicker { data in
                Task { await processImageData(data, mimeType: "image/jpeg") }
            }
        }
    }

    private var consentView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 60)).foregroundStyle(BaumioTheme.accent)
                Text("KI-Visitenkartenscan")
                    .font(.title2.bold())
                Text("Das Bild wird zur Texterkennung einmalig an **Google Gemini** (USA) übertragen. Google verarbeitet das Bild und gibt die erkannten Felder zurück. Das Bild wird von Google nach der Verarbeitung nicht gespeichert.\n\nRechtsgrundlage: Vertragserfüllung (Art. 6 Abs. 1 lit. b DSGVO).")
                    .font(.body).multilineTextAlignment(.center).foregroundStyle(BaumioTheme.secondaryText)
                PrimaryButton(title: "Verstanden & fortfahren", systemImage: "checkmark") {
                    consentGiven = true
                    step = .picking
                }
            }
            .padding(32)
        }
    }

    private var pickingView: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "person.text.rectangle").font(.system(size: 72)).foregroundStyle(BaumioTheme.accent)
            Text("Visitenkarte fotografieren oder aus der Mediathek wählen")
                .font(.headline).multilineTextAlignment(.center).padding(.horizontal)
            VStack(spacing: 12) {
                if CameraCapturePicker.isAvailable {
                    Button { showingCamera = true } label: {
                        Label("Kamera", systemImage: "camera")
                            .frame(maxWidth: .infinity).padding()
                            .background(BaumioTheme.accent).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Foto aus Bibliothek", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity).padding()
                        .background(BaumioTheme.elevatedSurface).foregroundStyle(BaumioTheme.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
                }
                .onChange(of: pickerItem) { _, item in
                    guard item != nil else { return }
                    Task { await processPickedImage() }
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(BaumioTheme.danger)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            Spacer()
        }
    }

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView().scaleEffect(2)
            Text("KI liest Visitenkarte …").font(.headline).foregroundStyle(BaumioTheme.secondaryText)
            Spacer()
        }
    }

    private var confirmingView: some View {
        Form {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(BaumioTheme.warning) }
            }
            Section("Erkannte Felder – bitte prüfen") {
                LabeledContent("Name") {
                    TextField("Ansprechpartner", text: $vName).multilineTextAlignment(.trailing)
                }
                LabeledContent("Firma") {
                    TextField("Firmenname", text: $vCompany).multilineTextAlignment(.trailing)
                }
                Picker("Gewerksart", selection: $vTradeType) {
                    Text("Bitte wählen").tag("")
                    ForEach(tradeTypeOptions, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Adresse") {
                    TextField("Adresse", text: $vAddress).multilineTextAlignment(.trailing)
                }
                LabeledContent("Telefon") {
                    TextField("Telefonnummer", text: $vPhone).multilineTextAlignment(.trailing)
                        .keyboardType(.phonePad)
                }
                LabeledContent("E-Mail") {
                    TextField("E-Mail-Adresse", text: $vEmail).multilineTextAlignment(.trailing)
                        .keyboardType(.emailAddress).autocorrectionDisabled()
                }
                TextField("Budget (€)", text: $vBudget).decimalOnly($vBudget)
                TextField("Notizen", text: $vNotes, axis: .vertical).lineLimit(2...4)
            }
        }
    }

    private func processPickedImage() async {
        guard let item = pickerItem else { return }
        step = .scanning
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Bild konnte nicht geladen werden."
                step = .picking; return
            }
            await processImageData(data, mimeType: "image/jpeg")
        } catch {
            errorMessage = error.localizedDescription
            step = .picking
        }
    }

    private func processImageData(_ data: Data, mimeType: String) async {
        step = .scanning
        do {
            let result = try await model.scanVisitenkarte(imageData: data, mimeType: mimeType)
            vName = result.name
            vCompany = result.company
            vTradeType = result.tradeType
            vAddress = result.address
            vPhone = result.phone
            vEmail = result.email
            step = .confirming
        } catch {
            errorMessage = error.localizedDescription
            step = .picking
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let parsedBudget = Decimal(string: vBudget.replacingOccurrences(of: ",", with: ".")) ?? 0
            let name = vCompany.isEmpty ? vName : vCompany
            try await model.createTrade(name: name, company: vCompany, tradeType: vTradeType, address: vAddress, phone: vPhone, email: vEmail, budget: parsedBudget, notes: vNotes)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - KI-Dokumentenscanner

struct DocumentScannerSheet: View {
    enum DocType { case rechnung, angebot }
    enum Step { case consent, picking, scanning, confirming }

    let docType: DocType
    @Bindable var model: BaumioAppViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ocrConsentGiven") private var consentGiven = false

    @State private var step: Step = .consent
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingFilePicker = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var scannedImageData: Data?
    @State private var scannedMimeType: String = "image/jpeg"
    @State private var saveAsDocument = true

    // Rechnung-Felder
    @State private var rFirma = ""
    @State private var rBetrag = ""
    @State private var rNummer = ""
    @State private var rDatum = Date()
    @State private var rFaellig = Date()
    @State private var rGewerk = ""
    @State private var rArbeit = ""
    @State private var rFahrt = ""
    @State private var rStatus = "offen"
    @State private var rNotes = ""

    // Angebot-Felder
    @State private var aFirma = ""
    @State private var aBetrag = ""
    @State private var aNummer = ""
    @State private var aLeistung = ""
    @State private var aGueltigBis = Date()
    @State private var aGewerk = ""
    @State private var aScope = ""
    @State private var aNotes = ""

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .consent:   consentView
                case .picking:   pickingView
                case .scanning:  scanningView
                case .confirming: confirmingView
                }
            }
            .navigationTitle(docType == .rechnung ? "Rechnung scannen" : "Angebot scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                if step == .confirming {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Speichert …" : "Speichern") {
                            Task { await save() }
                        }
                        .disabled(isSaving)
                    }
                }
            }
        }
        .onAppear { if consentGiven { step = .picking } }
        .sheet(isPresented: $showingCamera) {
            CameraCapturePicker { data in
                Task { await processImageData(data, mimeType: "image/jpeg") }
            }
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "PDF konnte nicht gelesen werden."
                return
            }
            Task { await processImageData(data, mimeType: "application/pdf") }
        }
    }

    // ── Consent ──────────────────────────────────────────────
    private var consentView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 60))
                    .foregroundStyle(BaumioTheme.accent)
                Text("KI-Dokumentenscan")
                    .font(.title2.bold())
                Text("Das Bild wird zur Texterkennung einmalig an **Google Gemini** (USA) übertragen. Google verarbeitet das Bild und gibt die erkannten Felder zurück. Das Bild wird von Google nach der Verarbeitung nicht gespeichert.\n\nRechtsgrundlage: Vertragserfüllung (Art. 6 Abs. 1 lit. b DSGVO). Drittlandübertragung über EU-Standardvertragsklauseln.\n\nWeitere Infos in unserer Datenschutzerklärung.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BaumioTheme.secondaryText)
                PrimaryButton(title: "Verstanden & fortfahren", systemImage: "checkmark") {
                    consentGiven = true
                    step = .picking
                }
            }
            .padding(32)
        }
    }

    // ── Picker ───────────────────────────────────────────────
    private var pickingView: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: docType == .rechnung ? "doc.text.viewfinder" : "doc.badge.plus")
                .font(.system(size: 72))
                .foregroundStyle(BaumioTheme.accent)
            Text(docType == .rechnung
                 ? "Rechnung fotografieren oder aus der Mediathek wählen"
                 : "Angebot fotografieren oder aus der Mediathek wählen")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            VStack(spacing: 12) {
                if CameraCapturePicker.isAvailable {
                    Button { showingCamera = true } label: {
                        Label("Kamera", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(BaumioTheme.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Foto aus Bibliothek", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(BaumioTheme.elevatedSurface)
                        .foregroundStyle(BaumioTheme.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }
                .onChange(of: pickerItem) { _, item in
                    guard item != nil else { return }
                    Task { await processPickedImage() }
                }
                Button { showingFilePicker = true } label: {
                    Label("PDF aus Dateien wählen", systemImage: "doc.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(BaumioTheme.elevatedSurface)
                        .foregroundStyle(BaumioTheme.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(BaumioTheme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
        }
    }

    // ── Scanning ─────────────────────────────────────────────
    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView().scaleEffect(2)
            Text("KI analysiert das Dokument …")
                .font(.headline)
                .foregroundStyle(BaumioTheme.secondaryText)
            Spacer()
        }
    }

    // ── Bestätigung ──────────────────────────────────────────
    private var confirmingView: some View {
        Form {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(BaumioTheme.warning) }
            }
            Section {
                Toggle("Scan als Dokument speichern", isOn: $saveAsDocument)
                    .tint(BaumioTheme.accent)
            }
            if docType == .rechnung {
                Section("Erkannte Felder – bitte prüfen") {
                    LabeledContent("Firma") {
                        TextField("Firma / Aussteller", text: $rFirma).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Betrag (€)") {
                        TextField("0,00", text: $rBetrag).multilineTextAlignment(.trailing).decimalOnly($rBetrag)
                    }
                    LabeledContent("Rechnungsnummer") {
                        TextField("–", text: $rNummer).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Rechnungsdatum", selection: $rDatum, displayedComponents: .date)
                    DatePicker("Fällig am", selection: $rFaellig, displayedComponents: .date)
                    LabeledContent("Gewerk") {
                        TextField("optional", text: $rGewerk).multilineTextAlignment(.trailing)
                    }
                }
                Section("Kostenaufteilung §35a (optional)") {
                    LabeledContent("Arbeitskosten (€)") {
                        TextField("0,00", text: $rArbeit).multilineTextAlignment(.trailing).decimalOnly($rArbeit)
                    }
                    LabeledContent("Fahrtkosten (€)") {
                        TextField("0,00", text: $rFahrt).multilineTextAlignment(.trailing).decimalOnly($rFahrt)
                    }
                }
                Section("Status") {
                    Picker("Status", selection: $rStatus) {
                        Text("Offen").tag("offen")
                        Text("Beauftragt").tag("beauftragt")
                        Text("Bezahlt").tag("bezahlt")
                    }
                }
                Section("Notizen") {
                    TextField("Notizen (optional)", text: $rNotes, axis: .vertical).lineLimit(2...4)
                }
            } else {
                Section("Erkannte Felder – bitte prüfen") {
                    LabeledContent("Firma") {
                        TextField("Firma / Anbieter", text: $aFirma).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Betrag (€)") {
                        TextField("0,00", text: $aBetrag).multilineTextAlignment(.trailing).decimalOnly($aBetrag)
                    }
                    LabeledContent("Leistung / Titel") {
                        TextField("–", text: $aLeistung).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Angebotsnummer") {
                        TextField("–", text: $aNummer).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Gewerk") {
                        TextField("optional", text: $aGewerk).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Gültig bis", selection: $aGueltigBis, displayedComponents: .date)
                }
                Section("Vergleichsgruppe") {
                    TextField("Ausschreibung (optional)", text: $aScope)
                    Text("Gleiche Bezeichnung bei mehreren Firmen → automatischer Preisvergleich.")
                        .font(.caption)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
                Section("Notizen") {
                    TextField("Notizen (optional)", text: $aNotes, axis: .vertical).lineLimit(2...4)
                }
            }
        }
    }

    // ── Logik ────────────────────────────────────────────────
    private func processPickedImage() async {
        guard let item = pickerItem else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = "Bild konnte nicht geladen werden."
            pickerItem = nil
            return
        }
        await processImageData(data)
        pickerItem = nil
    }

    private func processImageData(_ data: Data, mimeType: String = "image/jpeg") async {
        step = .scanning
        errorMessage = nil
        let isImage = mimeType.hasPrefix("image/")
        let finalData = isImage ? (ImageCompression.compressedJPEG(from: data) ?? data) : data
        let finalMime = isImage ? "image/jpeg" : mimeType
        do {
            switch docType {
            case .rechnung:
                let result = try await model.scanRechnung(imageData: finalData, mimeType: finalMime)
                prefillRechnung(result)
            case .angebot:
                let result = try await model.scanAngebot(imageData: finalData, mimeType: finalMime)
                prefillAngebot(result)
            }
            scannedImageData = finalData
            scannedMimeType = finalMime
            step = .confirming
        } catch {
            errorMessage = error.localizedDescription
            step = .picking
        }
    }

    private func prefillRechnung(_ r: RechnungScanResult) {
        rFirma  = r.firma
        rBetrag = r.betrag > 0 ? NSDecimalNumber(decimal: r.betrag).stringValue : ""
        rNummer = r.rechnungsnummer
        rGewerk = r.gewerk
        rArbeit = r.arbeitskosten > 0 ? NSDecimalNumber(decimal: r.arbeitskosten).stringValue : ""
        rFahrt  = r.fahrkosten > 0 ? NSDecimalNumber(decimal: r.fahrkosten).stringValue : ""
        if let d = r.datum        { rDatum  = d }
        if let f = r.faelligAm   { rFaellig = f }
    }

    private func prefillAngebot(_ a: AngebotScanResult) {
        aFirma     = a.firma
        aBetrag    = a.betrag > 0 ? NSDecimalNumber(decimal: a.betrag).stringValue : ""
        aNummer    = a.angebotsnummer
        aLeistung  = a.leistung
        aGewerk    = a.gewerk
        if let d = a.gueltigBis { aGueltigBis = d }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            if docType == .rechnung {
                let betrag = Decimal(string: rBetrag.replacingOccurrences(of: ",", with: ".")) ?? 0
                let labor  = Decimal(string: rArbeit.replacingOccurrences(of: ",", with: ".")) ?? 0
                let fahrt  = Decimal(string: rFahrt.replacingOccurrences(of: ",", with: ".")) ?? 0
                let hasInvoice = betrag > 0
                try await model.createCost(
                    title: rFirma.isEmpty ? "Rechnung" : rFirma,
                    amount: betrag,
                    category: rGewerk.isEmpty ? "sonstiges" : "lohn",
                    status: rStatus,
                    invoiceReference: rNummer,
                    notes: rNotes,
                    invoiceDate: hasInvoice ? rDatum : nil,
                    dueDate: hasInvoice ? rFaellig : nil,
                    laborAmount: labor,
                    travelAmount: fahrt
                )
                if saveAsDocument, let data = scannedImageData {
                    let ext = scannedMimeType.contains("pdf") ? "pdf" : "jpg"
                    let docName = rFirma.isEmpty ? "Rechnung" : "Rechnung \(rFirma)"
                    try? await model.uploadDocument(name: docName, docType: "rechnung", data: data, contentType: scannedMimeType, fileExtension: ext)
                }
            } else {
                let betrag = Decimal(string: aBetrag.replacingOccurrences(of: ",", with: ".")) ?? 0
                try await model.createOffer(
                    title: aLeistung.isEmpty ? aFirma : aLeistung,
                    company: aFirma,
                    amount: betrag,
                    validUntil: aGueltigBis,
                    status: "Erhalten",
                    notes: aNotes,
                    scope: aScope
                )
                if saveAsDocument, let data = scannedImageData {
                    let ext = scannedMimeType.contains("pdf") ? "pdf" : "jpg"
                    let docName = aFirma.isEmpty ? "Angebot" : "Angebot \(aFirma)"
                    try? await model.uploadDocument(name: docName, docType: "angebot", data: data, contentType: scannedMimeType, fileExtension: ext)
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct OfferComparisonCard: View {
    let scope: String
    let offers: [OfferItem]
    @Bindable var model: BaumioAppViewModel
    let onEdit: (OfferItem) -> Void

    private var cheapest: OfferItem? { offers.min(by: { $0.amount < $1.amount }) }
    private var mostExpensive: OfferItem? { offers.max(by: { $0.amount < $1.amount }) }
    private var hasAccepted: Bool { offers.contains { $0.status == "Angenommen" } }

    var body: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(scope, systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundStyle(BaumioTheme.primaryText)
                    Spacer()
                    Text("\(offers.count) Angebote")
                        .font(.caption)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }

                // Preisbalken-Vergleich
                if let maxAmount = mostExpensive?.amount, maxAmount > 0 {
                    VStack(spacing: 6) {
                        ForEach(offers) { offer in
                            let fraction = maxAmount > 0
                                ? CGFloat(truncating: (offer.amount / maxAmount) as NSDecimalNumber)
                                : 0
                            let isCheapest = offer.id == cheapest?.id
                            HStack(spacing: 8) {
                                Text(offer.provider)
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.primaryText)
                                    .frame(width: 80, alignment: .leading)
                                    .lineLimit(1)
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isCheapest ? BaumioTheme.success : BaumioTheme.warning.opacity(0.7))
                                        .frame(width: max(4, geo.size.width * fraction), height: 20)
                                }
                                .frame(height: 20)
                                Text(offer.amount.euroString)
                                    .font(.caption.bold())
                                    .foregroundStyle(isCheapest ? BaumioTheme.success : BaumioTheme.primaryText)
                                    .frame(width: 80, alignment: .trailing)
                                if isCheapest && offers.count > 1 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(BaumioTheme.success)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Divider()
                ForEach(offers) { offer in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(offer.provider).font(.subheadline.bold())
                                if offer.status == "Angenommen" {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(BaumioTheme.success).font(.caption)
                                } else if offer.status == "Abgelehnt" {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(BaumioTheme.secondaryText).font(.caption)
                                }
                            }
                            if let validUntil = offer.validUntil {
                                Text("bis \(validUntil.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(validUntil < Date() ? BaumioTheme.danger : BaumioTheme.secondaryText)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(offer.amount.euroString)
                                .font(.subheadline.bold())
                                .foregroundStyle(offer.id == cheapest?.id ? BaumioTheme.success : BaumioTheme.primaryText)
                            if let cheapestOffer = cheapest, offer.id != cheapestOffer.id, cheapestOffer.amount > 0 {
                                Text("+\((offer.amount - cheapestOffer.amount).euroString)")
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.warning)
                            } else if offer.id == cheapest?.id && offers.count > 1 {
                                Text("günstigstes")
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.success)
                            }
                        }
                        Menu {
                            Button("Bearbeiten") { onEdit(offer) }
                            Button("Erhalten") { model.handle { try await model.updateOfferStatus(offer, status: "Erhalten") } }
                            Button("Annehmen") { model.handle { try await model.updateOfferStatus(offer, status: "Angenommen") } }
                            Button("Ablehnen") { model.handle { try await model.updateOfferStatus(offer, status: "Abgelehnt") } }
                            Button("Löschen", role: .destructive) { model.handle { try await model.deleteOffer(offer) } }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText)
                        }
                    }
                }
                if let cheapestOffer = cheapest, !hasAccepted {
                    Divider()
                    Button {
                        model.handle { try await model.acceptOfferAndCreateCost(cheapestOffer) }
                    } label: {
                        Label("Günstigstes annehmen & als Kosten erfassen", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(BaumioTheme.success)
                    }
                }
            }
        }
    }
}

/// Lädt ein privates Foto per signierter URL und zeigt es als Thumbnail.
struct RemoteThumbnail: View {
    @Bindable var model: BaumioAppViewModel
    let bucket: String
    let path: String
    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                ZStack {
                    BaumioTheme.elevatedSurface
                    Image(systemName: "photo.slash")
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
            } else if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        ZStack {
                            BaumioTheme.elevatedSurface
                            Image(systemName: "photo.slash").foregroundStyle(BaumioTheme.secondaryText)
                        }
                    } else {
                        BaumioTheme.elevatedSurface
                    }
                }
            } else {
                BaumioTheme.elevatedSurface
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task {
            do { url = try await model.photoURL(bucket: bucket, path: path) }
            catch { failed = true }
        }
    }
}

/// Titelbild eines Projekts aus lokalem FileManager-Cache.
struct ProjectCoverImage: View {
    let projectID: UUID
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .listRowInsets(EdgeInsets())
            }
        }
        .task(id: projectID) { await loadImageAsync() }
    }

    private func loadImageAsync() async {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("project_cover_\(projectID.uuidString).jpg")
        let loaded = await Task.detached(priority: .background) {
            (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
        }.value
        image = loaded
    }
}

/// Foto-Streifen mit Hinzufügen-Button (komprimiert vor dem Upload).
// MARK: - PencilKit canvas for digital signature
private struct PKCanvasRepresentable: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var tool: PKInkingTool = PKInkingTool(.pen, color: .black, width: 2)

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.tool = tool
        canvas.backgroundColor = .white
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PKCanvasRepresentable
        init(_ parent: PKCanvasRepresentable) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

private struct SignatureCaptureView: View {
    let item: HandoverItem
    @Bindable var model: BaumioAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Tippe oder zeichne deine Unterschrift im weißen Feld.")
                    .font(.subheadline)
                    .foregroundStyle(BaumioTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                PKCanvasRepresentable(drawing: $drawing)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(BaumioTheme.secondaryText.opacity(0.3), lineWidth: 1))
                    .padding(.horizontal)

                Button("Löschen") { drawing = PKDrawing() }
                    .foregroundStyle(BaumioTheme.danger)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Digitale Unterschrift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Speichern") {
                            guard !drawing.strokes.isEmpty else { return }
                            isSaving = true
                            Task {
                                let rect = CGRect(x: 0, y: 0, width: 600, height: 200)
                                let image = drawing.image(from: rect, scale: 2)
                                if let data = image.pngData() {
                                    model.handle { try await model.saveHandoverSignature(item, imageData: data) }
                                }
                                dismiss()
                            }
                        }
                        .disabled(drawing.strokes.isEmpty)
                    }
                }
            }
        }
    }
}

// MARK: - Inline comment section for defects
private struct CommentSection: View {
    let defect: DefectItem
    @Bindable var model: BaumioAppViewModel
    @State private var newComment = ""
    @State private var isExpanded = false
    @FocusState private var isInputFocused: Bool

    private var comments: [DefectComment] { model.defectComments[defect.id] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.footnote)
                    Text(comments.isEmpty ? "Kommentar hinzufügen" : "\(comments.count) Kommentar\(comments.count == 1 ? "" : "e")")
                        .font(.footnote.bold())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(BaumioTheme.accent)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(comments) { comment in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                if !comment.author.isEmpty {
                                    Text(comment.author)
                                        .font(.caption.bold())
                                        .foregroundStyle(BaumioTheme.primaryText)
                                }
                                Text(comment.text)
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                                Text(comment.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(BaumioTheme.secondaryText.opacity(0.7))
                            }
                            Spacer()
                            Button(role: .destructive) {
                                model.handle { try await model.deleteDefectComment(comment) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.danger)
                            }
                            .accessibilityLabel("Kommentar löschen")
                        }
                        .padding(8)
                        .background(BaumioTheme.secondaryText.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    HStack(spacing: 8) {
                        TextField("Neuer Kommentar …", text: $newComment, axis: .vertical)
                            .font(.footnote)
                            .focused($isInputFocused)
                            .lineLimit(1...3)
                        Button {
                            let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            model.handle { try await model.addDefectComment(defect, text: trimmed) }
                            newComment = ""
                            isInputFocused = false
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(newComment.trimmingCharacters(in: .whitespaces).isEmpty ? BaumioTheme.secondaryText : BaumioTheme.accent)
                        }
                        .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(8)
                    .background(BaumioTheme.secondaryText.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

struct PhotoSection: View {
    @Bindable var model: BaumioAppViewModel
    let bucket: String
    let photos: [PhotoRef]
    let onPick: (Data) -> Void
    @State private var item: PhotosPickerItem?
    @State private var showingCamera = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            RemoteThumbnail(model: model, bucket: bucket, path: photo.storagePath)
                        }
                    }
                }
            }
            HStack(spacing: 16) {
                if CameraCapturePicker.isAvailable {
                    Button { showingCamera = true } label: {
                        Label("Kamera", systemImage: "camera")
                            .font(.footnote.bold())
                            .foregroundStyle(BaumioTheme.accent)
                    }
                }
                PhotosPicker(selection: $item, matching: .images) {
                    Label("Bibliothek", systemImage: "photo")
                        .font(.footnote.bold())
                        .foregroundStyle(BaumioTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraCapturePicker { data in
                onPick(ImageCompression.compressedJPEG(from: data) ?? data)
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    onPick(ImageCompression.compressedJPEG(from: data) ?? data)
                }
                item = nil
            }
        }
    }
}

struct DefectsView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var deletingDefect: DefectItem?
    @State private var exportSheet: ShareableURL?
    @State private var showingFloorPlan = false
    @State private var tradeFilter = "Alle"
    @State private var statusFilter = "Alle"
    @State private var searchText = ""
    @State private var isExportingWithFloorPlan = false

    private var tradeOptions: [String] {
        let names = model.defects.map(\.trade).filter { !$0.isEmpty }
        return ["Alle"] + Array(Set(names)).sorted()
    }

    private var filteredDefects: [DefectItem] {
        model.defects.filter { d in
            let matchesTrade = tradeFilter == "Alle" || d.trade == tradeFilter
            let matchesStatus = statusFilter == "Alle" || d.status == statusFilter
            let matchesSearch = searchText.isEmpty ||
                d.title.lowercased().contains(searchText.lowercased()) ||
                d.description.lowercased().contains(searchText.lowercased()) ||
                d.responsible.lowercased().contains(searchText.lowercased())
            return matchesTrade && matchesStatus && matchesSearch
        }
    }

    var body: some View {
        ScreenScaffold(title: "Mängel-Matrix", subtitle: "Fristen, Verantwortliche, Prioritäten und PDF-Export") {
            PrimaryButton(title: "Mangel erfassen", systemImage: "plus", action: { showingEditor = true })

            SecondaryButton(title: "Mängelliste als PDF", systemImage: "square.and.arrow.up") {
                if let url = PDFExporter.export(DefectsPDFPage(defects: model.defects, projectName: model.selectedProject?.name ?? "Projekt", exportDate: Date(), project: model.selectedProject), fileName: "Maengelliste.pdf") {
                    exportSheet = ShareableURL(url: url)
                }
            }
            .disabled(model.defects.isEmpty)

            if !model.floorPlans.isEmpty && !model.defects.filter({ $0.pinX != nil }).isEmpty {
                SecondaryButton(
                    title: isExportingWithFloorPlan ? "Wird erstellt …" : "PDF mit Grundriss & Legende",
                    systemImage: "map"
                ) {
                    isExportingWithFloorPlan = true
                    Task {
                        if let url = await exportDefectsWithFloorPlan() {
                            exportSheet = ShareableURL(url: url)
                        }
                        isExportingWithFloorPlan = false
                    }
                }
                .disabled(model.defects.isEmpty || isExportingWithFloorPlan)
            }

            SecondaryButton(title: "Grundriss", systemImage: "map") {
                showingFloorPlan = true
            }

            if !model.defects.isEmpty {
                BaumioCard {
                    HStack {
                        Picker("Gewerk", selection: $tradeFilter) {
                            ForEach(tradeOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Picker("Status", selection: $statusFilter) {
                            ForEach(["Alle", "Offen", "Gemeldet", "In Bearbeitung", "Behoben"], id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            ForEach(filteredDefects) { defect in
                BaumioCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(defect.title).font(.headline).foregroundStyle(BaumioTheme.primaryText)
                            Spacer()
                            Menu {
                                Button("Bearbeiten") { editingItem = .defect(defect) }
                                Button("Löschen", role: .destructive) {
                                    deletingDefect = defect
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Mangel bearbeiten oder löschen")
                            StatusBadge(title: defect.priority.rawValue, color: priorityColor(defect.priority))
                        }
                        Text(defect.description).foregroundStyle(BaumioTheme.secondaryText)
                        Text("\(defect.trade) · Verantwortlich: \(defect.responsible)")
                            .font(.footnote)
                            .foregroundStyle(BaumioTheme.secondaryText)
                        HStack {
                            Menu {
                                Button("Offen") {
                                    model.handle { try await model.updateDefectStatus(defect, status: "offen") }
                                }
                                Button("Gemeldet") {
                                    model.handle { try await model.updateDefectStatus(defect, status: "gemeldet") }
                                }
                                Button("In Bearbeitung") {
                                    model.handle { try await model.updateDefectStatus(defect, status: "in_bearbeitung") }
                                }
                                Button("Behoben") {
                                    model.handle { try await model.updateDefectStatus(defect, status: "behoben") }
                                }
                            } label: {
                                StatusBadge(title: defect.status, color: defect.status == "Behoben" ? BaumioTheme.success : defect.status == "Offen" ? BaumioTheme.warning : BaumioTheme.info)
                            }
                            .accessibilityLabel("Mangelstatus ändern")
                            Text("Frist: \(defect.deadline.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote.bold())
                                .foregroundStyle(BaumioTheme.secondaryText)
                            Spacer()
                            Button {
                                let next = defect.status == "Behoben" ? "offen" : "behoben"
                                model.handle { try await model.updateDefectStatus(defect, status: next) }
                            } label: {
                                Image(systemName: defect.status == "Behoben" ? "checkmark.circle.fill" : "checkmark.circle")
                                    .foregroundStyle(defect.status == "Behoben" ? BaumioTheme.success : BaumioTheme.secondaryText)
                                    .font(.title3)
                            }
                            .accessibilityLabel(defect.status == "Behoben" ? "Als offen markieren" : "Als behoben markieren")
                        }
                        PhotoSection(model: model, bucket: "defect-photos", photos: model.defectPhotos[defect.id] ?? []) { data in
                            model.handle { try await model.addDefectPhoto(defect, imageData: data) }
                        }
                        CommentSection(defect: defect, model: model)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Mangel suchen …")
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .defect, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(item: $exportSheet) { shareable in
            ShareSheet(items: [shareable.url])
        }
        .sheet(isPresented: $showingFloorPlan) {
            FloorPlanView(model: model)
        }
        .alert("Mangel löschen?", isPresented: Binding(get: { deletingDefect != nil }, set: { if !$0 { deletingDefect = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingDefect = nil }
            Button("Löschen", role: .destructive) {
                if let d = deletingDefect { model.handle { try await model.deleteDefect(d) }; deletingDefect = nil }
            }
        } message: {
            Text("\(deletingDefect?.title ?? "dieser Mangel") wird unwiderruflich gelöscht.")
        }
    }

    // Lädt Grundrissbilder und erstellt PDF mit nummerierten Markierungen + Legende
    @MainActor
    private func exportDefectsWithFloorPlan() async -> URL? {
        let defects = model.defects
        // Globale Nummerierung: Reihenfolge wie in model.defects
        let numberedDefects = Array(defects.enumerated()).map { (number: $0.offset + 1, defect: $0.element) }

        var floorPlanDataList: [FloorPlanPinData] = []

        for floorPlan in model.floorPlans {
            let pinned = numberedDefects.filter {
                $0.defect.floorPlanID == floorPlan.id && $0.defect.pinX != nil && $0.defect.pinY != nil
            }
            guard !pinned.isEmpty else { continue }

            // Bild herunterladen
            guard let url = try? await model.photoURL(bucket: "floor-plans", path: floorPlan.storagePath),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { continue }

            let pins = pinned.map { entry in
                (number: entry.number, x: entry.defect.pinX!, y: entry.defect.pinY!, title: entry.defect.title, trade: entry.defect.trade, status: entry.defect.status)
            }
            floorPlanDataList.append(FloorPlanPinData(label: floorPlan.label, image: image, pins: pins))
        }

        let page = DefectsPDFPage(
            defects: defects,
            projectName: model.selectedProject?.name ?? "Projekt",
            exportDate: Date(),
            project: model.selectedProject,
            floorPlanData: floorPlanDataList
        )
        return PDFExporter.export(page, fileName: "Maengelliste_Grundriss.pdf")
    }
}

struct FloorPlanView: View {
    @Bindable var model: BaumioAppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var placingDefect: DefectItem? = nil
    @State private var floorPlanURL: URL? = nil
    @State private var selectedFloorPlanID: UUID? = nil
    @State private var showingAddFloorPlan = false
    @State private var renamingFloorPlan: FloorPlan? = nil
    @State private var renameLabel = ""

    private var activeFloorPlan: FloorPlan? {
        model.floorPlans.first { $0.id == selectedFloorPlanID } ?? model.floorPlans.first
    }

    private var pinnedDefects: [DefectItem] {
        guard let fp = activeFloorPlan else { return [] }
        return model.defects.filter { $0.pinX != nil && $0.pinY != nil && $0.floorPlanID == fp.id }
    }

    private var unpinnedDefects: [DefectItem] {
        guard let fp = activeFloorPlan else { return model.defects.filter { $0.pinX == nil } }
        return model.defects.filter { $0.pinX == nil || $0.floorPlanID != fp.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.floorPlans.isEmpty {
                    emptyState
                } else if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 12) {
                            floorPicker
                            floorPlanCanvas
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 12) {
                            pinControls
                        }
                        .frame(width: 280)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            floorPicker
                            floorPlanCanvas
                            pinControls
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Grundrisse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddFloorPlan = true } label: {
                        Image(systemName: "plus")
                    }
                }
                if let fp = activeFloorPlan {
                    ToolbarItem(placement: .secondaryAction) {
                        Menu {
                            Button {
                                renameLabel = fp.label
                                renamingFloorPlan = fp
                            } label: { Label("Umbenennen", systemImage: "pencil") }
                            Button(role: .destructive) {
                                model.handle { try await model.deleteFloorPlan(fp) }
                                selectedFloorPlanID = model.floorPlans.first?.id
                            } label: { Label("Stockwerk löschen", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .background(BaumioTheme.background)
            .task(id: activeFloorPlan?.storagePath) {
                guard let path = activeFloorPlan?.storagePath else { floorPlanURL = nil; return }
                floorPlanURL = try? await model.photoURL(bucket: "floor-plans", path: path)
            }
            .onChange(of: model.floorPlans) { _, newPlans in
                if selectedFloorPlanID == nil || !newPlans.contains(where: { $0.id == selectedFloorPlanID }) {
                    selectedFloorPlanID = newPlans.first?.id
                }
            }
            .sheet(isPresented: $showingAddFloorPlan) {
                AddFloorPlanSheet(model: model, isPresented: $showingAddFloorPlan)
            }
            .alert("Stockwerk umbenennen", isPresented: Binding(
                get: { renamingFloorPlan != nil },
                set: { if !$0 { renamingFloorPlan = nil } }
            )) {
                TextField("Bezeichnung", text: $renameLabel)
                Button("Speichern") {
                    if let fp = renamingFloorPlan, !renameLabel.trimmingCharacters(in: .whitespaces).isEmpty {
                        model.handle { try await model.renameFloorPlan(fp, label: renameLabel) }
                    }
                    renamingFloorPlan = nil
                }
                Button("Abbrechen", role: .cancel) { renamingFloorPlan = nil }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                EmptyStateView(
                    title: "Noch keine Grundrisse",
                    message: "Lade Grundrisse für jedes Stockwerk hoch, um Mängel direkt auf dem Plan zu verorten.",
                    systemImage: "map"
                )
                .padding(.top, 40)
                PrimaryButton(title: "Ersten Grundriss hochladen", systemImage: "plus") {
                    showingAddFloorPlan = true
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var floorPicker: some View {
        if model.floorPlans.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.floorPlans) { fp in
                        Button {
                            selectedFloorPlanID = fp.id
                        } label: {
                            Text(fp.label)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(fp.id == (selectedFloorPlanID ?? model.floorPlans.first?.id) ? BaumioTheme.accent : BaumioTheme.surface)
                                .foregroundStyle(fp.id == (selectedFloorPlanID ?? model.floorPlans.first?.id) ? .white : BaumioTheme.primaryText)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        } else if let fp = model.floorPlans.first {
            Text(fp.label)
                .font(.headline)
                .foregroundStyle(BaumioTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var floorPlanCanvas: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 8) {
                if pinnedDefects.isEmpty && placingDefect == nil {
                    Label("Tippe auf einen Mangel unten, um ihn zu pinnen", systemImage: "pin")
                        .font(.caption)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
                GeometryReader { geo in
                    ZStack {
                        AsyncImage(url: floorPlanURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                            } else if phase.error != nil {
                                Rectangle().fill(BaumioTheme.surface)
                                    .overlay(Label("Laden fehlgeschlagen", systemImage: "exclamationmark.triangle").foregroundStyle(BaumioTheme.warning))
                            } else {
                                Rectangle().fill(BaumioTheme.surface)
                                    .overlay(ProgressView())
                            }
                        }
                        ForEach(pinnedDefects) { defect in
                            if let px = defect.pinX, let py = defect.pinY {
                                PinMarker(defect: defect) {
                                    model.handle { try await model.clearDefectPin(defect) }
                                }
                                .position(x: px * geo.size.width, y: py * geo.size.height)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let placing = placingDefect, let fp = activeFloorPlan else { return }
                        let x = max(0, min(1, location.x / geo.size.width))
                        let y = max(0, min(1, location.y / geo.size.height))
                        model.handle {
                            try await model.updateDefectPin(placing, x: x, y: y)
                            try await model.setDefectFloorPlan(placing, floorPlanID: fp.id)
                        }
                        placingDefect = nil
                    }
                }
                .frame(height: horizontalSizeClass == .regular ? 500 : 280)
            }
        }
    }

    private var pinControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(placingDefect == nil ? "Mängel ohne Pin:" : "Tippe auf den Grundriss …")
                    .font(.caption.bold())
                    .foregroundStyle(placingDefect == nil ? BaumioTheme.secondaryText : BaumioTheme.accent)
                Spacer()
                if placingDefect != nil {
                    Button("Abbrechen") { placingDefect = nil }
                        .font(.caption.bold()).foregroundStyle(BaumioTheme.danger)
                }
            }
            if placingDefect == nil {
                let toPin = unpinnedDefects
                if toPin.isEmpty {
                    Text("Alle Mängel sind gepinnt.")
                        .font(.caption).foregroundStyle(BaumioTheme.secondaryText)
                } else {
                    ForEach(toPin) { defect in
                        Button { placingDefect = defect } label: {
                            HStack {
                                Image(systemName: "pin.circle").foregroundStyle(BaumioTheme.secondaryText)
                                Text(defect.title).foregroundStyle(BaumioTheme.primaryText).font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(BaumioTheme.secondaryText)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

struct AddFloorPlanSheet: View {
    @Bindable var model: BaumioAppViewModel
    @Binding var isPresented: Bool
    @State private var label = "Erdgeschoss"
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data? = nil
    @State private var isUploading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Bezeichnung") {
                    TextField("z. B. Erdgeschoss, 1. OG, Keller", text: $label)
                }
                Section("Grundriss-Bild") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(imageData == nil ? "Bild auswählen" : "Bild gewählt ✓", systemImage: imageData == nil ? "photo.badge.plus" : "checkmark.circle.fill")
                            .foregroundStyle(imageData == nil ? BaumioTheme.accent : BaumioTheme.success)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BaumioTheme.background)
            .navigationTitle("Stockwerk hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isUploading ? "Lädt …" : "Hochladen") {
                        guard let data = imageData, !label.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        isUploading = true
                        model.handle {
                            let compressed = ImageCompression.compressedJPEG(from: data) ?? data
                            try await model.addFloorPlan(imageData: compressed, label: label)
                            isPresented = false
                        }
                    }
                    .disabled(imageData == nil || label.trimmingCharacters(in: .whitespaces).isEmpty || isUploading)
                }
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                imageData = try? await newItem.loadTransferable(type: Data.self)
                pickerItem = nil
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct PinMarker: View {
    let defect: DefectItem
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            VStack(spacing: 2) {
                Image(systemName: "pin.fill")
                    .font(.title3)
                    .foregroundStyle(priorityColor(defect.priority))
                Text(defect.title.prefix(12))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
            }
        }
        .accessibilityLabel("Pin entfernen: \(defect.title)")
    }
}

struct FundingView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: FundingItem?
    @State private var deletingFunding: FundingItem?

    var body: some View {
        ScreenScaffold(title: "Fördertracker", subtitle: "KfW 261 / 455, BAFA BEG EM, Fristen und Beträge") {
            PrimaryButton(title: "Förderung anlegen", systemImage: "plus", action: { showingEditor = true })

            BaumioCard {
                Text("Kein Rechts- oder Steuerrat. Förderbedingungen immer mit zugelassenem Energie-Effizienz-Experten abstimmen.")
                    .font(.footnote)
                    .foregroundStyle(BaumioTheme.warning)
            }

            if model.funding.isEmpty {
                EmptyStateView(
                    title: "Keine Förderungen erfasst",
                    message: "Lege KfW 458 oder BAFA BEG an und berechne deinen voraussichtlichen Förderbetrag.",
                    systemImage: "leaf"
                )
            } else {
                ForEach(model.funding) { item in
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                ItemLine(icon: "leaf", title: item.name, subtitle: item.provider.isEmpty ? "Förderung" : item.provider, tint: BaumioTheme.success)
                                Spacer()
                                StatusBadge(
                                    title: item.status,
                                    color: item.status == "Bewilligt" || item.status == "Ausgezahlt" ? BaumioTheme.success : item.status == "Abgelehnt" ? BaumioTheme.danger : BaumioTheme.info
                                )
                                Menu {
                                    Button("Bearbeiten") { editingItem = item }
                                    Button("Löschen", role: .destructive) {
                                        deletingFunding = item
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Förderung bearbeiten oder löschen")
                            }

                            if item.hasKfWData {
                                Divider()
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Voraussichtliche Förderung")
                                            .font(.caption)
                                            .foregroundStyle(BaumioTheme.secondaryText)
                                        Text(item.estimatedRefund.euroString)
                                            .font(.title3.bold())
                                            .foregroundStyle(BaumioTheme.success)
                                    }
                                    Spacer()
                                    if item.kfwFoerdersatz > 0 {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("Fördersatz")
                                                .font(.caption)
                                                .foregroundStyle(BaumioTheme.secondaryText)
                                            Text("\(item.kfwFoerdersatz) %")
                                                .font(.headline)
                                                .foregroundStyle(item.kfwFoerdersatz == 70 ? BaumioTheme.warning : BaumioTheme.accent)
                                        }
                                    }
                                }

                                if item.maxAmount > 0 {
                                    Text("Förderfähige Kosten (Max.): \(item.maxAmount.euroString)")
                                        .font(.caption)
                                        .foregroundStyle(BaumioTheme.secondaryText)
                                }

                                // Aktive BEG-Boni
                                if item.programType.usesBEGBoni {
                                    let activeBoni: [String] = {
                                        var boni: [String] = []
                                        if item.kfwGrundfoerderung { boni.append("Grundförderung +30 %") }
                                        if item.kfwKlimabonus      { boni.append("Klimabonus +16 %") }
                                        if item.kfwEinkommensbonus && item.kfwEffizienzbonus {
                                            boni.append("Einkommensbonus +40 %")
                                        } else if item.kfwEinkommensbonus {
                                            boni.append("Einkommensbonus +30 %")
                                        } else if item.kfwEffizienzbonus {
                                            boni.append("Einkommensbonus +10 %")
                                        }
                                        return boni
                                    }()
                                    if !activeBoni.isEmpty {
                                        Text(activeBoni.joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(BaumioTheme.success)
                                    }
                                }
                            } else if item.amount > 0 {
                                Text(item.amount.euroString).font(.headline).foregroundStyle(BaumioTheme.primaryText)
                            }

                            // Verknüpfte förderfähige Positionen
                            let eligibleCount = model.eligibleItemCount(for: item.id)
                            if eligibleCount > 0 {
                                Divider()
                                let eligibleSum = model.eligibleTotal(for: item.id)
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Verknüpfte Kosten")
                                            .font(.caption)
                                            .foregroundStyle(BaumioTheme.secondaryText)
                                        Text(eligibleSum.euroString)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(BaumioTheme.primaryText)
                                    }
                                    Spacer()
                                    Text("\(eligibleCount) Position\(eligibleCount == 1 ? "" : "en")")
                                        .font(.caption)
                                        .foregroundStyle(BaumioTheme.secondaryText)
                                }
                            }

                            if let docDead = item.documentDeadline {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.badge.clock").font(.caption2)
                                    Text("Dokumente bis: \(docDead.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption.bold())
                                }
                                .foregroundStyle(docDead < Date() ? BaumioTheme.danger : BaumioTheme.warning)
                            }

                            if let deadline = item.deadline {
                                Text("Antragsfrist: \(deadline.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }

                            if !item.notes.isEmpty {
                                Text(item.notes).font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            FundingEditorView(model: model)
        }
        .sheet(item: $editingItem) { item in
            FundingEditorView(model: model, editing: item)
        }
        .alert("Förderung löschen?", isPresented: Binding(get: { deletingFunding != nil }, set: { if !$0 { deletingFunding = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingFunding = nil }
            Button("Löschen", role: .destructive) {
                if let f = deletingFunding { model.handle { try await model.deleteFunding(f) }; deletingFunding = nil }
            }
        } message: {
            Text("\(deletingFunding?.name ?? "diese Förderung") wird unwiderruflich gelöscht.")
        }
    }
}

struct FundingEditorView: View {
    @Bindable var model: BaumioAppViewModel
    var editing: FundingItem? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var programType: FundingProgramType = .sonstige
    @State private var name = ""
    @State private var provider = ""
    @State private var maxAmountStr = ""
    @State private var manualGrantRateStr = ""
    @State private var status = "geplant"
    @State private var deadline = Date().addingTimeInterval(60 * 60 * 24 * 90)
    @State private var hasDocDeadline = false
    @State private var documentDeadline = Date().addingTimeInterval(60 * 60 * 24 * 60)
    @State private var kfwG = false   // Grundförderung 30 %
    @State private var kfwK = false   // Klimageschwindigkeitsbonus 16 %
    @State private var einkommensTier = 0  // 0=kein, 1=+10%, 2=+30%, 3=+40%
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var maxAmount: Decimal {
        Decimal(string: maxAmountStr.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var manualGrantRate: Int? {
        guard !programType.usesBEGBoni, let r = Int(manualGrantRateStr), r > 0 else { return nil }
        return r
    }
    private var foerdersatz: Int {
        if let r = manualGrantRate { return min(r, 100) }
        var pct = 0
        if kfwG { pct += 30 }
        if kfwK { pct += 16 }
        switch einkommensTier {
        case 1: pct += 10
        case 2: pct += 30
        case 3: pct += 40
        default: break
        }
        return pct
    }
    private var estimatedRefund: Decimal {
        guard maxAmount > 0, foerdersatz > 0 else { return 0 }
        return maxAmount * Decimal(foerdersatz) / 100
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Programm", selection: $programType) {
                        ForEach(FundingProgramType.allCases) { prog in
                            Text(prog.displayName).tag(prog)
                        }
                    }
                    if programType != .sonstige {
                        Text(programType.programDescription)
                            .font(.caption)
                            .foregroundStyle(BaumioTheme.secondaryText)
                    }
                } header: {
                    Text("Förderprogramm auswählen")
                }
                .onChange(of: programType) { _, newType in
                    guard editing == nil else { return }
                    if !newType.defaultProvider.isEmpty { provider = newType.defaultProvider }
                    if newType.defaultMaxAmount > 0 { maxAmountStr = "\(newType.defaultMaxAmount)" }
                    if newType.defaultGrantRate > 0 { manualGrantRateStr = "\(newType.defaultGrantRate)" }
                    if name.isEmpty { name = newType.displayName }
                }

                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Anbieter (KfW, BAFA …)", text: $provider)
                    Picker("Status", selection: $status) {
                        Text("Geplant").tag("geplant")
                        Text("Beantragt").tag("beantragt")
                        Text("Bewilligt").tag("bewilligt")
                        Text("Ausgezahlt").tag("ausgezahlt")
                        Text("Abgelehnt").tag("abgelehnt")
                    }
                }

                Section("Betrag & Fristen") {
                    HStack {
                        Text(programType == .kfwKredit261 ? "Kreditbetrag (€)" : "Förderfähige Kosten (€)")
                        Spacer()
                        TextField("z. B. 30000", text: $maxAmountStr)
                            .multilineTextAlignment(.trailing)
                            .decimalOnly($maxAmountStr)
                    }
                    if !programType.usesBEGBoni {
                        HStack {
                            Text(programType == .kfwKredit261 ? "Tilgungszuschuss (%)" : "Fördersatz (%)")
                            Spacer()
                            TextField("z. B. 45", text: $manualGrantRateStr)
                                .multilineTextAlignment(.trailing)
                                .integerOnly($manualGrantRateStr)
                        }
                    }
                    DatePicker("Antragsfrist", selection: $deadline, displayedComponents: .date)
                    Toggle("Dokumentenfrist eintragen", isOn: $hasDocDeadline)
                    if hasDocDeadline {
                        DatePicker("Alle Dokumente bis", selection: $documentDeadline, displayedComponents: .date)
                    }
                }

                if programType.usesBEGBoni {
                    Section {
                        Toggle(isOn: $kfwG) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Grundförderung +30 %").font(.subheadline.bold())
                                Text("Neueinbau klimafreundliche Heizung (Wärmepumpe, Biomasse, Wärmenetz)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: $kfwK) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Klimageschwindigkeitsbonus +16 %").font(.subheadline.bold())
                                Text("Ersatz Öl-/Kohle-/Gas- oder alter Heizung. Sinkt ab 01.02.2027 alle 6 Monate um 4 %.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Picker("Einkommensbonus", selection: $einkommensTier) {
                            Text("Kein Einkommensbonus").tag(0)
                            Text("+10 % — Einkommen ≤ 50.000 €").tag(1)
                            Text("+30 % — Einkommen ≤ 40.000 €").tag(2)
                            Text("+40 % — Einkommen ≤ 30.000 €").tag(3)
                        }
                        Text("Familien mit mind. 1 minderjährigem Kind: anzusetzendes Einkommen −10.000 €.")
                            .font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Text("BEG EM Boni – neu ab 21.07.2026 (kombinierbar)")
                    } footer: {
                        Text("Förderhöchstbetrag: 28.000 € / erste Wohneinheit (sinkt ab 01.02.2027 halbjährlich um 750 €). Effizienz- und Emissionsbonus entfallen.")
                    }
                }

                if foerdersatz > 0 || estimatedRefund > 0 {
                    Section("Berechnung") {
                        HStack {
                            Text(programType == .kfwKredit261 ? "Tilgungszuschuss" : "Gesamt-Fördersatz")
                            Spacer()
                            Text("\(foerdersatz) %")
                                .font(.headline)
                                .foregroundStyle(BaumioTheme.success)
                        }
                        if estimatedRefund > 0 {
                            HStack {
                                Text(programType == .kfwKredit261 ? "Max. Tilgungszuschuss" : "Voraussichtliche Förderung")
                                Spacer()
                                Text(estimatedRefund.euroString)
                                    .font(.title3.bold())
                                    .foregroundStyle(BaumioTheme.success)
                            }
                            if programType.usesBEGBoni {
                                Text("Förderhöchstbetrag beachten: max. 28.000 € / erste WE.")
                                    .font(.caption).foregroundStyle(BaumioTheme.secondaryText)
                            }
                        }
                    }
                }

                if programType == .heizungsfoerderungBEG {
                    Section("Pflichtdokumente BEG EM") {
                        Label("Grundbuchauszug oder Eigentümernachweis", systemImage: "doc.text")
                        Label("Meldebescheinigung (Selbstnutzer)", systemImage: "doc.text")
                        Label("Bestätigung Energieeffizienz-Experte (BEG)", systemImage: "doc.text")
                        Label("Kostenvoranschläge / Schlussrechnungen", systemImage: "doc.text")
                    }
                    .font(.footnote)
                } else if programType == .kfwKredit261 {
                    Section("Hinweis KfW 261") {
                        Text("Der Tilgungszuschuss richtet sich nach der Effizienzhaus-Stufe (EH 40, 55, 70, 85). Ab 21.07.2026: Tilgungszuschüsse pauschal um 10 % reduziert. Förderhöchstbetrag: 150.000 € / WE. Energieberater (BEG) ist Pflicht.")
                            .font(.footnote)
                            .foregroundStyle(BaumioTheme.secondaryText)
                    }
                } else if programType == .kfwZuschuss455 {
                    Section("Förderfähige Maßnahmen KfW 455") {
                        Label("Wärmedämmung Fassade / Dach / Keller", systemImage: "house")
                        Label("Neue Fenster und Außentüren", systemImage: "window.horizontal")
                        Label("Heizungsoptimierung", systemImage: "flame")
                        Label("Sommerlicher Wärmeschutz", systemImage: "sun.max")
                    }
                    .font(.footnote)
                }

                Section("Notizen") {
                    TextField("Notizen (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(BaumioTheme.danger) }
                }

                if editing != nil {
                    Section {
                        Button("Förderung löschen", role: .destructive) {
                            Task {
                                if let item = editing {
                                    try? await model.deleteFunding(item)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Förderung anlegen" : "Förderung bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert …" : "Speichern") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || model.selectedProject == nil)
                }
            }
        }
        .baumioBackground()
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let item = editing else { return }
        programType = item.programType
        name = item.name
        provider = item.provider.isEmpty ? item.programType.defaultProvider : item.provider
        maxAmountStr = item.maxAmount > 0 ? "\(item.maxAmount)" : ""
        if let r = item.manualGrantRate { manualGrantRateStr = "\(r)" }
        status = item.status.lowercased()
        if let d = item.deadline { deadline = d }
        if let dd = item.documentDeadline { documentDeadline = dd; hasDocDeadline = true }
        kfwG = item.kfwGrundfoerderung
        kfwK = item.kfwKlimabonus
        // Einkommensbonus-Tier aus 2-Bit dekodieren (E=kfwEinkommensbonus, F=kfwEffizienzbonus)
        einkommensTier = item.kfwEinkommensbonus && item.kfwEffizienzbonus ? 3
                       : item.kfwEinkommensbonus ? 2
                       : item.kfwEffizienzbonus  ? 1 : 0
        notes = item.notes
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let useProvider = provider.isEmpty ? programType.defaultProvider : provider
        do {
            // Einkommensbonus-Tier in 2 Bits kodieren
            let encE = einkommensTier == 2 || einkommensTier == 3
            let encF = einkommensTier == 1 || einkommensTier == 3
            if let item = editing {
                try await model.updateFunding(item, name: name, provider: useProvider, maxAmount: maxAmount,
                                              status: status, deadline: deadline,
                                              documentDeadline: hasDocDeadline ? documentDeadline : nil,
                                              kfwG: kfwG, kfwK: kfwK, kfwE: encE, kfwF: encF,
                                              notes: notes, programType: programType, manualGrantRate: manualGrantRate)
            } else {
                try await model.createFunding(name: name, provider: useProvider, maxAmount: maxAmount,
                                              status: status, deadline: deadline,
                                              documentDeadline: hasDocDeadline ? documentDeadline : nil,
                                              kfwG: kfwG, kfwK: kfwK, kfwE: encE, kfwF: encF,
                                              notes: notes, programType: programType, manualGrantRate: manualGrantRate)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TaxesView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var exportSheet: ShareableURL?

    private var taxRelevantCosts: [CostItem] { model.costs.filter { $0.taxRelevantAmount > 0 } }
    private var materialCosts: [CostItem] { model.costs.filter { $0.category == "Material" } }
    private var taxRelevantSum: Decimal { taxRelevantCosts.reduce(0) { $0 + $1.taxRelevantAmount } }

    var body: some View {
        ScreenScaffold(title: "§35a EStG Steuerexport", subtitle: "Handwerkerleistungen für die Steuererklärung") {
            AdaptiveGrid(minimum: 170) {
                DashboardMetricCard(title: "Arbeitskosten", value: taxRelevantSum.euroString, subtitle: "§35a-relevant", systemImage: "wrench.and.screwdriver", tint: BaumioTheme.success)
                DashboardMetricCard(title: "Positionen", value: "\(taxRelevantCosts.count)", subtitle: "inkl. Rechnungsaufteilung", systemImage: "list.bullet")
            }

            SecondaryButton(title: "Als PDF exportieren", systemImage: "square.and.arrow.up") {
                if let url = PDFExporter.export(TaxPDFPage(laborCosts: taxRelevantCosts, materialCosts: materialCosts, projectName: model.selectedProject?.name ?? "Projekt", exportDate: Date()), fileName: "35a-Steuerexport.pdf") {
                    exportSheet = ShareableURL(url: url)
                }
            }
            .disabled(taxRelevantCosts.isEmpty)

            if taxRelevantCosts.isEmpty {
                EmptyStateView(
                    title: "Keine Arbeitskosten erfasst",
                    message: "Erfasse Kosten mit Kategorie Lohn oder erfasse Handwerkerrechnungen mit Arbeits-/Fahrt-/Maschinenkosten.",
                    systemImage: "wrench.and.screwdriver"
                )
            } else {
                ForEach(taxRelevantCosts) { cost in
                    BaumioCard {
                        HStack {
                            ItemLine(icon: "wrench.and.screwdriver", title: cost.title, subtitle: cost.trade.isEmpty ? "Arbeitskosten" : cost.trade, tint: BaumioTheme.success)
                            Spacer()
                            Text(cost.taxRelevantAmount.euroString).font(.headline).foregroundStyle(BaumioTheme.primaryText)
                        }
                    }
                }
            }

            BaumioCard {
                Text("Hinweis: Baumio bietet keine Steuerberatung. Nach §35a EStG sind i. d. R. Arbeits-, Fahrt- und Maschinenkosten (nicht Material) begünstigt. Bitte mit dem Steuerberater abstimmen.")
                    .font(.footnote)
                    .foregroundStyle(BaumioTheme.warning)
            }
        }
        .sheet(item: $exportSheet) { shareable in
            ShareSheet(items: [shareable.url])
        }
    }
}

struct ReviewsView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingReview: ReviewItem?
    @State private var deletingReview: ReviewItem?

    var body: some View {
        ListScreen(title: "Bewertungen", subtitle: "Handwerker bewerten und Weiterempfehlung festhalten") {
            PrimaryButton(title: "Bewertung anlegen", systemImage: "plus", action: { showingEditor = true })

            if model.reviews.isEmpty {
                EmptyStateView(
                    title: "Noch keine Bewertungen",
                    message: model.trades.isEmpty ? "Lege zuerst eine Firma an, um sie bewerten zu können." : "Bewerte deine Handwerker nach Qualität, Pünktlichkeit, Kommunikation und Preis-Leistung.",
                    systemImage: "star"
                )
            } else {
                ForEach(model.reviews) { review in
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ItemLine(icon: "star", title: review.company, subtitle: review.trade, tint: BaumioTheme.accent)
                                Spacer()
                                StarRating(value: review.stars)
                                Menu {
                                    Button("Bearbeiten") { editingReview = review }
                                    Button("Löschen", role: .destructive) {
                                        deletingReview = review
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Bewertung bearbeiten oder löschen")
                            }
                            if !review.notes.isEmpty {
                                Text(review.notes).foregroundStyle(BaumioTheme.secondaryText)
                            }
                            StatusBadge(title: review.recommended ? "Weiterempfehlung" : "Keine Empfehlung", color: review.recommended ? BaumioTheme.success : BaumioTheme.warning)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ReviewEditorView(model: model)
        }
        .sheet(item: $editingReview) { review in
            ReviewEditorView(model: model, editing: review)
        }
        .alert("Bewertung löschen?", isPresented: Binding(get: { deletingReview != nil }, set: { if !$0 { deletingReview = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingReview = nil }
            Button("Löschen", role: .destructive) {
                if let r = deletingReview { model.handle { try await model.deleteReview(r) }; deletingReview = nil }
            }
        } message: {
            Text("Die Bewertung von \(deletingReview?.company ?? "dieser Firma") wird unwiderruflich gelöscht.")
        }
    }
}

struct ReviewEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: BaumioAppViewModel
    var editing: ReviewItem? = nil
    @State private var tradeID: UUID?
    @State private var quality = 5
    @State private var punctuality = 5
    @State private var communication = 5
    @State private var pricePerformance = 5
    @State private var recommended = true
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var selectedTrade: Trade? {
        model.trades.first { $0.id == tradeID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if editing != nil {
                    Section("Gewerk") {
                        Text(editing?.trade ?? "").foregroundStyle(BaumioTheme.secondaryText)
                    }
                } else if model.trades.isEmpty {
                    Text("Bitte lege zuerst eine Firma an.")
                        .foregroundStyle(BaumioTheme.warning)
                } else {
                    Section("Gewerk") {
                        Picker("Handwerker", selection: $tradeID) {
                            ForEach(model.trades) { trade in
                                Text(trade.company.isEmpty ? trade.name : "\(trade.name) · \(trade.company)").tag(Optional(trade.id))
                            }
                        }
                    }
                }

                Section("Bewertung (1–5)") {
                    Stepper("Qualität: \(quality)", value: $quality, in: 1...5)
                    Stepper("Pünktlichkeit: \(punctuality)", value: $punctuality, in: 1...5)
                    Stepper("Kommunikation: \(communication)", value: $communication, in: 1...5)
                    Stepper("Preis-Leistung: \(pricePerformance)", value: $pricePerformance, in: 1...5)
                    Toggle("Weiterempfehlung", isOn: $recommended)
                }
                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical).lineLimit(3...6)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(BaumioTheme.warning)
                }
            }
            .navigationTitle(editing == nil ? "Bewertung" : "Bewertung bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert …" : "Speichern") {
                        Task { await save() }
                    }
                    .disabled((editing == nil && selectedTrade == nil) || isSaving)
                }
            }
            .onAppear {
                if let review = editing {
                    quality = review.quality > 0 ? review.quality : review.stars
                    punctuality = review.punctuality > 0 ? review.punctuality : review.stars
                    communication = review.communication > 0 ? review.communication : review.stars
                    pricePerformance = review.pricePerformance > 0 ? review.pricePerformance : review.stars
                    recommended = review.recommended
                    notes = review.notes
                } else if tradeID == nil {
                    tradeID = model.trades.first?.id
                }
            }
        }
        .baumioBackground()
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if let review = editing {
                try await model.updateReview(review, quality: quality, punctuality: punctuality, communication: communication, pricePerformance: pricePerformance, recommended: recommended, notes: notes)
            } else {
                guard let trade = selectedTrade else { return }
                try await model.createReview(trade: trade, quality: quality, punctuality: punctuality, communication: communication, pricePerformance: pricePerformance, recommended: recommended, notes: notes)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PricingView: View {
    @Bindable var model: BaumioAppViewModel
    @Environment(\.openURL) private var openURL

    private var subtitle: String {
        if model.isBusiness { return "Baumio Business ist aktiv" }
        if model.isPro { return "Baumio Pro ist aktiv" }
        return "14 Tage kostenlos testen, danach \(model.store.proDisplayPrice)/Monat"
    }

    var body: some View {
        ScreenScaffold(title: "Abo", subtitle: subtitle) {
            if model.isBusiness {
                BaumioCard {
                    HStack {
                        Label("Baumio Business ist aktiv", systemImage: "building.2.fill")
                            .font(.headline)
                            .foregroundStyle(BaumioTheme.primaryText)
                        Spacer()
                        StatusBadge(title: "Business", color: BaumioTheme.accent)
                    }
                }
            } else if model.isPro {
                BaumioCard {
                    HStack {
                        Label("Baumio Pro ist aktiv", systemImage: "crown.fill")
                            .font(.headline)
                            .foregroundStyle(BaumioTheme.primaryText)
                        Spacer()
                        StatusBadge(title: "Pro", color: BaumioTheme.success)
                    }
                }
            }

            AdaptiveGrid(minimum: 280) {
                ForEach(model.pricingPlans.filter { $0.planType != "business" }) { plan in
                    PricingCard(plan: plan) {
                        model.choosePlan(plan)
                    }
                }
            }

            if let error = model.store.purchaseError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(BaumioTheme.warning)
            }

            SecondaryButton(title: "Käufe wiederherstellen", systemImage: "arrow.clockwise") {
                Task { await model.restorePurchases() }
            }

            BaumioCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Apple-Hinweis")
                        .font(.headline)
                        .foregroundStyle(BaumioTheme.primaryText)
                    Text("Abos werden in der iOS-App ausschließlich über Apple In-App-Käufe (StoreKit 2) abgeschlossen. Die Abrechnung läuft über deinen Apple-Account, das Abo verlängert sich automatisch und ist jederzeit über die Apple-Abo-Einstellungen kündbar.")
                        .font(.footnote)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
            }
        }
    }
}

struct PaywallView: View {
    @Bindable var model: BaumioAppViewModel
    var lockedSection: BaumioSection? = nil
    @State private var showingPurchaseError = false

    private var isButtonBusy: Bool {
        model.store.isPurchasing || model.store.isLoadingProducts
    }

    var body: some View {
        ScreenScaffold(title: lockedSection?.rawValue ?? "Baumio Pro", subtitle: lockedSection == nil ? nil : "Diese Funktion ist Teil von Baumio Pro") {

            if lockedSection != nil {
                BaumioCard {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.title3)
                            .foregroundStyle(BaumioTheme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(lockedSection!.rawValue) ist in Baumio Pro enthalten")
                                .font(.headline)
                                .foregroundStyle(BaumioTheme.primaryText)
                            Text("14 Tage kostenlos testen – dann \(model.store.proDisplayPrice)/Monat")
                                .font(.subheadline)
                                .foregroundStyle(BaumioTheme.secondaryText)
                        }
                    }
                }
            }

            BaumioCard {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Label("Baumio Pro", systemImage: "crown.fill")
                            .font(.title2.bold())
                            .foregroundStyle(BaumioTheme.primaryText)
                        Spacer()
                        StatusBadge(title: "14 Tage gratis", color: BaumioTheme.success)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if model.store.isLoadingProducts {
                            ProgressView()
                                .frame(height: 40)
                        } else {
                            Text(model.store.proDisplayPrice)
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .foregroundStyle(BaumioTheme.accent)
                        }
                        Text("pro Monat · monatlich kündbar")
                            .font(.footnote)
                            .foregroundStyle(BaumioTheme.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        FeatureRow(title: "§35a: Bis zu 1.200 € Steuern sparen – mit einem Klick")
                        FeatureRow(title: "KfW 261 / 455 & BAFA BEG EM: Förderungen bis 28.000 € nicht verpassen")
                        FeatureRow(title: "Baumängel-Matrix (Berliner Standard) + PDF")
                        FeatureRow(title: "Bauzeitenplan als PDF – für Architekten & Ämter")
                        FeatureRow(title: "Angebots-Vergleich – günstigsten Handwerker finden")
                        FeatureRow(title: "Handwerker bewerten & Übergabeprotokoll")
                        FeatureRow(title: "KI-gestützte Rechnungs- & Angebotserkennung")
                        FeatureRow(title: "Unbegrenzte Projekte & Gewerke · 5 GB Speicher")
                    }

                    PrimaryButton(
                        title: model.store.isPurchasing ? "Wird verarbeitet …" : (model.store.isLoadingProducts ? "Laden …" : "14 Tage kostenlos testen"),
                        systemImage: "crown.fill"
                    ) {
                        Task {
                            await model.purchasePro()
                            if model.store.purchaseError != nil {
                                showingPurchaseError = true
                            }
                        }
                    }
                    .disabled(isButtonBusy)
                    .opacity(isButtonBusy ? 0.6 : 1)

                    SecondaryButton(title: "Käufe wiederherstellen", systemImage: "arrow.clockwise") {
                        Task { await model.restorePurchases() }
                    }
                    .disabled(isButtonBusy)

                    Text("Abrechnung über deinen Apple-Account. Das Abo verlängert sich automatisch, sofern es nicht 24 Stunden vor Ablauf gekündigt wird. Verwaltung und Kündigung über die Apple-Abo-Einstellungen.")
                        .font(.caption)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
            }
        }
        .alert("Kauf nicht möglich", isPresented: $showingPurchaseError) {
            Button("OK") { model.store.purchaseError = nil; showingPurchaseError = false }
        } message: {
            Text(model.store.purchaseError ?? "Unbekannter Fehler")
        }
        .task {
            if model.store.products.isEmpty {
                await model.store.loadProducts()
            }
        }
    }
}

struct TabCustomizationView: View {
    @Bindable var model: BaumioAppViewModel
    @AppStorage("customTabSections") private var tabString = "Dashboard,Projekte,Termine,Dokumente"
    @Environment(\.dismiss) private var dismiss

    private static let pinnableOrder: [BaumioSection] = [
        .dashboard, .projects, .trades, .schedule, .diary, .tasks,
        .materials, .timeTracking, .handover, .documents, .costs,
        .offers, .defects, .funding, .taxes, .reviews
    ]

    private var pinned: [BaumioSection] {
        tabString.split(separator: ",")
            .compactMap { BaumioSection(rawValue: String($0)) }
            .filter { Self.pinnableOrder.contains($0) }
    }

    private var available: [BaumioSection] {
        Self.pinnableOrder.filter { !pinned.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pinned) { section in
                        row(section, isPinned: true)
                    }
                    .onMove { source, dest in
                        var arr = pinned
                        arr.move(fromOffsets: source, toOffset: dest)
                        save(arr)
                    }
                } header: {
                    HStack {
                        Text("In der Tab-Leiste (\(pinned.count)/4)")
                        Spacer()
                        Text("Halten zum Sortieren")
                            .font(.caption2)
                            .foregroundStyle(BaumioTheme.secondaryText)
                    }
                } footer: {
                    Text("Tippe auf einen Bereich, um ihn hinzuzufügen oder zu entfernen. \"Mehr\" ist immer der 5. Tab.")
                        .font(.caption)
                }

                Section("Verfügbar") {
                    ForEach(available) { section in
                        row(section, isPinned: false)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BaumioTheme.background)
            .navigationTitle("Tab-Leiste anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ section: BaumioSection, isPinned: Bool) -> some View {
        Button {
            toggle(section)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(isPinned ? BaumioTheme.accent : BaumioTheme.secondaryText)
                Text(section.rawValue)
                    .foregroundStyle(BaumioTheme.primaryText)
                Spacer()
                if section.requiresPro && !model.isPro {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
                Image(systemName: isPinned ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isPinned ? BaumioTheme.accent : BaumioTheme.secondaryText)
                    .font(.title3)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isPinned && pinned.count >= 4)
        .opacity(!isPinned && pinned.count >= 4 ? 0.4 : 1)
    }

    private func toggle(_ section: BaumioSection) {
        var arr = pinned
        if let idx = arr.firstIndex(of: section) {
            guard arr.count > 1 else { return } // mindestens 1 Tab behalten
            arr.remove(at: idx)
        } else {
            guard arr.count < 4 else { return }
            arr.append(section)
        }
        save(arr)
    }

    private func save(_ sections: [BaumioSection]) {
        tabString = sections.map(\.rawValue).joined(separator: ",")
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    helpSection("Erste Schritte", entries: [
                        ("house.fill", "Dashboard", "Auf einen Blick: Budget-Ampel, nächste Termine, offene Aufgaben und Mängel deines Bauprojekts."),
                        ("folder.badge.plus", "Projekt anlegen", "Beim ersten Start führt dich der Einrichtungs-Assistent durch Name, Adresse, Budget und Zeitraum – in drei kurzen Schritten."),
                        ("building.2.crop.circle", "Projektwechsel", "Oben im Dashboard zwischen mehreren Projekten wechseln oder ein neues anlegen.")
                    ])

                    helpSection("Baustelle & Planung", entries: [
                        ("calendar", "Termine", "Plane und verwalte alle Bau-Termine. Termine können mit Gewerken verknüpft werden."),
                        ("checkmark.square", "Aufgaben", "To-Do-Liste für die Baustelle. Aufgaben können priorisiert und Personen zugewiesen werden."),
                        ("book.closed", "Bautagebuch", "Tägliche Einträge mit Wetter, Temperatur, Fotos und Notizen. Das Wetter wird automatisch vom aktuellen Standort abgerufen."),
                        ("shippingbox", "Materialien", "Verwalte Bestellungen, Lieferungen und Lagerbestand deiner Baumaterialien."),
                        ("clock", "Zeiterfassung", "Erfasse Arbeitszeiten deiner Gewerke – mit Start, Ende und Pausen.")
                    ])

                    helpSection("Finanzen & Kosten", entries: [
                        ("eurosign.circle", "Kosten & Budget", "Buche Ausgaben und verfolge dein Budget. Die Budget-Ampel im Dashboard zeigt sofort ob du im grünen Bereich bist."),
                        ("doc.text.magnifyingglass", "Angebote", "Speichere und vergleiche Angebote von Handwerkern. Akzeptierte Angebote fließen automatisch in die Kosten ein."),
                        ("building.columns", "Förderungen", "Behalte den Überblick über beantragte Förderungen und deren Status (KfW, BAFA u. a.)."),
                        ("percent", "Steuern", "Erfasse steuerrelevante Ausgaben und nutze die Jahresübersicht für die Steuererklärung.")
                    ])

                    helpSection("Qualität & Abnahme", entries: [
                        ("exclamationmark.triangle", "Mängel", "Dokumentiere Baumängel mit Fotos, Gewerk, Verantwortlichem und Fristdatum. Mit dem Quick-Complete-Button schnell als 'Behoben' markieren."),
                        ("map", "Grundriss-Pin", "Lade einen Grundriss hoch und verorte Mängel direkt als Pin auf dem Plan. Tippe im Mängel-Bereich auf 'Grundriss', dann auf einen Mangel."),
                        ("checkmark.seal", "Übergabe & Abnahme", "Erstelle eine strukturierte Abnahme-Checkliste. Wenn alle Punkte abgehakt sind, unterschreiben beide Parteien digital – das Protokoll wird gesperrt und erhält einen Zeitstempel."),
                        ("signature", "Beidseitige Unterschrift", "Beim Finalisieren unterschreibt zuerst der Bauherr, dann der Handwerker. Danach ist das Protokoll unveränderlich."),
                        ("star.bubble", "Bewertungen", "Bewerte Handwerker nach Abschluss der Arbeiten – hilfreich für künftige Projekte.")
                    ])

                    helpSection("Gewerke & Dokumente", entries: [
                        ("wrench.and.screwdriver", "Gewerke & Firmen", "Verwalte alle beteiligten Firmen und Kontakte. Kontakte können direkt aus dem iPhone-Adressbuch importiert werden."),
                        ("folder", "Dokumente", "Lade Pläne, Verträge und Bescheide hoch. Dokumente können nach Gewerk gefiltert werden.")
                    ])

                    helpSection("App anpassen", entries: [
                        ("square.grid.2x2", "Tab-Leiste anpassen", "Wähle frei, welche 4 Bereiche unten in der Tab-Leiste erscheinen. Alle anderen sind über 'Mehr' erreichbar."),
                        ("crown", "Baumio Pro", "Schaltet PDF-Export, Förderungs-Tracker, Steuer-Übersicht, Gantt-Diagramm und mehr frei. Einmal kaufen, dauerhaft nutzen.")
                    ])
                }
                .padding(16)
                .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Hilfe & Handbuch")
            .navigationBarTitleDisplayMode(.large)
            .scrollContentBackground(.hidden)
            .background(BaumioTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .foregroundStyle(BaumioTheme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func helpSection(_ title: String, entries: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(BaumioTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            BaumioCard {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        if index > 0 {
                            Divider().padding(.leading, 44)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: entry.0)
                                .font(.body)
                                .foregroundStyle(BaumioTheme.accent)
                                .frame(width: 28, alignment: .center)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.1)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(BaumioTheme.primaryText)
                                Text(entry.2)
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingDeleteConfirm = false
    @State private var deleteError: String?
    @State private var showingProfileEditor = false
    @State private var showingMembers = false
    @State private var showingTeamOverview = false
    @State private var showingTabCustomizer = false
    @State private var showingHelp = false
    @State private var dsgvoExport: ShareableURL?
    @Environment(\.requestReview) private var requestReview
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let privacyURL = URL(string: "https://www.baumio.eu/datenschutz")
    private let termsURL = URL(string: "https://www.baumio.eu/agb")
    private let imprintURL = URL(string: "https://www.baumio.eu/impressum")

    var body: some View {
        ScreenScaffold(title: "Einstellungen", subtitle: "Profil, Datenschutz, Sprache und Account") {
            Button {
                showingProfileEditor = true
            } label: {
                SettingsRow(
                    icon: "person.crop.circle",
                    title: "Profil",
                    subtitle: model.displayName.isEmpty ? model.profileEmail : "\(model.displayName) · \(model.profileEmail)"
                )
            }
            .buttonStyle(.plain)

            SettingsRow(icon: "globe", title: "Sprache", subtitle: "Deutsch")
            SettingsRow(icon: "moon.fill", title: "Darstellung", subtitle: "Folgt den Systemeinstellungen")

            if horizontalSizeClass == .compact {
                Button {
                    showingTabCustomizer = true
                } label: {
                    SettingsRow(icon: "square.grid.2x2", title: "Tab-Leiste anpassen", subtitle: "Wähle, welche Bereiche unten erscheinen")
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingTabCustomizer) {
                    TabCustomizationView(model: model)
                }
            }

            Button {
                model.handle { try await model.loadProjectMembers() }
                showingMembers = true
            } label: {
                HStack {
                    SettingsRow(
                        icon: "person.2",
                        title: "Projektmitglieder",
                        subtitle: model.projectMembers.isEmpty ? "Personen zum Projekt einladen" : "\(model.projectMembers.count) Mitglied\(model.projectMembers.count == 1 ? "" : "er")"
                    )
                    if !model.pendingInvites.isEmpty {
                        Text("\(model.pendingInvites.count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(BaumioTheme.danger)
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingMembers) {
                MembersView(model: model)
            }

            if model.isBusiness {
                Button {
                    model.handle { try await model.loadAllTeamMembers() }
                    showingTeamOverview = true
                } label: {
                    SettingsRow(icon: "person.3.fill", title: "Team-Übersicht", subtitle: "Alle Mitglieder aller Projekte")
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingTeamOverview) {
                    TeamOverviewView(model: model)
                }
            }

            Button {
                showingHelp = true
            } label: {
                SettingsRow(icon: "questionmark.circle", title: "Hilfe & Handbuch", subtitle: "Alle Funktionen auf einen Blick erklärt")
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingHelp) {
                HelpView()
            }

            Text("Rechtliches")
                .font(.caption.bold())
                .foregroundStyle(BaumioTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            SettingsLinkRow(icon: "hand.raised", title: "Datenschutzerklärung", subtitle: "baumio.eu/datenschutz", url: privacyURL)
            SettingsLinkRow(icon: "doc.text", title: "AGB", subtitle: "baumio.eu/agb", url: termsURL)
            SettingsLinkRow(icon: "building.columns", title: "Impressum", subtitle: "baumio.eu/impressum", url: imprintURL)

            Text("Daten & Benachrichtigungen")
                .font(.caption.bold())
                .foregroundStyle(BaumioTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Button {
                if let url = model.exportDSGVOData() {
                    dsgvoExport = ShareableURL(url: url)
                }
            } label: {
                SettingsRow(icon: "person.text.rectangle", title: "DSGVO-Export", subtitle: "Alle deine Daten als Textdatei exportieren")
            }
            .buttonStyle(.plain)

            Button {
                model.scheduleLocalNotifications()
            } label: {
                SettingsRow(icon: "bell.badge", title: "Benachrichtigungen aktivieren", subtitle: "Erinnerungen für Termine, Mängel, Förderungen & Angebote")
            }
            .buttonStyle(.plain)

            if model.notificationPermissionDenied {
                BaumioCard {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.slash").foregroundStyle(BaumioTheme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Benachrichtigungen blockiert")
                                .font(.subheadline.bold())
                                .foregroundStyle(BaumioTheme.primaryText)
                            Text("In den Systemeinstellungen für Baumio aktivieren")
                                .font(.caption)
                                .foregroundStyle(BaumioTheme.secondaryText)
                        }
                        Spacer()
                        Button("Öffnen") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.footnote.bold())
                        .foregroundStyle(BaumioTheme.accent)
                    }
                }
            }

            Button {
                requestReview()
            } label: {
                SettingsRow(icon: "star.bubble", title: "Baumio bewerten", subtitle: "Hilf uns mit einer App Store-Bewertung")
            }
            .buttonStyle(.plain)

            Text("Account")
                .font(.caption.bold())
                .foregroundStyle(BaumioTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Button {
                model.logout()
            } label: {
                SettingsRow(icon: "arrow.right.square", title: "Abmelden", subtitle: "Von diesem Gerät abmelden")
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                BaumioCard {
                    ItemLine(icon: "trash", title: "Account löschen", subtitle: "Konto und alle Daten unwiderruflich löschen", tint: BaumioTheme.danger)
                }
            }
            .buttonStyle(.plain)

            if let deleteError {
                Text(deleteError)
                    .font(.footnote)
                    .foregroundStyle(BaumioTheme.warning)
            }
        }
        .alert("Account wirklich löschen?", isPresented: $showingDeleteConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                Task {
                    do {
                        try await model.deleteAccount()
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Dein Konto und alle zugehörigen Projektdaten werden unwiderruflich gelöscht. Das kann nicht rückgängig gemacht werden.")
        }
        .sheet(isPresented: $showingProfileEditor) {
            ProfileEditorView(model: model)
        }
        .sheet(item: $dsgvoExport) { shareable in
            ShareSheet(items: [shareable.url])
        }
    }
}

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: BaumioAppViewModel
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Anzeigename") {
                    TextField("Dein Name", text: $name)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Anzeigename")
                }
                Section("E-Mail") {
                    Text(model.profileEmail)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
                Section {
                    Text("Der Anzeigename wird lokal gespeichert. E-Mail-Änderungen sind über Supabase möglich.")
                        .font(.footnote)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
            }
            .navigationTitle("Profil bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        model.updateDisplayName(name)
                        dismiss()
                    }
                }
            }
            .onAppear { name = model.displayName }
        }
        .baumioBackground()
    }
}

/// Einstellungs-Zeile, die eine externe Webseite (z. B. Rechtstext) im Browser öffnet.
struct SettingsLinkRow: View {
    var icon: String
    var title: String
    var subtitle: String
    var url: URL?

    var body: some View {
        Group {
            if let url {
                Link(destination: url) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        BaumioCard {
            HStack {
                ItemLine(icon: icon, title: title, subtitle: subtitle, tint: BaumioTheme.accent)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(BaumioTheme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet \(subtitle) im Browser")
    }
}

struct ScreenScaffold<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    var onRefresh: (() async -> Void)? = nil
    let content: Content

    init(title: String, subtitle: String? = nil, onRefresh: (() async -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.onRefresh = onRefresh
        self.content = content()
    }

    private var scroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: title, subtitle: subtitle)
                content
            }
            .padding(20)
        }
        .navigationTitle(title)
        .baumioBackground()
    }

    var body: some View {
        if let onRefresh {
            scroll.refreshable { await onRefresh() }
        } else {
            scroll
        }
    }
}

struct ListScreen<Content: View>: View {
    var title: String
    var subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScreenScaffold(title: title, subtitle: subtitle) {
            content
        }
    }
}

struct AdaptiveGrid<Content: View>: View {
    var minimum: CGFloat
    let content: Content

    init(minimum: CGFloat, @ViewBuilder content: () -> Content) {
        self.minimum = minimum
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 14)], spacing: 14) {
            content
        }
    }
}

struct BrandHeader: View {
    var compact = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 12) {
                    Image("BaumioLogoMark")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Baumio")
                            .font(.title2.bold())
                            .foregroundStyle(BaumioTheme.primaryText)
                        Text("KOORDINATOR")
                            .font(.caption.bold())
                            .foregroundStyle(BaumioTheme.secondaryText)
                    }
                }
            } else {
                Image("BaumioLogoWide")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Baumio, regelt deine Baustelle")
    }
}

struct EditIconButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(BaumioTheme.accent)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bearbeiten")
    }
}

struct ItemLine: View {
    var icon: String
    var title: String
    var subtitle: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(BaumioTheme.primaryText)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(BaumioTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StarRating: View {
    var value: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= value ? "star.fill" : "star")
                    .foregroundStyle(index <= value ? BaumioTheme.accent : BaumioTheme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("\(value) von 5 Sternen")
    }
}

struct SettingsRow: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        BaumioCard {
            ItemLine(icon: icon, title: title, subtitle: subtitle, tint: BaumioTheme.accent)
        }
    }
}

enum QuickAddKind: String {
    case trade
    case appointment
    case diary
    case task
    case material
    case cost
    case offer
    case defect
    case timeLog
    case handover
    case funding

    var title: String {
        switch self {
        case .trade: "Firma anlegen"
        case .appointment: "Termin anlegen"
        case .diary: "Bautagebuch-Eintrag"
        case .task: "Aufgabe anlegen"
        case .material: "Material anlegen"
        case .cost: "Kosten erfassen"
        case .offer: "Angebot anlegen"
        case .defect: "Mangel erfassen"
        case .timeLog: "Zeit erfassen"
        case .handover: "Prüfpunkt anlegen"
        case .funding: "Förderung anlegen"
        }
    }

    var primaryPlaceholder: String {
        switch self {
        case .trade: "Ansprechpartner (optional)"
        case .appointment: "Termintitel"
        case .diary: "Erledigte Arbeiten"
        case .task: "Aufgabentitel"
        case .material: "Materialname"
        case .cost: "Kostenposition"
        case .offer: "Angebotstitel"
        case .defect: "Beschreibung des Mangels"
        case .timeLog: "Tätigkeit"
        case .handover: "Prüfpunkt (z. B. Fenster dicht)"
        case .funding: "Förderprogramm (z. B. KfW 261)"
        }
    }
}

enum EditingItem: Identifiable {
    case trade(Trade)
    case appointment(ScheduleItem)
    case diary(DiaryEntry)
    case task(TaskItem)
    case material(MaterialItem)
    case cost(CostItem)
    case offer(OfferItem)
    case defect(DefectItem)
    case handover(HandoverItem)
    case timeLog(TimeLogItem)

    var id: UUID {
        switch self {
        case .trade(let item): item.id
        case .appointment(let item): item.id
        case .diary(let item): item.id
        case .task(let item): item.id
        case .material(let item): item.id
        case .cost(let item): item.id
        case .offer(let item): item.id
        case .defect(let item): item.id
        case .handover(let item): item.id
        case .timeLog(let item): item.id
        }
    }

    var kind: QuickAddKind {
        switch self {
        case .trade: .trade
        case .appointment: .appointment
        case .diary: .diary
        case .task: .task
        case .material: .material
        case .cost: .cost
        case .offer: .offer
        case .defect: .defect
        case .handover: .handover
        case .timeLog: .timeLog
        }
    }
}

/// Wandelt eine angezeigte Statusbezeichnung zurück in den Supabase-Rohwert.
func rawStatusValue(_ display: String) -> String {
    switch display {
    case "In Bearbeitung": "in_bearbeitung"
    case "Offen": "offen"
    case "Gemeldet": "gemeldet"
    case "Behoben": "behoben"
    case "Geplant": "geplant"
    case "Bestellt": "bestellt"
    case "Geliefert": "geliefert"
    case "Verbaut": "verbaut"
    case "Retour": "retour"
    case "Beauftragt": "beauftragt"
    case "Bezahlt": "bezahlt"
    case "Storniert": "storniert"
    case "Lohn": "lohn"
    case "Material": "material"
    case "Nebenkosten": "nebenkosten"
    case "Planung": "planung"
    case "Förderung": "foerderung"
    case "Sonstiges": "sonstiges"
    case "Bewölkt": "bewölkt"
    case "Sonnig": "sonnig"
    case "Regnerisch": "regnerisch"
    case "Schnee": "schnee"
    case "Sturm": "sturm"
    default: display.lowercased()
    }
}

func appointmentStatusValue(_ status: WorkStatus) -> String {
    switch status {
    case .planned: "geplant"
    case .active: "bestaetigt"
    case .done: "abgeschlossen"
    case .blocked: "abgesagt"
    }
}

func todoPriorityValue(_ priority: Priority) -> String {
    switch priority {
    case .high: "high"
    case .medium: "normal"
    case .low: "low"
    }
}

private func decimalPlainString(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: QuickAddKind
    let editing: EditingItem?
    @Bindable var model: BaumioAppViewModel
    @State private var title: String
    @State private var secondary: String
    @State private var amount: String
    @State private var unit: String
    @State private var notes: String
    @State private var date: Date
    @State private var endDate: Date
    @State private var status: String
    @State private var category: String
    @State private var severity: String
    @State private var importance: String
    @State private var temperature: String
    @State private var supplier: String
    @State private var articleNumber: String
    @State private var hours: String
    @State private var minutes: String
    @State private var timeCategory: TimeLogCategory
    @State private var dependsOnID: UUID?
    @State private var budget: String
    @State private var invoiceReference: String
    @State private var defectTrade: String
    @State private var defectResponsible: String
    @State private var defectDeadline: Date
    @State private var fundingItemID: UUID?
    @State private var offerScope: String
    @State private var isInvoice: Bool
    @State private var invoiceDate: Date
    @State private var costDueDate: Date
    @State private var laborAmountStr: String
    @State private var machineAmountStr: String
    @State private var travelAmountStr: String
    @State private var warrantyEnd: Date
    @State private var costPaymentDate: Date
    @State private var isAllDay: Bool
    @State private var appointmentStartTime: Date
    @State private var appointmentEndTime: Date
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var quickAddPhotoData: Data?
    @State private var quickAddPhotoItem: PhotosPickerItem?
    @State private var showingQuickAddCamera = false
    @State private var materialURL: String = ""
    @State private var defectPinX: Double? = nil
    @State private var defectPinY: Double? = nil
    @State private var defectFloorPlanID: UUID? = nil
    @State private var quickAddFloorPlanURL: URL? = nil
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(kind: QuickAddKind, model: BaumioAppViewModel,
         initialWeather: String = "", initialTemperature: String = "",
         initialHours: Int = 0, initialMinutes: Int = 0) {
        self.kind = kind
        self.editing = nil
        self._model = Bindable(wrappedValue: model)
        _title = State(initialValue: "")
        _secondary = State(initialValue: initialWeather)
        _amount = State(initialValue: "")
        _unit = State(initialValue: "")
        _notes = State(initialValue: "")
        _date = State(initialValue: Date())
        _endDate = State(initialValue: Date())
        _status = State(initialValue: kind == .task ? "normal" : kind == .cost ? "offen" : kind == .defect ? "gemeldet" : "geplant")
        _category = State(initialValue: "sonstiges")
        _severity = State(initialValue: "mäßig")
        _importance = State(initialValue: "wichtig")
        _temperature = State(initialValue: initialTemperature)
        _supplier = State(initialValue: "")
        _articleNumber = State(initialValue: "")
        _fundingItemID = State(initialValue: nil)
        _offerScope = State(initialValue: "")
        _hours = State(initialValue: initialHours > 0 ? "\(initialHours)" : "")
        _minutes = State(initialValue: initialMinutes > 0 ? "\(initialMinutes)" : "")
        _timeCategory = State(initialValue: .planung)
        _dependsOnID = State(initialValue: nil)
        _budget = State(initialValue: "")
        _invoiceReference = State(initialValue: "")
        _defectTrade = State(initialValue: "")
        _defectResponsible = State(initialValue: "")
        _defectDeadline = State(initialValue: Date())
        _isInvoice = State(initialValue: false)
        _invoiceDate = State(initialValue: Date())
        _costDueDate = State(initialValue: Date())
        _laborAmountStr = State(initialValue: "")
        _machineAmountStr = State(initialValue: "")
        _travelAmountStr = State(initialValue: "")
        _warrantyEnd = State(initialValue: Date())
        _costPaymentDate = State(initialValue: Date())
        _isAllDay = State(initialValue: true)
        _appointmentStartTime = State(initialValue: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date())
        _appointmentEndTime = State(initialValue: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date())
    }

    init(editing: EditingItem, model: BaumioAppViewModel) {

        self.kind = editing.kind
        self.editing = editing
        self._model = Bindable(wrappedValue: model)

        // Defaults
        var title = ""
        var secondary = ""
        var amount = ""
        var unit = ""
        var notes = ""
        var date = Date()
        var endDate = Date()
        var status = "geplant"
        var category = "sonstiges"
        var severity = "mäßig"
        var importance = "wichtig"
        let temperature = ""
        var supplier = ""
        var articleNumber = ""
        var dependsOnID: UUID? = nil
        var budget = ""
        var invoiceReference = ""
        var offerScope = ""
        var defectTrade = ""
        var defectResponsible = ""
        var defectDeadline = Date()
        var defectPinX: Double? = nil
        var defectPinY: Double? = nil
        var defectFloorPlanID: UUID? = nil
        var isAllDay = true
        var appointmentStartTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        var appointmentEndTime = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
        var hoursStr = ""
        var minutesStr = ""
        var timeCategory: TimeLogCategory = .planung
        var fundingItemID: UUID? = nil

        switch editing {
        case .trade(let item):
            title = item.name
            secondary = item.company
            category = item.tradeType
            unit = item.address
            supplier = item.phone
            articleNumber = item.email
            notes = item.notes
            budget = item.budget > 0 ? decimalPlainString(item.budget) : ""
        case .appointment(let item):
            title = item.title
            date = item.date
            notes = item.notes
            status = appointmentStatusValue(item.status)
            dependsOnID = item.dependsOn
            isAllDay = item.startTime == nil
            if let st = item.startTime { appointmentStartTime = st }
            if let et = item.endTime { appointmentEndTime = et }
        case .diary(let item):
            title = item.notes
            date = item.date
            secondary = rawStatusValue(item.weather)
            supplier = item.companies.joined(separator: ", ")
        case .task(let item):
            title = item.title
            status = todoPriorityValue(item.priority)
            date = item.dueDate
        case .material(let item):
            title = item.name
            amount = item.quantity.formatted()
            unit = item.unit
            supplier = item.supplier
            articleNumber = item.articleNumber
            secondary = decimalPlainString(item.price)
            status = rawStatusValue(item.deliveryStatus)
            notes = item.notes
            fundingItemID = item.fundingItemID
        case .cost(let item):
            title = item.title
            amount = decimalPlainString(item.planned)
            category = rawStatusValue(item.category)
            status = rawStatusValue(item.status)
            invoiceReference = item.invoiceReference
            notes = item.notes
            fundingItemID = item.fundingItemID
            supplier = item.supplier
        case .offer(let item):
            title = item.title.isEmpty ? item.provider : item.title
            secondary = item.provider
            amount = decimalPlainString(item.amount)
            endDate = item.validUntil ?? Date()
            status = item.status
            notes = item.notes
            fundingItemID = item.fundingItemID
            offerScope = item.scope
        case .defect(let item):
            title = item.description
            severity = item.severity
            importance = item.importance
            status = rawStatusValue(item.status)
            defectTrade = item.trade
            defectResponsible = item.responsible
            defectDeadline = item.deadline
            defectPinX = item.pinX
            defectPinY = item.pinY
            defectFloorPlanID = item.floorPlanID
        case .handover(let item):
            title = item.item
            secondary = item.room
            unit = item.tradeType
            notes = item.notes
        case .timeLog(let item):
            title = item.title
            date = item.date
            notes = item.notes
            timeCategory = item.category
            let h = item.durationMinutes / 60
            let m = item.durationMinutes % 60
            hoursStr = h > 0 ? "\(h)" : ""
            minutesStr = m > 0 ? "\(m)" : ""
        }

        var isInvoice = false
        var invoiceDate = Date()
        var costDueDate = Date()
        var laborAmountStr = ""
        var machineAmountStr = ""
        var travelAmountStr = ""
        var warrantyEnd = Date()
        var costPaymentDate = Date()

        if case .cost(let item) = editing {
            isInvoice = item.isInvoice
            invoiceDate = item.invoiceDate ?? Date()
            costDueDate = item.dueDate ?? Date()
            laborAmountStr = item.laborAmount > 0 ? decimalPlainString(item.laborAmount) : ""
            machineAmountStr = item.machineAmount > 0 ? decimalPlainString(item.machineAmount) : ""
            travelAmountStr = item.travelAmount > 0 ? decimalPlainString(item.travelAmount) : ""
            warrantyEnd = item.warrantyEnd ?? Date()
            costPaymentDate = item.paymentDate ?? Date()
        }

        let initialMaterialURL: String
        if case .material(let item) = editing { initialMaterialURL = item.url } else { initialMaterialURL = "" }

        _title = State(initialValue: title)
        _secondary = State(initialValue: secondary)
        _amount = State(initialValue: amount)
        _unit = State(initialValue: unit)
        _notes = State(initialValue: notes)
        _date = State(initialValue: date)
        _endDate = State(initialValue: endDate)
        _status = State(initialValue: status)
        _category = State(initialValue: category)
        _severity = State(initialValue: severity)
        _importance = State(initialValue: importance)
        _temperature = State(initialValue: temperature)
        _supplier = State(initialValue: supplier)
        _articleNumber = State(initialValue: articleNumber)
        _hours = State(initialValue: hoursStr)
        _minutes = State(initialValue: minutesStr)
        _timeCategory = State(initialValue: timeCategory)
        _dependsOnID = State(initialValue: dependsOnID)
        _budget = State(initialValue: budget)
        _invoiceReference = State(initialValue: invoiceReference)
        _defectTrade = State(initialValue: defectTrade)
        _defectResponsible = State(initialValue: defectResponsible)
        _fundingItemID = State(initialValue: fundingItemID)
        _offerScope = State(initialValue: offerScope)
        _defectDeadline = State(initialValue: defectDeadline)
        _defectPinX = State(initialValue: defectPinX)
        _defectPinY = State(initialValue: defectPinY)
        _defectFloorPlanID = State(initialValue: defectFloorPlanID)
        _isInvoice = State(initialValue: isInvoice)
        _invoiceDate = State(initialValue: invoiceDate)
        _costDueDate = State(initialValue: costDueDate)
        _laborAmountStr = State(initialValue: laborAmountStr)
        _machineAmountStr = State(initialValue: machineAmountStr)
        _travelAmountStr = State(initialValue: travelAmountStr)
        _warrantyEnd = State(initialValue: warrantyEnd)
        _costPaymentDate = State(initialValue: costPaymentDate)
        _isAllDay = State(initialValue: isAllDay)
        _appointmentStartTime = State(initialValue: appointmentStartTime)
        _appointmentEndTime = State(initialValue: appointmentEndTime)
        _materialURL = State(initialValue: initialMaterialURL)
        _quickAddPhotoData = State(initialValue: nil)
        _quickAddPhotoItem = State(initialValue: nil)
        _showingQuickAddCamera = State(initialValue: false)
    }

    private var navigationTitle: String {
        editing == nil ? kind.title : "Bearbeiten"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(kind.title) {
                    TextField(kind.primaryPlaceholder, text: $title)

                    if kind == .trade {
                        Picker("Gewerksart", selection: $category) {
                            Text("Gewerksart wählen …").tag("")
                            ForEach(tradeTypeOptions, id: \.self) { Text($0).tag($0) }
                        }
                        TextField("Firmenname", text: $secondary)
                        TextField("Adresse", text: $unit)
                        TextField("Telefon", text: $supplier)
                            .keyboardType(.phonePad)
                        TextField("E-Mail", text: $articleNumber)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Budget (€)", text: $budget)
                            .decimalOnly($budget)
                    }

                    if kind == .appointment {
                        DatePicker("Datum", selection: $date, displayedComponents: .date)
                        Toggle("Ganztägig", isOn: $isAllDay)
                        if !isAllDay {
                            DatePicker("Startzeit", selection: $appointmentStartTime, displayedComponents: .hourAndMinute)
                            DatePicker("Endzeit", selection: $appointmentEndTime, displayedComponents: .hourAndMinute)
                        }
                        Picker("Status", selection: $status) {
                            Text("Geplant").tag("geplant")
                            Text("Bestätigt").tag("bestaetigt")
                            Text("Abgeschlossen").tag("abgeschlossen")
                            Text("Abgesagt").tag("abgesagt")
                        }
                        if !model.schedule.isEmpty {
                            Picker("Abhängt von", selection: $dependsOnID) {
                                Text("Keine Abhängigkeit").tag(UUID?.none)
                                ForEach(model.schedule.filter { s in editing.map({ $0.id != s.id }) ?? true }) { s in
                                    Text(s.title).tag(Optional(s.id))
                                }
                            }
                        }
                    }

                    if kind == .diary {
                        DatePicker("Datum", selection: $date, displayedComponents: .date)
                        Picker("Wetter", selection: $secondary) {
                            Text("Sonnig").tag("sonnig")
                            Text("Bewölkt").tag("bewölkt")
                            Text("Regnerisch").tag("regnerisch")
                            Text("Schnee").tag("schnee")
                            Text("Sturm").tag("sturm")
                        }
                        TextField("Temperatur (°C)", text: $temperature)
                        TextField("Anwesende Handwerker, kommagetrennt", text: $supplier)
                    }

                    if kind == .task {
                        Picker("Priorität", selection: $status) {
                            Text("Hoch").tag("high")
                            Text("Normal").tag("normal")
                            Text("Niedrig").tag("low")
                        }
                        DatePicker("Fällig am", selection: $date, displayedComponents: .date)
                    }

                    if kind == .material {
                        TextField("Menge", text: $amount)
                        TextField("Einheit", text: $unit)
                        TextField("Lieferant", text: $supplier)
                        TextField("Artikelnummer", text: $articleNumber)
                        TextField("Preis/Einheit (€)", text: $secondary)
                        TextField("Produktlink (optional)", text: $materialURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Picker("Status", selection: $status) {
                            Text("Geplant").tag("geplant")
                            Text("Bestellt").tag("bestellt")
                            Text("Geliefert").tag("geliefert")
                            Text("Verbaut").tag("verbaut")
                            Text("Retour").tag("retour")
                        }
                        DatePicker("Bestellt am", selection: $date, displayedComponents: .date)
                        DatePicker("Lieferung erwartet", selection: $endDate, displayedComponents: .date)
                    }

                    if kind == .cost {
                        TextField("Betrag brutto (€)", text: $amount)
                            .decimalOnly($amount)
                        Picker("Kategorie", selection: $category) {
                            Text("Lohn").tag("lohn")
                            Text("Material").tag("material")
                            Text("Nebenkosten").tag("nebenkosten")
                            Text("Planung").tag("planung")
                            Text("Förderung").tag("foerderung")
                            Text("Sonstiges").tag("sonstiges")
                        }
                        Picker("Status", selection: $status) {
                            Text("Offen").tag("offen")
                            Text("Beauftragt").tag("beauftragt")
                            Text("Bezahlt").tag("bezahlt")
                            Text("Storniert").tag("storniert")
                        }
                        TextField("Rechnungsnummer (optional)", text: $invoiceReference)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()
                        if category == "material" {
                            TextField("Lieferant (optional)", text: $supplier)
                                .autocorrectionDisabled()
                        }
                        Toggle("Als Handwerkerrechnung erfassen", isOn: $isInvoice)
                    }

                    if kind == .cost && isInvoice {
                        DatePicker("Rechnungsdatum", selection: $invoiceDate, displayedComponents: .date)
                        DatePicker("Fällig am", selection: $costDueDate, displayedComponents: .date)
                        TextField("Arbeitskosten (€)", text: $laborAmountStr).decimalOnly($laborAmountStr)
                        TextField("Maschinenkosten (€)", text: $machineAmountStr).decimalOnly($machineAmountStr)
                        TextField("Fahrtkosten (€)", text: $travelAmountStr).decimalOnly($travelAmountStr)
                        let labor = Decimal(string: laborAmountStr.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let machine = Decimal(string: machineAmountStr.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let travel = Decimal(string: travelAmountStr.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let total = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let material = total - labor - machine - travel
                        if total > 0 {
                            Text("Materialanteil (nicht §35a): \(max(material, 0).euroString)")
                                .font(.footnote)
                                .foregroundStyle(BaumioTheme.secondaryText)
                        }
                        DatePicker("Gewährleistung bis", selection: $warrantyEnd, displayedComponents: .date)
                        DatePicker("Bezahlt am", selection: $costPaymentDate, displayedComponents: .date)
                    }

                    if kind == .offer {
                        TextField("Ausschreibung / Vergleichsgruppe (optional)", text: $offerScope)
                        if kind == .offer {
                            Text("Tipp: Gleiche Ausschreibungsbezeichnung bei mehreren Firmen → automatischer Preisvergleich in der Übersicht.")
                                .font(.caption)
                                .foregroundStyle(BaumioTheme.secondaryText)
                        }
                        TextField("Anbieter", text: $secondary)
                        TextField("Betrag (€)", text: $amount)
                        DatePicker("Erhalten am", selection: $date, displayedComponents: .date)
                        DatePicker("Gültig bis", selection: $endDate, displayedComponents: .date)
                        Picker("Status", selection: $status) {
                            Text("Geplant").tag("Geplant")
                            Text("Angefragt").tag("Angefragt")
                            Text("Erhalten").tag("Erhalten")
                            Text("Angenommen").tag("Angenommen")
                            Text("Abgelehnt").tag("Abgelehnt")
                        }
                    }

                    if kind == .defect || kind == .diary || kind == .cost || kind == .task {
                        if let data = quickAddPhotoData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        HStack(spacing: 16) {
                            if CameraCapturePicker.isAvailable {
                                Button { showingQuickAddCamera = true } label: {
                                    Label("Kamera", systemImage: "camera")
                                        .font(.footnote.bold())
                                        .foregroundStyle(BaumioTheme.accent)
                                }
                                .buttonStyle(.plain)
                            }
                            PhotosPicker(selection: $quickAddPhotoItem, matching: .images) {
                                Label("Foto wählen", systemImage: "photo")
                                    .font(.footnote.bold())
                                    .foregroundStyle(BaumioTheme.accent)
                            }
                            if quickAddPhotoData != nil {
                                Button(role: .destructive) { quickAddPhotoData = nil } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(BaumioTheme.danger)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if kind == .defect {
                        Picker("Schadensgrad", selection: $severity) {
                            Text("Geringfügig").tag("geringfügig")
                            Text("Mäßig").tag("mäßig")
                            Text("Deutlich").tag("deutlich")
                            Text("Sehr stark").tag("sehr stark")
                        }
                        Picker("Wichtigkeit", selection: $importance) {
                            Text("Unwichtig").tag("unwichtig")
                            Text("Eher unwichtig").tag("eher unwichtig")
                            Text("Wichtig").tag("wichtig")
                            Text("Sehr wichtig").tag("sehr wichtig")
                        }
                        Picker("Status", selection: $status) {
                            Text("Offen").tag("offen")
                            Text("Gemeldet").tag("gemeldet")
                            Text("In Bearbeitung").tag("in_bearbeitung")
                            Text("Behoben").tag("behoben")
                        }
                        if model.trades.isEmpty {
                            TextField("Gewerk (z. B. Elektriker)", text: $defectTrade)
                        } else {
                            Picker("Gewerk", selection: $defectTrade) {
                                Text("Kein Gewerk").tag("")
                                ForEach(model.trades) { t in
                                    Text(t.name).tag(t.name)
                                }
                            }
                        }
                        TextField("Verantwortlicher", text: $defectResponsible)
                        DatePicker("Frist", selection: $defectDeadline, displayedComponents: .date)

                        if !model.floorPlans.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Position auf Grundriss (optional)")
                                        .font(.caption)
                                        .foregroundStyle(BaumioTheme.secondaryText)
                                    Spacer()
                                    if defectPinX != nil {
                                        Button("Entfernen") {
                                            defectPinX = nil
                                            defectPinY = nil
                                        }
                                        .font(.caption)
                                        .foregroundStyle(BaumioTheme.danger)
                                    }
                                }
                                if model.floorPlans.count > 1 {
                                    Picker("Stockwerk", selection: $defectFloorPlanID) {
                                        Text("Bitte wählen").tag(UUID?.none)
                                        ForEach(model.floorPlans) { fp in
                                            Text(fp.label).tag(Optional(fp.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                                GeometryReader { geo in
                                    ZStack {
                                        if let url = quickAddFloorPlanURL {
                                            AsyncImage(url: url) { img in
                                                img.resizable().scaledToFill()
                                            } placeholder: {
                                                ProgressView()
                                            }
                                            .frame(width: geo.size.width, height: geo.size.height)
                                            .clipped()
                                        } else {
                                            RoundedRectangle(cornerRadius: 8).fill(BaumioTheme.surface)
                                            ProgressView()
                                        }
                                        if let px = defectPinX, let py = defectPinY {
                                            Circle()
                                                .fill(BaumioTheme.danger)
                                                .frame(width: 18, height: 18)
                                                .shadow(color: .black.opacity(0.4), radius: 3)
                                                .position(x: px * geo.size.width, y: py * geo.size.height)
                                        }
                                        if defectPinX == nil {
                                            Text("Antippen um Position zu markieren")
                                                .font(.caption2)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.black.opacity(0.45))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { location in
                                        defectPinX = max(0, min(1, location.x / geo.size.width))
                                        defectPinY = max(0, min(1, location.y / geo.size.height))
                                        if defectFloorPlanID == nil {
                                            defectFloorPlanID = model.floorPlans.first?.id
                                        }
                                    }
                                }
                                .frame(height: horizontalSizeClass == .regular ? 260 : 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(BaumioTheme.accent.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                    }

                    if kind == .timeLog {
                        Picker("Kategorie", selection: $timeCategory) {
                            ForEach(TimeLogCategory.allCases) { Text($0.rawValue).tag($0) }
                        }
                        DatePicker("Datum", selection: $date, displayedComponents: .date)
                        HStack {
                            TextField("Stunden", text: $hours)
                            TextField("Minuten", text: $minutes)
                        }
                    }

                    if kind == .handover {
                        TextField("Raum (optional)", text: $secondary)
                        TextField("Gewerk (optional)", text: $unit)
                    }

                    // .funding wird über FundingEditorView verwaltet – kein QuickAdd-Block nötig

                    if kind == .cost || kind == .material || kind == .offer {
                        if !model.funding.isEmpty {
                            Toggle("Förderfähige Kosten", isOn: Binding(
                                get: { fundingItemID != nil },
                                set: { on in
                                    if !on { fundingItemID = nil }
                                    else if fundingItemID == nil { fundingItemID = model.funding.first?.id }
                                }
                            ))
                            if fundingItemID != nil {
                                Picker("Förderprogramm", selection: Binding(
                                    get: { fundingItemID ?? model.funding.first!.id },
                                    set: { fundingItemID = $0 }
                                )) {
                                    ForEach(model.funding) { f in
                                        Text(f.name).tag(f.id)
                                    }
                                }
                            }
                        }
                    }

                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let selectedProject = model.selectedProject {
                    Section("Projekt") {
                        Text(selectedProject.name)
                    }
                } else {
                    Section {
                        Text("Bitte zuerst ein Projekt anlegen oder auswählen.")
                            .foregroundStyle(BaumioTheme.warning)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(BaumioTheme.warning)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert" : "Speichern") {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || model.selectedProject == nil)
                }
            }
        }
        .baumioBackground()
        .task {
            // Wetter für Bautagebuch automatisch eintragen wenn Formular öffnet
            if kind == .diary && secondary.isEmpty {
                if let result = await fetchCurrentWeather() {
                    secondary = result.weather
                    if temperature.isEmpty { temperature = result.temp }
                }
            }
        }
        .task(id: defectFloorPlanID) {
            guard kind == .defect else { return }
            if defectFloorPlanID == nil { defectFloorPlanID = model.floorPlans.first?.id }
            guard let fp = model.floorPlans.first(where: { $0.id == defectFloorPlanID }) else { return }
            quickAddFloorPlanURL = try? await model.photoURL(bucket: "floor-plans", path: fp.storagePath)
        }
        .sheet(isPresented: $showingQuickAddCamera) {
            CameraCapturePicker { data in
                quickAddPhotoData = ImageCompression.compressedJPEG(from: data) ?? data
            }
        }
        .onChange(of: quickAddPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    quickAddPhotoData = ImageCompression.compressedJPEG(from: data) ?? data
                }
                quickAddPhotoItem = nil
            }
        }
    }

    private func save() async {
        errorMessage = nil
        if kind == .appointment && !isAllDay && appointmentEndTime <= appointmentStartTime {
            errorMessage = "Die Endzeit muss nach der Startzeit liegen."
            return
        }
        isSaving = true
        defer { isSaving = false }

        do {
            if let editing {
                try await update(editing)
            } else {
                try await create()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func create() async throws {
        switch kind {
        case .trade:
            let parsedBudget = Decimal(string: budget.replacingOccurrences(of: ",", with: ".")) ?? 0
            try await model.createTrade(name: title, company: secondary, tradeType: category, address: unit, phone: supplier, email: articleNumber, budget: parsedBudget, notes: notes)
        case .appointment:
            try await model.createAppointment(title: title, date: date, notes: notes, startTime: isAllDay ? nil : appointmentStartTime, endTime: isAllDay ? nil : appointmentEndTime, status: status, dependsOn: dependsOnID)
        case .diary:
            let createdDiary = try await model.createDiaryEntry(date: date, notes: title, weather: secondary.isEmpty ? "bewölkt" : secondary, temperature: Int(temperature), presentTrades: supplier)
            if let data = quickAddPhotoData { try? await model.addDiaryPhoto(createdDiary, imageData: data) }
        case .task:
            let createdTask = try await model.createTask(title: title, priority: status == "geplant" ? "normal" : status, dueDate: date)
            if let data = quickAddPhotoData { try? await model.addTaskPhoto(createdTask, imageData: data) }
        case .material:
            try await model.createMaterial(name: title, quantity: decimal(amount, fallback: 1), unit: unit, supplier: supplier, articleNumber: articleNumber, price: decimal(secondary), status: status, orderDate: date, deliveryDate: endDate, notes: notes, fundingItemID: fundingItemID, url: materialURL)
        case .cost:
            let createdCost = try await model.createCost(
                title: title, amount: decimal(amount), category: category,
                status: status == "geplant" ? "offen" : status,
                invoiceReference: invoiceReference, notes: notes, fundingItemID: fundingItemID,
                invoiceDate: isInvoice ? invoiceDate : nil,
                dueDate: isInvoice ? costDueDate : nil,
                laborAmount: isInvoice ? decimal(laborAmountStr) : 0,
                machineAmount: isInvoice ? decimal(machineAmountStr) : 0,
                travelAmount: isInvoice ? decimal(travelAmountStr) : 0,
                warrantyEnd: isInvoice ? warrantyEnd : nil,
                paymentDate: isInvoice ? costPaymentDate : nil,
                supplier: supplier
            )
            if let data = quickAddPhotoData { try? await model.addCostPhoto(createdCost, imageData: data) }
        case .offer:
            try await model.createOffer(title: title, company: secondary, amount: decimal(amount), validUntil: endDate, status: status, notes: notes, fundingItemID: fundingItemID, scope: offerScope)
        case .defect:
            let createdDefect = try await model.createDefect(description: title, trade: defectTrade, responsible: defectResponsible, deadline: defectDeadline, severity: severity, importance: importance, status: status, floorPlanID: defectFloorPlanID)
            if let data = quickAddPhotoData { try? await model.addDefectPhoto(createdDefect, imageData: data) }
            if let px = defectPinX, let py = defectPinY {
                try? await model.updateDefectPin(createdDefect, x: px, y: py)
            }
        case .timeLog:
            let totalMinutes = (Int(hours) ?? 0) * 60 + (Int(minutes) ?? 0)
            guard totalMinutes > 0 else {
                throw SupabaseError.requestFailed("Bitte gib eine Dauer größer als 0 an.")
            }
            try await model.createTimeLog(title: title, category: timeCategory, date: date, durationMinutes: totalMinutes, notes: notes)
        case .handover:
            try await model.createHandoverItem(item: title, room: secondary, tradeType: unit)
        case .funding:
            try await model.createFunding(name: title, provider: secondary, maxAmount: decimal(amount),
                                          status: status == "geplant" ? "geplant" : status,
                                          deadline: date, documentDeadline: nil,
                                          kfwG: false, kfwK: false, kfwE: false, kfwF: false, notes: notes)
        }
    }

    private func update(_ editing: EditingItem) async throws {
        switch editing {
        case .trade(let item):
            let parsedBudget = Decimal(string: budget.replacingOccurrences(of: ",", with: ".")) ?? 0
            try await model.updateTrade(item, name: title, company: secondary, tradeType: category, address: unit, phone: supplier, email: articleNumber, budget: parsedBudget, notes: notes)
        case .appointment(let item):
            try await model.updateAppointment(item, title: title, date: date, notes: notes, startTime: isAllDay ? nil : appointmentStartTime, endTime: isAllDay ? nil : appointmentEndTime, status: status, dependsOn: dependsOnID)
        case .diary(let item):
            try await model.updateDiaryEntry(item, date: date, notes: title, weather: secondary.isEmpty ? "bewölkt" : secondary, temperature: Int(temperature), presentTrades: supplier)
        case .task(let item):
            try await model.updateTask(item, title: title, priority: status == "geplant" ? "normal" : status, dueDate: date)
        case .material(let item):
            try await model.updateMaterial(item, name: title, quantity: decimal(amount, fallback: 1), unit: unit, supplier: supplier, articleNumber: articleNumber, price: decimal(secondary), status: status, notes: notes, fundingItemID: fundingItemID, url: materialURL)
        case .cost(let item):
            try await model.updateCost(
                item, title: title, amount: decimal(amount), category: category,
                status: status == "geplant" ? "offen" : status,
                invoiceReference: invoiceReference, notes: notes, fundingItemID: fundingItemID,
                invoiceDate: isInvoice ? invoiceDate : nil,
                dueDate: isInvoice ? costDueDate : nil,
                laborAmount: isInvoice ? decimal(laborAmountStr) : 0,
                machineAmount: isInvoice ? decimal(machineAmountStr) : 0,
                travelAmount: isInvoice ? decimal(travelAmountStr) : 0,
                warrantyEnd: isInvoice ? warrantyEnd : nil,
                paymentDate: isInvoice ? costPaymentDate : nil,
                supplier: supplier
            )
        case .offer(let item):
            try await model.updateOffer(item, title: title, company: secondary, amount: decimal(amount), validUntil: endDate, notes: notes, fundingItemID: fundingItemID, scope: offerScope)
        case .defect(let item):
            try await model.updateDefect(item, description: title, trade: defectTrade, responsible: defectResponsible, deadline: defectDeadline, severity: severity, importance: importance, status: status)
        case .handover(let item):
            try await model.updateHandoverItem(item, itemText: title, room: secondary, tradeType: unit, notes: notes)
        case .timeLog(let item):
            let totalMinutes = (Int(hours) ?? 0) * 60 + (Int(minutes) ?? 0)
            guard totalMinutes > 0 else {
                throw SupabaseError.requestFailed("Bitte gib eine Dauer größer als 0 an.")
            }
            try await model.updateTimeLog(item, title: title, category: timeCategory, date: date, durationMinutes: totalMinutes, notes: notes)
        }
    }

    private func decimal(_ value: String, fallback: Decimal = 0) -> Decimal {
        Decimal(string: value.replacingOccurrences(of: ",", with: ".")) ?? fallback
    }
}

struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: BaumioAppViewModel
    var editing: Project? = nil
    @State private var name = ""
    @State private var budget = ""
    @State private var description = ""
    @State private var status: ProjectStatus = .planned
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(60 * 60 * 24 * 180)
    @State private var eigenkapital = ""
    @State private var kredit = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var coverImageData: Data?
    @State private var coverPhotoItem: PhotosPickerItem?
    @State private var showingCoverCamera = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Titelbild") {
                    if let data = coverImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .listRowInsets(EdgeInsets())
                    }
                    HStack(spacing: 16) {
                        if CameraCapturePicker.isAvailable {
                            Button { showingCoverCamera = true } label: {
                                Label("Kamera", systemImage: "camera")
                                    .font(.footnote.bold())
                                    .foregroundStyle(BaumioTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        PhotosPicker(selection: $coverPhotoItem, matching: .images) {
                            Label("Foto wählen", systemImage: "photo")
                                .font(.footnote.bold())
                                .foregroundStyle(BaumioTheme.accent)
                        }
                        if coverImageData != nil {
                            Button(role: .destructive) { coverImageData = nil } label: {
                                Image(systemName: "trash").foregroundStyle(BaumioTheme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Projekt") {
                    TextField("Projektname", text: $name)
                        .accessibilityLabel("Projektname")
                    TextField("Budget (€)", text: $budget)
                        .decimalOnly($budget)
                        .accessibilityLabel("Budget")
                    Picker("Status", selection: $status) {
                        ForEach(ProjectStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DatePicker("Startdatum", selection: $startDate, displayedComponents: .date)
                    DatePicker("Geplantes Ende", selection: $endDate, displayedComponents: .date)
                    TextField("Beschreibung", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Beschreibung")
                }

                Section("Finanzierung") {
                    TextField("Eigenkapital (€)", text: $eigenkapital)
                        .decimalOnly($eigenkapital)
                        .accessibilityLabel("Eigenkapital")
                    TextField("Baudarlehen / Kredit (€)", text: $kredit)
                        .decimalOnly($kredit)
                        .accessibilityLabel("Baudarlehen")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(BaumioTheme.warning)
                    }
                }

                if editing != nil {
                    Section {
                        Button("Projekt löschen", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                } else {
                    Section {
                        Text("Adresse und Objekt werden in der Web-App über die Tabelle objects verwaltet.")
                            .font(.footnote)
                            .foregroundStyle(BaumioTheme.secondaryText)
                    }
                }
            }
            .navigationTitle(editing == nil ? "Projekt anlegen" : "Projekt bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert" : "Speichern") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .baumioBackground()
        .onAppear { prefill() }
        .alert("Projekt löschen?", isPresented: $showingDeleteConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                Task {
                    if let project = editing {
                        do {
                            try await model.deleteProject(project)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        } message: {
            Text("Das Projekt \"\(editing?.name ?? "")\" und alle zugehörigen Daten (Kosten, Mängel, Fotos, Dokumente) werden unwiderruflich gelöscht.")
        }
        .sheet(isPresented: $showingCoverCamera) {
            CameraCapturePicker { data in
                coverImageData = ImageCompression.compressedJPEG(from: data) ?? data
            }
        }
        .onChange(of: coverPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    coverImageData = ImageCompression.compressedJPEG(from: data) ?? data
                }
                coverPhotoItem = nil
            }
        }
    }

    private static func coverImageURL(for projectID: UUID) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("project_cover_\(projectID.uuidString).jpg")
    }

    private func prefill() {
        guard let project = editing else { return }
        name = project.name
        budget = project.budget > 0 ? NSDecimalNumber(decimal: project.budget).stringValue : ""
        description = project.description
        status = project.status
        startDate = project.startDate
        endDate = project.plannedEndDate
        eigenkapital = project.eigenkapital > 0 ? NSDecimalNumber(decimal: project.eigenkapital).stringValue : ""
        kredit = project.kredit > 0 ? NSDecimalNumber(decimal: project.kredit).stringValue : ""
        coverImageData = try? Data(contentsOf: Self.coverImageURL(for: project.id))
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let parsedBudget = Decimal(string: budget.replacingOccurrences(of: ",", with: ".")) ?? 0
        let parsedEigenkapital = Decimal(string: eigenkapital.replacingOccurrences(of: ",", with: ".")) ?? 0
        let parsedKredit = Decimal(string: kredit.replacingOccurrences(of: ",", with: ".")) ?? 0
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let project = editing {
                try await model.updateProject(project, name: trimmedName, budget: parsedBudget, status: status, description: description.trimmingCharacters(in: .whitespacesAndNewlines), startDate: startDate, endDate: endDate, eigenkapital: parsedEigenkapital, kredit: parsedKredit)
                saveCoverImage(for: project.id)
            } else {
                try await model.createProject(name: trimmedName, budget: parsedBudget, status: status, description: description.trimmingCharacters(in: .whitespacesAndNewlines))
                if let created = model.projects.first(where: { $0.name == trimmedName }) {
                    saveCoverImage(for: created.id)
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveCoverImage(for projectID: UUID) {
        let url = Self.coverImageURL(for: projectID)
        if let data = coverImageData {
            try? data.write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: – Team-Übersicht (Business)

struct TeamOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: BaumioAppViewModel

    private var byProject: [(name: String, members: [ProjectMember])] {
        let grouped = Dictionary(grouping: model.allTeamMembers) { $0.projectID }
        return grouped.map { (key, members) in
            let name = members.first?.projectName ?? model.projects.first(where: { $0.id == key })?.name ?? "Projekt"
            return (name: name, members: members)
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if model.allTeamMembers.isEmpty {
                    ContentUnavailableView("Noch keine Mitglieder", systemImage: "person.3", description: Text("Lade Mitglieder in deine Projekte ein und sie erscheinen hier."))
                } else {
                    ForEach(byProject, id: \.name) { group in
                        Section(group.name) {
                            ForEach(group.members) { member in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(member.invitedEmail)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(member.role.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    StatusBadge(
                                        title: member.status == .accepted ? "Aktiv" : "Ausstehend",
                                        color: member.status == .accepted ? BaumioTheme.success : BaumioTheme.warning
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Team-Übersicht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

// MARK: – Projektmitglieder

struct MembersView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: BaumioAppViewModel
    @State private var inviteEmail = ""
    @State private var inviteRole: MemberRole = .viewer
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var shareMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !model.pendingInvites.isEmpty {
                    Section("Offene Einladungen für dich") {
                        ForEach(model.pendingInvites) { invite in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(invite.projectName.isEmpty ? "Projekt-Einladung" : invite.projectName)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(BaumioTheme.primaryText)
                                Text(invite.role.displayName)
                                    .font(.caption)
                                    .foregroundStyle(BaumioTheme.secondaryText)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Annehmen") {
                                    model.handle { try await model.acceptInvite(invite) }
                                }
                                .tint(BaumioTheme.success)
                            }
                        }
                    }
                }

                Section {
                    if model.isBusiness {
                        Label("Unbegrenzte Mitglieder (Business)", systemImage: "building.2.fill")
                            .font(.caption)
                            .foregroundStyle(BaumioTheme.accent)
                    } else if model.isPro {
                        let used = model.projectMembers.count
                        let max = model.maxMembersPerProject
                        HStack {
                            Text("\(used) von \(max) Mitglieder genutzt (Pro)")
                                .font(.caption)
                                .foregroundStyle(used >= max ? BaumioTheme.warning : BaumioTheme.secondaryText)
                            Spacer()
                            if used >= max {
                                Text("Limit erreicht")
                                    .font(.caption.bold())
                                    .foregroundStyle(BaumioTheme.warning)
                            }
                        }
                    }

                    let atLimit = !model.isBusiness && model.isPro && model.projectMembers.count >= model.maxMembersPerProject

                    if atLimit {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pro-Limit erreicht")
                                .font(.subheadline.bold())
                                .foregroundStyle(BaumioTheme.primaryText)
                            Text("Mit Business kannst du unbegrenzt Architekten, Bauleiter und Partner einladen.")
                                .font(.caption)
                                .foregroundStyle(BaumioTheme.secondaryText)
                            Button("Auf Business upgraden") {
                                model.selectedSection = .pricing
                            }
                            .font(.caption.bold())
                            .foregroundStyle(BaumioTheme.accent)
                        }
                        .padding(.vertical, 4)
                    } else {
                        TextField("E-Mail-Adresse", text: $inviteEmail)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Picker("Rolle", selection: $inviteRole) {
                            ForEach(MemberRole.allCases) { Text($0.displayName).tag($0) }
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(BaumioTheme.danger)
                        }
                        Button(isSaving ? "Einladen …" : "Einladen") {
                            Task { await invite() }
                        }
                        .disabled(inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    }
                } header: {
                    Text("Mitglieder einladen")
                }

                if !model.projectMembers.isEmpty {
                    Section("Aktuell eingeladen") {
                        ForEach(model.projectMembers) { member in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(member.invitedEmail)
                                        .font(.subheadline)
                                        .foregroundStyle(BaumioTheme.primaryText)
                                    HStack(spacing: 6) {
                                        Text(member.role.displayName)
                                            .font(.caption)
                                            .foregroundStyle(BaumioTheme.secondaryText)
                                        Text("·")
                                            .font(.caption)
                                            .foregroundStyle(BaumioTheme.secondaryText)
                                        Text(member.status == .accepted ? "Akzeptiert" : "Ausstehend")
                                            .font(.caption)
                                            .foregroundStyle(member.status == .accepted ? BaumioTheme.success : BaumioTheme.warning)
                                    }
                                }
                                Spacer()
                                Image(systemName: member.status == .accepted ? "checkmark.circle.fill" : "clock")
                                    .foregroundStyle(member.status == .accepted ? BaumioTheme.success : BaumioTheme.warning)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Entfernen", role: .destructive) {
                                    model.handle { try await model.removeMember(member) }
                                }
                            }
                        }
                    }
                }

                Section {
                    Text("Eingeladene Personen erhalten Zugriff auf alle Daten des aktuell gewählten Projekts. Pro-Abo erforderlich.")
                        .font(.caption)
                        .foregroundStyle(BaumioTheme.secondaryText)
                }
            }
            .navigationTitle("Projektmitglieder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear {
                model.handle { try await model.loadPendingInvites() }
            }
            .sheet(item: Binding(
                get: { shareMessage.map { ShareableText(text: $0) } },
                set: { if $0 == nil { shareMessage = nil } }
            )) { item in
                ShareLink(item: item.text) {
                    Label("Einladung teilen", systemImage: "square.and.arrow.up")
                }
                .padding()
                .presentationDetents([.height(120)])
            }
        }
    }

    private func invite() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let emailToInvite = inviteEmail
        let projectName = model.selectedProject?.name ?? "Baumio-Projekt"
        do {
            try await model.inviteMember(email: emailToInvite, role: inviteRole)
            inviteEmail = ""
            shareMessage = """
                Du wurdest zu „\(projectName)" auf Baumio eingeladen!

                So startest du:
                1. Lade Baumio kostenlos im App Store: https://baumio.eu/download
                2. Erstelle ein Konto mit genau dieser E-Mail: \(emailToInvite)
                3. Öffne Einstellungen → Projektmitglieder → Einladung annehmen

                Fertig – du siehst dann das Projekt direkt in deiner Projektliste.
                """
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: – Finanzierungsübersicht

struct FinanzierungsCard: View {
    let project: Project
    let foerderungSumme: Decimal
    let geplanteSumme: Decimal

    private var gesamtFinanzierung: Decimal { project.eigenkapital + project.kredit + foerderungSumme }
    private var differenz: Decimal { gesamtFinanzierung - geplanteSumme }
    private var hatLuecke: Bool { differenz < 0 }

    var body: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "building.columns")
                        .foregroundStyle(BaumioTheme.accent)
                    Text("Finanzierungsübersicht")
                        .font(.headline)
                        .foregroundStyle(BaumioTheme.primaryText)
                }

                HStack(spacing: 8) {
                    if project.eigenkapital > 0 {
                        finanzTile("Eigenkapital", project.eigenkapital, color: BaumioTheme.success)
                    }
                    if project.kredit > 0 {
                        finanzTile("Baudarlehen", project.kredit, color: BaumioTheme.info)
                    }
                    if foerderungSumme > 0 {
                        finanzTile("Förderungen", foerderungSumme, color: BaumioTheme.accent)
                    }
                }

                Divider()

                VStack(spacing: 6) {
                    finanzRow("Gesamtfinanzierung", gesamtFinanzierung, bold: true)
                    finanzRow("Geplante Kosten", geplanteSumme)
                    HStack {
                        Text(hatLuecke ? "Finanzierungslücke" : "Puffer")
                            .font(.subheadline)
                            .foregroundStyle(hatLuecke ? BaumioTheme.danger : BaumioTheme.success)
                        Spacer()
                        Text((hatLuecke ? -differenz : differenz).euroString)
                            .font(.subheadline.bold())
                            .foregroundStyle(hatLuecke ? BaumioTheme.danger : BaumioTheme.success)
                    }
                }
            }
        }
    }

    private func finanzTile(_ label: String, _ amount: Decimal, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(amount.euroString)
                .font(.subheadline.bold())
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(BaumioTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(BaumioTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func finanzRow(_ label: String, _ amount: Decimal, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .subheadline.bold() : .subheadline)
                .foregroundStyle(BaumioTheme.secondaryText)
            Spacer()
            Text(amount.euroString)
                .font(bold ? .subheadline.bold() : .subheadline)
                .foregroundStyle(BaumioTheme.primaryText)
        }
    }
}

func statusColor(_ status: WorkStatus) -> Color {
    switch status {
    case .planned: BaumioTheme.secondaryText
    case .active: BaumioTheme.accent
    case .done: BaumioTheme.success
    case .blocked: BaumioTheme.danger
    }
}

func priorityColor(_ priority: Priority) -> Color {
    switch priority {
    case .low: BaumioTheme.secondaryText
    case .medium: BaumioTheme.warning
    case .high: BaumioTheme.danger
    }
}

extension Decimal {
    private static let euroFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var euroString: String {
        Self.euroFormatter.string(from: NSDecimalNumber(decimal: self)) ?? "0,00 €"
    }
}
