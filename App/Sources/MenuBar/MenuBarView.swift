import SwiftUI
import VMSystem

struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image("ObjectAppicon").resizable().scaledToFit().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("voicemode").font(.onest(15, .semibold))
                    Text("Whisper turbo · офлайн").font(.onest(12)).foregroundStyle(.secondary)
                }
                Spacer()
                StatusChip(ready: missingPermissions.isEmpty)
            }
            if !missingPermissions.isEmpty {
                Text("Нет разрешений: \(missingPermissions.joined(separator: ", "))")
                    .font(.onest(12.5))
                    .foregroundStyle(.secondary)
            }
            Divider()
            MenuRow(title: "Открыть voicemode", shortcut: "⌘,") { model.windows.showMain() }
            MenuRow(title: "Выйти", shortcut: "⌘Q") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var missingPermissions: [String] {
        Permission.allCases.compactMap { permission in
            guard model.state(of: permission) != .granted else { return nil }
            return switch permission {
            case .microphone: "микрофон"
            case .accessibility: "универсальный доступ"
            case .inputMonitoring: "мониторинг ввода"
            }
        }
    }
}

private struct StatusChip: View {
    let ready: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(ready ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(ready ? "Готов" : "Настройка").font(.onest(12, .medium))
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(.quaternary))
    }
}

private struct MenuRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.onest(14))
                Spacer()
                Text(shortcut).font(.onest(12.5)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
