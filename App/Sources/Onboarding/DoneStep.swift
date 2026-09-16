import SwiftUI

/// Step 8: a summary of the choices and launch at login.
struct DoneStep: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        let settings = model.settings.value
        ZStack(alignment: .topLeading) {
            HeroObject(
                name: "ObjectAppicon",
                halo: CGRect(x: 40, y: 80, width: 480, height: 440),
                object: CGRect(x: 77, y: 116, width: 408, height: 348)
            )

            VStack(alignment: .leading, spacing: 0) {
                StepTitle("Done")
                StepSubtitle("voicemode is in the menu bar. Hold \(settings.recordKey.inlineName) in any app.")
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    SummaryRow(title: "Key") {
                        Kbd(text: settings.recordKey.inlineName)
                    }
                    RowDivider()
                    SummaryRow(title: "Overlay") {
                        Text(settings.overlayStyle.title).font(.onest(14, .semibold))
                    }
                    RowDivider()
                    SummaryRow(title: "Model") {
                        Text(verbatim: "Whisper turbo").font(.onest(14, .semibold))
                    }
                    RowDivider()
                    Toggle(isOn: loginBinding) {
                        Text("Open at login")
                            .font(.onest(14))
                            .foregroundStyle(.white.opacity(0.74))
                    }
                    .toggleStyle(WorldToggleStyle(accent: OnboardingStep.done.world.accent))
                    .padding(.horizontal, 20)
                    .frame(minHeight: 46)
                }
                .frost()
                .padding(.top, 24)
            }
            .frame(width: OnboardingLayout.column.width, alignment: .leading)
            .place(x: OnboardingLayout.column.minX, y: OnboardingLayout.column.minY)
        }
        .stepCanvas()
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private var loginBinding: Binding<Bool> {
        Binding {
            launchAtLogin
        } set: { enabled in
            LoginItem.set(enabled)
            launchAtLogin = LoginItem.isEnabled
        }
    }
}

private struct SummaryRow<Value: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.onest(14))
                .foregroundStyle(.white.opacity(0.74))
            Spacer(minLength: 0)
            value
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: 46)
    }
}
