import AppKit
import CoreGraphics

/// Catches key presses in every app and can swallow them, so a shortcut acts on saytype
/// instead of reaching the focused app.
///
/// Runs only while it is needed (the dictation card is on screen). Swallowing events needs
/// Accessibility; without it `start()` returns false and nothing is intercepted.
public final class KeyInterceptor: @unchecked Sendable {
    public struct Press: Sendable {
        /// Physical key, the same on every keyboard layout (HIToolbox `kVK_*`).
        public let keyCode: Int64
        public let command: Bool
        public let option: Bool
        public let control: Bool
        public let shift: Bool
        public let isRepeat: Bool

        public var hasModifiers: Bool { command || option || control || shift }
    }

    /// Return true to swallow the key press. Called on the main thread.
    public typealias Handler = @MainActor (Press) -> Bool

    private let handler: Handler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Keys whose key-down was swallowed; their key-up is swallowed too.
    private var swallowed: Set<Int64> = []

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    @discardableResult
    public func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: keyInterceptorCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    public func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
    }

    /// Returns true when the event must not reach other apps.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown, .keyUp:
            // Our own synthetic ⌘V from the paster must go through.
            guard event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(getpid()) else { return false }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if type == .keyUp {
                return swallowed.remove(keyCode) != nil
            }
            let flags = event.flags
            let press = Press(
                keyCode: keyCode,
                command: flags.contains(.maskCommand),
                option: flags.contains(.maskAlternate),
                control: flags.contains(.maskControl),
                shift: flags.contains(.maskShift),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
            // Event taps call back on the run loop they were added to: the main one.
            let swallow = MainActor.assumeIsolated { handler(press) }
            if swallow { swallowed.insert(keyCode) }
            return swallow
        default:
            return false
        }
    }
}

private func keyInterceptorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
    return interceptor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
