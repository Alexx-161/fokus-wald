import SwiftUI

@main
struct FokusWaldApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// iPhone: tab bar. iPad (wide): timer on the left, tabs on the right – like the Mac app's large window.
struct RootView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var prefs = AppModel.shared.prefs
    @ObservedObject private var garden = AppModel.shared.garden
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    private var shownIsland: Int { min(model.island ?? garden.currentIsland, garden.currentIsland) }

    var body: some View {
        Group {
            if sizeClass == .regular {
                wide
            } else {
                TabView(selection: $model.tab) {
                    ForEach(AppModel.Tab.allCases) { tab in
                        page(tab)
                            .tabItem { Label(tab.title, systemImage: tab.symbol) }
                            .tag(tab)
                    }
                }
                .tint(Palette.stem)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .fontDesign(.rounded)
        .id(prefs.themeID)
        .fullScreenCover(isPresented: $model.showOnboarding) {
            OnboardingView(prefs: prefs, timer: model.timer, garden: garden) { model.finishOnboarding() }
                .foregroundStyle(Theme.ink)
                .fontDesign(.rounded)
                .id(prefs.themeID)
        }
        .onChange(of: scenePhase) { _, phase in model.sceneBecameActive(phase == .active) }
        .onAppear { model.sceneBecameActive(true) }
    }

    @ViewBuilder
    private func page(_ tab: AppModel.Tab) -> some View {
        switch tab {
        case .timer:
            ScrollView { TimerScreen() }
                .scrollIndicators(.hidden)
                .background(Theme.bg)
        case .island:
            IslandView(garden: garden, timer: model.timer, island: shownIsland) { model.island = $0 }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.bg)
        case .catalog:
            titled("Pflanzen") { CatalogView(garden: garden) }
        case .stats:
            titled("Statistik") { StatsView(garden: garden) }
        case .archipelago:
            titled("Archipel") {
                ArchipelagoView(garden: garden) { index in
                    model.island = index
                    model.tab = .island
                }
            }
        }
    }

    private func titled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
            content()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(Theme.bg)
    }

    private var wide: some View {
        HStack(spacing: 0) {
            ScrollView { TimerScreen() }
                .scrollIndicators(.hidden)
                .frame(width: 360)
            Divider().opacity(0.4)
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        wideTabs(showTitles: true)
                        wideTabs(showTitles: false)
                    }
                    Spacer(minLength: 0)
                }
                page(wideTab).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(18)
        }
    }

    private func wideTabs(showTitles: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(AppModel.Tab.allCases.filter { $0 != .timer }) { tab in
                let selected = wideTab == tab
                Button { model.tab = tab } label: {
                    Group {
                        if showTitles {
                            Label(tab.title, systemImage: tab.symbol).lineLimit(1).fixedSize()
                        } else {
                            Image(systemName: tab.symbol)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(selected ? .white : Theme.ink)
                    .background(Capsule().fill(selected ? Palette.stem : Theme.track))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
    }

    private var wideTab: AppModel.Tab { model.tab == .timer ? .island : model.tab }
}
