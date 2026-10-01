import Combine
import CoreGraphics
import Foundation

// Platform-independent model shared by the Mac app and the iPhone/iPad app.

/// An unfinished plant. Stopping a session early keeps it in the island's seedbed, and a later session lets it grow on.
struct Sapling: Codable, Identifiable, Hashable {
    let id: UUID
    var date: Date
    let speciesID: String
    let seed: Double
    /// Growth reached so far (0..<1).
    var progress: Double
    /// Focus time already invested, in seconds.
    var elapsed: TimeInterval

    var species: PlantSpecies { PlantSpecies.find(speciesID) }
}

final class FocusTimer: ObservableObject {
    enum Phase { case idle, running, paused, finished }

    struct Completion {
        /// All focus time that went into the plant, including earlier sessions of a continued sapling.
        let minutes: Int
        let seed: Double
        let speciesID: String
        /// When the session actually ended, which can be long before the app notices (e.g. after relaunch).
        let date: Date
        let saplingID: UUID?
    }

    struct Abandonment {
        let progress: Double
        let elapsed: TimeInterval
        let seed: Double
        let speciesID: String
        let saplingID: UUID?
    }

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
    /// The sapling the next session continues, if any.
    @Published private(set) var pending: Sapling?
    /// Set while the break after a finished session is running.
    @Published private(set) var breakEnd: Date?

    private(set) var total: TimeInterval = 1
    private(set) var endDate: Date?
    /// Growth and focus time the running session started from (non-zero when it continues a sapling).
    private(set) var baseProgress: Double = 0
    private(set) var carried: TimeInterval = 0
    private(set) var saplingID: UUID?
    private var ticker: Timer?
    var onComplete: ((Completion) -> Void)?
    var onAbandon: ((Abandonment) -> Void)?
    var onBreakEnd: (() -> Void)?
    var pickSpecies: ((_ seed: Double) -> String)?

