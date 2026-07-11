import Foundation
import Observation
import StoreKit
import UserNotifications
import UIKit

@MainActor
@Observable
final class BaumioAppViewModel {
    var hasCompletedOnboarding = false
    var isAuthenticated = false
    var selectedSection: BaumioSection = .dashboard
    var selectedProject: Project?
    var email = ""
    var password = ""
    var authError: String?
    var authInfo: String?
    var isLoading = false
    /// Fehler einer Aktion (Status ändern, Löschen …) – wird als Alert angezeigt.
    var actionError: String?
    /// Wird auf true gesetzt wenn der Nutzer Benachrichtigungen in den Systemeinstellungen blockiert hat.
    var notificationPermissionDenied = false

    /// Pro-Status aus Supabase (plattformübergreifend, auch für die Website).
    var profileIsPro = false
    let store = StoreManager()

    /// Im kostenlosen Plan: 1 Projekt, 5 Gewerke, 10 Kostenpositionen.
    static let freeProjectLimit = 1
    static let freeTradeLimit = 5
    static let freeCostLimit = 10

    var projects: [Project]
    var trades: [Trade]
    var schedule: [ScheduleItem]
    var diary: [DiaryEntry]
    var tasks: [TaskItem]
    var materials: [MaterialItem]
    var documents: [DocumentItem]
    var costs: [CostItem]
    var offers: [OfferItem]
    var defects: [DefectItem]
    var funding: [FundingItem]
    var reviews: [ReviewItem]
    var timeLogs: [TimeLogItem] = []
    var handoverItems: [HandoverItem] = []
    var displayName = ""
    var triggerReviewRequest = false
    /// Fotos je Mangel bzw. Tagebuch-Eintrag (Schlüssel = Eintrags-ID).
    var defectPhotos: [UUID: [PhotoRef]] = [:]
    var diaryPhotos: [UUID: [PhotoRef]] = [:]
    let pricingPlans = DemoData.pricingPlans

    private let supabase = SupabaseService()
    private var supabaseSession: SupabaseSession?

    init() {
        projects = DemoData.projects
        trades = DemoData.trades
        schedule = DemoData.schedule
        diary = DemoData.diary
        tasks = DemoData.tasks
        materials = DemoData.materials
        documents = DemoData.documents
        costs = DemoData.costs
        offers = DemoData.offers
        defects = DemoData.defects
        funding = DemoData.funding
        reviews = DemoData.reviews
        selectedProject = DemoData.projects.first

        if !supabase.isConfigured {
            authInfo = "Demo-Modus: Supabase ist vorbereitet, aber noch nicht konfiguriert."
        }

    }

    var usesSupabase: Bool {
        supabase.isConfigured
    }

    /// Pro ist freigeschaltet, wenn ein aktives App-Abo besteht ODER der Supabase-Status Pro ist
    /// (z. B. via Web-Abo gesetzt). So sind App und Website konsistent.
    var isPro: Bool {
        store.isSubscribed || profileIsPro
    }

    var canCreateProject: Bool {
        isPro || projects.count < Self.freeProjectLimit
    }

    var canCreateTrade: Bool {
        isPro || trades.count < Self.freeTradeLimit
    }

    var canCreateCost: Bool {
        isPro || costs.count < Self.freeCostLimit
    }

    var openTasks: [TaskItem] {
        tasks.filter { !$0.isDone }
    }

