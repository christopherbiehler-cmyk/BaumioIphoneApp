import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = BaumioAppViewModel()
    @AppStorage("hasSeenAppTour") private var hasSeenAppTour = false
    @AppStorage("projectWizardShown") private var projectWizardShown = false
    @State private var showingTour = false
    @State private var showingWizard = false

    var body: some View {
        Group {
            if !model.hasCompletedOnboarding {
                OnboardingView(model: model)
            } else if !model.isAuthenticated {
                AuthView(model: model)
            } else if horizontalSizeClass == .regular {
                iPadRootView(model: model)
                    .fullScreenCover(isPresented: $showingTour, onDismiss: triggerWizardIfNeeded) {
                        AppTourView(isPresented: $showingTour)
                    }
                    .sheet(isPresented: $showingWizard) {
                        ProjectSetupWizardView(model: model, isPresented: $showingWizard)
                    }
            } else {
                iPhoneRootView(model: model)
                    .fullScreenCover(isPresented: $showingTour, onDismiss: triggerWizardIfNeeded) {
                        AppTourView(isPresented: $showingTour)
                    }
                    .sheet(isPresented: $showingWizard) {
                        ProjectSetupWizardView(model: model, isPresented: $showingWizard)
                    }
            }
        }
        .tint(BaumioTheme.accent)
        .preferredColorScheme(.dark)
        .alert("Aktion fehlgeschlagen", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
        .task {
            await model.restoreSession()
        }
        .onChange(of: model.isAuthenticated) { _, isAuth in
            guard isAuth else { return }
            if !hasSeenAppTour {
                showingTour = true
            } else if model.projects.isEmpty && !projectWizardShown {
                projectWizardShown = true
                showingWizard = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Bei Rückkehr in den Vordergrund Pro-Status neu laden,
            // damit z. B. im Backend manuell vergebenes Pro schnell erscheint.
            guard newPhase == .active, model.isAuthenticated else { return }
            Task { await model.refreshProStatus() }
        }
    }

    private func triggerWizardIfNeeded() {
        guard model.projects.isEmpty && !projectWizardShown else { return }
        projectWizardShown = true
        showingWizard = true
    }
}

private struct iPhoneRootView: View {
    @Bindable var model: BaumioAppViewModel
    @AppStorage("customTabSections") private var tabString = "Dashboard,Projekte,Termine,Dokumente"

    private var pinnedSections: [BaumioSection] {
        let parsed = tabString.split(separator: ",").compactMap { BaumioSection(rawValue: String($0)) }
        return parsed.isEmpty ? [.dashboard, .projects, .schedule, .documents] : parsed
    }

    var body: some View {
        TabView(selection: $model.selectedSection) {
            ForEach(pinnedSections) { section in
                NavigationStack {
                    sectionView(section, model: model)
                }
                .tabItem { Label(section.rawValue, systemImage: section.systemImage) }
                .tag(section)
            }

            NavigationStack {
                MoreView(model: model, pinnedSections: pinnedSections)
            }
            .tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
            .tag(BaumioSection.settings)
        }
        .baumioBackground()
    }
}

private struct iPadRootView: View {
    @Bindable var model: BaumioAppViewModel

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    sidebarRow(.dashboard)
                    sidebarRow(.projects)
                } header: {
                    BrandHeader(compact: true)
                        .padding(.vertical, 12)
                }

                Section("Planung") {
                    sidebarRow(.schedule)
                    sidebarRow(.diary)
                    sidebarRow(.tasks)
                    sidebarRow(.materials)
                    sidebarRow(.timeTracking)
                    sidebarRow(.handover)
                    sidebarRow(.documents)
                }

                Section("Kosten & Verträge") {
                    sidebarRow(.costs)
                    sidebarRow(.offers)
                    sidebarRow(.funding)
                    sidebarRow(.taxes)
                }

                Section("Firmen & Qualität") {
                    sidebarRow(.trades)
                    sidebarRow(.defects)
                    sidebarRow(.reviews)
                }

                Section("App") {
                    sidebarRow(.pricing)
                    sidebarRow(.settings)
                }
            }
            .navigationTitle("Baumio")
            .scrollContentBackground(.hidden)
            .background(BaumioTheme.surface)
        } detail: {
            NavigationStack {
                sectionView(model.selectedSection, model: model)
            }
        }
        .baumioBackground()
    }

    @ViewBuilder
    private func sidebarRow(_ section: BaumioSection) -> some View {
        Button {
            model.selectedSection = section
        } label: {
            HStack {
                Label(section.rawValue, systemImage: section.systemImage)
                    .foregroundStyle(section == model.selectedSection ? BaumioTheme.accent : BaumioTheme.primaryText)
                Spacer()
                if section.requiresPro && !model.isPro {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(BaumioTheme.secondaryText)
                        .accessibilityLabel("Pro erforderlich")
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(section == model.selectedSection ? .isSelected : [])
    }
}

private struct MoreView: View {
    @Bindable var model: BaumioAppViewModel
    var pinnedSections: [BaumioSection] = []

    private static let allSectionsOrdered: [BaumioSection] = [
        .dashboard, .projects, .trades, .schedule, .diary, .tasks,
        .materials, .timeTracking, .handover, .documents, .costs,
        .offers, .defects, .funding, .taxes, .reviews, .pricing, .settings
    ]

    private var sections: [BaumioSection] {
        Self.allSectionsOrdered.filter { !pinnedSections.contains($0) }
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                NavigationLink {
                    sectionView(section, model: model)
                } label: {
                    HStack {
                        Label(section.rawValue, systemImage: section.systemImage)
                        Spacer()
                        if section.requiresPro && !model.isPro {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(BaumioTheme.secondaryText)
                                .accessibilityLabel("Pro erforderlich")
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .navigationTitle("Mehr")
        .scrollContentBackground(.hidden)
        .background(BaumioTheme.background)
    }
}

@ViewBuilder
private func sectionView(_ section: BaumioSection, model: BaumioAppViewModel) -> some View {
    if section.requiresPro && !model.isPro {
        PaywallView(model: model, lockedSection: section)
    } else {
        unlockedSectionView(section, model: model)
    }
}

@ViewBuilder
private func unlockedSectionView(_ section: BaumioSection, model: BaumioAppViewModel) -> some View {
    switch section {
    case .dashboard:
        DashboardView(model: model)
    case .projects:
        ProjectsView(model: model)
    case .trades:
        TradesView(model: model)
    case .schedule:
        ScheduleView(model: model)
    case .diary:
        DiaryView(model: model)
    case .tasks:
        TasksView(model: model)
    case .materials:
        MaterialsView(model: model)
    case .timeTracking:
        TimeLogsView(model: model)
    case .handover:
        HandoverView(model: model)
    case .documents:
        DocumentsView(model: model)
    case .costs:
        CostsView(model: model)
    case .offers:
        OffersView(model: model)
    case .defects:
        DefectsView(model: model)
    case .funding:
        FundingView(model: model)
    case .taxes:
        TaxesView(model: model)
    case .reviews:
        ReviewsView(model: model)
    case .pricing:
        PricingView(model: model)
    case .settings:
        SettingsView(model: model)
    }
}

#Preview("iPhone") {
    ContentView()
}
