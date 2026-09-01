import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let controller = DictationController()
    private let hotkeys = HotkeyMonitor()
    private var trustTimer: Timer?
    private let accessibilityItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        controller.onStateChange = { [weak self] _ in self?.updateIcon() }
        hotkeys.onDoubleTapRightOption = { [weak self] in self?.controller.toggle() }
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
        let hint = NSMenuItem(title: "Double-tap Right ⌥ to dictate · Esc to stop", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

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

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }
}
