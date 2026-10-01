import Combine
import CoreGraphics
import Foundation

// Platform-independent model shared by the Mac app and the iPhone/iPad app.

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
    private(set) var endDate: Date?
    private var ticker: Timer?
    /// `date` is when the session actually ended, which can be long before the app notices (e.g. after relaunch).
    var onComplete: ((_ minutes: Int, _ seed: Double, _ speciesID: String, _ date: Date) -> Void)?
    var pickSpecies: ((_ seed: Double) -> String)?

    var species: PlantSpecies { PlantSpecies.find(speciesID) }

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
        guard phase == .running || phase == .paused else {
            defaults.removeObject(forKey: "timer.session")
            return
        }
        defaults.set([
            "paused": phase == .paused, "end": endDate?.timeIntervalSince1970 ?? 0, "remaining": remaining,
            "total": total, "seed": seed, "species": speciesID,
        ] as [String: Any], forKey: "timer.session")
    }

    private func restore(from defaults: UserDefaults) {
        guard let s = defaults.dictionary(forKey: "timer.session"),
              let total = s["total"] as? Double, let seed = s["seed"] as? Double,
              let species = s["species"] as? String, let paused = s["paused"] as? Bool else { return }
        self.total = total
        self.seed = seed
        speciesID = species
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

    func reset() {
        stopTicker()
        endDate = nil
        phase = .idle
        seed = .random(in: 0..<1)
        remaining = TimeInterval(minutes * 60)
        refreshSpecies()
        persist()
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

    /// Completes the session if its end time has passed; call when the app becomes active again.
    func tick() {
        guard phase == .running, let endDate, endDate.timeIntervalSinceNow <= 0 else { return }
        stopTicker()
        self.endDate = nil
        remaining = 0
        phase = .finished
        persist()
        onComplete?(Int((total / 60).rounded()), seed, speciesID, endDate)
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

    func add(minutes: Int, seed: Double, speciesID: String, date: Date = Date()) {
        plants.append(PlantRecord(date: date, minutes: minutes, seed: seed, speciesID: speciesID, island: currentIsland))
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

