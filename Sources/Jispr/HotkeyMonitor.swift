import CoreGraphics
import Foundation

/// Global keyboard tap. Detects a double tap of the right Option key and the Escape key.
/// Runs on the main thread (the tap's run loop source is added to the main run loop).
@MainActor
final class HotkeyMonitor {
    /// Fired on every clean single tap of the right Option key.
    /// Return true to consume it; a consumed tap does not count toward a double tap.
    var onTapRightOption: (() -> Bool)?
    /// Fired after two quick taps of the right Option key (when the first was not consumed).
    var onDoubleTapRightOption: (() -> Void)?
    /// Fired on Escape. Return true to swallow the key so the front app never sees it.
    var onEscape: (() -> Bool)?

    /// Max time the key may be held for one press to count as a tap.
    var maxTapDuration: TimeInterval = 0.35
    /// Max gap between the two taps.
    var maxDoubleTapInterval: TimeInterval = 0.45

    private static let rightOptionKeyCode: Int64 = 61  // kVK_RightOption
    private static let escapeKeyCode: Int64 = 53       // kVK_Escape
    private static let rightOptionDeviceFlag: UInt64 = 0x40  // NX_DEVICERALTKEYMASK

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var optionDownTime: TimeInterval?
    private var otherKeyDuringHold = false
    private var lastTapTime: TimeInterval = 0

    var isRunning: Bool { tap != nil }

    /// Returns false when the tap could not be created (usually: no Accessibility permission).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (CGEventMask(1) << CGEventMask(CGEventType.flagsChanged.rawValue)) |
            (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue))
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            Log.hotkey.error("Could not create event tap (Accessibility permission missing?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        Log.hotkey.info("Event tap started")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Log.hotkey.warning("Event tap was disabled; re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keyCode == Self.rightOptionKeyCode else {
                // Another modifier changed: this is not a clean tap sequence.
                resetSequence()
                return pass
            }
            let now = ProcessInfo.processInfo.systemUptime
            let isDown = (event.flags.rawValue & Self.rightOptionDeviceFlag) != 0
                || event.flags.contains(.maskAlternate)
            if isDown {
                optionDownTime = now
                otherKeyDuringHold = false
            } else {
                let downTime = optionDownTime
                optionDownTime = nil
                guard let downTime, !otherKeyDuringHold, now - downTime <= maxTapDuration else {
                    lastTapTime = 0
                    return pass
                }
                if onTapRightOption?() == true {
                    lastTapTime = 0
                    return pass
                }
                if now - lastTapTime <= maxDoubleTapInterval {
                    lastTapTime = 0
                    Log.hotkey.debug("Double tap of right Option")
                    onDoubleTapRightOption?()
                } else {
                    lastTapTime = now
                }
            }
            return pass

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            // Any real key press breaks a pending Option tap sequence.
            otherKeyDuringHold = true
            lastTapTime = 0
            if keyCode == Self.escapeKeyCode, onEscape?() == true {
                return nil  // swallow
            }
            return pass

        default:
            return pass
        }
    }

    private func resetSequence() {
        optionDownTime = nil
        otherKeyDuringHold = false
        lastTapTime = 0
    }
}
