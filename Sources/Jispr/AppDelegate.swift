import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let controller = DictationController()
    private let hotkeys = HotkeyMonitor()
    private var trustTimer: Timer?
    private let accessibilityItem = NSMenuItem()
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
        item.button?.image = icon(filled: false)
        item.button?.toolTip = "Jispr"

        let menu = NSMenu()
        let hint = NSMenuItem(title: "Double-tap Right ⌥ to dictate · tap ⌥ to paste · Esc to abort", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

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
        for item in engineItems {
            item.state = (item.representedObject as? String) == EngineKind.selected.rawValue ? .on : .off
        }
        if hotkeys.isRunning {
            accessibilityItem.title = "Accessibility: granted"
        } else {
            accessibilityItem.title = "Accessibility: not granted – open settings…"
        }
    }

    private func updateIcon() {
        statusItem?.button?.image = icon(filled: controller.state != .idle)
    }

    private func icon(filled: Bool) -> NSImage? {
        let name = filled ? "mic.fill" : "mic"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Jispr")
        image?.isTemplate = true
        return image
    }

    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = EngineKind(rawValue: raw) else { return }
        EngineKind.selected = kind
        updateMenu()
        controller.engineSelectionChanged()
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }
}
