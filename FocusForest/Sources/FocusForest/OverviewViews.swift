import SwiftUI

// MARK: Catalog

struct CatalogView: View {
    @ObservedObject var garden: Garden
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Wähle, was in deiner nächsten Session wachsen soll. Mit jeder Session schaltest du neue Pflanzen frei.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.muted)

                RandomCard(selected: garden.selection == Garden.randomSelection) {
                    garden.selection = Garden.randomSelection
                }
                .frame(maxWidth: 420, alignment: .leading)

                ForEach(PlantCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(category.title, systemImage: category.symbol)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(PlantSpecies.all.filter { $0.category == category }) { species in
                                SpeciesCard(species: species,
                                            unlocked: garden.isUnlocked(species),
                                            missing: species.unlockAt - garden.plants.count,
                                            planted: garden.count(of: species),
                                            selected: garden.selection == species.id) {
                                    garden.selection = species.id
                                }
                            }
                        }
                    }
                }
            }
            .padding(4)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SpeciesCard: View {
    let species: PlantSpecies
    let unlocked: Bool
    let missing: Int
    let planted: Int
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(species.light.opacity(0.35)).frame(width: 96, height: 96)
                    PlantIcon(species: species).frame(width: 100, height: 96)
                        .saturation(unlocked ? 1 : 0)
                        .opacity(unlocked ? 1 : 0.35)
                    if !unlocked {
                        Image(systemName: "lock.fill").font(.system(size: 20)).foregroundStyle(Theme.muted)
                    }
                }
                Text(species.name).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(species.blurb)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                Group {
                    if !unlocked {
                        Label(missing == 1 ? "noch 1 Session" : "noch \(missing) Sessions", systemImage: "lock.fill")
                    } else if planted > 0 {
                        Text("\(planted)× gepflanzt")
                    } else {
                        Text("noch nie gepflanzt")
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(selected ? species.deep : Theme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? species.deep : .clear, lineWidth: 2.5))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(species.deep).padding(8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}

private struct RandomCard: View {
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "dice.fill").font(.system(size: 26)).foregroundStyle(Palette.stem)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Überraschung").font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Jedes Mal eine zufällige freigeschaltete Pflanze")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.stem) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Palette.stem : .clear, lineWidth: 2.5))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

/// Compact chooser shown as a popover from the small timer window.
struct SpeciesPickerList: View {
    @ObservedObject var garden: Garden
    var onPick: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                row(icon: AnyView(Image(systemName: "dice.fill").foregroundStyle(Palette.stem)), title: "Überraschung",
                    detail: nil, selected: garden.selection == Garden.randomSelection, enabled: true) {
                    garden.selection = Garden.randomSelection
                }
                ForEach(PlantCategory.allCases) { category in
                    Text(category.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 8).padding(.leading, 8)
                    ForEach(PlantSpecies.all.filter { $0.category == category }) { s in
                        let unlocked = garden.isUnlocked(s)
                        row(icon: AnyView(PlantIcon(species: s).saturation(unlocked ? 1 : 0).opacity(unlocked ? 1 : 0.4)),
                            title: s.name,
                            detail: unlocked ? nil : "ab \(s.unlockAt) Sessions",
                            selected: garden.selection == s.id, enabled: unlocked) {
                            garden.selection = s.id
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 250, height: 360)
        .fontDesign(.rounded)
    }

    private func row(icon: AnyView, title: String, detail: String?, selected: Bool, enabled: Bool,
                     action: @escaping () -> Void) -> some View {
        Button {
            action()
            onPick()
        } label: {
            HStack(spacing: 10) {
                icon.frame(width: 28, height: 28)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if let detail {
                    Label(detail, systemImage: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.muted)
                } else if selected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.stem)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.track : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: Statistics

struct StatsView: View {
    @ObservedObject var garden: Garden

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEEEE"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    StatTile(value: "\(garden.plants.count)", label: "Pflanzen", symbol: "leaf.fill")
                    StatTile(value: TimeFormat.duration(minutes: garden.totalMinutes), label: "Fokuszeit", symbol: "clock.fill")
                    StatTile(value: "\(garden.todayCount)", label: "heute", symbol: "sun.max.fill")
                    StatTile(value: "\(garden.streak) \(garden.streak == 1 ? "Tag" : "Tage")", label: "Serie", symbol: "flame.fill")
                    StatTile(value: "\(garden.currentIsland)", label: "Inseln vollendet", symbol: "flag.fill")
                }

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fokus der letzten 7 Tage").font(.system(size: 14, weight: .semibold, design: .rounded))
                        weekChart
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)], spacing: 12) {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lieblingspflanze").font(.system(size: 14, weight: .semibold, design: .rounded))
                            if let fav = garden.favoriteSpecies {
                                HStack(spacing: 10) {
                                    PlantIcon(species: fav).frame(width: 52, height: 52)
                                    VStack(alignment: .leading) {
                                        Text(fav.name).font(.system(size: 13, weight: .semibold, design: .rounded))
                                        Text("\(garden.count(of: fav))× gepflanzt")
                                            .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.muted)
                                    }
                                }
                            } else {
                                Text("Pflanze deine erste Pflanze!").font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nächste Freischaltung").font(.system(size: 14, weight: .semibold, design: .rounded))
                            if let next = garden.nextUnlock {
                                HStack(spacing: 10) {
                                    PlantIcon(species: next).frame(width: 52, height: 52).saturation(0).opacity(0.5)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(next.name).font(.system(size: 13, weight: .semibold, design: .rounded))
                                        CapacityBar(filled: garden.plants.count, total: next.unlockAt)
                                    }
                                }
                            } else {
                                Text("Alles freigeschaltet – Wahnsinn!").font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
        .scrollIndicators(.hidden)
    }

    private var weekChart: some View {
        let days = garden.minutesPerDay(last: 7)
        let maxMinutes = max(25, days.map(\.minutes).max() ?? 0)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(days, id: \.day) { entry in
                VStack(spacing: 6) {
                    Text(entry.minutes > 0 ? "\(entry.minutes)" : "")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Calendar.current.isDateInToday(entry.day) ? Palette.stem : Palette.grass)
                        .frame(height: max(4, 120 * CGFloat(entry.minutes) / CGFloat(maxMinutes)))
                    Text(Self.weekday.string(from: entry.day))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 160, alignment: .bottom)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Palette.stem)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }
}

// MARK: Archipelago

struct ArchipelagoView: View {
    @ObservedObject var garden: Garden
    var onOpen: (Int) -> Void

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hat eine Insel \(Garden.islandCapacity) Pflanzen, ist sie vollendet: Sie bekommt ein Fähnchen, wandert in dein Archipel, und eine neue Insel taucht auf.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach((0...garden.currentIsland).reversed(), id: \.self) { index in
                        Button { onOpen(index) } label: { islandCard(index) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(4)
        }
        .scrollIndicators(.hidden)
    }

    private func islandCard(_ index: Int) -> some View {
        let complete = garden.isComplete(index)
        return VStack(alignment: .leading, spacing: 8) {
            IslandThumbnail(plants: garden.plants(on: index), decorations: garden.decorations(on: index), complete: complete)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack {
                Text(Garden.islandName(index)).font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                if complete { Image(systemName: "flag.fill").foregroundStyle(Palette.flag) }
            }
            Group {
                if complete, let date = garden.completionDate(of: index) {
                    Text("Vollendet am \(Self.dateFormat.string(from: date))")
                } else {
                    Text("Wächst gerade · \(garden.plants(on: index).count) / \(Garden.islandCapacity)")
                }
            }
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(Theme.muted)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}
