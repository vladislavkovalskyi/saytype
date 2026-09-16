import AppKit
import Combine
import SwiftUI
import VMCore

/// Step 3: the record key, a live check that it is held, and the Globe key conflict.
struct KeyStep: View {
    @Environment(AppModel.self) private var model
    @State private var probe = KeyHoldProbe()
    @State private var globe = GlobeUsage.current()

    var body: some View {
        @Bindable var settings = model.settings
        let key = settings.value.recordKey
        ZStack(alignment: .topLeading) {
            HeroObject(
                name: "ObjectKeycap",
                halo: CGRect(x: 40, y: 90, width: 480, height: 420),
                object: CGRect(x: 66, y: 105, width: 428, height: 390)
            )

            if let since = probe.heldSince {
                HoldReadout(key: key, since: since)
                    .frame(width: 210)
                    .place(x: 196, y: 470)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            VStack(alignment: .leading, spacing: 0) {
                StepTitle("Hold \(key.inlineName)")
                StepSubtitle("Hold: record. Release: paste. Double-press: hands-free.")
                    .padding(.top, 12)
                Text("Key")
                    .font(.onest(12.5, .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 28)
                HStack(spacing: 8) {
                    ForEach(AppSettings.RecordKey.allCases, id: \.self) { option in
                        KeyChip(title: option.title, selected: option == key) {
                            settings.value.recordKey = option
                        }
                    }
                }
                .padding(.top, 10)

                if key == .fn, let warning = globe.warning {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 16, weight: .regular))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(warning).font(.onest(14, .semibold))
                            Muted("Keyboard › Press Globe key to")
                        }
                        Spacer(minLength: 0)
                        WhiteButton(title: "Turn Off") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.leading, 16)
                    .padding(.trailing, 12)
                    .frost()
                    .padding(.top, 22)
                    .transition(.opacity)
                }
            }
            .frame(width: OnboardingLayout.column.width, alignment: .leading)
            .place(x: OnboardingLayout.column.minX, y: OnboardingLayout.column.minY)
        }
        .stepCanvas()
        .animation(.snappy(duration: 0.2), value: probe.heldSince == nil)
        .animation(.snappy(duration: 0.25), value: key)
        .onAppear {
            probe.key = key
            probe.start()
            globe = GlobeUsage.current()
        }
        .onDisappear { probe.stop() }
        .onChange(of: key) { _, new in probe.key = new }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            globe = GlobeUsage.current()
        }
    }
}

private struct KeyChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if selected {
                label
                    .foregroundStyle(Color(hex: 0x1D1A20))
                    .background(Capsule().fill(.white).shadow(color: Color(hex: 0x140A1E, opacity: 0.18), radius: 7, y: 4))
            } else {
                label.frost(cornerRadius: 16)
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        Text(title)
            .font(.onest(13, selected ? .semibold : .medium))
            .padding(.horizontal, 13)
            .frame(height: 32)
            .contentShape(Capsule())
    }
}

/// "fn held · 0.42 sec" while the key is down.
private struct HoldReadout: View {
    let key: AppSettings.RecordKey
    let since: Date

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .background(Circle().fill(.white.opacity(0.25)).frame(width: 16, height: 16))
                .shadow(color: .white, radius: 6)
            TimelineView(.animation(minimumInterval: 0.03)) { context in
                let seconds = max(0, context.date.timeIntervalSince(since))
                HStack(spacing: 0) {
                    Text("\(key.title) held", comment: "Readout while the record key is down, followed by the time")
                    Text(verbatim: " · ")
                    Text(Duration.seconds(seconds), format: .units(allowed: [.seconds], width: .abbreviated, fractionalPart: .show(length: 2)))
                        .font(.mono(12.5, .medium))
                        .monospacedDigit()
                }
            }
            .font(.onest(13.5, .medium))
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(height: 36)
        .frost(cornerRadius: 18)
        .fixedSize()
    }
}

/// Watches the record key through a local monitor while the step is on screen.
/// Works without Input Monitoring because the onboarding window is key.
@MainActor
@Observable
final class KeyHoldProbe {
    private(set) var heldSince: Date?
    var key = AppSettings.RecordKey.fn {
        didSet { heldSince = nil }
    }

    @ObservationIgnored private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        heldSince = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == key.keyCode else { return }
        if event.modifierFlags.contains(key.modifierFlag) {
            if heldSince == nil { heldSince = Date() }
        } else {
            heldSince = nil
        }
    }
}

/// What the Globe (fn) key does on its own, from Keyboard settings.
struct GlobeUsage: Equatable {
    let rawValue: Int

    static func current() -> GlobeUsage {
        GlobeUsage(rawValue: UserDefaults(suiteName: "com.apple.HIToolbox")?.integer(forKey: "AppleFnUsageType") ?? 0)
    }

    /// Nil when the key does nothing and fn is free for recording.
    var warning: String? {
        switch rawValue {
        case 1: String(localized: "Globe changes input source")
        case 2: String(localized: "Globe shows emoji")
        case 3: String(localized: "Globe starts dictation")
        default: nil
        }
    }
}
