import CoreGraphics
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The backup file shared by the web app, the Mac app and the iPhone/iPad app, so progress can move between them.
/// Dates are ISO 8601 strings and decoration points are `{x, y}` objects, as the web app writes them.
struct Backup: Codable {
    struct Plant: Codable {
        var id: String
        var date: String
        var minutes: Int
        var seed: Double
        var speciesID: String
        var island: Int
        var tag: String?
        var note: String?
    }

    struct Point: Codable {
        var x: Double
        var y: Double
    }

    struct Ornament: Codable {
        var id: String?
        var kind: String
        var island: Int
        var points: [Point]
    }

    struct Seedling: Codable {
        var id: String
        var date: String
        var speciesID: String
        var seed: Double
        var progress: Double
        var elapsed: Double
    }

    enum Problem: Error { case notABackup }

    var app = "fokus-wald"
    var version = 2
    var plants: [Plant]
    var decorations: [Ornament]?
    var saplings: [Seedling]?
    var tags: [String]?
    var weeklyGoal: Int?

    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    private static func date(_ text: String) -> Date {
        withFraction.date(from: text) ?? plain.date(from: text) ?? Date()
    }
}

extension Garden {
    func backupData() -> Data {
        let iso = ISO8601DateFormatter()
        let backup = Backup(
            plants: plants.map {
                Backup.Plant(id: $0.id.uuidString, date: iso.string(from: $0.date), minutes: $0.minutes, seed: $0.seed,
                             speciesID: $0.speciesID, island: $0.island, tag: $0.tag, note: $0.note)
            },
            decorations: decorations.map {
                Backup.Ornament(id: $0.id.uuidString, kind: $0.kind.rawValue, island: $0.island,
                                points: $0.points.map { Backup.Point(x: $0.x, y: $0.y) })
            },
            saplings: saplings.map {
                Backup.Seedling(id: $0.id.uuidString, date: iso.string(from: $0.date), speciesID: $0.speciesID,
                                seed: $0.seed, progress: $0.progress, elapsed: $0.elapsed)
            },
            tags: tags, weeklyGoal: weeklyGoal)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(backup)) ?? Data()
    }

    /// Replaces the whole garden with a backup's contents. Throws if the file is not a Fokus-Wald backup.
    func restore(fromBackup data: Data) throws {
        guard let backup = try? JSONDecoder().decode(Backup.self, from: data), backup.app == "fokus-wald" else {
            throw Backup.Problem.notABackup
        }
        // Ids written by browsers without crypto.randomUUID are not UUIDs; those entries get fresh ones.
        let plants = backup.plants.map {
            PlantRecord(id: UUID(uuidString: $0.id) ?? UUID(), date: Backup.parseDate($0.date), minutes: $0.minutes,
                        seed: $0.seed, speciesID: $0.speciesID, island: $0.island, tag: $0.tag, note: $0.note)
        }
        let decorations = (backup.decorations ?? []).compactMap { item -> Decoration? in
            guard let kind = Decoration.Kind(rawValue: item.kind), item.points.count >= 2 else { return nil }
            return Decoration(id: item.id.flatMap(UUID.init(uuidString:)) ?? UUID(), kind: kind, island: item.island,
                              points: item.points.map { CGPoint(x: $0.x, y: $0.y) })
        }
        let saplings = (backup.saplings ?? []).map {
            Sapling(id: UUID(uuidString: $0.id) ?? UUID(), date: Backup.parseDate($0.date), speciesID: $0.speciesID,
                    seed: $0.seed, progress: min(0.97, max(0, $0.progress)), elapsed: $0.elapsed)
        }
        restore(plants: plants, decorations: decorations, saplings: saplings, tags: backup.tags, weeklyGoal: backup.weeklyGoal)
    }
}

extension Backup {
    static func parseDate(_ text: String) -> Date { date(text) }
}

/// Lets SwiftUI's file exporter write a backup.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// "Save progress" and "load backup" buttons with their file dialogs; used in the settings of every platform.
struct BackupButtons: View {
    @ObservedObject var garden: Garden

    @State private var exporting = false
    @State private var importing = false
    @State private var pendingImport: Data?
    @State private var message: String?

    var body: some View {
        Group {
            Button { exporting = true } label: { Label("Fortschritt sichern", systemImage: "square.and.arrow.down") }
            Button { importing = true } label: { Label("Sicherung laden", systemImage: "square.and.arrow.up") }
        }
        .fileExporter(isPresented: $exporting, document: BackupDocument(data: garden.backupData()),
                      contentType: .json, defaultFilename: "fokus-wald-sicherung") { result in
            if case .success = result { message = "Sicherung gespeichert." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pendingImport = try? Data(contentsOf: url)
            if pendingImport == nil { message = "Die Datei konnte nicht gelesen werden." }
        }
        .confirmationDialog("Sicherung laden?", isPresented: Binding(get: { pendingImport != nil },
                                                                    set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible) {
            Button("Aktuellen Fortschritt ersetzen", role: .destructive) {
                guard let data = pendingImport else { return }
                do {
                    try garden.restore(fromBackup: data)
                    message = "Sicherung geladen."
                } catch {
                    message = "Diese Datei ist keine Fokus-Wald-Sicherung."
                }
                pendingImport = nil
            }
            Button("Abbrechen", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Dein jetziger Fortschritt auf diesem Gerät wird durch die Sicherung ersetzt.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
    }
}
