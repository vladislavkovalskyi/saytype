import SwiftUI
import VMSystem

/// First launch: eight steps on one window, each on its own colour world.
struct OnboardingWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flow = OnboardingFlow(step: OnboardingFlow.launchStep ?? .welcome)

    var body: some View {
        let step = flow.step
        ZStack(alignment: .top) {
            ZStack {
                // The previous world stays opaque underneath, so the cross-fade
                // never lets the window background show through.
                WorldBackground(world: flow.previous.world)
                    .transaction { $0.animation = nil }
                WorldBackground(world: step.world)
                    .id(step)
                    .transition(.opacity)
            }

            ZStack(alignment: .topLeading) {
                content(for: step)
                    .id(step)
                    .transition(StepTransition(flow: flow, reduceMotion: reduceMotion))
            }
            .stepCanvas()

            Text("Шаг \(step.rawValue) из \(OnboardingStep.allCases.count)")
                .font(.onest(13, .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.numericText())
                .frame(width: OnboardingLayout.size.width, height: 44)
                .allowsHitTesting(false)

            bottomBar(for: step)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        // Flexible so the window can be brought to the design size below.
        .frame(minWidth: OnboardingLayout.size.width, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func content(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome: WelcomeStep()
        case .look: LookStep()
        case .key: KeyStep()
        case .microphone: MicrophoneStep()
        case .access: AccessStep()
        case .model: ModelStep()
        case .practice: PracticeStep()
        case .done: DoneStep()
        }
    }

    private func bottomBar(for step: OnboardingStep) -> some View {
        ZStack(alignment: .bottom) {
            if !flow.isFirst {
                TextAction(title: "Назад", chevron: true) { move(flow.back) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 30)
                    .padding(.bottom, 52)
                    .transition(.opacity)
            }
            if step == .access && !accessGranted {
                TextAction(title: "Позже", chevron: false) { move(flow.next) }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 30)
                    .padding(.bottom, 52)
                    .transition(.opacity)
            }
            RoundActionButton(title: step.actionTitle, world: step.world) {
                primaryAction(for: step)
            }
            .opacity(canAdvance(from: step) ? 1 : 0.55)
            .disabled(!canAdvance(from: step))
            .padding(.bottom, 30)
        }
        .frame(width: OnboardingLayout.size.width)
    }

    private var accessGranted: Bool {
        model.state(of: .accessibility) == .granted && model.state(of: .inputMonitoring) == .granted
    }

    private func canAdvance(from step: OnboardingStep) -> Bool {
        step != .access || accessGranted
    }

    private func primaryAction(for step: OnboardingStep) {
        if step == .done {
            model.finishOnboarding()
        } else {
            move(flow.next)
        }
    }

    private func move(_ change: () -> Void) {
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.4, bounce: 0.12)
        withAnimation(animation, change)
    }
}

/// Steps slide in the direction of travel and fade; with Reduce Motion they only fade.
private struct StepTransition: Transition {
    /// Read at transition time, so a step leaving the screen uses the new direction.
    let flow: OnboardingFlow
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        let sign: CGFloat = flow.direction == .forward ? 1 : -1
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .offset(x: reduceMotion ? 0 : -phase.value * 70 * sign)
    }
}

/// "Назад" and "Позже": plain text at the bottom corners.
private struct TextAction: View {
    let title: String
    let chevron: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if chevron {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.onest(14, .medium))
            }
            .foregroundStyle(.white.opacity(0.82))
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
