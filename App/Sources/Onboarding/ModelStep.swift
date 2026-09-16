import Darwin
import SwiftUI

/// Step 6: download and prepare Whisper, starting as soon as the step opens.
struct ModelStep: View {
    @Environment(AppModel.self) private var model
    @State private var rate = TransferRate()

    private static let totalMegabytes = 632.0

    var body: some View {
        @Bindable var settings = model.settings
        let state = model.dictation.modelState
        ZStack(alignment: .topLeading) {
            HeroObject(
                name: "ObjectChip",
                halo: CGRect(x: 30, y: 90, width: 500, height: 420),
                object: CGRect(x: 57, y: 94, width: 436, height: 425)
            )

            VStack(alignment: .leading, spacing: 0) {
                StepTitle(verbatim: "Whisper turbo")
                StepSubtitle("The model downloads once. After that everything works offline.")
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 0) {
                    header(for: state)
                    StageList(stages: stages(for: state))
                        .padding(.top, 16)
                }
                .padding(18)
                .frost()
                .padding(.top, 24)

                Toggle(isOn: smartBinding) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Smart structure").font(.onest(14.5, .semibold))
                        Muted(verbatim: smartSubtitle)
                    }
                }
                .toggleStyle(WorldToggleStyle(accent: OnboardingStep.model.world.accent))
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frost()
                .padding(.top, 12)
            }
            .frame(width: OnboardingLayout.column.width, alignment: .leading)
            .place(x: OnboardingLayout.column.minX, y: 128)
        }
        .stepCanvas()
        .onAppear(perform: startIfNeeded)
        .onChange(of: state) { _, new in
            if case .downloading(let fraction) = new {
                rate.record(megabytes: fraction * Self.totalMegabytes)
            }
        }
    }

    /// On means the setting is on and the model is on disk or on its way; turning it on downloads.
    private var smartBinding: Binding<Bool> {
        model.smartStructureBinding
    }

    private var smartSubtitle: String {
        model.dictation.smart.detail
    }

    private func startIfNeeded() {
        let dictation = model.dictation
        switch dictation.modelState {
        case .missing:
            if dictation.isModelDownloaded {
                dictation.loadModelIfPresent()
            } else {
                dictation.downloadModel()
            }
        default:
            break
        }
    }

    private func retry() {
        let dictation = model.dictation
        if dictation.isModelDownloaded {
            dictation.loadModelIfPresent()
        } else {
            rate = TransferRate()
            dictation.downloadModel()
        }
    }

    @ViewBuilder
    private func header(for state: DictationController.ModelState) -> some View {
        switch state {
        case .failed(let message):
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.dictation.isModelDownloaded ? "Model failed to load" : "Download interrupted")
                        .font(.onest(17, .semibold))
                    Muted(verbatim: message)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                WhiteButton(title: "Retry", action: retry)
            }
        default:
            let fraction = progress(for: state)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(Int((fraction * 100).rounded(.down)))%")
                    .font(.onest(26, .bold))
                    .tracking(-0.26)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                if state == .missing {
                    WhiteButton(title: "Download", action: retry)
                } else {
                    Muted(verbatim: detail(for: state, fraction: fraction))
                        .monospacedDigit()
                }
            }
            ProgressTrack(fraction: fraction)
                .padding(.top, 12)
        }
    }

    private func progress(for state: DictationController.ModelState) -> Double {
        switch state {
        case .missing, .failed: 0
        case .downloading(let fraction): min(max(fraction, 0), 1)
        case .loading, .ready: 1
        }
    }

    private func detail(for state: DictationController.ModelState, fraction: Double) -> String {
        let total = Int(Self.totalMegabytes)
        let done = Int((fraction * Self.totalMegabytes).rounded(.down))
        var text = String(localized: "\(done) of \(total) MB", comment: "Download progress in megabytes")
        if case .downloading = state, let speed = rate.megabytesPerSecond {
            text += " · " + String(localized: "\(Int(speed.rounded())) MB/s", comment: "Download speed")
        }
        return text
    }

    private func stages(for state: DictationController.ModelState) -> [Stage] {
        let download = String(localized: "Downloading", comment: "Model setup stage")
        let prepare = String(localized: "Preparing for \(Self.chipName)", comment: "Model setup stage; the argument is a chip name such as M3 Pro")
        let ready = String(localized: "Ready", comment: "Model setup stage")
        switch state {
        case .missing:
            return [Stage(title: download, status: .pending), Stage(title: prepare, status: .pending), Stage(title: ready, status: .pending)]
        case .downloading(let fraction):
            return [Stage(title: download, status: .active(fraction)), Stage(title: prepare, status: .pending), Stage(title: ready, status: .pending)]
        case .loading:
            return [Stage(title: download, status: .done), Stage(title: prepare, status: .active(nil)), Stage(title: ready, status: .pending)]
        case .ready:
            return [Stage(title: download, status: .done), Stage(title: prepare, status: .done), Stage(title: ready, status: .done)]
        case .failed:
            if model.dictation.isModelDownloaded {
                return [Stage(title: download, status: .done), Stage(title: prepare, status: .failed), Stage(title: ready, status: .pending)]
            }
            return [Stage(title: download, status: .failed), Stage(title: prepare, status: .pending), Stage(title: ready, status: .pending)]
        }
    }

    /// "M3 Pro" from "Apple M3 Pro"; "this Mac" when the name is unavailable.
    static let chipName: String = {
        let fallback = String(localized: "this Mac", comment: "Stands in for the chip name: Preparing for this Mac")
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return fallback }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return fallback }
        let brand = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard brand.hasPrefix("Apple ") else { return fallback }
        return String(brand.dropFirst("Apple ".count))
    }()
}

