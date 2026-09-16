import SwiftUI

/// Step 1: what voicemode is.
struct WelcomeStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .topLeading) {
            HeroObject(
                name: "ObjectCapsule",
                halo: CGRect(x: 20, y: 120, width: 520, height: 360),
                object: CGRect(x: 4, y: 191, width: 516, height: 230)
            )
            VStack(alignment: .leading, spacing: 0) {
                StepTitle(verbatim: "voicemode")
                StepSubtitle("Voice input for macOS. Transcribes speech on this Mac, without internet.")
                    .padding(.top, 12)
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(object: "ObjectKeycap", title: "Hold \(model.settings.value.recordKey.inlineName)", detail: "and speak in any app")
                    FeatureRow(object: "ObjectTextcard", title: "Finished text", detail: "commas, paragraphs, lists")
                    FeatureRow(object: "ObjectLock", title: "Offline", detail: "audio never leaves the Mac")
                }
                .padding(.top, 30)
            }
            .frame(width: 330, alignment: .leading)
            .place(x: 592, y: OnboardingLayout.column.minY)
        }
        .stepCanvas()
    }
}

private struct FeatureRow: View {
    let object: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            Image(object)
                .resizable()
                .scaledToFit()
                .frame(width: 41, height: 41)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.onest(15, .semibold))
                Muted(detail)
            }
        }
    }
}
