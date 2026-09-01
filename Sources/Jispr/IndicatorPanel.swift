import AppKit
import SwiftUI

/// Small floating pill at the bottom of the screen. Never takes focus.
@MainActor
final class IndicatorPanel {
    let model = IndicatorModel()
    private var panel: NSPanel?
    private var smoothedLevel: Float = 0

    func show(_ phase: IndicatorModel.Phase) {
        model.phase = phase
        model.level = 0
        smoothedLevel = 0
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func update(level: Float) {
        // Fast attack, slow release.
        smoothedLevel = level > smoothedLevel ? level : smoothedLevel * 0.8 + level * 0.2
        model.level = smoothedLevel
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 320, height: 96)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: IndicatorView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let area = screen.visibleFrame
        let origin = NSPoint(x: area.midX - panel.frame.width / 2, y: area.minY + 8)
        panel.setFrameOrigin(origin)
    }
}
