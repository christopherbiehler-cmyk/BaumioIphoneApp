import SwiftUI
import AuthenticationServices
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import StoreKit

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
        .clipShape(RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous))
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
            // Abbruch durch den Nutzer nicht als Fehler anzeigen.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            model.authError = error.localizedDescription
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

            if let project = model.selectedProject {
                SecondaryButton(title: "Baubericht exportieren", systemImage: "square.and.arrow.up") {
                    if let url = BauberichtPDFExporter.export(model: model, project: project) {
                        bauberichtExport = ShareableURL(url: url)
                    }
                }
            }
        }
        .sheet(item: $bauberichtExport) { shareable in
            ShareSheet(items: [shareable.url])
        }
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
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(project.name).font(.headline).foregroundStyle(BaumioTheme.primaryText)
                                Spacer()
                                if model.selectedProject?.id == project.id {
                                    StatusBadge(title: "Ausgewählt", color: BaumioTheme.accent)
                                }
                                StatusBadge(title: project.status.rawValue, color: project.status == .active ? BaumioTheme.success : BaumioTheme.secondaryText)
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
    @State private var editingItem: EditingItem?

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

            ForEach(model.trades) { trade in
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
                                Button("Löschen", role: .destructive) {
                                    model.handle { try await model.deleteTrade(trade) }
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
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .trade, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(isPresented: $showingBizCardScanner) {
            VisitenkarteScannerSheet(model: model)
        }
    }
}

struct ScheduleView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var viewMode = "Liste"
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var exportSheet: ShareableURL?
    private let modes = ["Liste", "Zeitstrahl"]

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
                ForEach(model.schedule) { item in
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
                                        model.handle { try await model.deleteAppointment(item) }
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
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .appointment, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(item: $exportSheet) { shareable in
            ShareSheet(items: [shareable.url])
        }
    }
}

struct DiaryView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?

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
                                    model.handle { try await model.deleteDiaryEntry(entry) }
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
            QuickAddView(kind: .diary, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
    }
}

struct TasksView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?

    var body: some View {
        ListScreen(title: "Aufgaben", subtitle: "Prioritäten, Fälligkeiten und Filter") {
            PrimaryButton(title: "Aufgabe anlegen", systemImage: "plus", action: { showingEditor = true })

            ForEach(model.tasks) { task in
                BaumioCard {
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
                                model.handle { try await model.deleteTask(task) }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Aufgabe bearbeiten oder löschen")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .task, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
    }
}

struct MaterialsView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var searchText = ""
    @State private var statusFilter = "Alle"
    @State private var supplierFilter = "Alle"

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
                                    model.handle { try await model.deleteMaterial(material) }
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
                        Text(material.notes).font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .material, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
    }
}

