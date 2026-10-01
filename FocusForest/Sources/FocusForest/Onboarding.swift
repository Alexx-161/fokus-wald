import SwiftUI
#if os(macOS)
import AppKit
#endif

struct OnboardingView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var timer: FocusTimer
    @ObservedObject var garden: Garden
    var onFinish: () -> Void

    @State private var page = 0
    @State private var forward = true
    private let pageCount = 5

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                if page < pageCount - 1 {
                    Button("Überspringen", action: onFinish)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(height: 18)

            GeometryReader { geo in
                ScrollView(.vertical) {
                    content
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
                .id(page)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxHeight: .infinity)
            .clipped()

            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Palette.stem : Theme.track)
                        .frame(width: i == page ? 18 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)

            HStack(spacing: 8) {
                if page > 0 {
                    Button("Zurück") { go(-1) }.buttonStyle(SoftButtonStyle())
                }
                Button(page == pageCount - 1 ? "Los geht's!" : "Weiter") {
                    if page == pageCount - 1 { onFinish() } else { go(1) }
                }
                .buttonStyle(PrimaryButtonStyle(color: Palette.stem))
            }
            .id(prefs.themeID)
        }
        .padding(22)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { page += delta }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case 0: welcome
        case 1: howItWorks
        case 2: themePage
        case 3: firstPlant
        default: extras
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let cycle = 6.5
                let showcase = ["kirsche", "tulpe", "fliegenpilz", "tanne", "sonnenblume", "regenbogenbaum"]
                let species = PlantSpecies.find(showcase[Int(t / cycle) % showcase.count])
                let p = TreeMath.smooth(0.3, 4.8, t.truncatingRemainder(dividingBy: cycle))
                ZStack {
                    Circle().fill(Theme.card).shadow(color: .black.opacity(0.06), radius: 12, y: 5)
                    Canvas { ctx, size in
                        PlantPainter.draw(ctx, species: species, base: CGPoint(x: size.width / 2, y: size.height * 0.84),
                                          unit: size.width, progress: p, seed: 0.42, time: t)
                    }
                    .padding(30)
                }
                .frame(width: 210, height: 210)
            }
            VStack(spacing: 8) {
                Text("Willkommen im Fokus-Wald")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Konzentrier dich – und schau zu, wie dabei etwas Schönes wächst.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("So funktioniert's").font(.system(size: 22, weight: .bold, design: .rounded))
            IslandThumbnail(plants: Self.demoPlants, decorations: Self.demoDecorations, complete: false)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            step("timer", "Zeit wählen & pflanzen", "Stell ein, wie lange du dich konzentrieren willst.")
            step("leaf.fill", "Deine Pflanze wächst mit", "Solange du fokussiert bleibst, wächst sie vom Keimling zur vollen Pracht.")
            step("mountain.2.fill", "Deine Insel füllt sich", "Jede Session pflanzt sie auf deine Insel. Bei 30 Pflanzen ist sie vollendet – und eine neue taucht auf.")
            Spacer(minLength: 0)
        }
    }

    private var themePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wähle deinen Stil").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Du kannst das Theme später jederzeit in den Einstellungen ändern.")
                .font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(AppTheme.all) { theme in
                    Button { prefs.themeID = theme.id } label: {
                        VStack(spacing: 6) {
                            ThemeSwatch(theme: theme).frame(height: 70)
                            Text(theme.name).font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(prefs.themeID == theme.id ? Palette.stem : .clear, lineWidth: 2.5))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var firstPlant: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Was soll zuerst wachsen?").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Mit jeder Session schaltest du weitere Pflanzen frei – bis hin zu Pilzen und Kristallbäumen.")
                .font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                choice(selected: garden.selection == Garden.randomSelection, title: "Überraschung") {
                    Image(systemName: "dice.fill").font(.system(size: 26)).foregroundStyle(Palette.stem)
                } action: { garden.selection = Garden.randomSelection }
                ForEach(PlantSpecies.all.filter(garden.isUnlocked)) { species in
                    choice(selected: garden.selection == species.id, title: species.name) {
                        PlantIcon(species: species)
                    } action: { garden.selection = species.id }
                }
            }
            Text("Wie lange möchtest du dich konzentrieren?")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(spacing: 6) {
                ForEach([15, 25, 45, 60], id: \.self) { m in
                    Button("\(m) min") { timer.minutes = m }
                        .buttonStyle(ChipButtonStyle(selected: timer.minutes == m, color: Palette.stem))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fast geschafft!").font(.system(size: 22, weight: .bold, design: .rounded))
            VStack(alignment: .leading, spacing: 12) {
                #if os(macOS)
                if Self.hasNotch {
                    Toggle(isOn: $prefs.notchEnabled) {
                        option("Anzeige neben der Notch", "Kleine Pille mit Restzeit oben neben der Notch.")
                    }
                }
                Toggle(isOn: $prefs.pinned) {
                    option("Mini-Timer anheften", "Schwebt über allen Fenstern – auch über Apps im Vollbild.")
                }
                #else
                Toggle(isOn: $prefs.liveActivity) {
                    option("Live-Anzeige", "Zeigt deine Session in der Dynamic Island und auf dem Sperrbildschirm.")
                }
                Toggle(isOn: $prefs.notify) {
                    option("Mitteilung bei Ablauf", "Meldet sich, wenn deine Pflanze fertig gewachsen ist.")
                }
                #endif
            }
            .toggleStyle(.switch)
            .tint(Palette.stem)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))

            #if os(macOS)
            step("leaf", "Immer griffbereit", "Das Blatt oben in der Menüleiste startet und pausiert den Timer.")
            step("arrow.up.left.and.arrow.down.right", "Mehr Platz, mehr Features",
                 "Zieh das Fenster größer oder nutze den Vollbildmodus für Insel, Katalog und Statistik.")
            #else
            step("lock.fill", "Leg das iPhone ruhig weg", "Der Timer läuft weiter, auch wenn die App geschlossen ist.")
            step("map.fill", "Mehr entdecken",
                 "Unter „Insel“ kannst du zoomen und Wege, Flüsse und Brücken malen. „Pflanzen“ zeigt alles, was du freischalten kannst.")
            #endif
            Spacer(minLength: 0)
        }
    }

    // MARK: Building blocks

    private func step(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.stem))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(text).font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func option(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(text).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choice<Icon: View>(selected: Bool, title: String, @ViewBuilder icon: () -> Icon,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                icon().frame(width: 52, height: 48)
                Text(title).font(.system(size: 10, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Palette.stem : .clear, lineWidth: 2.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    #if os(macOS)
    private static let hasNotch = NSScreen.screens.contains { $0.auxiliaryTopLeftArea != nil }
    #endif

    private static let demoPlants: [PlantRecord] = ["minze", "tulpe", "kirsche", "tanne", "sonnenblume", "fliegenpilz", "lavendel", "gaensebluemchen"]
        .enumerated().map { PlantRecord(minutes: 25, seed: 0.2 + Double($0.offset) * 0.09, speciesID: $0.element, island: 0) }

    private static let demoDecorations = [
        Decoration(id: UUID(), kind: .path, island: 0,
                   points: [CGPoint(x: -3.2, y: 0.9), CGPoint(x: -1.4, y: 1.1), CGPoint(x: 0.4, y: 1.4), CGPoint(x: 2.6, y: 1.0)]),
    ]
}
