import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem?
    private let controller = DictationController()
    private let hotkeys = HotkeyMonitor()
    private var trustTimer: Timer?
    private let hintItem = NSMenuItem()
    private let accessibilityItem = NSMenuItem()
    private var modeItems: [NSMenuItem] = []
    private var engineItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        controller.onStateChange = { [weak self] _ in self?.updateIcon() }
        hotkeys.onDoubleTapRightOption = { [weak self] in self?.controller.handleDoubleTap() }
        hotkeys.onTapRightOption = { [weak self] in self?.controller.handleOptionTap() ?? false }
        hotkeys.onEscape = { [weak self] in self?.controller.handleEscape() ?? false }

        startHotkeysWhenTrusted()
        Log.app.info("Jispr launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.stop()
    }

    // MARK: - Hotkeys and permission

    private func startHotkeysWhenTrusted() {
        if Permissions.isAccessibilityTrusted(prompt: true) {
            hotkeys.start()
            updateMenu()
            return
        }
        Log.app.warning("Accessibility not granted yet; waiting")
        updateMenu()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, Permissions.isAccessibilityTrusted(prompt: false) else { return }
                self.trustTimer?.invalidate()
                self.trustTimer = nil
                self.hotkeys.start()
                self.updateMenu()
            }
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = icon(for: .idle)
        item.button?.toolTip = "Jispr"

        let menu = NSMenu()
        hintItem.isEnabled = false
        menu.addItem(hintItem)
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for mode in Mode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            modeMenu.addItem(item)
            modeItems.append(item)
        }
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let engineMenu = NSMenu()
        for kind in EngineKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(selectEngine(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            engineMenu.addItem(item)
            engineItems.append(item)
        }
        let engineItem = NSMenuItem(title: "Engine", action: nil, keyEquivalent: "")
        engineItem.submenu = engineMenu
        menu.addItem(engineItem)

        let transcribeItem = NSMenuItem(title: "Transcribe Audio File…", action: #selector(transcribeFile), keyEquivalent: "")
        transcribeItem.target = self
        menu.addItem(transcribeItem)

        accessibilityItem.target = self
        accessibilityItem.action = #selector(openAccessibility)
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Jispr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        updateMenu()
    }

    private func updateMenu() {
        hintItem.title = Mode.selected.hint
        for item in modeItems {
            item.state = (item.representedObject as? String) == Mode.selected.rawValue ? .on : .off
        }
        for item in engineItems {
            item.state = (item.representedObject as? String) == EngineKind.selected.rawValue ? .on : .off
        }
        if hotkeys.isRunning {
            accessibilityItem.title = "Accessibility: granted"
        } else {
            accessibilityItem.title = "Accessibility: not granted – open settings…"
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(transcribeFile) { return controller.state == .idle }
        return true
    }

    private func updateIcon() {
        statusItem?.button?.image = icon(for: controller.state)
    }

    private func icon(for state: DictationController.State) -> NSImage? {
        let name: String
        switch state {
        case .idle: name = "mic"
        case .recording: name = "record.circle.fill"
        default: name = "mic.fill"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Jispr")
        image?.isTemplate = true
        return image
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = Mode(rawValue: raw) else { return }
        Mode.selected = mode
        updateMenu()
    }

    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = EngineKind(rawValue: raw) else { return }
        EngineKind.selected = kind
        updateMenu()
        controller.engineSelectionChanged()
    }

    /// Pick an audio file; the transcript is saved as `.txt` next to it.
    @objc private func transcribeFile() {
        let panel = NSOpenPanel()
        panel.title = "Transcribe Audio File"
        panel.prompt = "Transcribe"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = Recordings.downloads
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller.transcribeFile(url)
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }
}
