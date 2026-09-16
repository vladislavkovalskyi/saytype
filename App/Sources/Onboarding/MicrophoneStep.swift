import AVFoundation
import SwiftUI
import VMAudio
import VMSystem

/// Step 4: microphone permission and a live level meter.
struct MicrophoneStep: View {
    @Environment(AppModel.self) private var model
    @State private var meter = MicMeter()
    @State private var deviceName = MicrophoneStep.defaultDeviceName()

    var body: some View {
        let permission = model.state(of: .microphone)
        ZStack(alignment: .topLeading) {
            HeroObject(
                name: "ObjectMic",
                halo: CGRect(x: 40, y: 80, width: 480, height: 440),
                object: CGRect(x: 152, y: 105, width: 253, height: 390)
            )

            VStack(alignment: .leading, spacing: 0) {
                StepTitle("Microphone")
                StepSubtitle("Say a few words. The bars move only when there is sound.")
                    .padding(.top, 12)

                HStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 15, weight: .regular))
                        .frame(width: 17)
                    Text(deviceName)
                        .font(.onest(14.5, .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .frost()
                .padding(.top, 26)

                HStack(spacing: 16) {
                    LevelBars(levels: meter.levels)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Self.decibels(meter.peak))
                            .font(.onest(22, .bold))
                            .tracking(-0.22)
                        Muted(verbatim: "dB")
                    }
                    .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .frame(height: 96)
                .frost()
                .padding(.top, 12)

                switch permission {
                case .granted:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 16, weight: .regular))
                        Text("Microphone access allowed")
                            .font(.onest(13.5, .medium))
                    }
                    .padding(.top, 16)
                case .denied:
                    HStack(spacing: 12) {
                        Text("No microphone access")
                            .font(.onest(14, .semibold))
                        Spacer(minLength: 0)
                        WhiteButton(title: "Open Settings") {
                            Permissions.openSystemSettings(for: .microphone)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.leading, 16)
                    .padding(.trailing, 12)
                    .frost()
                    .padding(.top, 12)
                case .notDetermined:
                    EmptyView()
                }
            }
            .frame(width: OnboardingLayout.column.width, alignment: .leading)
            .place(x: OnboardingLayout.column.minX, y: OnboardingLayout.column.minY)
        }
        .stepCanvas()
        .task {
            deviceName = Self.defaultDeviceName()
            var state = Permissions.state(of: .microphone)
            if state == .notDetermined {
                state = await Permissions.request(.microphone)
                model.refreshPermissions()
            }
            guard !Task.isCancelled, state == .granted else { return }
            meter.start()
        }
        .onChange(of: permission) { _, new in
            if new == .granted {
                meter.start()
            } else {
                meter.stop()
            }
        }
        .onDisappear { meter.stop() }
    }

    static func defaultDeviceName() -> String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? String(localized: "Microphone")
    }

    /// Level 0…1 is −60…0 dBFS.
    static func decibels(_ level: Float) -> String {
        let value = Int((level * 60 - 60).rounded())
        return value < 0 ? "−\(-value)" : "\(value)"
    }
}

private struct LevelBars: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(levels.indices, id: \.self) { index in
                if index > 0 { Spacer(minLength: 4) }
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: height(for: levels[index]))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 54)
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    /// Room noise stays flat; speech fills the 54 pt height.
    private func height(for level: Float) -> CGFloat {
        let voiced = max(0, (CGFloat(level) - 0.2) / 0.8)
        return 3 + 51 * min(1, voiced)
    }
}

/// Runs its own capture while the microphone step is visible.
@MainActor
@Observable
final class MicMeter {
    static let barCount = 30

    private(set) var levels = [Float](repeating: 0, count: MicMeter.barCount)
    /// Loudest of the last few chunks, steadier to read than the latest one.
    private(set) var peak: Float = 0

    @ObservationIgnored private let capture = AudioCapture()
    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        guard let stream = try? capture.start() else { return }
        task = Task { [weak self] in
            for await chunk in stream {
                self?.push(chunk.level)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        capture.stop()
        levels = [Float](repeating: 0, count: Self.barCount)
        peak = 0
    }

    private func push(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
        peak = levels.suffix(6).max() ?? 0
    }
}
