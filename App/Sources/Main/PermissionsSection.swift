import SwiftUI
import VMSystem

struct PermissionsSection: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    private let world = MainSection.permissions.world

    var body: some View {
        ZStack(alignment: .topLeading) {
            HeaderArt(name: "ObjectLock", width: 230, right: 10, top: -24)

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Разрешения", subtitle: "Системные настройки › Конфиденциальность и безопасность")
                    .frame(height: 94, alignment: .topLeading)

                VStack(spacing: 0) {
                    ForEach(Array(Permission.allCases.enumerated()), id: \.element) { index, permission in
                        if index > 0 {
                            RowDivider()
                        }
                        PermissionRow(permission: permission, state: model.state(of: permission), detail: detail(for: permission))
                    }
                }
                .frame(width: 620)
                .frost()

                VStack(spacing: 0) {
                    ToggleRow(
                        "Открывать при входе в систему",
                        detail: loginNeedsApproval ? "ждёт подтверждения в Системных настройках" : nil,
                        isOn: Binding(
                            get: { launchAtLogin },
                            set: { enabled in
                                LoginItem.set(enabled)
                                launchAtLogin = LoginItem.isEnabled
                                loginNeedsApproval = LoginItem.needsApproval
                            }
                        ),
                        accent: world.accent
                    )
                }
                .frame(width: 620)
                .frost()
                .padding(.top, 16)
            }
        }
        .onChange(of: model.permissions) {
            // Re-read the login item on the same one-second beat as permissions.
            launchAtLogin = LoginItem.isEnabled
            loginNeedsApproval = LoginItem.needsApproval
        }
    }

    private func detail(for permission: Permission) -> String {
        switch permission {
        case .microphone: "запись речи"
        case .accessibility: "вставка текста в активное окно"
        case .inputMonitoring: "\(model.settings.value.recordKey.inlineName) в любом приложении"
        }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let state: PermissionState
    let detail: String

    var body: some View {
        SettingsRow(title, detail: detail) {
            HStack(spacing: 10) {
                if state == .granted {
                    HStack(spacing: 6) {
                        Icon(.check, size: 14, stroke: 2.6)
                        Text("Разрешено")
                    }
                    .font(.onest(13, .semibold))
                    .foregroundStyle(Color(hex: 0x13804A))
                    .padding(.leading, 9)
                    .padding(.trailing, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(.white.opacity(0.9)))
                    Button("Открыть", action: open)
                        .buttonStyle(ChipButtonStyle())
                } else {
                    Text(state == .denied ? "Запрещено" : "Нет доступа")
                        .font(.onest(13, .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(ChipFill())
                    Button("Открыть", action: open)
                        .buttonStyle(WhiteButtonStyle())
                }
            }
        }
    }

    private var title: String {
        switch permission {
        case .microphone: "Микрофон"
        case .accessibility: "Универсальный доступ"
        case .inputMonitoring: "Мониторинг ввода"
        }
    }

    private func open() {
        let permission = permission
        let state = state
        Task { @MainActor in
            // Asking first puts voicemode into the System Settings list.
            if state == .notDetermined {
                let result = await Permissions.request(permission)
                if permission == .microphone, result == .granted { return }
            }
            Permissions.openSystemSettings(for: permission)
        }
    }
}