    var dueTodayCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let dueTasks = tasks.filter { !$0.isDone && $0.dueDate >= today && $0.dueDate < tomorrow }.count
        let dueDefects = defects.filter { $0.status != "Behoben" && $0.deadline >= today && $0.deadline < tomorrow }.count
        return dueTasks + dueDefects
    }

    // MARK: - Projektfortschritt (wie im Portal: Mittel aus 4 Dimensionen)

    var progressTasks: Int {
        guard !tasks.isEmpty else { return 0 }
        return Int((Double(tasks.filter(\.isDone).count) / Double(tasks.count) * 100).rounded())
    }

    var progressCosts: Int {
        selectedProject?.progressByCosts ?? 0
    }

    var progressMaterials: Int {
        guard !materials.isEmpty else { return 0 }
        let ordered = materials.filter { ["Bestellt", "Geliefert", "Verbaut"].contains($0.deliveryStatus) }.count
        return Int((Double(ordered) / Double(materials.count) * 100).rounded())
    }

    var progressTimeline: Int {
        guard !schedule.isEmpty else { return 0 }
        let done = schedule.filter { $0.status == .done }.count
        return Int((Double(done) / Double(schedule.count) * 100).rounded())
    }

    var overallProgress: Int {
        Int((Double(progressTasks + progressCosts + progressMaterials + progressTimeline) / 4.0).rounded())
    }

    var totalTrackedMinutes: Int {
        timeLogs.reduce(0) { $0 + $1.durationMinutes }
    }

    /// Formatiert Minuten als "X h Y min".
    var totalTrackedTimeText: String {
        let minutes = totalTrackedMinutes
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    /// Plan/Bestellt/Bezahlt-Anteile einer Materialposition – exakt wie die Website:
    /// Betrag = Einzelpreis × Menge; verbaut → bezahlt, bestellt/geliefert → beauftragt.
    func materialCostShares(_ material: MaterialItem) -> (planned: Decimal, ordered: Decimal, paid: Decimal) {
        let total = material.price * Decimal(material.quantity)
        let planned = total
        let ordered = ["Bestellt", "Geliefert", "Verbaut"].contains(material.deliveryStatus) ? total : 0
        let paid = material.deliveryStatus == "Verbaut" ? total : 0
        return (planned, ordered, paid)
    }

    /// Materialsummen (für die zusammengefasste Zeile in der Kostenliste).
    var materialCostTotals: (planned: Decimal, ordered: Decimal, paid: Decimal) {
        materials.reduce((planned: 0, ordered: 0, paid: 0)) { acc, material in
            let s = materialCostShares(material)
            return (acc.planned + s.planned, acc.ordered + s.ordered, acc.paid + s.paid)
        }
    }

    var paidCosts: Decimal {
        costs.reduce(0) { $0 + $1.paid } + materials.reduce(0) { $0 + materialCostShares($1).paid }
    }

    var plannedCosts: Decimal {
        costs.reduce(0) { $0 + $1.planned } + materials.reduce(0) { $0 + materialCostShares($1).planned }
    }

    var orderedCosts: Decimal {
        costs.reduce(0) { $0 + $1.ordered } + materials.reduce(0) { $0 + materialCostShares($1).ordered }
    }

    var openDefects: [DefectItem] {
        defects.filter { $0.status != "Behoben" }
    }

    func startFree() {
        hasCompletedOnboarding = true

        if supabase.isConfigured {
            authInfo = "Bitte registriere dich oder logge dich ein, damit Baumio deine Supabase-Daten lädt."
            isAuthenticated = false
        } else {
            isAuthenticated = true
        }
    }

    func showLogin() {
        hasCompletedOnboarding = true
        isAuthenticated = false
    }

    func login() async {
        authError = nil
        authInfo = nil

        guard email.contains("@"), password.count >= 6 else {
            authError = "Bitte gib eine gültige E-Mail-Adresse und ein Passwort mit mindestens 6 Zeichen ein."
            return
        }

        guard supabase.isConfigured else {
            authInfo = "Demo-Modus aktiv. Trage SUPABASE_URL und SUPABASE_ANON_KEY ein, um echte Anmeldung zu nutzen."
            isAuthenticated = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            supabaseSession = try await supabase.signIn(email: email, password: password)
            persistSession()
            clearLocalData()
            try await loadProjects()
            await refreshProStatus()
            isAuthenticated = true
        } catch {
            authError = error.localizedDescription
        }
    }

    /// Stellt eine gespeicherte Sitzung beim App-Start wieder her (angemeldet bleiben).
    func restoreSession() async {
        guard supabaseSession == nil, supabase.isConfigured, let stored = SessionStore.load(), let refreshToken = stored.refreshToken else { return }
        do {
            let refreshed = try await supabase.refreshSession(refreshToken: refreshToken)
            supabaseSession = refreshed
            persistSession()
            hasCompletedOnboarding = true
            try await loadProjects()
            await refreshProStatus()
            isAuthenticated = true
        } catch {
            SessionStore.clear()
        }
    }

    func logout() {
        supabaseSession = nil
        SessionStore.clear()
        profileIsPro = false
        email = ""
        password = ""
        clearLocalData()
        isAuthenticated = false
        selectedSection = .dashboard
    }

    func deleteAccount() async throws {
        guard let session = supabaseSession else { throw SupabaseError.missingSession }
        try await supabase.deleteAccount(accessToken: session.accessToken)
        logout()
        hasCompletedOnboarding = false
    }

    private func persistSession() {
        if let supabaseSession {
            SessionStore.save(supabaseSession)
        }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        authError = nil
        authInfo = nil

        guard supabase.isConfigured else {
            authInfo = "Sign in with Apple ist vorbereitet. Im Demo-Modus ohne Supabase wird fortgefahren."
            hasCompletedOnboarding = true
            isAuthenticated = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            supabaseSession = try await supabase.signInWithApple(idToken: idToken, nonce: nonce)
            persistSession()
            clearLocalData()
            try await loadProjects()
            await refreshProStatus()
            hasCompletedOnboarding = true
            isAuthenticated = true
        } catch {
            authError = error.localizedDescription
        }
    }

    func register() async {
        authError = nil
        authInfo = nil

        guard email.contains("@"), password.count >= 6 else {
            authError = "Die Registrierung benötigt eine gültige E-Mail-Adresse und ein sicheres Passwort."
            return
        }

        guard supabase.isConfigured else {
            authInfo = "Registrierung ist vorbereitet. Im Demo-Modus wird ohne Supabase fortgefahren."
            isAuthenticated = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            supabaseSession = try await supabase.signUp(email: email, password: password)
            persistSession()
            clearLocalData()
            try await loadProjects()
            await refreshProStatus()
            isAuthenticated = true
        } catch {
            authError = error.localizedDescription
        }
    }

    /// Liest den Pro-Status aus Supabase und gleicht ihn mit dem App-Abo ab.
    func refreshProStatus() async {
        await store.refreshSubscriptionStatus()

        guard let session = supabaseSession, let userID = session.user?.id else { return }
        do {
            profileIsPro = try await supabase.fetchProStatus(userID: userID, accessToken: session.accessToken)
        } catch {
            // Profil noch nicht angelegt o. Ä. – Pro bleibt beim App-Abo-Status.
        }

        // Aktives App-Abo zentral in Supabase spiegeln, damit die Website denselben Status kennt.
        if store.isSubscribed && !profileIsPro {
            await syncProToSupabase()
        }
    }

    /// Startet den Pro-Kauf via StoreKit und spiegelt den Status nach Supabase.
    @discardableResult
    func purchasePro() async -> Bool {
        // Supabase-User-ID als appAccountToken mitgeben → ermöglicht die serverseitige Zuordnung.
        let success = await store.purchasePro(appAccountToken: supabaseSession?.user?.id)
        if success {
            await syncProToSupabase()
        }
        return success
    }

    func restorePurchases() async {
        await store.restore()
        if store.isSubscribed {
            await syncProToSupabase()
        }
    }

    private func syncProToSupabase() async {
        guard let session = supabaseSession, let userID = session.user?.id else { return }
        // Bereits 'pro' oder 'business' (z. B. via Website) → nicht überschreiben (kein Downgrade von business).
        if profileIsPro { return }
        do {
            try await supabase.setPlan(userID: userID, plan: "pro", accessToken: session.accessToken)
            profileIsPro = true
        } catch {
            // Spiegelung fehlgeschlagen – App-Abo bleibt trotzdem aktiv (store.isSubscribed).
        }
    }

    func loadProjects() async throws {
        guard let accessToken = supabaseSession?.accessToken else {
            throw SupabaseError.missingSession
        }

        projects = try await supabase.fetchProjects(accessToken: accessToken)
        selectedProject = projects.first
        if let selectedProject {
            try await loadDetails(for: selectedProject)
        }
    }

    func selectProject(_ project: Project) {
        selectedProject = project
        clearProjectScopedData()
        Task {
            do {
                try await loadDetails(for: project)
            } catch {
                authError = error.localizedDescription
            }
        }
    }

    /// Führt eine Aktion aus und zeigt Fehler zentral als Alert an.
    func handle(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { actionError = error.localizedDescription }
        }
    }

    /// Manuelles Neuladen (Pull-to-Refresh).
    func reload() async {
        guard selectedProject != nil else { return }
        do { try await reloadSelectedProjectDetails() } catch { actionError = error.localizedDescription }
    }

    func deleteTimeLog(_ item: TimeLogItem) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "time_logs", id: item.id, accessToken: context.accessToken)
        timeLogs.removeAll { $0.id == item.id }
    }

    func deleteHandoverItem(_ item: HandoverItem) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "handover_items", id: item.id, accessToken: context.accessToken)
        handoverItems.removeAll { $0.id == item.id }
    }

    func updateProject(_ project: Project, name: String, budget: Decimal, status: ProjectStatus, description: String, startDate: Date, endDate: Date) async throws {
        guard let accessToken = supabaseSession?.accessToken else { throw SupabaseError.missingSession }
        try await supabase.update(
            UpdateSupabaseProject(name: name, status: status.supabaseValue, budget: budget,
                                  startDate: BaumioDateFormatter.string(from: startDate),
                                  endDate: BaumioDateFormatter.string(from: endDate),
                                  description: description.nilIfEmpty),
            in: "projects", id: project.id, accessToken: accessToken
        )
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i].name = name
            projects[i].budget = budget
            projects[i].status = status
            projects[i].description = description
            projects[i].startDate = startDate
            projects[i].plannedEndDate = endDate
        }
        if selectedProject?.id == project.id {
            selectedProject?.name = name
            selectedProject?.budget = budget
            selectedProject?.status = status
        }
    }

    func deleteProject(_ project: Project) async throws {
        guard let accessToken = supabaseSession?.accessToken else { throw SupabaseError.missingSession }
        try await supabase.delete(from: "projects", id: project.id, accessToken: accessToken)
        projects.removeAll { $0.id == project.id }
        if selectedProject?.id == project.id {
            selectedProject = projects.first
            clearProjectScopedData()
            if let newProject = selectedProject {
                try? await loadDetails(for: newProject)
            }
        }
    }

    func deleteTrade(_ trade: Trade) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "trades", id: trade.id, accessToken: context.accessToken)
        trades.removeAll { $0.id == trade.id }
    }

    func deleteAppointment(_ item: ScheduleItem) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "appointments", id: item.id, accessToken: context.accessToken)
        schedule.removeAll { $0.id == item.id }
    }

    func deleteTask(_ task: TaskItem) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "project_todos", id: task.id, accessToken: context.accessToken)
        tasks.removeAll { $0.id == task.id }
    }

    func deleteMaterial(_ material: MaterialItem) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "materials", id: material.id, accessToken: context.accessToken)
        materials.removeAll { $0.id == material.id }
    }

    func deleteCost(_ cost: CostItem) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "costs", id: cost.id, accessToken: context.accessToken)
        costs.removeAll { $0.id == cost.id }
    }

    func deleteOffer(_ offer: OfferItem) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "quotes", id: offer.id, accessToken: context.accessToken)
        offers.removeAll { $0.id == offer.id }
    }

    func deleteDefect(_ defect: DefectItem) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "defects", id: defect.id, accessToken: context.accessToken)
        defects.removeAll { $0.id == defect.id }
    }

    func deleteDiaryEntry(_ entry: DiaryEntry) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "diary_entries", id: entry.id, accessToken: context.accessToken)
        diary.removeAll { $0.id == entry.id }
    }

    func deleteReview(_ review: ReviewItem) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "trade_ratings", id: review.id, accessToken: context.accessToken)
        reviews.removeAll { $0.id == review.id }
    }

    private func loadDetails(for project: Project) async throws {
        guard let accessToken = supabaseSession?.accessToken else { throw SupabaseError.missingSession }
        let details = try await supabase.fetchProjectDetails(projectID: project.id, accessToken: accessToken)
        trades = details.trades
        schedule = details.schedule
        tasks = details.tasks
        materials = details.materials
        costs = details.costs
        offers = details.offers
        defects = details.defects
        diary = details.diary
        documents = details.documents
        timeLogs = details.timeLogs
        handoverItems = details.handoverItems
        funding = details.funding
        reviews = details.reviews
        await refreshStorageUsage()
        await loadPhotos(accessToken: accessToken)
    }

    private func loadPhotos(accessToken: String) async {
        defectPhotos = (try? await groupedPhotos(table: "defect_photos", parentColumn: "defect_id", ids: defects.map(\.id), accessToken: accessToken)) ?? [:]
        diaryPhotos = (try? await groupedPhotos(table: "diary_photos", parentColumn: "diary_entry_id", ids: diary.map(\.id), accessToken: accessToken)) ?? [:]
    }

    private func groupedPhotos(table: String, parentColumn: String, ids: [UUID], accessToken: String) async throws -> [UUID: [PhotoRef]] {
        let rows = try await supabase.fetchPhotos(table: table, parentColumn: parentColumn, parentIDs: ids, accessToken: accessToken)
        var result: [UUID: [PhotoRef]] = [:]
        for row in rows {
            guard let parent = row.parent else { continue }
            result[parent, default: []].append(PhotoRef(id: row.id, storagePath: row.storagePath))
        }
        return result
    }

    func photoURL(bucket: String, path: String) async throws -> URL {
        guard let session = supabaseSession else { throw SupabaseError.missingSession }
        return try await supabase.createSignedURL(bucket: bucket, path: path, accessToken: session.accessToken)
    }

    func addDefectPhoto(_ defect: DefectItem, imageData: Data) async throws {
        let path = try await uploadPhoto(bucket: "defect-photos", parentID: defect.id, imageData: imageData)
        try await supabase.insert(NewSupabaseDefectPhoto(defectID: defect.id, storagePath: path, fileSize: imageData.count), into: "defect_photos", accessToken: try supabaseContext().accessToken)
        defectPhotos[defect.id, default: []].append(PhotoRef(storagePath: path))
        await refreshStorageUsage()
    }

    func addDiaryPhoto(_ entry: DiaryEntry, imageData: Data) async throws {
        let path = try await uploadPhoto(bucket: "diary-photos", parentID: entry.id, imageData: imageData)
        try await supabase.insert(NewSupabaseDiaryPhoto(diaryEntryID: entry.id, storagePath: path, fileSize: imageData.count), into: "diary_photos", accessToken: try supabaseContext().accessToken)
        diaryPhotos[entry.id, default: []].append(PhotoRef(storagePath: path))
        await refreshStorageUsage()
    }

    private func uploadPhoto(bucket: String, parentID: UUID, imageData: Data) async throws -> String {
        guard let session = supabaseSession, let userID = session.user?.id else { throw SupabaseError.missingSession }
        guard canUpload(imageData.count) else {
            throw SupabaseError.requestFailed("Speicherlimit erreicht (\(storageLimitBytes / 1_048_576) MB). Upgrade auf Baumio Pro für 5 GB.")
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let path = "\(userID.uuidString.lowercased())/\(parentID.uuidString)/\(stamp).jpg"
        try await supabase.uploadToStorage(bucket: bucket, path: path, data: imageData, contentType: "image/jpeg", accessToken: session.accessToken)
        return path
    }

    func createProject(name: String, budget: Decimal, status: ProjectStatus, description: String?) async throws {
        guard canCreateProject else {
            throw SupabaseError.requestFailed("Im kostenlosen Plan ist 1 Projekt möglich. Mit Baumio Pro legst du unbegrenzt viele Projekte an.")
        }
        guard let session = supabaseSession, let userID = session.user?.id else {
            throw SupabaseError.missingSession
        }

        let newProject = NewSupabaseProject(
            userID: userID,
            name: name,
            status: status.supabaseValue,
            budget: budget,
            startDate: nil,
            endDate: nil,
            description: description?.isEmpty == true ? nil : description
        )

        let createdProject = try await supabase.createProject(newProject, accessToken: session.accessToken)
        projects.insert(createdProject, at: 0)
        selectedProject = createdProject
        clearProjectScopedData()
    }

    func createTrade(name: String, company: String, tradeType: String = "", address: String = "", phone: String = "", email: String = "", budget: Decimal = 0, notes: String) async throws {
        guard canCreateTrade else {
            throw SupabaseError.requestFailed("Im kostenlosen Plan sind bis zu 5 Firmen möglich. Mit Baumio Pro sind es unbegrenzt viele.")
        }
        let context = try supabaseContext()
        let encodedNotes = TradeContactCoder.encode(address: address, phone: phone, email: email, userNotes: notes)
        let rows: [SupabaseTradeRow] = try await supabase.insertReturning(NewSupabaseTrade(projectID: context.projectID, name: name, company: company.nilIfEmpty, tradeType: tradeType.nilIfEmpty, status: "angefragt", budget: budget > 0 ? budget : nil, notes: encodedNotes), into: "trades", accessToken: context.accessToken)
        if let created = rows.first?.appTrade { trades.append(created) }
    }

    func createAppointment(title: String, date: Date, notes: String, startTime: Date? = nil, endTime: Date? = nil, status: String = "geplant", dependsOn: UUID? = nil) async throws {
        let context = try supabaseContext()
        let encodedNotes = AppointmentTimeCoder.encode(startTime: startTime, endTime: endTime, userNotes: notes)
        let rows: [SupabaseAppointmentRow] = try await supabase.insertReturning(NewSupabaseAppointment(projectID: context.projectID, title: title, date: BaumioDateFormatter.string(from: date), notes: encodedNotes, status: status), into: "appointments", accessToken: context.accessToken)
        if var created = rows.first?.appScheduleItem {
            created.dependsOn = dependsOn
            schedule.append(created)
        }
    }

    func createTask(title: String, priority: String, dueDate: Date?) async throws {
        let context = try supabaseContext()
        guard let userID = supabaseSession?.user?.id else { throw SupabaseError.missingSession }
        let rows: [SupabaseTodoRow] = try await supabase.insertReturning(
            NewSupabaseTodo(projectID: context.projectID, userID: userID, title: title, priority: priority, dueDate: dueDate.map(BaumioDateFormatter.string(from:))),
            into: "project_todos",
            accessToken: context.accessToken
        )
        if let created = rows.first?.appTask { tasks.append(created) }
    }

    func createMaterial(name: String, quantity: Decimal, unit: String, supplier: String, articleNumber: String, price: Decimal, status: String, orderDate: Date?, deliveryDate: Date?, notes: String, fundingItemID: UUID? = nil) async throws {
        let context = try supabaseContext()
        let encodedNotes = FundingLinkCoder.encode(fundingID: fundingItemID, userNotes: notes)
        let rows: [SupabaseMaterialRow] = try await supabase.insertReturning(
            NewSupabaseMaterial(
                projectID: context.projectID,
                name: name,
                quantity: quantity,
                unit: unit.isEmpty ? "Stück" : unit,
                supplier: supplier.nilIfEmpty,
                articleNumber: articleNumber.nilIfEmpty,
                priceEstimated: price,
                status: status,
                orderDate: orderDate.map(BaumioDateFormatter.string(from:)),
                deliveryDate: deliveryDate.map(BaumioDateFormatter.string(from:)),
                notes: encodedNotes
            ),
            into: "materials",
            accessToken: context.accessToken
        )
        if let created = rows.first?.appMaterial { materials.append(created) }
    }

    func createCost(
        title: String, amount: Decimal, category: String, status: String,
        invoiceReference: String = "", notes: String, fundingItemID: UUID? = nil,
        invoiceDate: Date? = nil, dueDate: Date? = nil,
        laborAmount: Decimal = 0, machineAmount: Decimal = 0, travelAmount: Decimal = 0,
        warrantyEnd: Date? = nil, paymentDate: Date? = nil, supplier: String = ""
    ) async throws {
        guard canCreateCost else {
            throw SupabaseError.requestFailed("Im kostenlosen Plan sind bis zu \(Self.freeCostLimit) Kostenpositionen möglich. Mit Baumio Pro kannst du unbegrenzt budgetieren.")
        }
        let context = try supabaseContext()
        let encodedNotes = FundingLinkCoder.encode(fundingID: fundingItemID, userNotes: notes)
        let rows: [SupabaseCostRow] = try await supabase.insertReturning(
            NewSupabaseCost(
                projectID: context.projectID, description: title, category: category,
                costType: "rechnung", amount: amount, status: status,
                invoiceNumber: invoiceReference.nilIfEmpty, notes: encodedNotes,
                invoiceDate: invoiceDate.map(BaumioDateFormatter.string(from:)),
                dueDate: dueDate.map(BaumioDateFormatter.string(from:)),
                laborAmount: laborAmount > 0 ? laborAmount : nil,
                machineAmount: machineAmount > 0 ? machineAmount : nil,
                travelAmount: travelAmount > 0 ? travelAmount : nil,
                warrantyEnd: warrantyEnd.map(BaumioDateFormatter.string(from:)),
                paymentDate: paymentDate.map(BaumioDateFormatter.string(from:)),
                supplier: supplier.nilIfEmpty
            ),
            into: "costs", accessToken: context.accessToken
        )
        if let created = rows.first?.appCost { costs.append(created) }
    }

    func createOffer(title: String, company: String, amount: Decimal, validUntil: Date?, status: String, notes: String, fundingItemID: UUID? = nil, scope: String = "") async throws {
        let context = try supabaseContext()
        let encodedNotes = FundingLinkCoder.encode(fundingID: fundingItemID, userNotes: notes)
        let rows: [SupabaseQuoteRow] = try await supabase.insertReturning(NewSupabaseQuote(projectID: context.projectID, title: title, company: company.nilIfEmpty, amount: amount, validUntil: validUntil.map(BaumioDateFormatter.string(from:)), notes: encodedNotes, scope: scope.nilIfEmpty), into: "quotes", accessToken: context.accessToken)
        if let created = rows.first?.appOffer { offers.append(created) }
    }

    func createDefect(description: String, trade: String = "", responsible: String = "", deadline: Date = Date(), severity: String, importance: String, status: String) async throws {
        let context = try supabaseContext()
        let encoded = DefectMetaCoder.encode(trade: trade, responsible: responsible, deadline: deadline, userNotes: description)
        let rows: [SupabaseDefectRow] = try await supabase.insertReturning(NewSupabaseDefect(projectID: context.projectID, description: encoded, severity: severity, importance: importance, status: status), into: "defects", accessToken: context.accessToken)
        if let created = rows.first?.appDefect { defects.append(created) }
    }

    // MARK: - Dokumente / Speicher

    var storageUsedBytes: Int = 0

    /// Speicherlimit nach Plan: Free 500 MB, Pro/Business 5 GB (wie die Website).
    var storageLimitBytes: Int {
        isPro ? 5_368_709_120 : 524_288_000
    }

    var storageUsedFraction: Double {
        guard storageLimitBytes > 0 else { return 0 }
        return min(Double(storageUsedBytes) / Double(storageLimitBytes), 1)
    }

    func canUpload(_ size: Int) -> Bool {
        storageUsedBytes + size <= storageLimitBytes
    }

    func refreshStorageUsage() async {
        guard let session = supabaseSession, let userID = session.user?.id else { return }
        do {
            storageUsedBytes = try await supabase.fetchStorageUsage(userID: userID, accessToken: session.accessToken)
        } catch {
            // View bleibt unverändert – Verbrauch konnte nicht geladen werden.
        }
    }

    func uploadDocument(name: String, docType: String, data: Data, contentType: String, fileExtension: String) async throws {
        guard let session = supabaseSession, let userID = session.user?.id else { throw SupabaseError.missingSession }
        guard let projectID = selectedProject?.id else { throw SupabaseError.missingProject }
        guard canUpload(data.count) else {
            throw SupabaseError.requestFailed("Speicherlimit erreicht (\(storageLimitBytes / 1_048_576) MB). Upgrade auf Baumio Pro für 5 GB.")
        }

        let safeName = name.isEmpty ? "dokument" : name
        let sanitized = safeName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        let stamp = Int(Date().timeIntervalSince1970)
        let ext = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        let path = "\(userID.uuidString.lowercased())/\(projectID.uuidString)/\(stamp)_\(sanitized)\(ext)"

        try await supabase.uploadToStorage(bucket: "documents", path: path, data: data, contentType: contentType, accessToken: session.accessToken)
        try await supabase.insert(
            NewSupabaseDocument(projectID: projectID, name: safeName, docType: docType, storagePath: path, fileSize: data.count),
            into: "documents",
            accessToken: session.accessToken
        )
        try await reloadSelectedProjectDetails()
        await refreshStorageUsage()
    }

    func documentURL(_ document: DocumentItem) async throws -> URL {
        guard let session = supabaseSession else { throw SupabaseError.missingSession }
        guard !document.storagePath.isEmpty else { throw SupabaseError.requestFailed("Für dieses Dokument ist keine Datei hinterlegt.") }
        return try await supabase.createSignedURL(bucket: "documents", path: document.storagePath, accessToken: session.accessToken)
    }

    func deleteDocument(_ document: DocumentItem) async throws {
        let context = try supabaseContext()
        if !document.storagePath.isEmpty {
            try? await supabase.deleteFromStorage(bucket: "documents", path: document.storagePath, accessToken: context.accessToken)
        }
        try await supabase.delete(from: "documents", id: document.id, accessToken: context.accessToken)
        try await reloadSelectedProjectDetails()
        await refreshStorageUsage()
    }

    // MARK: - Fördertracker & Bewertungen

    func createFunding(name: String, provider: String, maxAmount: Decimal, status: String,
                       deadline: Date?, documentDeadline: Date?,
                       kfwG: Bool, kfwK: Bool, kfwE: Bool, kfwF: Bool,
                       notes: String, programType: FundingProgramType = .sonstige,
                       manualGrantRate: Int? = nil) async throws {
        let context = try supabaseContext()
        let encodedNotes = FundingKfWCoder.encode(programType: programType, maxAmount: maxAmount, rate: manualGrantRate, documentDeadline: documentDeadline, g: kfwG, k: kfwK, e: kfwE, f: kfwF, userNotes: notes)
        let pct = manualGrantRate ?? kfwFoerdersatzCalc(g: kfwG, k: kfwK, e: kfwE, f: kfwF)
        let estimated: Decimal = pct > 0 ? maxAmount * Decimal(pct) / 100 : maxAmount
        let rows: [SupabaseSubsidyRow] = try await supabase.insertReturning(
            NewSupabaseSubsidy(projectID: context.projectID, name: name, provider: provider.nilIfEmpty, amount: estimated > 0 ? estimated : nil, status: status, deadline: deadline.map(BaumioDateFormatter.string(from:)), notes: encodedNotes.nilIfEmpty),
            into: "subsidies",
            accessToken: context.accessToken
        )
        if let created = rows.first?.appFunding { funding.append(created) }
    }

    func updateFunding(_ item: FundingItem, name: String, provider: String, maxAmount: Decimal, status: String,
                       deadline: Date?, documentDeadline: Date?,
                       kfwG: Bool, kfwK: Bool, kfwE: Bool, kfwF: Bool,
                       notes: String, programType: FundingProgramType = .sonstige,
                       manualGrantRate: Int? = nil) async throws {
        let context = try supabaseContext()
        let encodedNotes = FundingKfWCoder.encode(programType: programType, maxAmount: maxAmount, rate: manualGrantRate, documentDeadline: documentDeadline, g: kfwG, k: kfwK, e: kfwE, f: kfwF, userNotes: notes)
        let pct = manualGrantRate ?? kfwFoerdersatzCalc(g: kfwG, k: kfwK, e: kfwE, f: kfwF)
        let estimated: Decimal = pct > 0 ? maxAmount * Decimal(pct) / 100 : maxAmount
        try await supabase.update(
            UpdateSupabaseSubsidy(name: name, provider: provider.nilIfEmpty, amount: estimated > 0 ? estimated : nil, status: status, deadline: deadline.map(BaumioDateFormatter.string(from:)), notes: encodedNotes.nilIfEmpty),
            in: "subsidies", id: item.id, accessToken: context.accessToken
        )
        if let idx = funding.firstIndex(where: { $0.id == item.id }) {
            funding[idx] = FundingItem(id: item.id, name: name, provider: provider, amount: estimated,
                                       status: status.displayStatus, deadline: deadline,
                                       referenceNumber: item.referenceNumber, notes: notes,
                                       maxAmount: maxAmount, documentDeadline: documentDeadline,
                                       kfwGrundfoerderung: kfwG, kfwKlimabonus: kfwK,
                                       kfwEinkommensbonus: kfwE, kfwEffizienzbonus: kfwF,
                                       programType: programType, manualGrantRate: manualGrantRate)
        }
    }

    /// Summe aller Kosten/Materialien/Angebote, die einer Förderung zugeordnet sind.
    func eligibleTotal(for fundingID: UUID) -> Decimal {
        let costTotal = costs.filter { $0.fundingItemID == fundingID }.reduce(Decimal(0)) { $0 + $1.planned }
        let materialTotal = materials.filter { $0.fundingItemID == fundingID }.reduce(Decimal(0)) { total, m in
            total + m.price * Decimal(m.quantity)
        }
        let offerTotal = offers.filter { $0.fundingItemID == fundingID }.reduce(Decimal(0)) { $0 + $1.amount }
        return costTotal + materialTotal + offerTotal
    }

    func eligibleItemCount(for fundingID: UUID) -> Int {
        costs.filter { $0.fundingItemID == fundingID }.count
        + materials.filter { $0.fundingItemID == fundingID }.count
        + offers.filter { $0.fundingItemID == fundingID }.count
    }

    func deleteFunding(_ item: FundingItem) async throws {
        let context = try supabaseContext()
        try await supabase.delete(from: "subsidies", id: item.id, accessToken: context.accessToken)
        funding.removeAll { $0.id == item.id }
    }

    private func kfwFoerdersatzCalc(g: Bool, k: Bool, e: Bool, f: Bool) -> Int {
        var pct = 0
        if g { pct += 30 }
        if k { pct += 16 }
        if e && f  { pct += 40 }
        else if e  { pct += 30 }
        else if f  { pct += 10 }
        return pct
    }

    func updateReview(_ review: ReviewItem, quality: Int, punctuality: Int, communication: Int, pricePerformance: Int, recommended: Bool, notes: String) async throws {
        let context = try supabaseContext()
        try await supabase.update(UpdateSupabaseTradeRating(quality: quality, punctuality: punctuality, communication: communication, pricePerformance: pricePerformance, wouldRecommend: recommended, notes: notes.nilIfEmpty), in: "trade_ratings", id: review.id, accessToken: context.accessToken)
        if let i = reviews.firstIndex(where: { $0.id == review.id }) {
            let stars = Int((Double(quality + punctuality + communication + pricePerformance) / 4.0).rounded())
            reviews[i].stars = stars
            reviews[i].notes = notes
            reviews[i].recommended = recommended
            reviews[i].quality = quality
            reviews[i].punctuality = punctuality
            reviews[i].communication = communication
            reviews[i].pricePerformance = pricePerformance
        }
    }

    func createReview(trade: Trade, quality: Int, punctuality: Int, communication: Int, pricePerformance: Int, recommended: Bool, notes: String) async throws {
        let context = try supabaseContext()
        try await supabase.insert(
            NewSupabaseTradeRating(projectID: context.projectID, tradeID: trade.id, quality: quality, punctuality: punctuality, communication: communication, pricePerformance: pricePerformance, wouldRecommend: recommended, notes: notes.nilIfEmpty),
            into: "trade_ratings",
            accessToken: context.accessToken
        )
        let stars = Int((Double(quality + punctuality + communication + pricePerformance) / 4.0).rounded())
        reviews.append(ReviewItem(company: trade.company.isEmpty ? trade.name : trade.company, trade: trade.name, stars: stars, notes: notes, recommended: recommended))
    }

    // MARK: - Übergabeprotokoll

    var handoverProgress: Int {
        guard !handoverItems.isEmpty else { return 0 }
        let done = handoverItems.filter { $0.status == .akzeptiert }.count
        return Int((Double(done) / Double(handoverItems.count) * 100).rounded())
    }

    func createHandoverItem(item: String, room: String, tradeType: String) async throws {
        let context = try supabaseContext()
        let rows: [SupabaseHandoverRow] = try await supabase.insertReturning(
            NewSupabaseHandover(projectID: context.projectID, item: item, room: room.nilIfEmpty, tradeType: tradeType.nilIfEmpty, status: "offen"),
            into: "handover_items",
            accessToken: context.accessToken
        )
        if let created = rows.first?.appHandoverItem { handoverItems.append(created) }
    }

    func updateHandoverItem(_ handoverItem: HandoverItem, itemText: String, room: String, tradeType: String, notes: String) async throws {
        let context = try supabaseContext()
        try await supabase.update(UpdateSupabaseHandoverItem(item: itemText, room: room.nilIfEmpty, tradeType: tradeType.nilIfEmpty, notes: notes.nilIfEmpty), in: "handover_items", id: handoverItem.id, accessToken: context.accessToken)
        if let i = handoverItems.firstIndex(where: { $0.id == handoverItem.id }) {
            handoverItems[i].item = itemText
            handoverItems[i].room = room
            handoverItems[i].tradeType = tradeType
            handoverItems[i].notes = notes
        }
    }

    func updateHandoverStatus(_ handoverItem: HandoverItem, status: HandoverStatus) async throws {
        let context = try supabaseContext()
        let done = status == .akzeptiert
        try await supabase.update(UpdateSupabaseHandover(status: status.supabaseValue, isDone: done), in: "handover_items", id: handoverItem.id, accessToken: context.accessToken)
        if let index = handoverItems.firstIndex(where: { $0.id == handoverItem.id }) {
            handoverItems[index].status = status
            handoverItems[index].isDone = done
        }
    }

    func updateTimeLog(_ log: TimeLogItem, title: String, category: TimeLogCategory, date: Date, durationMinutes: Int, notes: String) async throws {
        let context = try supabaseContext()
        try await supabase.update(UpdateSupabaseTimeLog(title: title, category: category.supabaseValue, logDate: BaumioDateFormatter.string(from: date), durationMinutes: durationMinutes, description: notes.nilIfEmpty), in: "time_logs", id: log.id, accessToken: context.accessToken)
        if let i = timeLogs.firstIndex(where: { $0.id == log.id }) {
            timeLogs[i].title = title
            timeLogs[i].category = category
            timeLogs[i].date = date
            timeLogs[i].durationMinutes = durationMinutes
            timeLogs[i].notes = notes
        }
    }

    func createTimeLog(title: String, category: TimeLogCategory, date: Date, durationMinutes: Int, notes: String) async throws {
        let context = try supabaseContext()
        let rows: [SupabaseTimeLogRow] = try await supabase.insertReturning(
            NewSupabaseTimeLog(projectID: context.projectID, title: title, category: category.supabaseValue, logDate: BaumioDateFormatter.string(from: date), durationMinutes: durationMinutes, description: notes.nilIfEmpty),
            into: "time_logs",
            accessToken: context.accessToken
        )
        if let created = rows.first?.appTimeLog { timeLogs.append(created) }
    }

    func createDiaryEntry(date: Date, notes: String, weather: String, temperature: Int?, presentTrades: String) async throws {
        let context = try supabaseContext()
        let companies = presentTrades.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let rows: [SupabaseDiaryRow] = try await supabase.insertReturning(NewSupabaseDiaryEntry(projectID: context.projectID, date: BaumioDateFormatter.string(from: date), weather: weather.nilIfEmpty ?? "bewölkt", temperature: temperature, notes: notes, presentTrades: companies), into: "diary_entries", accessToken: context.accessToken)
        if let created = rows.first?.appDiaryEntry { diary.append(created) }
    }

    func updateDefectStatus(_ defect: DefectItem, status: String) async throws {
        let context = try supabaseContext()
        try await supabase.update(UpdateSupabaseStatus(status: status), in: "defects", id: defect.id, accessToken: context.accessToken)
        if let index = defects.firstIndex(where: { $0.id == defect.id }) {
            defects[index].status = status.displayStatus
        }
    }

    func updateMaterialStatus(_ material: MaterialItem, status: String) async throws {
        let context = try supabaseContext()
        try await supabase.update(UpdateSupabaseStatus(status: status), in: "materials", id: material.id, accessToken: context.accessToken)
        if let index = materials.firstIndex(where: { $0.id == material.id }) {
            materials[index].deliveryStatus = status.displayStatus
        }
    }

    func updateCostStatus(_ cost: CostItem, status: String) async throws {
        let context = try supabaseContext()
        try await supabase.update(UpdateSupabaseStatus(status: status), in: "costs", id: cost.id, accessToken: context.accessToken)
        if let index = costs.firstIndex(where: { $0.id == cost.id }) {
            costs[index].status = status.displayStatus
            costs[index].ordered = ["beauftragt", "bezahlt"].contains(status) ? cost.planned : 0
            costs[index].paid = status == "bezahlt" ? cost.planned : 0
        }
    }

    func updateOfferStatus(_ offer: OfferItem, status: String) async throws {
        let context = try supabaseContext()
        try await supabase.update(UpdateSupabaseQuoteSelection(isSelected: status == "Angenommen", quoteStatus: status), in: "quotes", id: offer.id, accessToken: context.accessToken)
        if let index = offers.firstIndex(where: { $0.id == offer.id }) {
            offers[index].status = status
        }
    }

    func toggleTask(_ task: TaskItem) async throws {
        let context = try supabaseContext()
        let newValue = !task.isDone
        try await supabase.update(UpdateSupabaseTodoDone(done: newValue), in: "project_todos", id: task.id, accessToken: context.accessToken)
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isDone = newValue
        }
    }

    func updateTrade(_ trade: Trade, name: String, company: String, tradeType: String = "", address: String = "", phone: String = "", email: String = "", budget: Decimal = 0, notes: String) async throws {
        let context = try supabaseContext()
        let encodedNotes = TradeContactCoder.encode(address: address, phone: phone, email: email, userNotes: notes)
        try await supabase.update(UpdateSupabaseTrade(name: name, company: company.nilIfEmpty, tradeType: tradeType.nilIfEmpty, budget: budget > 0 ? budget : nil, notes: encodedNotes), in: "trades", id: trade.id, accessToken: context.accessToken)
        if let i = trades.firstIndex(where: { $0.id == trade.id }) {
            trades[i].name = name
            trades[i].company = company
            trades[i].tradeType = tradeType
            trades[i].address = address
            trades[i].phone = phone
            trades[i].email = email
            trades[i].budget = budget
            trades[i].notes = notes
        }
    }

    func scanVisitenkarte(imageData: Data, mimeType: String) async throws -> VisitenkarteScanResult {
        let context = try supabaseContext()
        return try await supabase.scanVisitenkarte(imageData: imageData, mimeType: mimeType, accessToken: context.accessToken)
    }

    func updateAppointment(_ item: ScheduleItem, title: String, date: Date, notes: String, startTime: Date? = nil, endTime: Date? = nil, status: String, dependsOn: UUID? = nil) async throws {
        let context = try supabaseContext()
        let encodedNotes = AppointmentTimeCoder.encode(startTime: startTime, endTime: endTime, userNotes: notes)
        try await supabase.update(UpdateSupabaseAppointment(title: title, date: BaumioDateFormatter.string(from: date), notes: encodedNotes, status: status), in: "appointments", id: item.id, accessToken: context.accessToken)
        if let i = schedule.firstIndex(where: { $0.id == item.id }) {
            schedule[i].title = title
            schedule[i].date = date
            schedule[i].notes = notes
            schedule[i].startTime = startTime
            schedule[i].endTime = endTime
            schedule[i].status = WorkStatus(appointmentValue: status)
            schedule[i].dependsOn = dependsOn
        }
    }

    func updateTask(_ task: TaskItem, title: String, priority: String, dueDate: Date?) async throws {
        let context = try supabaseContext()
        try await supabase.update(UpdateSupabaseTodo(title: title, priority: priority, dueDate: dueDate.map(BaumioDateFormatter.string(from:))), in: "project_todos", id: task.id, accessToken: context.accessToken)
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i].title = title
            tasks[i].priority = Priority(todoValue: priority)
            if let dueDate { tasks[i].dueDate = dueDate }
        }
    }

    func updateMaterial(_ material: MaterialItem, name: String, quantity: Decimal, unit: String, supplier: String, articleNumber: String, price: Decimal, status: String, notes: String, fundingItemID: UUID? = nil) async throws {
        let context = try supabaseContext()
        let encodedNotes = FundingLinkCoder.encode(fundingID: fundingItemID, userNotes: notes)
        try await supabase.update(
            UpdateSupabaseMaterial(
                name: name,
                quantity: quantity,
                unit: unit.isEmpty ? "Stück" : unit,
                supplier: supplier.nilIfEmpty,
                articleNumber: articleNumber.nilIfEmpty,
                priceEstimated: price,
                status: status,
                notes: encodedNotes
            ),
            in: "materials",
            id: material.id,
            accessToken: context.accessToken
        )
        if let i = materials.firstIndex(where: { $0.id == material.id }) {
            materials[i].name = name
            materials[i].quantity = NSDecimalNumber(decimal: quantity).doubleValue
            materials[i].unit = unit.isEmpty ? "Stück" : unit
            materials[i].supplier = supplier
            materials[i].articleNumber = articleNumber
            materials[i].price = price
            materials[i].deliveryStatus = status.displayStatus
            materials[i].notes = notes
            materials[i].fundingItemID = fundingItemID
        }
    }

    func updateCost(
        _ cost: CostItem, title: String, amount: Decimal, category: String, status: String,
        invoiceReference: String = "", notes: String, fundingItemID: UUID? = nil,
        invoiceDate: Date? = nil, dueDate: Date? = nil,
        laborAmount: Decimal = 0, machineAmount: Decimal = 0, travelAmount: Decimal = 0,
        warrantyEnd: Date? = nil, paymentDate: Date? = nil, supplier: String = ""
    ) async throws {
        let context = try supabaseContext()
        let encodedNotes = FundingLinkCoder.encode(fundingID: fundingItemID, userNotes: notes)
        try await supabase.update(
            UpdateSupabaseCost(
                description: title, category: category, amount: amount, status: status,
                invoiceNumber: invoiceReference.nilIfEmpty, notes: encodedNotes,
                invoiceDate: invoiceDate.map(BaumioDateFormatter.string(from:)),
                dueDate: dueDate.map(BaumioDateFormatter.string(from:)),
                laborAmount: laborAmount > 0 ? laborAmount : nil,
                machineAmount: machineAmount > 0 ? machineAmount : nil,
                travelAmount: travelAmount > 0 ? travelAmount : nil,
                warrantyEnd: warrantyEnd.map(BaumioDateFormatter.string(from:)),
                paymentDate: paymentDate.map(BaumioDateFormatter.string(from:)),
                supplier: supplier.nilIfEmpty
            ),
            in: "costs", id: cost.id, accessToken: context.accessToken
        )
        if let i = costs.firstIndex(where: { $0.id == cost.id }) {
            costs[i].title = title
            costs[i].planned = amount
            costs[i].category = category.displayStatus
            costs[i].status = status.displayStatus
            costs[i].ordered = ["beauftragt", "bezahlt"].contains(status) ? amount : 0
            costs[i].paid = status == "bezahlt" ? amount : 0
            costs[i].invoiceReference = invoiceReference
            costs[i].notes = notes
            costs[i].fundingItemID = fundingItemID
            costs[i].invoiceDate = invoiceDate
            costs[i].dueDate = dueDate
            costs[i].laborAmount = laborAmount
            costs[i].machineAmount = machineAmount
            costs[i].travelAmount = travelAmount
            costs[i].warrantyEnd = warrantyEnd
            costs[i].paymentDate = paymentDate
            costs[i].supplier = supplier
        }
    }

    func updateOffer(_ offer: OfferItem, title: String, company: String, amount: Decimal, validUntil: Date?, notes: String, fundingItemID: UUID? = nil, scope: String = "") async throws {
        let context = try supabaseContext()
        let encodedNotes = FundingLinkCoder.encode(fundingID: fundingItemID, userNotes: notes)
        try await supabase.update(UpdateSupabaseQuote(title: title, company: company.nilIfEmpty, amount: amount, validUntil: validUntil.map(BaumioDateFormatter.string(from:)), notes: encodedNotes, scope: scope.nilIfEmpty), in: "quotes", id: offer.id, accessToken: context.accessToken)
        if let i = offers.firstIndex(where: { $0.id == offer.id }) {
            offers[i].title = title
            offers[i].provider = company.isEmpty ? title : company
            offers[i].amount = amount
            offers[i].validUntil = validUntil
            offers[i].notes = notes
            offers[i].fundingItemID = fundingItemID
            offers[i].scope = scope
        }
    }

    func acceptOfferAndCreateCost(_ offer: OfferItem) async throws {
        try await updateOfferStatus(offer, status: "Angenommen")
        if !offer.scope.isEmpty {
            for other in offers where other.id != offer.id && other.scope == offer.scope {
                try await updateOfferStatus(other, status: "Abgelehnt")
            }
        }
        try await createCost(
            title: offer.title.isEmpty ? offer.provider : offer.title,
            amount: offer.amount,
            category: "sonstiges",
            status: "beauftragt",
            notes: "Angenommenes Angebot von \(offer.provider)"
        )
    }

    // MARK: - KI-Dokumentenscan

    func scanRechnung(imageData: Data, mimeType: String) async throws -> RechnungScanResult {
        let context = try supabaseContext()
        let jws = await store.currentTransactionJWS()
        return try await supabase.scanRechnung(imageData: imageData, mimeType: mimeType, accessToken: context.accessToken, transactionJWS: jws)
    }

    func scanAngebot(imageData: Data, mimeType: String) async throws -> AngebotScanResult {
        let context = try supabaseContext()
        let jws = await store.currentTransactionJWS()
        return try await supabase.scanAngebot(imageData: imageData, mimeType: mimeType, accessToken: context.accessToken, transactionJWS: jws)
    }

    func updateDefect(_ defect: DefectItem, description: String, trade: String = "", responsible: String = "", deadline: Date = Date(), severity: String, importance: String, status: String) async throws {
        let context = try supabaseContext()
        let encoded = DefectMetaCoder.encode(trade: trade, responsible: responsible, deadline: deadline, userNotes: description)
        try await supabase.update(UpdateSupabaseDefect(description: encoded, severity: severity, importance: importance, status: status), in: "defects", id: defect.id, accessToken: context.accessToken)
        if let i = defects.firstIndex(where: { $0.id == defect.id }) {
            let rawTitle = description.split(separator: "\n", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            defects[i].title = rawTitle.isEmpty ? "Mangel" : (rawTitle.count > 60 ? String(rawTitle.prefix(60)) + "…" : rawTitle)
            defects[i].description = description
            defects[i].trade = trade
            defects[i].responsible = responsible
            defects[i].deadline = deadline
            defects[i].severity = severity
            defects[i].importance = importance
            defects[i].status = status.displayStatus
            defects[i].priority = Priority(defectSeverity: severity)
        }
    }

    func updateDiaryEntry(_ entry: DiaryEntry, date: Date, notes: String, weather: String, temperature: Int?, presentTrades: String) async throws {
        let context = try supabaseContext()
        let companies = presentTrades.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        try await supabase.update(UpdateSupabaseDiary(date: BaumioDateFormatter.string(from: date), weather: weather.nilIfEmpty ?? "bewölkt", temperature: temperature, notes: notes, presentTrades: companies), in: "diary_entries", id: entry.id, accessToken: context.accessToken)
        if let i = diary.firstIndex(where: { $0.id == entry.id }) {
            diary[i].date = date
            diary[i].notes = notes
            diary[i].completedWork = notes
            diary[i].weather = (weather.nilIfEmpty ?? "bewölkt").displayStatus
            diary[i].companies = companies
        }
    }

    private func supabaseContext() throws -> (accessToken: String, projectID: UUID) {
        guard let accessToken = supabaseSession?.accessToken else { throw SupabaseError.missingSession }
        guard let projectID = selectedProject?.id else { throw SupabaseError.missingProject }
        return (accessToken, projectID)
    }

    private func reloadSelectedProjectDetails() async throws {
        guard let selectedProject else { throw SupabaseError.missingProject }
        try await loadDetails(for: selectedProject)
    }

    func resetPassword() {
        authError = nil
        authInfo = nil

        guard email.contains("@") else {
            authError = "Bitte gib zuerst deine E-Mail-Adresse ein."
            return
        }

        Task {
            guard supabase.isConfigured else {
                authInfo = "Passwort-Zurücksetzen ist vorbereitet. Für echte E-Mails muss Supabase konfiguriert sein."
                return
            }

            do {
                try await supabase.resetPassword(email: email)
                authInfo = "Wenn ein Konto existiert, wurde eine E-Mail zum Zurücksetzen gesendet."
            } catch {
                authError = error.localizedDescription
            }
        }
    }

    func choosePlan(_ plan: PricingPlan) {
        if plan.isHighlighted {
            // Pro-Plan: Kauf ausschließlich über StoreKit 2 / Apple In-App-Kauf.
            Task { await purchasePro() }
        } else {
            selectedSection = .dashboard
        }
    }

    private func clearLocalData() {
        projects = []
        clearProjectScopedData()
        selectedProject = nil
    }

    private func clearProjectScopedData() {
        trades = []
        schedule = []
        diary = []
        tasks = []
        materials = []
        documents = []
        costs = []
        offers = []
        defects = []
        funding = []
        reviews = []
        timeLogs = []
        handoverItems = []
        defectPhotos = [:]
        diaryPhotos = [:]
    }

    // MARK: - Profil

    func updateDisplayName(_ name: String) {
        displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var profileEmail: String {
        supabaseSession?.user?.email ?? (email.isEmpty ? "–" : email)
    }

    // MARK: - DSGVO-Export

    func exportDSGVOData() -> URL? {
        var lines: [String] = [
            "Baumio – DSGVO-Datenexport",
            "Erstellt: \(Date().formatted())",
            "E-Mail: \(profileEmail)",
            "Anzeigename: \(displayName.isEmpty ? "–" : displayName)",
            ""
        ]
        lines.append("PROJEKTE (\(projects.count))")
        for p in projects {
            lines.append("  • \(p.name) | \(p.address) | Budget: \(p.budget)€ | Status: \(p.status.rawValue)")
        }
        lines.append("")
        lines.append("GEWERKE (\(trades.count))")
        for t in trades {
            lines.append("  • \(t.name) | \(t.company) | Kosten: \(t.costs)€ | Budget: \(t.budget)€")
        }
        lines.append("")
        lines.append("TERMINE (\(schedule.count))")
        for s in schedule {
            lines.append("  • \(s.title) | \(s.date.formatted(date: .abbreviated, time: .omitted)) | \(s.durationDays) Tg | \(s.status.rawValue)")
        }
        lines.append("")
        lines.append("AUFGABEN (\(tasks.count))")
        for t in tasks {
            lines.append("  • [\(t.isDone ? "x" : " ")] \(t.title) | Prio: \(t.priority.rawValue) | Fällig: \(t.dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        lines.append("")
        lines.append("KOSTEN (\(costs.count))")
        for c in costs {
            lines.append("  • \(c.title) | Geplant: \(c.planned)€ | Bezahlt: \(c.paid)€ | Kat: \(c.category)")
        }
        lines.append("")
        lines.append("MATERIALLISTE (\(materials.count))")
        for m in materials {
            lines.append("  • \(m.name) | \(m.quantity) \(m.unit) | \(m.price)€ | \(m.deliveryStatus)")
        }
        lines.append("")
        lines.append("MÄNGEL (\(defects.count))")
        for d in defects {
            lines.append("  • \(d.title) | \(d.status) | Prio: \(d.priority.rawValue) | Frist: \(d.deadline.formatted(date: .abbreviated, time: .omitted))")
        }
        lines.append("")
        lines.append("BAUTAGEBUCH (\(diary.count) Einträge)")
        for d in diary {
            lines.append("  • \(d.date.formatted(date: .abbreviated, time: .omitted)) | \(d.weather) | \(d.completedWork)")
        }
        lines.append("")
        lines.append("DOKUMENTE (\(documents.count))")
        for d in documents {
            lines.append("  • \(d.title) | \(d.category.rawValue) | \(d.uploadDate.formatted(date: .abbreviated, time: .omitted))")
        }
        lines.append("")
        lines.append("ZEITERFASSUNG (\(timeLogs.count) Einträge)")
        for t in timeLogs {
            lines.append("  • \(t.date.formatted(date: .abbreviated, time: .omitted)) | \(t.category.rawValue) | \(t.durationMinutes) min | \(t.title)")
        }
        lines.append("")
        lines.append("ÜBERGABE & ABNAHME (\(handoverItems.count) Punkte)")
        for h in handoverItems {
            lines.append("  • [\(h.isDone ? "x" : " ")] \(h.item) | \(h.room) | \(h.status.rawValue)")
        }
        lines.append("")
        lines.append("FÖRDERUNGEN (\(funding.count))")
        for f in funding {
            lines.append("  • \(f.name) | \(f.provider) | \(f.estimatedRefund.euroString) | \(f.status)")
        }
        lines.append("")
        lines.append("ANGEBOTE (\(offers.count))")
        for o in offers {
            lines.append("  • \(o.title) | \(o.provider) | \(o.amount.euroString) | \(o.status)")
        }
        lines.append("")
        lines.append("BEWERTUNGEN (\(reviews.count))")
        for r in reviews {
            lines.append("  • \(r.company) (\(r.trade)) | \(r.stars)/5 Sterne | \(r.recommended ? "Empfohlen" : "Nicht empfohlen")")
        }
        lines.append("")
        lines.append("Alle Daten werden ausschließlich auf deinem Supabase-Account gespeichert und nicht an Dritte weitergegeben.")
        let text = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Baumio-DSGVO-Export.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - App-Bewertung

    func requestAppReview() {
        triggerReviewRequest = true
    }

    // MARK: - Lokale Benachrichtigungen

    func scheduleLocalNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted {
                Task { @MainActor in self.notificationPermissionDenied = true }
                return
            }
            Task { @MainActor in await self.reScheduleNotifications() }
        }
    }

    private func reScheduleNotifications() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        let cal = Calendar.current
        let now = Date()

        for defect in defects where defect.status != "Behoben" {
            guard defect.deadline > now else { continue }
            let notifyAt = cal.date(byAdding: .day, value: -1, to: defect.deadline) ?? defect.deadline
            guard notifyAt > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Mangel-Frist morgen"
            content.body = "\"\(defect.title)\" – Frist: \(defect.deadline.formatted(date: .abbreviated, time: .omitted))"
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: notifyAt)
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "defect-\(defect.id)", content: content,
                                      trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            )
        }

        for item in schedule where item.status != .done {
            guard item.date > now else { continue }
            let notifyAt = cal.date(byAdding: .day, value: -1, to: item.date) ?? item.date
            guard notifyAt > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Termin morgen"
            content.body = "\(item.title) – \(item.date.formatted(date: .abbreviated, time: .omitted))"
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: notifyAt)
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "schedule-\(item.id)", content: content,
                                      trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            )
        }

        for task in tasks where !task.isDone {
            guard task.dueDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Aufgabe fällig"
            content.body = "\(task.title) – Fällig: \(task.dueDate.formatted(date: .abbreviated, time: .omitted))"
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day], from: task.dueDate)
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "task-\(task.id)", content: content,
                                      trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            )
        }

        for item in funding where item.status != "Ausgezahlt" {
            let deadline = item.documentDeadline ?? item.deadline
            guard let deadline, deadline > now else { continue }
            let notifyAt = cal.date(byAdding: .day, value: -7, to: deadline) ?? deadline
            guard notifyAt > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Förderung – Dokumente einreichen"
            content.body = "\"\(item.name)\" – Frist: \(deadline.formatted(date: .abbreviated, time: .omitted))"
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: notifyAt)
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "funding-\(item.id)", content: content,
                                      trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            )
        }

        for offer in offers where offer.status != "Angenommen" {
            guard let expiry = offer.validUntil, expiry > now else { continue }
            let notifyAt = cal.date(byAdding: .day, value: -3, to: expiry) ?? expiry
            guard notifyAt > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Angebot läuft ab"
            content.body = "\"\(offer.title)\" – Gültig bis: \(expiry.formatted(date: .abbreviated, time: .omitted))"
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: notifyAt)
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "offer-\(offer.id)", content: content,
                                      trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
