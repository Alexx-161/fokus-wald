import AppKit
import SwiftUI

@main
struct FocusForestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Fokus-Wald", id: "timer") {
            MainView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 320, height: 640)

        MenuBarExtra {
            MenuBarMenu()
        } label: {
            MenuBarIcon()
        }
    }
}

/// Icon only (no running clock text) to keep the status item narrow so it isn't pushed behind the notch.
private struct MenuBarIcon: View {
    @ObservedObject private var timer = AppState.shared.timer

    var body: some View {
        Image(systemName: timer.phase == .running ? "leaf.fill" : "leaf")
    }
}

private struct MenuBarMenu: View {
    @ObservedObject private var timer = AppState.shared.timer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Timer öffnen") { show("timer") }
        Button("Insel ansehen") {
            show("timer")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { AppState.shared.expand(to: .island) }
        }
        Divider()
        switch timer.phase {
        case .idle: Button(timer.pending == nil ? "\(timer.minutes) min pflanzen" : "Setzling \(timer.minutes) min weiterziehen") { timer.start() }
        case .running: Button("Pause") { timer.pause() }
        case .paused: Button("Weiter") { timer.resume() }
        case .finished: Button(timer.isOnBreak ? "Gießzeit beenden" : "Neue Pflanze vorbereiten") { timer.reset() }
        }
        if timer.isActive {
            Button("Aufhören – als Setzling aufheben") { timer.giveUp() }
        }
        Divider()
        Button("Beenden") { NSApp.terminate(nil) }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchPanelController?
    private var miniTimer: MiniTimerController?
    private var extras: MacExtras?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState.shared
        notchController = NotchPanelController(timer: state.timer, settings: state.prefs)
        miniTimer = MiniTimerController(prefs: state.prefs)
        extras = MacExtras(timer: state.timer, prefs: state.prefs)
    }

    // The timer keeps running (and the notch widget stays) after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