    var species: PlantSpecies { PlantSpecies.find(speciesID) }
    var isActive: Bool { phase == .running || phase == .paused }
    var isOnBreak: Bool { breakEnd != nil }

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.integer(forKey: "timer.minutes")
        minutes = saved > 0 ? saved : 25
        remaining = TimeInterval((saved > 0 ? saved : 25) * 60)
        restore(from: defaults)
    }

    // A running or paused session survives quitting the app (iOS may end it at any time in the background).
    private func persist() {
        let defaults = UserDefaults.standard
        guard isActive else {
            defaults.removeObject(forKey: "timer.session")
            return
        }
        defaults.set([
            "paused": phase == .paused, "end": endDate?.timeIntervalSince1970 ?? 0, "remaining": remaining,
            "total": total, "seed": seed, "species": speciesID,
            "base": baseProgress, "carried": carried, "sapling": saplingID?.uuidString ?? "",
        ] as [String: Any], forKey: "timer.session")
    }

    private func restore(from defaults: UserDefaults) {
        guard let s = defaults.dictionary(forKey: "timer.session"),
              let total = s["total"] as? Double, let seed = s["seed"] as? Double,
              let species = s["species"] as? String, let paused = s["paused"] as? Bool else { return }
        self.total = total
        self.seed = seed
        speciesID = species
        baseProgress = s["base"] as? Double ?? 0
        carried = s["carried"] as? Double ?? 0
        saplingID = (s["sapling"] as? String).flatMap(UUID.init(uuidString:))
        if paused {
            remaining = s["remaining"] as? Double ?? total
            phase = .paused
        } else {
            endDate = Date(timeIntervalSince1970: s["end"] as? Double ?? 0)
            phase = .running
            startTicker()
        }
    }

    func remaining(at date: Date) -> TimeInterval {
        if phase == .running, let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return phase == .finished ? 0 : remaining
    }

    func progress(at date: Date) -> Double {
        switch phase {
        case .idle: return pending?.progress ?? 0
        case .finished: return 1
        case .running, .paused:
            return min(1, max(0, baseProgress + (1 - baseProgress) * (1 - remaining(at: date) / total)))
        }
    }

    func breakRemaining(at date: Date) -> TimeInterval {
        max(0, breakEnd?.timeIntervalSince(date) ?? 0)
    }

    /// Focus minutes the plant will hold when this session completes.
    var plannedMinutes: Int {
        let seconds = phase == .idle ? (pending?.elapsed ?? 0) + TimeInterval(minutes * 60) : carried + total
        return Int((seconds / 60).rounded())
    }

    var growsGolden: Bool { PlantSpecies.isGolden(minutes: plannedMinutes) }

    /// Re-picks what grows next (only before a session starts, and not while a sapling is waiting to grow on).
    func refreshSpecies() {
        guard phase == .idle, pending == nil, let pickSpecies else { return }
        speciesID = pickSpecies(seed)
    }

    /// Chooses the sapling the next session continues; nil plants something new.
    func prepare(_ sapling: Sapling?) {
        guard sapling != pending else { return }
        let hadSapling = pending != nil
        pending = sapling
        guard phase == .idle else { return }
        if let sapling {
            seed = sapling.seed
            speciesID = sapling.speciesID
        } else if hadSapling {
            seed = .random(in: 0..<1)
            refreshSpecies()
        }
    }

    func start() {
        guard phase == .idle else { return }
        total = TimeInterval(minutes * 60)
        remaining = total
        baseProgress = pending?.progress ?? 0
        carried = pending?.elapsed ?? 0
        saplingID = pending?.id
        endDate = Date().addingTimeInterval(total)
        phase = .running
        startTicker()
        persist()
    }

    func pause() {
        guard phase == .running, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        phase = .paused
        stopTicker()
        persist()
    }

    func resume() {
        guard phase == .paused else { return }
        endDate = Date().addingTimeInterval(remaining)
        phase = .running
        startTicker()
        persist()
    }

    /// Stops the session early. Nothing dies: the plant is handed to `onAbandon`, which keeps it as a sapling.
    func giveUp() {
        guard isActive else { return }
        let now = Date()
        let abandonment = Abandonment(progress: progress(at: now), elapsed: carried + total - remaining(at: now),
                                      seed: seed, speciesID: speciesID, saplingID: saplingID)
        reset()
        onAbandon?(abandonment)
    }

    func reset() {
        stopTicker()
        endDate = nil
        breakEnd = nil
        baseProgress = 0
        carried = 0
        saplingID = nil
        phase = .idle
        remaining = TimeInterval(minutes * 60)
        if let pending {
            seed = pending.seed
            speciesID = pending.speciesID
        } else {
            seed = .random(in: 0..<1)
            refreshSpecies()
        }
        persist()
    }

    func startBreak(minutes: Int) {
        guard phase == .finished else { return }
        breakEnd = Date().addingTimeInterval(TimeInterval(minutes * 60))
        startTicker()
    }

    func adjustMinutes(up: Bool) {
        if up {
            minutes = minutes < 5 ? minutes + 1 : min(180, minutes + 5)
        } else {
            minutes = minutes <= 5 ? max(1, minutes - 1) : minutes - 5
        }
    }

    /// Starts, pauses or resumes, whichever fits the current phase (menu bar, hotkey, URL commands).
    func toggle() {
        switch phase {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        case .finished: reset()
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

    /// Completes the session (or the break) if its end time has passed; call when the app becomes active again.
    func tick() {
        if phase == .finished, let breakEnd, breakEnd.timeIntervalSinceNow <= 0 {
            reset()
            onBreakEnd?()
            return
        }
        guard phase == .running, let endDate, endDate.timeIntervalSinceNow <= 0 else { return }
        stopTicker()
        self.endDate = nil
        remaining = 0
        phase = .finished
        persist()
        onComplete?(Completion(minutes: Int(((carried + total) / 60).rounded()), seed: seed, speciesID: speciesID,
                               date: endDate, saplingID: saplingID))
    }
}

struct PlantRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let minutes: Int
    let seed: Double
    let speciesID: String
    let island: Int
    /// What the session was spent on (subject or project), if the user picked one.
    var tag: String?
    var note: String?

    init(id: UUID = UUID(), date: Date = Date(), minutes: Int, seed: Double, speciesID: String, island: Int,
         tag: String? = nil, note: String? = nil) {
        self.id = id
        self.date = date
        self.minutes = minutes
        self.seed = seed
        self.speciesID = speciesID
        self.island = island
        self.tag = tag
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        minutes = try c.decode(Int.self, forKey: .minutes)
        seed = try c.decode(Double.self, forKey: .seed)
        speciesID = try c.decodeIfPresent(String.self, forKey: .speciesID) ?? PlantSpecies.legacyID(seed: seed)
        island = try c.decodeIfPresent(Int.self, forKey: .island) ?? 0
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    var species: PlantSpecies { PlantSpecies.find(speciesID) }
    var isGolden: Bool { PlantSpecies.isGolden(minutes: minutes) }
}

struct Decoration: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case path, river, bridge }

    let id: UUID
    let kind: Kind
    let island: Int
    /// Island world coordinates; a bridge has exactly two points.
    let points: [CGPoint]
}

