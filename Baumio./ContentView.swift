import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = BaumioAppViewModel()
    @AppStorage("hasSeenAppTour") private var hasSeenAppTour = false
    @State private var showingTour = false

    var body: some View {
        Group {
            if !model.hasCompletedOnboarding {
                OnboardingView(model: model)
            } else if !model.isAuthenticated {
                AuthView(model: model)
            } else if horizontalSizeClass == .regular {
                iPadRootView(model: model)
                    .fullScreenCover(isPresented: $showingTour) {
                        AppTourView(isPresented: $showingTour)
                    }
            } else {
                iPhoneRootView(model: model)
                    .fullScreenCover(isPresented: $showingTour) {
                        AppTourView(isPresented: $showingTour)
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
            if isAuth && !hasSeenAppTour {
                showingTour = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Bei Rückkehr in den Vordergrund Pro-Status neu laden,
            // damit z. B. im Backend manuell vergebenes Pro schnell erscheint.
            guard newPhase == .active, model.isAuthenticated else { return }
            Task { await model.refreshProStatus() }
        }
    }
}

private struct iPhoneRootView: View {
    @Bindable var model: BaumioAppViewModel

    var body: some View {
        TabView(selection: $model.selectedSection) {
            NavigationStack {
                DashboardView(model: model)
            }
            .tabItem { Label("Dashboard", systemImage: BaumioSection.dashboard.systemImage) }
            .tag(BaumioSection.dashboard)

            NavigationStack {
                ProjectsView(model: model)
            }
            .tabItem { Label("Projekte", systemImage: BaumioSection.projects.systemImage) }
            .tag(BaumioSection.projects)

            NavigationStack {
                ScheduleView(model: model)
            }
            .tabItem { Label("Termine", systemImage: BaumioSection.schedule.systemImage) }
            .tag(BaumioSection.schedule)

            NavigationStack {
                DocumentsView(model: model)
            }
            .tabItem { Label("Dokumente", systemImage: BaumioSection.documents.systemImage) }
            .tag(BaumioSection.documents)

            NavigationStack {
                MoreView(model: model)
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

    private let sections: [BaumioSection] = [
        .trades,
        .diary,
        .tasks,
        .materials,
        .timeTracking,
        .handover,
        .costs,
        .offers,
        .defects,
        .funding,
        .taxes,
        .reviews,
        .pricing,
        .settings
    ]

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
