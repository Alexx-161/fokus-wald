import ActivityKit
import AVFoundation
import Combine
import SwiftUI
import UIKit
import UserNotifications

final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var themeID: String {
        didSet {
            defaults.set(themeID, forKey: "theme")
            Self.apply(AppTheme.find(themeID))
        }
    }
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "ios.sound") } }
    @Published var haptics: Bool { didSet { defaults.set(haptics, forKey: "ios.haptics") } }
    @Published var keepAwake: Bool { didSet { defaults.set(keepAwake, forKey: "ios.keepAwake") } }
    /// Dynamic Island and Lock Screen display while a session runs.
    @Published var liveActivity: Bool { didSet { defaults.set(liveActivity, forKey: "ios.liveActivity") } }
    @Published var notify: Bool { didSet { defaults.set(notify, forKey: "ios.notify") } }

    init() {
        defaults.register(defaults: [
            "ios.sound": true, "ios.haptics": true, "ios.keepAwake": false, "ios.liveActivity": true, "ios.notify": true,
        ])
        sound = defaults.bool(forKey: "ios.sound")
        haptics = defaults.bool(forKey: "ios.haptics")
        keepAwake = defaults.bool(forKey: "ios.keepAwake")
        liveActivity = defaults.bool(forKey: "ios.liveActivity")
        notify = defaults.bool(forKey: "ios.notify")
        themeID = defaults.string(forKey: "theme") ?? AppTheme.all[0].id
        AppTheme.current = AppTheme.find(themeID)
    }

    /// Fixed themes force light or dark for the whole app; "Wiese" follows the system.
    static func apply(_ theme: AppTheme) {
        AppTheme.current = theme
        let style: UIUserInterfaceStyle = theme.scheme == .dark ? .dark : theme.scheme == .light ? .light : .unspecified
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}

final class AppModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case timer, island, catalog, stats, archipelago
        var id: String { rawValue }
        var title: String {
            switch self {
            case .timer: return "Timer"
            case .island: return "Insel"
            case .catalog: return "Pflanzen"
            case .stats: return "Statistik"
            case .archipelago: return "Archipel"
            }
        }
        var symbol: String {
            switch self {
            case .timer: return "timer"
            case .island: return "mountain.2.fill"
            case .catalog: return "leaf.fill"
            case .stats: return "chart.bar.fill"
            case .archipelago: return "map.fill"
            }
        }
    }

    static let shared = AppModel()

    let timer = FocusTimer()
    let garden = Garden()
    let prefs = Preferences()

    @Published var tab: Tab = .timer
    /// nil follows the island currently being planted.
    @Published var island: Int?
    @Published var showOnboarding: Bool

    private let live = LiveActivityController()
    private let chime = Chime()
    private var cancellables = Set<AnyCancellable>()
    private var isActive = true

    private init() {
        let defaults = UserDefaults.standard
        showOnboarding = !defaults.bool(forKey: "onboarding.done") || defaults.bool(forKey: "onboarding.forceShow")

        timer.pickSpecies = { [garden] seed in garden.pickSpecies(seed: seed) }
        timer.refreshSpecies()
        timer.onComplete = { [weak self] minutes, seed, speciesID, date in
            guard let self else { return }
            self.garden.add(minutes: minutes, seed: seed, speciesID: speciesID, date: date)
            self.celebrate()
        }
        garden.$selection
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [timer] _ in timer.refreshSpecies() }
            .store(in: &cancellables)
        // @Published fires in willSet; defer so the timer already holds the new phase.
        timer.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sessionChanged() }
            .store(in: &cancellables)
        prefs.$keepAwake.merge(with: prefs.$liveActivity, prefs.$notify)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sessionChanged() }
            .store(in: &cancellables)
        // A session restored from the last run may already be over.
        timer.tick()
    }

    // MARK: Session actions

    func start() {
        if prefs.notify { requestNotificationPermission() }
        timer.start()
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding.done")
        showOnboarding = false
        if prefs.notify { requestNotificationPermission() }
    }

    /// Called whenever the app comes to the foreground: the session may have ended while it was away.
    func sceneBecameActive(_ active: Bool) {
        isActive = active
        guard active else { return }
        Preferences.apply(AppTheme.find(prefs.themeID))
        timer.tick()
        sessionChanged()
    }

    private func sessionChanged() {
        UIApplication.shared.isIdleTimerDisabled = prefs.keepAwake && timer.phase == .running
        live.sync(with: timer, enabled: prefs.liveActivity)
        scheduleEndNotification()
    }

    private func celebrate() {
        guard isActive else { return }
        if prefs.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        if prefs.sound { chime.play() }
    }

    // MARK: Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.scheduleEndNotification() }
        }
    }

    private func scheduleEndNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["session-end"])
        guard prefs.notify, timer.phase == .running, let end = timer.endDate, end.timeIntervalSinceNow > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(timer.species.name) ist fertig gewachsen!"
        content.body = "Deine Fokus-Session ist geschafft. Schau auf deiner Insel vorbei."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: "session-end", content: content, trigger: trigger))
    }
}