/// Animals that move onto the island once a milestone is reached. They never leave again.
enum Resident: String, CaseIterable, Identifiable {
    case butterfly, bird, bunny, fox, fireflies

    var id: String { rawValue }

    var name: String {
        switch self {
        case .butterfly: return "Schmetterlinge"
        case .bird: return "Vogel"
        case .bunny: return "Hase"
        case .fox: return "Fuchs"
        case .fireflies: return "Glühwürmchen"
        }
    }

    var condition: String {
        switch self {
        case .butterfly: return "ab 3 Pflanzen"
        case .bird: return "ab 10 Pflanzen"
        case .bunny: return "erste vollendete Insel"
        case .fox: return "7 Tage in Folge"
        case .fireflies: return "10 Stunden Fokuszeit · kommen nachts"
        }
    }
}

final class Garden: ObservableObject {
    static let islandCapacity = 30
    static let randomSelection = "random"
    static let maxTags = 12

    @Published private(set) var plants: [PlantRecord] = []
    @Published private(set) var decorations: [Decoration] = []
    @Published private(set) var saplings: [Sapling] = []
    /// The animal that moved in with the most recent session, for the "new resident" message.
    @Published private(set) var newResident: Resident?
    @Published var selection: String {
        didSet { defaults.set(selection, forKey: "garden.selection") }
    }
    /// Subjects or projects a session can be filed under.
    @Published private(set) var tags: [String] {
        didSet { defaults.set(tags, forKey: "garden.tags") }
    }
    @Published var currentTag: String? {
        didSet { defaults.set(currentTag ?? "", forKey: "garden.tag") }
    }
    /// Focus minutes aimed for per week; reaching them lights the lighthouse. 0 switches the goal off.
    @Published var weeklyGoal: Int {
        didSet { defaults.set(weeklyGoal, forKey: "garden.weeklyGoal") }
    }
    /// Time of day and season of the real world show on the island.
    @Published var livingSky: Bool {
        didSet { defaults.set(livingSky, forKey: "garden.livingSky") }
    }
    @Published var breakMinutes: Int {
        didSet { defaults.set(breakMinutes, forKey: "garden.breakMinutes") }
    }
    /// Whether the next session grows the waiting sapling on or plants something new.
    @Published var continueSapling: Bool {
        didSet { defaults.set(continueSapling, forKey: "garden.continueSapling") }
    }

