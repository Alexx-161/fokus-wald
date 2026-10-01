import AppKit
import Combine
import SwiftUI

/// Borderless, click-through panel that never takes focus.
/// Level `.statusBar` sits below Boring Notch's window (`.mainMenu + 3`), so if the two ever overlap,
/// Boring Notch stays on top and keeps receiving all mouse/hover events.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class NotchPanelController {
    private static let width: CGFloat = 116

    private let panel = NotchPanel()
    private let timer: FocusTimer
    private let settings: Preferences
    private var cancellables = Set<AnyCancellable>()
    private var showFinishedBadge = false
    private var finishedWork: DispatchWorkItem?
    private var wantsVisible = false

    init(timer: FocusTimer, settings: Preferences) {
        self.timer = timer
        self.settings = settings

        let host = NSHostingView(rootView: NotchWidgetView(timer: timer, settings: settings))
        host.sizingOptions = []
        panel.contentView = host

        timer.$phase
            .sink { [weak self] phase in self?.phaseChanged(to: phase) }
            .store(in: &cancellables)

        // @Published fires in willSet, so defer reading the new values until the next runloop turn.
        Publishers.MergeMany(
            settings.$notchEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$side.map { _ in () }.eraseToAnyPublisher(),
            settings.$gap.map { _ in () }.eraseToAnyPublisher(),
            settings.$onlyWhileActive.map { _ in () }.eraseToAnyPublisher(),
            settings.$previewing.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                .map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.update() }
        .store(in: &cancellables)
    }

    private func phaseChanged(to phase: FocusTimer.Phase) {
        finishedWork?.cancel()
        showFinishedBadge = phase == .finished
        if phase == .finished {
            let work = DispatchWorkItem { [weak self] in
                self?.showFinishedBadge = false
                self?.update()
            }
            finishedWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
        }
        DispatchQueue.main.async { [weak self] in self?.update() }
    }

    private func update() {
        let phase = timer.phase
        let active = phase == .running || phase == .paused || (phase == .finished && showFinishedBadge)
        let visible = settings.notchEnabled && (settings.previewing || !settings.onlyWhileActive || active)

        guard visible, let frame = targetFrame() else {
            hide()
            return
        }
        panel.setFrame(frame, display: true)
        wantsVisible = true
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        wantsVisible = false
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.wantsVisible else { return }
            self.panel.orderOut(nil)
        })
    }

    /// Places the panel in the menu-bar strip beside the notch, never over it.
    private func targetFrame() -> NSRect? {
        guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main else {
            return nil
        }
        let f = screen.frame
        let barHeight: CGFloat
        let notchMinX: CGFloat
        let notchMaxX: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            barHeight = left.height
            notchMinX = f.minX + left.width
            notchMaxX = f.maxX - right.width
        } else {
            barHeight = max(24, f.maxY - screen.visibleFrame.maxY)
            notchMinX = f.midX
            notchMaxX = f.midX
        }
        let gap = CGFloat(settings.gap)
        let width = Self.width
        var x = settings.side == .right ? notchMaxX + gap : notchMinX - gap - width
        x = min(max(x, f.minX), f.maxX - width)
        return NSRect(x: x, y: f.maxY - barHeight, width: width, height: barHeight)
    }
}

struct NotchWidgetView: View {
    @ObservedObject var timer: FocusTimer
    @ObservedObject var settings: Preferences

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 6) {
                Canvas { ctx, size in
                    let p = timer.progress(at: timeline.date)
                    // Zoom in on early stages so the seedling is still legible at icon size.
                    let unit = size.height * 0.95 / (0.2 + 0.4 * TreeMath.smooth(0, 1, p))
                    PlantPainter.draw(ctx, species: timer.species, base: CGPoint(x: size.width / 2, y: size.height),
                                      unit: unit, progress: p, seed: timer.seed, time: 0, ground: false, detail: false)
                }
                .frame(width: 18, height: 18)

                switch timer.phase {
                case .finished:
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.star)
                    Text("Fertig")
                case .paused:
                    Image(systemName: "pause.fill").font(.system(size: 8, weight: .bold)).opacity(0.7)
                    Text(TimeFormat.clock(timer.remaining(at: timeline.date))).opacity(0.6)
                case .idle, .running:
                    Text(TimeFormat.clock(timer.remaining(at: timeline.date)))
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(.black))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: settings.side == .right ? .leading : .trailing)
    }
}
