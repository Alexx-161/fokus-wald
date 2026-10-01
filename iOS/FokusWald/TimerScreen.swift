import SwiftUI

struct TimerScreen: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var timer = AppModel.shared.timer
    @ObservedObject private var garden = AppModel.shared.garden
    @State private var showSettings = false
    @State private var confirmGiveUp = false

    private var species: PlantSpecies { timer.species }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill").foregroundStyle(species.deep)
                Text("Fokus-Wald").font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(RoundIconButtonStyle(size: 34))
                    .accessibilityLabel("Einstellungen")
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                VStack(spacing: 10) {
                    stage(at: timeline.date)
                    clock(at: timeline.date)
                }
            }

            VStack(spacing: 5) {
                Text(SessionText.status(timer: timer, garden: garden))
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                SessionHighlights(timer: timer, garden: garden)
            }

            if timer.phase == .idle {
                SaplingSwitch(garden: garden)
                if timer.pending == nil { speciesChip }
                HStack(spacing: 7) {
                    ForEach([15, 25, 45, 60], id: \.self) { m in
                        Button("\(m) min") { timer.minutes = m }
                            .buttonStyle(ChipButtonStyle(selected: timer.minutes == m, color: species.deep))
                    }
                }
                TagChips(garden: garden)
                GoldenHint(timer: timer)
            }
            if timer.phase == .finished && !timer.isOnBreak {
                SessionNoteField(garden: garden)
            }
            controls
            if confirmGiveUp {
                Text("Keine Sorge: Sie bleibt als Setzling auf deiner Insel und wächst beim nächsten Mal weiter.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: timer.phase)
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }

    private func stage(at date: Date) -> some View {
        let p = timer.progress(at: date)
        return ZStack {
            Circle().fill(Theme.card).shadow(color: .black.opacity(0.07), radius: 14, y: 6)
            Circle().inset(by: 9).stroke(Theme.track, lineWidth: 8)
            Circle().inset(by: 9).trim(from: 0, to: p)
                .stroke(species.deep, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Canvas { ctx, size in
                let base = CGPoint(x: size.width / 2, y: size.height * 0.84)
                let t = date.timeIntervalSinceReferenceDate
                PlantPainter.draw(ctx, species: species, base: base, unit: size.width, progress: p, seed: timer.seed,
                                  time: t, golden: timer.growsGolden)
                if timer.isOnBreak {
                    LivingPainter.drawWateringCan(ctx, at: CGPoint(x: base.x + size.width * 0.26, y: base.y - size.width * 0.66),
                                                  unit: size.width, time: t)
                }
            }
            .padding(38)
            if timer.phase == .finished && !timer.isOnBreak {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(Palette.star)
                    .symbolEffect(.pulse)
                    .offset(x: 88, y: -88)
            }
        }
        .frame(width: 264, height: 264)
    }

    private func clock(at date: Date) -> some View {
        HStack(spacing: 18) {
            if timer.phase == .idle {
                Button { timer.adjustMinutes(up: false) } label: { Image(systemName: "minus") }
                    .buttonStyle(RoundIconButtonStyle(size: 38))
                    .accessibilityLabel("Kürzer")
            }
            Text(TimeFormat.clock(timer.isOnBreak ? timer.breakRemaining(at: date) : timer.remaining(at: date)))
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .opacity(timer.phase == .paused ? 0.5 : 1)
            if timer.phase == .idle {
                Button { timer.adjustMinutes(up: true) } label: { Image(systemName: "plus") }
                    .buttonStyle(RoundIconButtonStyle(size: 38))
                    .accessibilityLabel("Länger")
            }
        }
    }

    private var speciesChip: some View {
        Button { model.tab = .catalog } label: {
            HStack(spacing: 8) {
                PlantIcon(species: species, seed: timer.seed).frame(width: 30, height: 30)
                Text(garden.selection == Garden.randomSelection ? "Überraschung" : species.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .padding(.leading, 7).padding(.trailing, 14).padding(.vertical, 5)
            .background(Capsule().fill(Theme.track))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auswählen, was wachsen soll")
    }

    @ViewBuilder
    private var controls: some View {
        switch timer.phase {
        case .idle:
            Button { model.start() } label: {
                Label(timer.pending == nil ? "Pflanzen" : "Weiterwachsen lassen", systemImage: "leaf.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: species.deep))
        case .running, .paused:
            HStack(spacing: 10) {
                if timer.phase == .running {
                    Button { timer.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                        .buttonStyle(SoftButtonStyle())
                } else {
                    Button { timer.resume() } label: { Label("Weiter", systemImage: "play.fill") }
                        .buttonStyle(PrimaryButtonStyle(color: species.deep))
                }
                Button(confirmGiveUp ? "Wirklich?" : "Aufhören") {
                    if confirmGiveUp {
                        confirmGiveUp = false
                        timer.giveUp()
                    } else {
                        confirmGiveUp = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmGiveUp = false }
                    }
                }
                .buttonStyle(SoftButtonStyle(tint: confirmGiveUp ? Color(hex: 0xE07A7A) : nil))
            }
        case .finished:
            HStack(spacing: 10) {
                if timer.isOnBreak {
                    Button { model.tab = .island } label: { Label("Insel", systemImage: "paintbrush.fill") }
                        .buttonStyle(SoftButtonStyle())
                    Button { timer.reset() } label: { Label("Pause beenden", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle(color: species.deep))
                } else {
                    Button { timer.startBreak(minutes: garden.breakMinutes) } label: {
                        Label("Gießzeit · \(garden.breakMinutes) min", systemImage: "drop.fill")
                    }
                    .buttonStyle(SoftButtonStyle())
                    Button { timer.reset() } label: { Label("Weiter", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle(color: species.deep))
                }
            }
        }
    }
}

struct SettingsSheet: View {
    @ObservedObject private var prefs = AppModel.shared.prefs
    @ObservedObject private var garden = AppModel.shared.garden
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme: \(AppTheme.find(prefs.themeID).name)") {
                    HStack(spacing: 10) {
                        ForEach(AppTheme.all) { theme in
                            Button { prefs.themeID = theme.id } label: {
                                ThemeSwatch(theme: theme)
                                    .frame(width: 50, height: 50)
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(prefs.themeID == theme.id ? Palette.stem : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(theme.name)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Section {
                    Toggle("Live-Anzeige", isOn: $prefs.liveActivity)
                    Toggle("Mitteilung bei Ablauf", isOn: $prefs.notify)
                } footer: {
                    Text("Die Live-Anzeige zeigt deine Session in der Dynamic Island und auf dem Sperrbildschirm.")
                }
                Section {
                    Toggle("Ton bei Ablauf", isOn: $prefs.sound)
                    Toggle("Vibration bei Ablauf", isOn: $prefs.haptics)
                    Toggle("Bildschirm anlassen", isOn: $prefs.keepAwake)
                }
                Section {
                    Toggle("Tageszeit & Jahreszeit", isOn: $garden.livingSky)
                    Stepper("Gießzeit: \(garden.breakMinutes) min", value: $garden.breakMinutes, in: 1...30)
                } footer: {
                    Text("Der Himmel über deiner Insel folgt der echten Uhrzeit, das Wetter dem Monat. Die Gießzeit ist die Pause nach einer Session.")
                }
                Section {
                    BackupButtons(garden: garden)
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { AppModel.shared.showOnboarding = true }
                    } label: {
                        Label("Einführung erneut ansehen", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Dein Fortschritt wird nur auf diesem Gerät gespeichert. Die Sicherung lässt sich auch in der Web-App und der Mac-App laden – und umgekehrt.")
                }
            }
            .tint(Palette.stem)
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .onChange(of: prefs.notify) { _, on in
                if on { AppModel.shared.requestNotificationPermission() }
            }
        }
        .fontDesign(.rounded)
        .id(prefs.themeID)
    }
}