    private let defaults = UserDefaults.standard
    private let plantsURL: URL
    private let decorationsURL: URL
    private let saplingsURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusForest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        plantsURL = dir.appendingPathComponent("forest.json")
        decorationsURL = dir.appendingPathComponent("decorations.json")
        saplingsURL = dir.appendingPathComponent("saplings.json")
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "garden.tags": ["Lernen", "Arbeit", "Lesen"], "garden.weeklyGoal": 120, "garden.livingSky": true,
            "garden.breakMinutes": 5, "garden.continueSapling": true,
        ])
        selection = defaults.string(forKey: "garden.selection") ?? Garden.randomSelection
        tags = defaults.stringArray(forKey: "garden.tags") ?? []
        currentTag = defaults.string(forKey: "garden.tag").flatMap { $0.isEmpty ? nil : $0 }
        weeklyGoal = defaults.integer(forKey: "garden.weeklyGoal")
        livingSky = defaults.bool(forKey: "garden.livingSky")
        breakMinutes = max(1, defaults.integer(forKey: "garden.breakMinutes"))
        continueSapling = defaults.bool(forKey: "garden.continueSapling")
        plants = Self.load([PlantRecord].self, from: plantsURL) ?? []
        decorations = Self.load([Decoration].self, from: decorationsURL) ?? []
        saplings = Self.load([Sapling].self, from: saplingsURL) ?? []
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

    static var currentMonth: Int { Calendar.current.component(.month, from: Date()) }

    /// Seasonal plants are available during their month only; everything else unlocks with completed sessions.
    func isUnlocked(_ species: PlantSpecies) -> Bool {
        if let month = species.month { return month == Self.currentMonth }
        return plants.count >= species.unlockAt
    }

    var nextUnlock: PlantSpecies? {
        PlantSpecies.all.filter { $0.month == nil && !isUnlocked($0) }.min { $0.unlockAt < $1.unlockAt }
    }

    func pickSpecies(seed: Double) -> String {
        if selection != Self.randomSelection {
            let chosen = PlantSpecies.find(selection)
            if chosen.id == selection && isUnlocked(chosen) { return chosen.id }
        }
        let unlocked = PlantSpecies.all.filter(isUnlocked)
        return unlocked[min(unlocked.count - 1, Int(seed * Double(unlocked.count)))].id
    }

    /// Plants a finished session on the current island.
    @discardableResult
    func complete(_ session: FocusTimer.Completion) -> PlantRecord {
        let before = Set(residents)
        let record = PlantRecord(date: session.date, minutes: session.minutes, seed: session.seed,
                                 speciesID: session.speciesID, island: currentIsland, tag: currentTag)
        plants.append(record)
        Self.save(plants, to: plantsURL)
        if let id = session.saplingID {
            saplings.removeAll { $0.id == id }
            Self.save(saplings, to: saplingsURL)
        }
        newResident = residents.first { !before.contains($0) }
        return record
    }

    func count(of species: PlantSpecies) -> Int { plants.filter { $0.speciesID == species.id }.count }
    func goldenCount(of species: PlantSpecies) -> Int { plants.filter { $0.speciesID == species.id && $0.isGolden }.count }

    func setNote(_ note: String, for id: UUID) {
        guard let index = plants.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
        guard plants[index].note ?? "" != trimmed else { return }
        plants[index].note = trimmed.isEmpty ? nil : trimmed
        Self.save(plants, to: plantsURL)
    }

    // MARK: Saplings

    /// The sapling the next session grows on, if the user wants to continue one.
    var pendingSapling: Sapling? { continueSapling ? saplings.last : nil }

    /// Keeps a session that was stopped early as a sapling. Sessions under a minute leave nothing behind.
    func keep(_ session: FocusTimer.Abandonment) {
        guard session.elapsed >= 60 else { return }
        let sapling = Sapling(id: session.saplingID ?? UUID(), date: Date(), speciesID: session.speciesID, seed: session.seed,
                              progress: min(0.97, session.progress), elapsed: session.elapsed)
        saplings.removeAll { $0.id == sapling.id }
        saplings.append(sapling)
        continueSapling = true
        Self.save(saplings, to: saplingsURL)
    }

    // MARK: Tags

    func addTag(_ name: String) {
        let tag = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        guard !tag.isEmpty else { return }
        if !tags.contains(tag) {
            guard tags.count < Self.maxTags else { return }
            tags.append(tag)
        }
        currentTag = tag
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        if currentTag == tag { currentTag = nil }
    }

    /// Stable palette slot for a tag, so its color survives other tags being added or removed.
    static func tagColorIndex(_ tag: String) -> Int {
        tag.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 1_000_003 } % 8
    }

    /// Focus minutes per tag, largest first; sessions without a tag are grouped under nil.
    var minutesByTag: [(tag: String?, minutes: Int)] {
        Dictionary(grouping: plants, by: \.tag)
            .map { (tag: $0.key, minutes: $0.value.reduce(0) { $0 + $1.minutes }) }
            .sorted { $0.minutes != $1.minutes ? $0.minutes > $1.minutes : ($0.tag ?? "") < ($1.tag ?? "") }
    }

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

    /// The longest run of consecutive days ever reached.
    var longestStreak: Int {
        let cal = Calendar.current
        let days = Set(plants.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, cal.dateComponents([.day], from: previous, to: day).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// Focus minutes since Monday.
    var weekMinutes: Int {
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        return plants.filter { $0.date >= start }.reduce(0) { $0 + $1.minutes }
    }

    var weeklyGoalReached: Bool { weeklyGoal > 0 && weekMinutes >= weeklyGoal }

    /// True when the most recent session is the one that pushed the week over its goal.
    var goalJustReached: Bool {
        guard weeklyGoalReached, let last = plants.last else { return false }
        return weekMinutes - last.minutes < weeklyGoal
    }

    var residents: [Resident] {
        Resident.allCases.filter { resident in
            switch resident {
            case .butterfly: return plants.count >= 3
            case .bird: return plants.count >= 10
            case .bunny: return currentIsland >= 1
            case .fox: return longestStreak >= 7
            case .fireflies: return totalMinutes >= 600
            }
        }
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

    /// Replaces everything with the contents of a backup.
    func restore(plants: [PlantRecord], decorations: [Decoration], saplings: [Sapling], tags: [String]?, weeklyGoal: Int?) {
        self.plants = plants
        self.decorations = decorations
        self.saplings = saplings
        if let tags { self.tags = Array(tags.prefix(Self.maxTags)) }
        if let currentTag, !self.tags.contains(currentTag) { self.currentTag = nil }
        if let weeklyGoal { self.weeklyGoal = max(0, weeklyGoal) }
        newResident = nil
        Self.save(plants, to: plantsURL)
        Self.save(decorations, to: decorationsURL)
        Self.save(saplings, to: saplingsURL)
    }

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

/// Wires a timer to a garden: what grows next, saplings, finished and abandoned sessions.
enum SessionLink {
    static func connect(timer: FocusTimer, garden: Garden,
                        onPlanted: @escaping (PlantRecord) -> Void) -> Set<AnyCancellable> {
        var cancellables = Set<AnyCancellable>()
        timer.pickSpecies = { [garden] seed in garden.pickSpecies(seed: seed) }
        timer.onComplete = { [garden] session in onPlanted(garden.complete(session)) }
        timer.onAbandon = { [garden] session in garden.keep(session) }
        timer.prepare(garden.pendingSapling)
        timer.refreshSpecies()
        garden.$selection
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [timer] _ in timer.refreshSpecies() }
            .store(in: &cancellables)
        // @Published fires in willSet, so the new values are read on the next runloop turn.
        garden.$saplings.map { _ in () }.merge(with: garden.$continueSapling.map { _ in () })
            .dropFirst(2)
            .receive(on: DispatchQueue.main)
            .sink { [timer, garden] in timer.prepare(garden.pendingSapling) }
            .store(in: &cancellables)
        return cancellables
    }
}

/// Commands other apps can send, e.g. from the Shortcuts app via "Open URL":
/// fokuswald://start?minutes=25 · pause · resume · toggle · stop
enum URLCommand {
    static func run(_ url: URL, timer: FocusTimer) {
        guard url.scheme == "fokuswald" else { return }
        let minutes = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "minutes" }?.value.flatMap { Int($0) }
        switch url.host ?? "" {
        case "start":
            if timer.phase == .finished { timer.reset() }
            if timer.phase == .paused { timer.resume() }
            guard timer.phase == .idle else { return }
            if let minutes { timer.minutes = min(180, max(1, minutes)) }
            timer.start()
        case "pause": timer.pause()
        case "resume": timer.resume()
        case "toggle": timer.toggle()
        case "stop": timer.giveUp()
        default: break
        }
    }
}