// MARK: Parts

private struct Stage: Identifiable {
    enum Status: Equatable {
        case pending
        /// Progress 0…1, or nil when the length is unknown.
        case active(Double?)
        case done
        case failed
    }

    let title: String
    let status: Status
    var id: String { title }
}

private struct StageList: View {
    let stages: [Stage]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(stages) { stage in
                HStack(spacing: 10) {
                    StageIndicator(status: stage.status)
                    Text(stage.title)
                        .font(.onest(14, isActive(stage) ? .semibold : .regular))
                }
                .opacity(stage.status == .pending ? 0.8 : 1)
            }
        }
    }

    private func isActive(_ stage: Stage) -> Bool {
        if case .active = stage.status { return true }
        return false
    }
}

private struct StageIndicator: View {
    let status: Stage.Status
    @State private var turning = false

    var body: some View {
        ZStack {
            switch status {
            case .pending:
                Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
            case .active(let fraction?):
                Circle().stroke(.white.opacity(0.25), lineWidth: 3).padding(1.5)
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(.white, style: StrokeStyle(lineWidth: 3))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            case .active(.none):
                Circle().stroke(.white.opacity(0.25), lineWidth: 3).padding(1.5)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(turning ? 270 : -90))
                    .padding(1.5)
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turning = true }
                    }
            case .done:
                Circle().fill(.white)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(OnboardingStep.model.world.accent)
            case .failed:
                Circle().fill(.white)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xC8323C))
            }
        }
        .frame(width: 18, height: 18)
    }
}

/// Download speed over the last few seconds of progress updates.
@MainActor
@Observable
final class TransferRate {
    private var samples: [(time: Date, megabytes: Double)] = []

    func record(megabytes: Double, at time: Date = Date()) {
        samples.append((time, megabytes))
        samples.removeAll { time.timeIntervalSince($0.time) > 3 }
    }

    var megabytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let seconds = last.time.timeIntervalSince(first.time)
        guard seconds >= 1 else { return nil }
        return max(0, (last.megabytes - first.megabytes) / seconds)
    }
}
