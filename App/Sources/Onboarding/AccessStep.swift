import SwiftUI
import VMSystem

/// Step 5: Accessibility and Input Monitoring. macOS has no prompt for these,
/// so each row opens the right pane of System Settings.
struct AccessStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .topLeading) {
            HeroObject(
                name: "ObjectLock",
                halo: CGRect(x: 40, y: 90, width: 480, height: 420),
                object: CGRect(x: 122, y: 101, width: 317, height: 403)
            )

            VStack(alignment: .leading, spacing: 0) {
                StepTitle("Two permissions")
                StepSubtitle("saytype does not read the screen or use the network.")
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    PermissionRow(permission: .accessibility, title: "Accessibility", detail: "pasting text into the active window")
                    RowDivider()
                    PermissionRow(permission: .inputMonitoring, title: "Input Monitoring", detail: "fn in any app")
                }
                .frost()
                .padding(.top, 26)

                Muted("System Settings › Privacy & Security")
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            .frame(width: OnboardingLayout.column.width, alignment: .leading)
            .place(x: OnboardingLayout.column.minX, y: OnboardingLayout.column.minY)
        }
        .stepCanvas()
        .onAppear { model.refreshPermissions() }
    }
}

private struct PermissionRow: View {
    @Environment(AppModel.self) private var model
    let permission: Permission
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.onest(14.5, .medium))
                Text(detail)
                    .font(.onest(12.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            if model.state(of: permission) == .granted {
                GrantedPill()
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                WhiteButton(title: "Open") {
                    Task {
                        _ = await Permissions.request(permission)
                        Permissions.openSystemSettings(for: permission)
                        model.refreshPermissions()
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .animation(.snappy(duration: 0.25), value: model.state(of: permission))
    }
}
