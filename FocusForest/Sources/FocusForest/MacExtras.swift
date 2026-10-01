import AppKit
import Carbon.HIToolbox
import Combine

/// A system-wide keyboard shortcut. Carbon hot keys need no accessibility permission.
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit { unregister() }

    /// ⌃⌥F
    func register() {
        guard hotKey == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        // "FkWd"
        let id = EventHotKeyID(signature: 0x466B_5764, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}

/// The Mac-only conveniences: global hot key, URL commands and shortcuts that run around a session.
final class MacExtras: NSObject {
    private let timer: FocusTimer
    private let prefs: Preferences
    private lazy var hotKey = GlobalHotKey { [timer] in timer.toggle() }
    private var cancellables = Set<AnyCancellable>()
    private var focusIsOn = false

    init(timer: FocusTimer, prefs: Preferences) {
        self.timer = timer
        self.prefs = prefs
        super.init()

        prefs.$hotkeyEnabled
            .sink { [weak self] enabled in
                if enabled { self?.hotKey.register() } else { self?.hotKey.unregister() }
            }
            .store(in: &cancellables)

        // macOS has no public switch for "Do Not Disturb"; a shortcut the user made can flip a Focus mode instead.
        timer.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in self?.sessionChanged(to: phase) }
            .store(in: &cancellables)

        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    private func sessionChanged(to phase: FocusTimer.Phase) {
        let wanted = phase == .running || phase == .paused
        guard wanted != focusIsOn else { return }
        focusIsOn = wanted
        guard prefs.focusShortcuts else { return }
        Self.runShortcut(named: wanted ? prefs.focusOnShortcut : prefs.focusOffShortcut)
    }

    static func runShortcut(named name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        try? process.run()
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: text) else { return }
        URLCommand.run(url, timer: timer)
    }
}
