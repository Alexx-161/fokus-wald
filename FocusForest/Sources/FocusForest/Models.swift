import AppKit
import Combine
import Foundation

final class Preferences: ObservableObject {
    enum Side: String { case left, right }

    private let defaults = UserDefaults.standard

    @Published var notchEnabled: Bool { didSet { defaults.set(notchEnabled, forKey: "notch.enabled") } }
    @Published var side: Side { didSet { defaults.set(side.rawValue, forKey: "notch.side") } }
    @Published var gap: Double { didSet { defaults.set(gap, forKey: "notch.gap") } }
    @Published var onlyWhileActive: Bool { didSet { defaults.set(onlyWhileActive, forKey: "notch.onlyWhileActive") } }
    /// Shows the floating mini timer, which stays above all windows including other apps in full screen.
    @Published var pinned: Bool { didSet { defaults.set(pinned, forKey: "window.pinned") } }
    @Published var themeID: String {
        didSet {
            defaults.set(themeID, forKey: "theme")
            Self.apply(AppTheme.find(themeID))
        }
    }
    // Shows the notch widget while the settings panel is open so placement can be tuned live.
    @Published var previewing = false

    init() {
        defaults.register(defaults: [
            "notch.enabled": true,
            "notch.side": Side.right.rawValue,
            "notch.gap": 56.0,
            "notch.onlyWhileActive": true,
            "window.pinned": false,
        ])
        notchEnabled = defaults.bool(forKey: "notch.enabled")
        side = Side(rawValue: defaults.string(forKey: "notch.side") ?? "") ?? .right
        gap = defaults.double(forKey: "notch.gap")
        onlyWhileActive = defaults.bool(forKey: "notch.onlyWhileActive")
        pinned = defaults.bool(forKey: "window.pinned")
        themeID = defaults.string(forKey: "theme") ?? AppTheme.all[0].id
        Self.apply(AppTheme.find(themeID))
    }

    /// SwiftUI's preferredColorScheme(nil) doesn't reliably return to the system setting, so the
    /// light/dark choice is made app-wide via NSApp.appearance instead.
    private static func apply(_ theme: AppTheme) {
        AppTheme.current = theme
        switch theme.scheme {
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        default: NSApp?.appearance = nil
        }
    }
}

final class UIState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case island, catalog, stats, archipelago
        var id: String { rawValue }
        var title: String {
            switch self {
            case .island: return "Insel"
            case .catalog: return "Pflanzen"
            case .stats: return "Statistik"
            case .archipelago: return "Archipel"
            }
        }
        var symbol: String {
            switch self {
            case .island: return "mountain.2.fill"
            case .catalog: return "leaf.fill"
            case .stats: return "chart.bar.fill"
            case .archipelago: return "map.fill"
            }
        }
    }

    @Published var tab: Tab = .island
    /// nil follows the island currently being planted.
    @Published var island: Int?
    @Published var showOnboarding = false
}

final class AppState {
    static let shared = AppState()

    let timer = FocusTimer()
    let garden = Garden()
    let prefs = Preferences()
    let ui = UIState()

    private weak var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let defaults = UserDefaults.standard
        // People who already planted something before the welcome screen existed never see it automatically.
        if !defaults.bool(forKey: "onboarding.done") && !garden.plants.isEmpty {
            defaults.set(true, forKey: "onboarding.done")
        }
        // "onboarding.forceShow" is only ever passed as a launch argument (-onboarding.forceShow YES) for previews.
        ui.showOnboarding = !defaults.bool(forKey: "onboarding.done") || defaults.bool(forKey: "onboarding.forceShow")

        timer.pickSpecies = { [garden] seed in garden.pickSpecies(seed: seed) }
        timer.refreshSpecies()
        timer.onComplete = { [garden] minutes, seed, speciesID, date in
            garden.add(minutes: minutes, seed: seed, speciesID: speciesID, date: date)
            NSSound(named: "Glass")?.play()
        }
        // A session restored from the last run may already be over.
        timer.tick()
        garden.$selection
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [timer] _ in timer.refreshSpecies() }
            .store(in: &cancellables)
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding.done")
        ui.showOnboarding = false
    }

    // MARK: Main window

    /// Set by the SwiftUI scene so AppKit code can reopen the timer window after it was closed.
    var openMainWindow: (() -> Void)?

    func attach(window: NSWindow) {
        let isNew = self.window !== window
        self.window = window
        guard isNew && ui.showOnboarding else { return }
        // Runs after SwiftUI has restored the saved window frame, which would otherwise undo the resize.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak window] in
            guard let self, let window, !self.isFullScreen, window.frame.width < 420 || window.frame.height < 680 else { return }
            self.resize(window, to: NSSize(width: max(window.frame.width, 420), height: max(window.frame.height, 680)))
        }
    }

    var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }

    func showMainWindow() {
        NSApp.activate()
        if let window, window.isVisible || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    func expand(to tab: UIState.Tab) {
        ui.tab = tab
        guard let window, !isFullScreen else { return }
        resize(window, to: NSSize(width: max(window.frame.width, 1120), height: max(window.frame.height, 720)))
    }

    func collapse() {
        guard let window else { return }
        if isFullScreen {
            window.toggleFullScreen(nil)
            return
        }
        resize(window, to: NSSize(width: 320, height: 640))
    }

    /// Keeps the top-left corner in place and stays on the window's screen.
    private func resize(_ window: NSWindow, to size: NSSize) {
        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        if let visible = window.screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        }
        window.setFrame(frame, display: true, animate: true)
    }
}
