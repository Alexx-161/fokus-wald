import AppKit
import SwiftUI

/// Small window: just the timer. Wide window or full screen: timer on the left, island and tabs on the right.
struct MainView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var ui = AppState.shared.ui
    @ObservedObject private var garden = AppState.shared.garden
    @ObservedObject private var prefs = AppState.shared.prefs
    private let timer = AppState.shared.timer

    var body: some View {
        GeometryReader { geo in
            if ui.showOnboarding {
                OnboardingView(prefs: prefs, timer: timer, garden: garden) {
                    withAnimation(.easeInOut(duration: 0.35)) { AppState.shared.finishOnboarding() }
                }
                .transition(.opacity)
            } else if geo.size.width >= 700 {
                expanded.id(prefs.themeID)
            } else {
                ScrollView(.vertical) {
                    TimerView(expanded: false).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .id(prefs.themeID)
            }
        }
        .frame(minWidth: 300, minHeight: 560)
        .background(Theme.bg)
        .foregroundStyle(Theme.ink)
        .fontDesign(.rounded)
        .background(WindowAccessor { AppState.shared.attach(window: $0) })
        .onAppear { AppState.shared.openMainWindow = { openWindow(id: "timer") } }
    }

    private func tabBar(showTitles: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(UIState.Tab.allCases) { tab in
                Button { ui.tab = tab } label: {
                    Group {
                        if showTitles {
                            Label(tab.title, systemImage: tab.symbol).lineLimit(1).fixedSize()
                        } else {
                            Image(systemName: tab.symbol)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(ui.tab == tab ? .white : Theme.ink)
                    .background(Capsule().fill(ui.tab == tab ? Palette.stem : Theme.track))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }

    private var expanded: some View {
        HStack(spacing: 0) {
            ScrollView(.vertical) {
                TimerView(expanded: true)
            }
            .scrollIndicators(.hidden)
            .frame(width: 330)

            Divider().opacity(0.4)

            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        tabBar(showTitles: true)
                        tabBar(showTitles: false)
                    }
                    Spacer(minLength: 0)
                    Button { AppState.shared.collapse() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                        .buttonStyle(RoundIconButtonStyle(size: 28))
                        .help("Kleines Timer-Fenster")
                }

                Group {
                    switch ui.tab {
                    case .island:
                        IslandView(garden: garden, timer: timer, island: min(ui.island ?? garden.currentIsland, garden.currentIsland)) {
                            ui.island = $0
                        }
                    case .catalog:
                        CatalogView(garden: garden)
                    case .stats:
                        StatsView(garden: garden)
                    case .archipelago:
                        ArchipelagoView(garden: garden) { index in
                            ui.island = index
                            ui.tab = .island
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.top, 10)
        }
    }
}

struct TimerView: View {
    let expanded: Bool

    @ObservedObject private var timer = AppState.shared.timer
    @ObservedObject private var garden = AppState.shared.garden
    @ObservedObject private var prefs = AppState.shared.prefs
    @State private var showSettings = false
    @State private var showPicker = false
    @State private var confirmGiveUp = false

    private var species: PlantSpecies { timer.species }

    var body: some View {
        VStack(spacing: 14) {
            header

            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                VStack(spacing: 8) {
                    stage(at: timeline.date)
                    clock(at: timeline.date)
                }
            }

            VStack(spacing: 4) {
                Text(statusText)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                if let unlocked = newlyUnlocked {
                    Label("Neu freigeschaltet: \(unlocked.name)", systemImage: "lock.open.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(unlocked.deep)
                }
            }

            if timer.phase == .idle {
                speciesChip
                presets
            }
            controls

            if showSettings {
                SettingsPanel(prefs: prefs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !expanded {
                Divider().opacity(0.5)
                footer
            }
        }
        .padding(18)
        .frame(width: 300)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: timer.phase)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSettings)
        .onChange(of: showSettings) { _, open in prefs.previewing = open }
        .onDisappear { prefs.previewing = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill").foregroundStyle(species.deep)
            Text("Fokus-Wald").font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer()
            Button { prefs.pinned.toggle() } label: {
                Image(systemName: prefs.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(RoundIconButtonStyle(size: 26, active: prefs.pinned ? species.deep : nil))
            .help(prefs.pinned ? "Mini-Timer ausblenden" : "Mini-Timer anheften – schwebt über allem, auch über Vollbild-Apps")
            Button { showSettings.toggle() } label: {
                Image(systemName: showSettings ? "xmark" : "slider.horizontal.3")
            }
            .buttonStyle(RoundIconButtonStyle(size: 26))
            .help("Einstellungen")
        }
    }

    private func stage(at date: Date) -> some View {
        let p = timer.progress(at: date)
        let size: CGFloat = expanded ? 220 : 190
        return ZStack {
            Circle().fill(Theme.card).shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            Circle().inset(by: 7).stroke(Theme.track, lineWidth: 6)
            Circle().inset(by: 7).trim(from: 0, to: p)
                .stroke(species.deep, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Canvas { ctx, canvasSize in
                PlantPainter.draw(ctx, species: species, base: CGPoint(x: canvasSize.width / 2, y: canvasSize.height * 0.84),
                                  unit: canvasSize.width, progress: p, seed: timer.seed,
                                  time: date.timeIntervalSinceReferenceDate)
            }
            .padding(size * 0.14)
            if timer.phase == .finished {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.star)
                    .symbolEffect(.pulse)
                    .offset(x: size * 0.33, y: -size * 0.33)
            }
        }
        .frame(width: size, height: size)
    }

    private func clock(at date: Date) -> some View {
        HStack(spacing: 14) {
            if timer.phase == .idle {
                Button { timer.adjustMinutes(up: false) } label: { Image(systemName: "minus") }
                    .buttonStyle(RoundIconButtonStyle(size: 28))
            }
            Text(TimeFormat.clock(timer.remaining(at: date)))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .opacity(timer.phase == .paused ? 0.5 : 1)
            if timer.phase == .idle {
                Button { timer.adjustMinutes(up: true) } label: { Image(systemName: "plus") }
                    .buttonStyle(RoundIconButtonStyle(size: 28))
            }
        }
    }

    private var statusText: String {
        switch timer.phase {
        case .idle:
            return "Als Nächstes wächst: \(species.name)"
        case .running:
            return "\(species.name) wächst …"
        case .paused:
            return "Pausiert – deine Pflanze wartet auf dich"
        case .finished:
            if let last = garden.plants.last, garden.plants(on: last.island).count == Garden.islandCapacity {
                return "\(Garden.islandName(last.island)) ist vollendet! Eine neue Insel taucht auf."
            }
            return "\(species.name) steht jetzt auf deiner Insel!"
        }
    }

    /// A species whose unlock threshold was reached by the session that just finished.
    private var newlyUnlocked: PlantSpecies? {
        guard timer.phase == .finished else { return nil }
        return PlantSpecies.all.first { $0.unlockAt > 0 && $0.unlockAt == garden.plants.count }
    }

    private var speciesChip: some View {
        Button {
            if expanded { AppState.shared.ui.tab = .catalog } else { showPicker = true }
        } label: {
            HStack(spacing: 8) {
                PlantIcon(species: species, seed: timer.seed).frame(width: 26, height: 26)
                Text(garden.selection == Garden.randomSelection ? "Überraschung" : species.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 4)
            .background(Capsule().fill(Theme.track))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Auswählen, was wachsen soll")
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            SpeciesPickerList(garden: garden) { showPicker = false }
        }
    }

    private var presets: some View {
        HStack(spacing: 6) {
            ForEach([15, 25, 45, 60], id: \.self) { m in
                Button("\(m) min") { timer.minutes = m }
                    .buttonStyle(ChipButtonStyle(selected: timer.minutes == m, color: species.deep))
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch timer.phase {
        case .idle:
            Button { timer.start() } label: { Label("Pflanzen", systemImage: "leaf.fill") }
                .buttonStyle(PrimaryButtonStyle(color: species.deep))
        case .running, .paused:
            HStack(spacing: 8) {
                if timer.phase == .running {
                    Button { timer.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                        .buttonStyle(SoftButtonStyle())
                } else {
                    Button { timer.resume() } label: { Label("Weiter", systemImage: "play.fill") }
                        .buttonStyle(PrimaryButtonStyle(color: species.deep))
                }
                Button(confirmGiveUp ? "Wirklich?" : "Aufgeben") {
                    if confirmGiveUp {
                        confirmGiveUp = false
                        timer.reset()
                    } else {
                        confirmGiveUp = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmGiveUp = false }
                    }
                }
                .buttonStyle(SoftButtonStyle(tint: confirmGiveUp ? Color(hex: 0xE07A7A) : nil))
            }
        case .finished:
            Button { timer.reset() } label: { Label("Neue Pflanze", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle(color: species.deep))
        }
    }

    private var footer: some View {
        HStack {
            Button { AppState.shared.expand(to: .island) } label: {
                Label("Insel · \(garden.plants.count)", systemImage: "mountain.2.fill")
            }
            .buttonStyle(.plain)
            .help("Fenster vergrößern und Insel zeigen")
            Spacer()
            Button("Beenden") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
    }
}

private struct SettingsPanel: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Theme: \(AppTheme.find(prefs.themeID).name)")
            HStack(spacing: 6) {
                ForEach(AppTheme.all) { theme in
                    Button { prefs.themeID = theme.id } label: {
                        ThemeSwatch(theme: theme)
                            .frame(width: 44, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(prefs.themeID == theme.id ? Palette.stem : .clear, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                    .help(theme.name)
                }
            }
            Divider()
            Toggle("Mini-Timer anheften", isOn: $prefs.pinned)
            Text("Ein kleiner schwebender Timer über allen Fenstern – auch über Apps im Vollbild. Verschieben durch Ziehen.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("Anzeige neben der Notch", isOn: $prefs.notchEnabled)
            if prefs.notchEnabled {
                Picker("Seite", selection: $prefs.side) {
                    Text("Links").tag(Preferences.Side.left)
                    Text("Rechts").tag(Preferences.Side.right)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Abstand zur Notch: \(Int(prefs.gap)) pt")
                    Slider(value: $prefs.gap, in: 0...400)
                }
                Toggle("Nur während einer Session", isOn: $prefs.onlyWhileActive)
                Text("Boring Notch braucht beim Abspielen von Musik ca. 50 pt neben der Notch – lass dort etwas Platz.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Button {
                withAnimation(.easeInOut(duration: 0.35)) { AppState.shared.ui.showOnboarding = true }
            } label: {
                Label("Einführung erneut ansehen", systemImage: "sparkles")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.stem)
        }
        .font(.system(size: 12, design: .rounded))
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
    }
}

/// Hands the hosting NSWindow to AppKit-level code (pinning, resizing).
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReporterView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReporterView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(color))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(tint ?? Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.track))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ChipButtonStyle: ButtonStyle {
    var selected: Bool
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(selected ? color : Theme.track))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct RoundIconButtonStyle: ButtonStyle {
    var size: CGFloat
    var active: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(active == nil ? Theme.ink : .white)
            .frame(width: size, height: size)
            .background(Circle().fill(active ?? Theme.track))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
    }
}
