import AppKit
import Combine
import Foundation

final class FocusTimer: ObservableObject {
    enum Phase { case idle, running, paused, finished }

    @Published var minutes: Int {
        didSet {
            UserDefaults.standard.set(minutes, forKey: "timer.minutes")
            if phase == .idle { remaining = TimeInterval(minutes * 60) }
        }
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var seed: Double = .random(in: 0..<1)
    @Published private(set) var speciesID = PlantSpecies.all[0].id
    // Only authoritative while idle or paused; while running, time is derived from endDate.
    @Published private(set) var remaining: TimeInterval

    private(set) var total: TimeInterval = 1
    private var endDate: Date?
    private var ticker: Timer?
    var onComplete: ((_ minutes: Int, _ seed: Double, _ speciesID: String) -> Void)?
    var pickSpecies: ((_ seed: Double) -> String)?

    var species: PlantSpecies { PlantSpecies.find(speciesID) }

    init() {
        let saved = UserDefaults.standard.integer(forKey: "timer.minutes")
        minutes = saved > 0 ? saved : 25
        remaining = TimeInterval((saved > 0 ? saved : 25) * 60)
    }

    func remaining(at date: Date) -> TimeInterval {
        if phase == .running, let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return phase == .finished ? 0 : remaining
    }

    func progress(at date: Date) -> Double {
        switch phase {
        case .idle: return 0
        case .finished: return 1
        case .running, .paused: return min(1, max(0, 1 - remaining(at: date) / total))
        }
    }

    /// Re-picks what grows next (only before a session starts).
    func refreshSpecies() {
        guard phase == .idle, let pickSpecies else { return }
        speciesID = pickSpecies(seed)
    }

    func start() {
        guard phase == .idle else { return }
        total = TimeInterval(minutes * 60)
        remaining = total
        endDate = Date().addingTimeInterval(total)
        phase = .running
        startTicker()
    }

    func pause() {
        guard phase == .running, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        phase = .paused
        stopTicker()
    }

    func resume() {
        guard phase == .paused else { return }
        endDate = Date().addingTimeInterval(remaining)
        phase = .running
        startTicker()
    }

    func reset() {
        stopTicker()
        endDate = nil
        phase = .idle
        seed = .random(in: 0..<1)
        remaining = TimeInterval(minutes * 60)
        refreshSpecies()
    }

    func adjustMinutes(up: Bool) {
        if up {
            minutes = minutes < 5 ? minutes + 1 : min(180, minutes + 5)
        } else {
            minutes = minutes <= 5 ? max(1, minutes - 1) : minutes - 5
        }
    }

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard phase == .running, let endDate, endDate.timeIntervalSinceNow <= 0 else { return }
        stopTicker()
        self.endDate = nil
        remaining = 0
        phase = .finished
        onComplete?(Int((total / 60).rounded()), seed, speciesID)
        NSSound(named: "Glass")?.play()
    }
}

struct PlantRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let minutes: Int
    let seed: Double
    let speciesID: String
    let island: Int

    init(id: UUID = UUID(), date: Date = Date(), minutes: Int, seed: Double, speciesID: String, island: Int) {
        self.id = id
        self.date = date
        self.minutes = minutes
        self.seed = seed
        self.speciesID = speciesID
        self.island = island
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        minutes = try c.decode(Int.self, forKey: .minutes)
        seed = try c.decode(Double.self, forKey: .seed)
        speciesID = try c.decodeIfPresent(String.self, forKey: .speciesID) ?? PlantSpecies.legacyID(seed: seed)
        island = try c.decodeIfPresent(Int.self, forKey: .island) ?? 0
    }

    var species: PlantSpecies { PlantSpecies.find(speciesID) }
}

struct Decoration: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case path, river, bridge }

    let id: UUID
    let kind: Kind
    let island: Int
    /// Island world coordinates; a bridge has exactly two points.
    let points: [CGPoint]
}

final class Garden: ObservableObject {
    static let islandCapacity = 30
    static let randomSelection = "random"

    @Published private(set) var plants: [PlantRecord] = []
    @Published private(set) var decorations: [Decoration] = []
    @Published var selection: String {
        didSet { UserDefaults.standard.set(selection, forKey: "garden.selection") }
    }

