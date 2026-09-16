import AppKit
import CoreGraphics
import VMCore

/// Listens to the record key in every app through a listen-only event tap.
///
/// Needs Input Monitoring. The tap never swallows events, so fn keeps working
/// for the system and other apps.
public final class RecordKeyMonitor: @unchecked Sendable {
    public typealias Handler = @MainActor @Sendable (RecordKeyGesture.Input) -> Void

    private let key: AppSettings.RecordKey
    private let handler: Handler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var isDown = false

    public init(key: AppSettings.RecordKey, handler: @escaping Handler) {
        self.key = key
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Returns false when macOS refused the tap, usually because Input Monitoring is off.
    @discardableResult
    public func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: recordKeyTapCallback,
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
        isDown = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables slow taps; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .flagsChanged:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keycode == key.keycode else { return }
            let down = event.flags.contains(key.flag)
            guard down != isDown else { return }
            isDown = down
            let time = Double(event.timestamp) / 1_000_000_000
            emit(down ? .keyDown(time) : .keyUp(time))

        case .keyDown:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == 53 {
                emit(.escape)
            } else if isDown {
                emit(.otherKey)
            }

        default:
            break
        }
    }

    private func emit(_ input: RecordKeyGesture.Input) {
        let handler = handler
        Task { @MainActor in handler(input) }
    }
}

private func recordKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<RecordKeyMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}

extension AppSettings.RecordKey {
    /// Virtual keycodes from HIToolbox Events.h.
    var keycode: Int64 {
        switch self {
        case .fn: 63
        case .rightOption: 61
        case .rightCommand: 54
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .fn: .maskSecondaryFn
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        }
    }
}
