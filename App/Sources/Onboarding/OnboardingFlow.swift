import AppKit
import Foundation
import Observation
import VMCore

enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome = 1
    case look
    case key
    case microphone
    case access
    case model
    case practice
    case done

    var world: World {
        switch self {
        case .welcome: .ember
        case .look: .violet
        case .key: .blue
        case .microphone: .coral
        case .access: .green
        case .model: .cyan
        case .practice: .teal
        case .done: .ember
        }
    }

    var actionTitle: String {
        switch self {
        case .welcome: String(localized: "Start", comment: "Round button on the first onboarding step")
        case .done: String(localized: "Close", comment: "Round button on the last onboarding step")
        default: String(localized: "Next", comment: "Round button that moves onboarding forward")
        }
    }
}

/// Where the user is in the first launch and which way they last moved.
@MainActor
@Observable
final class OnboardingFlow {
    enum Direction {
        case forward
        case backward
    }

    private(set) var step: OnboardingStep
    /// The step shown before the last move; its world stays under the cross-fade.
    private(set) var previous: OnboardingStep
    private(set) var direction = Direction.forward

    init(step: OnboardingStep = .welcome) {
        self.step = step
        previous = step
    }

    var isFirst: Bool { step == OnboardingStep.allCases.first }

    func next() {
        guard let target = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        move(to: target, direction: .forward)
    }

    func back() {
        guard let target = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        move(to: target, direction: .backward)
    }

    private func move(to target: OnboardingStep, direction: Direction) {
        previous = step
        self.direction = direction
        step = target
    }

    /// `--show-onboarding <step>` opens onboarding at that step even after it was
    /// completed. Used for screenshots.
    nonisolated static var launchStep: OnboardingStep? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--show-onboarding") else { return nil }
        guard index + 1 < arguments.count, let number = Int(arguments[index + 1]) else { return .welcome }
        return OnboardingStep(rawValue: min(max(number, 1), OnboardingStep.allCases.count))
    }
}

extension AppSettings.RecordKey {
    /// Chip and readout label.
    var title: String {
        switch self {
        case .fn: "fn"
        case .rightOption: String(localized: "Right ⌥", comment: "Record key name on a chip or in a menu")
        case .rightCommand: String(localized: "Right ⌘", comment: "Record key name on a chip or in a menu")
        }
    }

    /// The key inside a sentence: "Hold right ⌥".
    var inlineName: String {
        switch self {
        case .fn: "fn"
        case .rightOption: String(localized: "right ⌥", comment: "Record key name inside a sentence, e.g. Hold right ⌥")
        case .rightCommand: String(localized: "right ⌘", comment: "Record key name inside a sentence, e.g. Hold right ⌘")
        }
    }

    /// Virtual keycode from HIToolbox Events.h.
    var keyCode: UInt16 {
        switch self {
        case .fn: 63
        case .rightOption: 61
        case .rightCommand: 54
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn: .function
        case .rightOption: .option
        case .rightCommand: .command
        }
    }
}

extension AppSettings.OverlayStyle {
    var title: String {
        switch self {
        case .island: String(localized: "Island", comment: "Overlay style: a black shape under the camera notch")
        case .pill: String(localized: "Pill", comment: "Overlay style: a capsule at the bottom of the screen")
        }
    }
}
