import AppKit
import Combine
import SwiftUI

/// Regular app windows can't enter another app's full-screen Space; a non-activating panel that joins
/// all Spaces as a full-screen auxiliary can, so the pinned timer lives in one.
final class MiniTimerPanel: NSPanel {
    static let size = NSSize(width: 250, height: 84)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class MiniTimerController {
    private let panel = MiniTimerPanel()
    private var cancellables = Set<AnyCancellable>()

    init(prefs: Preferences) {
        let host = NSHostingView(rootView: MiniTimerView())
        host.sizingOptions = []
        panel.contentView = host

        if !panel.setFrameUsingName("MiniTimer"), let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - MiniTimerPanel.size.width - 24,
                                         y: visible.maxY - MiniTimerPanel.size.height - 24))
        }
        panel.setFrameAutosaveName("MiniTimer")

        cancellables.insert(prefs.$pinned
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pinned in
                guard let self else { return }
                if pinned {
                    self.avoidNotchZone()
                    self.panel.orderFrontRegardless()
                } else {
                    self.panel.orderOut(nil)
                }
            })
        cancellables.insert(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.avoidNotchZone() })
    }

    /// Boring Notch keeps a transparent 640×210 pt window centered on the notch above ours, which would swallow
    /// clicks on the mini timer, so a timer dropped there slides just below it.
    private func avoidNotchZone() {
        guard let screen = panel.screen ?? NSScreen.main,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return }
        let f = screen.frame
        let notchMid = f.minX + left.width + (f.width - left.width - right.width) / 2
        let zone = NSRect(x: notchMid - 328, y: f.maxY - 218, width: 656, height: 218)
        guard panel.frame.intersects(zone) else { return }
        var frame = panel.frame
        frame.origin.y = zone.minY - frame.height - 8
        panel.setFrame(frame, display: true, animate: true)
    }
}

struct MiniTimerView: View {
    @ObservedObject private var timer = AppState.shared.timer

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            let p = timer.progress(at: timeline.date)
            let species = timer.species
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.card)
                    Circle().inset(by: 3).stroke(Theme.track, lineWidth: 4)
                    Circle().inset(by: 3).trim(from: 0, to: p)
                        .stroke(species.deep, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Canvas { ctx, size in
                        // Zoom in on early stages so the seedling stays visible at this small size.
                        let unit = size.height * 0.95 / (0.2 + 0.4 * TreeMath.smooth(0, 1, p))
                        PlantPainter.draw(ctx, species: species, base: CGPoint(x: size.width / 2, y: size.height),
                                          unit: unit, progress: p, seed: timer.seed,
                                          time: timeline.date.timeIntervalSinceReferenceDate, ground: false, detail: false)
                    }
                    .padding(12)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 1) {
                    Text(TimeFormat.clock(timer.remaining(at: timeline.date)))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .opacity(timer.phase == .paused ? 0.5 : 1)
                    Text(status(species))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(spacing: 6) {
                    Button(action: primaryAction) { Image(systemName: primarySymbol) }
                        .buttonStyle(RoundIconButtonStyle(size: 30, active: species.deep))
                        .help(primaryHelp)
                    HStack(spacing: 4) {
                        Button { AppState.shared.showMainWindow() } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(RoundIconButtonStyle(size: 20))
                        .help("Großes Fenster öffnen")
                        Button { AppState.shared.prefs.pinned = false } label: { Image(systemName: "xmark") }
                            .buttonStyle(RoundIconButtonStyle(size: 20))
                            .help("Mini-Timer schließen")
                    }
                }
            }
            .padding(.horizontal, 13)
            .frame(width: MiniTimerPanel.size.width, height: MiniTimerPanel.size.height)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.track, lineWidth: 1))
        }
        .foregroundStyle(Theme.ink)
        .fontDesign(.rounded)
    }

    private func status(_ species: PlantSpecies) -> String {
        switch timer.phase {
        case .idle: return "Bereit: \(species.name)"
        case .running: return "\(species.name) wächst …"
        case .paused: return "Pausiert"
        case .finished: return "Fertig – \(species.name)!"
        }
    }

    private var primarySymbol: String {
        switch timer.phase {
        case .idle: return "leaf.fill"
        case .running: return "pause.fill"
        case .paused: return "play.fill"
        case .finished: return "plus"
        }
    }

    private var primaryHelp: String {
        switch timer.phase {
        case .idle: return "Pflanzen"
        case .running: return "Pause"
        case .paused: return "Weiter"
        case .finished: return "Neue Pflanze"
        }
    }

    private func primaryAction() {
        switch timer.phase {
        case .idle: timer.start()
        case .running: timer.pause()
        case .paused: timer.resume()
        case .finished: timer.reset()
        }
    }
}
