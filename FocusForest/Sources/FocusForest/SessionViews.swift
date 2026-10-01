import SwiftUI

// Pieces of the timer screen shared by the Mac app and the iPhone/iPad app.

enum TagPalette {
    static let colors: [Color] = [0x5FAF6A, 0xE07A99, 0x7183D9, 0xF2B93B, 0x4FB7C2, 0xDC8443, 0x9179D6, 0xC9473F]
        .map { Color(hex: $0) }

    static func color(_ tag: String?) -> Color {
        tag.map { colors[Garden.tagColorIndex($0)] } ?? Theme.muted
    }
}

enum SessionText {
    static func status(timer: FocusTimer, garden: Garden) -> String {
        let species = timer.species
        switch timer.phase {
        case .idle:
            if let sapling = timer.pending {
                let grown = TimeFormat.duration(minutes: max(1, Int(sapling.elapsed / 60)))
                return "Dein Setzling wächst weiter: \(species.name) · schon \(grown)"
            }
            return "Als Nächstes wächst: \(species.name)"
        case .running:
            return "\(species.name) wächst …"
        case .paused:
            return "Pausiert – deine Pflanze wartet auf dich"
        case .finished:
            if timer.isOnBreak { return "Gießzeit – streck dich kurz oder gestalte deine Insel." }
            guard let last = garden.plants.last else { return "\(species.name) steht jetzt auf deiner Insel!" }
            if garden.plants(on: last.island).count == Garden.islandCapacity {
                return "\(Garden.islandName(last.island)) ist vollendet! Eine neue Insel taucht auf."
            }
            return last.isGolden ? "\(species.name) steht jetzt auf deiner Insel – in Gold!"
                : "\(species.name) steht jetzt auf deiner Insel!"
        }
    }
}

/// What the session that just finished brought along: a new plant, a new resident, the weekly goal.
struct SessionHighlights: View {
    @ObservedObject var timer: FocusTimer
    @ObservedObject var garden: Garden

    private var unlocked: PlantSpecies? {
        PlantSpecies.all.first { $0.month == nil && $0.unlockAt > 0 && $0.unlockAt == garden.plants.count }
    }

    var body: some View {
        if timer.phase == .finished && !timer.isOnBreak {
            VStack(spacing: 4) {
                if let unlocked {
                    Label("Neu freigeschaltet: \(unlocked.name)", systemImage: "lock.open.fill").foregroundStyle(unlocked.deep)
                }
                if let resident = garden.newResident {
                    Label("Neu eingezogen: \(resident.name)", systemImage: "pawprint.fill").foregroundStyle(Palette.stem)
                }
                if garden.goalJustReached {
                    Label("Wochenziel erreicht – der Leuchtturm leuchtet!", systemImage: "light.beacon.max.fill")
                        .foregroundStyle(Color(hex: 0xD99A1E))
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
        }
    }
}

/// Chooses between growing the waiting sapling on and planting something new.
struct SaplingSwitch: View {
    @ObservedObject var garden: Garden

    var body: some View {
        if let sapling = garden.saplings.last {
            HStack(spacing: 6) {
                Button { garden.continueSapling = true } label: {
                    Label("Setzling · \(Int(sapling.progress * 100)) %", systemImage: "leaf")
                }
                .buttonStyle(ChipButtonStyle(selected: garden.continueSapling, color: sapling.species.deep))
                Button("Neue Pflanze") { garden.continueSapling = false }
                    .buttonStyle(ChipButtonStyle(selected: !garden.continueSapling, color: Palette.stem))
            }
        }
    }
}

/// The subject or project the next session counts towards.
struct TagChips: View {
    @ObservedObject var garden: Garden

    @State private var adding = false
    @State private var draft = ""

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill").font(.system(size: 11)).foregroundStyle(Theme.muted)
                ForEach(garden.tags, id: \.self) { tag in
                    Button(tag) { garden.currentTag = garden.currentTag == tag ? nil : tag }
                        .buttonStyle(ChipButtonStyle(selected: garden.currentTag == tag, color: TagPalette.color(tag)))
                        .contextMenu {
                            Button("„\(tag)“ entfernen", role: .destructive) { garden.removeTag(tag) }
                        }
                }
                if garden.tags.count < Garden.maxTags {
                    Button {
                        draft = ""
                        adding = true
                    } label: { Image(systemName: "plus") }
                    .buttonStyle(ChipButtonStyle(selected: false, color: Palette.stem))
                    .accessibilityLabel("Fach oder Projekt hinzufügen")
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .alert("Neues Fach oder Projekt", isPresented: $adding) {
            TextField("z. B. Mathe", text: $draft)
            Button("Hinzufügen") { garden.addTag(draft) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Ordne Sessions einem Fach zu – die Statistik zeigt dann, wohin deine Zeit geflossen ist.")
        }
    }
}

/// Tells that long sessions grow the golden variant.
struct GoldenHint: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        Group {
            if timer.growsGolden {
                Label("Diese Session lässt eine goldene Variante wachsen", systemImage: "sparkles")
                    .foregroundStyle(Color(hex: 0xD99A1E))
            } else {
                Text("Ab \(PlantSpecies.goldenMinutes) Minuten wächst eine goldene Variante")
                    .foregroundStyle(Theme.muted)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .multilineTextAlignment(.center)
    }
}

/// A one-line note for the plant that was just finished.
struct SessionNoteField: View {
    @ObservedObject var garden: Garden
    @State private var text = ""

    var body: some View {
        if let last = garden.plants.last {
            TextField("Notiz zu dieser Session (optional)", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Theme.track))
                .onAppear { text = last.note ?? "" }
                .onChange(of: text) { _, new in garden.setNote(new, for: last.id) }
        }
    }
}

/// The diary entry of one plant: when it grew, for how long, what for, and a note.
struct PlantDetailCard: View {
    let plant: PlantRecord
    @ObservedObject var garden: Garden
    var onClose: () -> Void

    @State private var note = ""

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlantIcon(species: plant.species, seed: plant.seed, golden: plant.isGolden)
                .frame(width: 58, height: 58)
                .background(Circle().fill(plant.species.light.opacity(0.35)))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(plant.species.name).font(.system(size: 14, weight: .bold, design: .rounded))
                    if plant.isGolden {
                        Label("Gold", systemImage: "sparkles")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: 0xD99A1E)))
                    }
                    Spacer(minLength: 0)
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(RoundIconButtonStyle(size: 22))
                        .accessibilityLabel("Schließen")
                }
                Text("\(Self.dateFormat.string(from: plant.date)) · \(TimeFormat.duration(minutes: plant.minutes))")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.muted)
                if let tag = plant.tag {
                    Label(tag, systemImage: "tag.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(TagPalette.color(tag))
                }
                TextField("Notiz hinzufügen", text: $note)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.track))
                    .onChange(of: note) { _, new in garden.setNote(new, for: plant.id) }
            }
        }
        .padding(12)
        .frame(maxWidth: 340)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
        .foregroundStyle(Theme.ink)
        .onAppear { note = plant.note ?? "" }
    }
}