    private let plantsURL: URL
    private let decorationsURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusForest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        plantsURL = dir.appendingPathComponent("forest.json")
        decorationsURL = dir.appendingPathComponent("decorations.json")
        selection = UserDefaults.standard.string(forKey: "garden.selection") ?? Garden.randomSelection
        plants = Self.load([PlantRecord].self, from: plantsURL) ?? []
        decorations = Self.load([Decoration].self, from: decorationsURL) ?? []
    }

    // MARK: Islands

    /// The island the next plant lands on: once an island holds `islandCapacity` plants, a new one begins.
    var currentIsland: Int {
        guard let last = plants.last?.island else { return 0 }
        return plants(on: last).count >= Self.islandCapacity ? last + 1 : last
    }

    func plants(on island: Int) -> [PlantRecord] { plants.filter { $0.island == island } }
    func isComplete(_ island: Int) -> Bool { plants(on: island).count >= Self.islandCapacity }

    func completionDate(of island: Int) -> Date? {
        let list = plants(on: island)
        return list.count >= Self.islandCapacity ? list.last?.date : nil
    }

    static func islandName(_ index: Int) -> String {
        let names = ["Moosinsel", "Kirschwolke", "Sonnenfels", "Pilzhügel", "Lavendelbucht", "Sternenriff",
                     "Nebelhain", "Honigwiese", "Tannenkuppe", "Glitzerinsel", "Wolkenacker", "Blütenbogen"]
        let round = index / names.count
        return names[index % names.count] + (round > 0 ? " \(round + 1)" : "")
    }

    // MARK: Plants & unlocking

    func isUnlocked(_ species: PlantSpecies) -> Bool { plants.count >= species.unlockAt }

    var nextUnlock: PlantSpecies? {
        PlantSpecies.all.filter { !isUnlocked($0) }.min { $0.unlockAt < $1.unlockAt }
    }

    func pickSpecies(seed: Double) -> String {
        if selection != Self.randomSelection {
            let chosen = PlantSpecies.find(selection)
            if chosen.id == selection && isUnlocked(chosen) { return chosen.id }
        }
        let unlocked = PlantSpecies.all.filter(isUnlocked)
        return unlocked[min(unlocked.count - 1, Int(seed * Double(unlocked.count)))].id
    }

    func add(minutes: Int, seed: Double, speciesID: String) {
        plants.append(PlantRecord(minutes: minutes, seed: seed, speciesID: speciesID, island: currentIsland))
        Self.save(plants, to: plantsURL)
    }

    func count(of species: PlantSpecies) -> Int { plants.filter { $0.speciesID == species.id }.count }

    // MARK: Decorations

    func decorations(on island: Int) -> [Decoration] { decorations.filter { $0.island == island } }

    func addDecoration(_ kind: Decoration.Kind, points: [CGPoint], island: Int) {
        decorations.append(Decoration(id: UUID(), kind: kind, island: island, points: points))
        Self.save(decorations, to: decorationsURL)
    }

    func undoDecoration(on island: Int) {
        guard let index = decorations.lastIndex(where: { $0.island == island }) else { return }
        decorations.remove(at: index)
        Self.save(decorations, to: decorationsURL)
    }

    /// Removes the most recently drawn decoration passing within `tolerance` of `point`.
    func removeDecoration(near point: CGPoint, on island: Int, tolerance: Double) {
        guard let index = decorations.lastIndex(where: { d in
            d.island == island && zip(d.points, d.points.dropFirst()).contains { Self.distance(point, $0, $1) < tolerance }
        }) else { return }
        decorations.remove(at: index)
        Self.save(decorations, to: decorationsURL)
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: Statistics

    var totalMinutes: Int { plants.reduce(0) { $0 + $1.minutes } }
    var todayCount: Int { plants.filter { Calendar.current.isDateInToday($0.date) }.count }

    /// Consecutive days with at least one session, ending today (or yesterday if today is still empty).
    var streak: Int {
        let cal = Calendar.current
        let days = Set(plants.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    func minutesPerDay(last days: Int) -> [(day: Date, minutes: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let minutes = plants.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
            return (day, minutes)
        }
    }

    var favoriteSpecies: PlantSpecies? {
        Dictionary(grouping: plants, by: \.speciesID).max { $0.value.count < $1.value.count }.map { PlantSpecies.find($0.key) }
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

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
        timer.onComplete = { [garden] minutes, seed, speciesID in
            garden.add(minutes: minutes, seed: seed, speciesID: speciesID)
        }
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