/// Keeps the Live Activity (Dynamic Island and Lock Screen) in step with the timer.
final class LiveActivityController {
    private var activity: Activity<FocusActivityAttributes>? = Activity<FocusActivityAttributes>.activities.first

    func sync(with timer: FocusTimer, enabled: Bool) {
        let now = Date()
        switch timer.phase {
        case .idle:
            end(nil)
        case .running:
            guard enabled, let endDate = timer.endDate else { return end(nil) }
            show(.init(startDate: endDate.addingTimeInterval(-timer.total), endDate: endDate, total: timer.total,
                       pausedRemaining: nil, finished: false),
                 staleDate: endDate, for: timer)
        case .paused:
            guard enabled else { return end(nil) }
            let remaining = timer.remaining(at: now)
            show(.init(startDate: now.addingTimeInterval(remaining - timer.total), endDate: now.addingTimeInterval(remaining),
                       total: timer.total, pausedRemaining: remaining, finished: false),
                 staleDate: nil, for: timer)
        case .finished:
            end(.init(startDate: now.addingTimeInterval(-timer.total), endDate: now, total: timer.total,
                      pausedRemaining: nil, finished: true))
        }
    }

    private func show(_ state: FocusActivityAttributes.ContentState, staleDate: Date?, for timer: FocusTimer) {
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let activity, activity.attributes.seed == timer.seed, activity.activityState != .ended, activity.activityState != .dismissed {
            Task { await activity.update(content) }
            return
        }
        end(nil)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(
            attributes: FocusActivityAttributes(speciesID: timer.speciesID, seed: timer.seed),
            content: content, pushType: nil)
    }

    /// With a final state the activity stays visible for a few minutes as "Fertig"; without one it disappears at once.
    private func end(_ finalState: FocusActivityAttributes.ContentState?) {
        guard let activity else { return }
        self.activity = nil
        Task {
            if let finalState {
                await activity.end(ActivityContent(state: finalState, staleDate: nil),
                                   dismissalPolicy: .after(Date().addingTimeInterval(8 * 60)))
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

/// A soft three-note chime, synthesized so no audio file needs to be bundled.
final class Chime {
    private var player: AVAudioPlayer?

    func play() {
        if player == nil { player = try? AVAudioPlayer(data: Self.wave()) }
        // .ambient respects the silent switch and mixes with music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        player?.currentTime = 0
        player?.play()
    }

    private static func wave() -> Data {
        let rate = 44_100.0
        let notes: [(freq: Double, start: Double)] = [(659.25, 0), (783.99, 0.16), (1046.5, 0.32)]
        let count = Int(rate * 1.6)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / rate
            var value = 0.0
            for note in notes where t >= note.start {
                let local = t - note.start
                value += sin(2 * .pi * note.freq * local) * min(1, local / 0.02) * exp(-local * 4.5)
            }
            samples[i] = Int16(max(-1, min(1, value * 0.28)) * Double(Int16.max))
        }
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