struct TimeLogsView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?

    var body: some View {
        ScreenScaffold(title: "Zeiterfassung", subtitle: "Arbeitszeiten erfassen und auswerten") {
            PrimaryButton(title: "Zeit erfassen", systemImage: "plus", action: { showingEditor = true })

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
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
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

struct HandoverView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var showingTemplates = false
    @State private var editingItem: EditingItem?
    @State private var exportSheet: ShareableURL?
    @State private var jsonExportSheet: ShareableURL?

    var body: some View {
        ScreenScaffold(title: "Übergabe & Abnahme", subtitle: "Prüfpunkte abhaken und Status festhalten") {
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
            }

            BaumioCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Abnahme-Fortschritt", systemImage: "checkmark.seal")
                            .font(.headline)
                            .foregroundStyle(BaumioTheme.primaryText)
                        Spacer()
                        Text("\(model.handoverProgress) %")
                            .font(.title3.bold())
                            .foregroundStyle(BaumioTheme.primaryText)
                    }
                    ProgressView(value: Double(model.handoverProgress) / 100)
                        .tint(BaumioTheme.success)
                }
            }

            if model.handoverItems.isEmpty {
                EmptyStateView(
                    title: "Noch keine Prüfpunkte",
                    message: "Lege Prüfpunkte für die Bauabnahme an – z. B. Fenster dicht, Heizung funktioniert.",
                    systemImage: "checkmark.seal"
                )
            } else {
                ForEach(model.handoverItems) { entry in
                    BaumioCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                ItemLine(icon: entry.isDone ? "checkmark.circle.fill" : "circle", title: entry.item, subtitle: handoverSubtitle(entry), tint: entry.isDone ? BaumioTheme.success : BaumioTheme.secondaryText)
                                Spacer()
                                StatusBadge(title: entry.status.rawValue, color: handoverColor(entry.status))
                                Menu {
                                    Button("Bearbeiten") { editingItem = .handover(entry) }
                                    Divider()
                                    ForEach(HandoverStatus.allCases) { status in
                                        Button(status.rawValue) {
                                            model.handle { try await model.updateHandoverStatus(entry, status: status) }
                                        }
                                    }
                                    Divider()
                                    Button("Löschen", role: .destructive) {
                                        model.handle { try await model.deleteHandoverItem(entry) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").foregroundStyle(BaumioTheme.secondaryText).font(.title3).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Prüfpunkt bearbeiten, Status ändern oder löschen")
                            }
                            if !entry.notes.isEmpty {
                                Text(entry.notes).font(.footnote).foregroundStyle(BaumioTheme.secondaryText)
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
    }

    private func exportChecklistAsJSON() -> URL? {
        let items = model.handoverItems.map { entry -> [String: String] in
            ["item": entry.item, "room": entry.room, "tradeType": entry.tradeType, "notes": entry.notes]
        }
        let wrapper: [String: Any] = [
            "name": model.selectedProject?.name ?? "Meine Checkliste",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "items": items
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper, options: .prettyPrinted) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Baumio_Checkliste.json")
        try? data.write(to: url)
        return url
    }

    private func handoverSubtitle(_ entry: HandoverItem) -> String {
        [entry.room, entry.tradeType].filter { !$0.isEmpty }.joined(separator: " · ")
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
            let entries = rawItems.compactMap { dict -> (item: String, room: String, trade: String)? in
                guard let item = dict["item"], !item.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return (item: item, room: dict["room"] ?? "", trade: dict["tradeType"] ?? "")
            }
            guard !entries.isEmpty else {
                importError = "Keine gültigen Prüfpunkte gefunden."
                return
            }
            isLoading = true
            Task {
                do {
                    for entry in entries {
                        try await model.createHandoverItem(item: entry.item, room: entry.room, tradeType: entry.trade)
                    }
                    loadedTemplate = "Import (\(entries.count) Punkte geladen)"
                } catch {
                    importError = error.localizedDescription
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

struct CostsView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var showingScanner = false

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
                ForEach(model.costs) { cost in
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
                                        model.handle { try await model.deleteCost(cost) }
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
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .cost, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(isPresented: $showingScanner) {
            DocumentScannerSheet(docType: .rechnung, model: model)
        }
    }

    private var availableBudget: Decimal {
        (model.selectedProject?.budget ?? 0) - model.plannedCosts
    }
}

struct OffersView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: EditingItem?
    @State private var showingScanner = false

    private var groupedOffers: [(scope: String, offers: [OfferItem])] {
        let byScope = Dictionary(grouping: model.offers.filter { !$0.scope.isEmpty }) { $0.scope }
        return byScope.compactMap { key, values -> (scope: String, offers: [OfferItem])? in
            guard values.count >= 2 else { return nil }
            return (scope: key, offers: values.sorted { $0.amount < $1.amount })
        }.sorted { $0.scope < $1.scope }
    }

    private var ungroupedOffers: [OfferItem] {
        let byScope = Dictionary(grouping: model.offers.filter { !$0.scope.isEmpty }) { $0.scope }
        let singleScopeOffers = byScope.filter { $0.value.count < 2 }.flatMap { $0.value }
        return model.offers.filter { $0.scope.isEmpty } + singleScopeOffers
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
                if !groupedOffers.isEmpty {
                    Text("Einzelangebote")
                        .font(.headline)
                        .foregroundStyle(BaumioTheme.primaryText)
                        .padding(.top, 4)
                }
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

/// Foto-Streifen mit Hinzufügen-Button (komprimiert vor dem Upload).
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
    @State private var exportSheet: ShareableURL?
    @State private var tradeFilter = "Alle"
    @State private var statusFilter = "Alle"

    private var tradeOptions: [String] {
        let names = model.defects.map(\.trade).filter { !$0.isEmpty }
        return ["Alle"] + Array(Set(names)).sorted()
    }

    private var filteredDefects: [DefectItem] {
        model.defects.filter { d in
            let matchesTrade = tradeFilter == "Alle" || d.trade == tradeFilter
            let matchesStatus = statusFilter == "Alle" || d.status == statusFilter
            return matchesTrade && matchesStatus
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
                                    model.handle { try await model.deleteDefect(defect) }
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
                        }
                        PhotoSection(model: model, bucket: "defect-photos", photos: model.defectPhotos[defect.id] ?? []) { data in
                            model.handle { try await model.addDefectPhoto(defect, imageData: data) }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            QuickAddView(kind: .defect, model: model)
        }
        .sheet(item: $editingItem) { item in
            QuickAddView(editing: item, model: model)
        }
        .sheet(item: $exportSheet) { shareable in
            ShareSheet(items: [shareable.url])
        }
    }
}

struct FundingView: View {
    @Bindable var model: BaumioAppViewModel
    @State private var showingEditor = false
    @State private var editingItem: FundingItem?

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
                                        model.handle { try await model.deleteFunding(item) }
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
                                        model.handle { try await model.deleteReview(review) }
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

    var body: some View {
        ScreenScaffold(title: "Abo", subtitle: model.isPro ? "Baumio Pro ist aktiv" : "14 Tage kostenlos testen, danach \(model.store.proDisplayPrice)/Monat") {
            if model.isPro {
                BaumioCard {
                    HStack {
                        Label("Baumio Pro ist aktiv", systemImage: "crown.fill")
                            .font(.headline)
                            .foregroundStyle(BaumioTheme.primaryText)
                        Spacer()
                        StatusBadge(title: "Aktiv", color: BaumioTheme.success)
                    }
                }
            }

            AdaptiveGrid(minimum: 280) {
                ForEach(model.pricingPlans) { plan in
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
                        Text(model.store.proDisplayPrice)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(BaumioTheme.accent)
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

                    if let error = model.store.purchaseError {
                        Text(error).font(.footnote).foregroundStyle(BaumioTheme.warning)
                    }

                    PrimaryButton(
                        title: model.store.isPurchasing ? "Wird verarbeitet …" : "14 Tage kostenlos testen",
                        systemImage: "crown.fill"
                    ) {
                        Task { await model.purchasePro() }
                    }

                    SecondaryButton(title: "Käufe wiederherstellen", systemImage: "arrow.clockwise") {
                        Task { await model.restorePurchases() }
                    }

                    Text("Abrechnung über deinen Apple-Account. Das Abo verlängert sich automatisch, sofern es nicht 24 Stunden vor Ablauf gekündigt wird. Verwaltung und Kündigung über die Apple-Abo-Einstellungen.")
                        .font(.caption)
                        .foregroundStyle(BaumioTheme.secondaryText)
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
    @State private var dsgvoExport: ShareableURL?
    @Environment(\.requestReview) private var requestReview

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

    init(kind: QuickAddKind, model: BaumioAppViewModel) {
        self.kind = kind
        self.editing = nil
        self._model = Bindable(wrappedValue: model)
        _title = State(initialValue: "")
        _secondary = State(initialValue: "")
        _amount = State(initialValue: "")
        _unit = State(initialValue: "")
        _notes = State(initialValue: "")
        _date = State(initialValue: Date())
        _endDate = State(initialValue: Date())
        _status = State(initialValue: kind == .task ? "normal" : kind == .cost ? "offen" : "geplant")
        _category = State(initialValue: "sonstiges")
        _severity = State(initialValue: "mäßig")
        _importance = State(initialValue: "wichtig")
        _temperature = State(initialValue: "")
        _supplier = State(initialValue: "")
        _articleNumber = State(initialValue: "")
        _fundingItemID = State(initialValue: nil)
        _offerScope = State(initialValue: "")
        _hours = State(initialValue: "")
        _minutes = State(initialValue: "")
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
    }

    private func save() async {
        errorMessage = nil
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
            try await model.createDiaryEntry(date: date, notes: title, weather: secondary.isEmpty ? "bewölkt" : secondary, temperature: Int(temperature), presentTrades: supplier)
        case .task:
            try await model.createTask(title: title, priority: status == "geplant" ? "normal" : status, dueDate: date)
        case .material:
            try await model.createMaterial(name: title, quantity: decimal(amount, fallback: 1), unit: unit, supplier: supplier, articleNumber: articleNumber, price: decimal(secondary), status: status, orderDate: date, deliveryDate: endDate, notes: notes, fundingItemID: fundingItemID)
        case .cost:
            try await model.createCost(
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
        case .offer:
            try await model.createOffer(title: title, company: secondary, amount: decimal(amount), validUntil: endDate, status: status, notes: notes, fundingItemID: fundingItemID, scope: offerScope)
        case .defect:
            try await model.createDefect(description: title, trade: defectTrade, responsible: defectResponsible, deadline: defectDeadline, severity: severity, importance: importance, status: status)
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
            try await model.updateMaterial(item, name: title, quantity: decimal(amount, fallback: 1), unit: unit, supplier: supplier, articleNumber: articleNumber, price: decimal(secondary), status: status, notes: notes, fundingItemID: fundingItemID)
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
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
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

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(BaumioTheme.warning)
                    }
                }

                if editing != nil {
                    Section {
                        Button("Projekt löschen", role: .destructive) {
                            Task {
                                if let project = editing {
                                    try? await model.deleteProject(project)
                                    dismiss()
                                }
                            }
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
    }

    private func prefill() {
        guard let project = editing else { return }
        name = project.name
        budget = project.budget > 0 ? NSDecimalNumber(decimal: project.budget).stringValue : ""
        description = project.description
        status = project.status
        startDate = project.startDate
        endDate = project.plannedEndDate
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let parsedBudget = Decimal(string: budget.replacingOccurrences(of: ",", with: ".")) ?? 0
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let project = editing {
                try await model.updateProject(project, name: trimmedName, budget: parsedBudget, status: status, description: description.trimmingCharacters(in: .whitespacesAndNewlines), startDate: startDate, endDate: endDate)
            } else {
                try await model.createProject(name: trimmedName, budget: parsedBudget, status: status, description: description.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
