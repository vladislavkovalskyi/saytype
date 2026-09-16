import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VMCore

struct KeysSection: View {
    @Environment(AppModel.self) private var model
    private let world = MainSection.keys.world

    var body: some View {
        @Bindable var settings = model.settings
        ZStack(alignment: .topLeading) {
            HeaderArt(name: "ObjectKeycap", width: 300, right: -30, top: -40)

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Клавиша и плашка", subtitle: "Как начинать запись и где она видна")
                    .frame(height: 94, alignment: .topLeading)

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        SettingsRow("Клавиша записи", detail: "держать, чтобы говорить") {
                            PopupMenu(items: AppSettings.RecordKey.allCases.map { key in
                                MenuOption(title: key.title, isOn: key == settings.value.recordKey) {
                                    settings.value.recordKey = key
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Keycap(settings.value.recordKey.title)
                                    Icon(.chevronDown, size: 16).opacity(0.7)
                                }
                            }
                        }
                        RowDivider()
                        ToggleRow("Двойное нажатие", detail: "запись без рук", isOn: $settings.value.doubleTapHandsFree, accent: world.accent)
                        RowDivider()
                        SettingsRow("Отмена") { Keycap("esc") }
                        RowDivider()
                        ToggleRow("Звук начала и конца", isOn: $settings.value.sounds, accent: world.accent)
                    }
                    .frame(width: 520)
                    .frost()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            OverlayStyleCard(title: "Остров", isSelected: settings.value.overlayStyle == .island) {
                                IslandPreview()
                            } action: {
                                settings.value.overlayStyle = .island
                            }
                            OverlayStyleCard(title: "Пилюля", isSelected: settings.value.overlayStyle == .pill) {
                                PillPreview(light: settings.value.glass == .light)
                            } action: {
                                settings.value.overlayStyle = .pill
                            }
                        }
                        HStack {
                            PanelLabel("Стекло")
                            Spacer()
                            WorldSegmented(selection: $settings.value.glass, options: [(.dark, "Тёмное"), (.light, "Светлое")])
                        }
                    }
                    .padding(16)
                    .frame(width: 532, height: 250, alignment: .top)
                    .frost()
                }

                AfterRecordingPanel(world: world)
                    .frame(width: 1068, height: 308, alignment: .topLeading)
                    .frost()
                    .padding(.top, 16)
            }
        }
        .onChange(of: settings.value.doubleTapHandsFree) {
            // The gesture reads this flag when the key monitor starts.
            model.dictation.startKeyMonitor()
        }
    }
}

// MARK: Overlay style

private struct OverlayStyleCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder let preview: Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                MiniWallpaper()
                    .overlay { preview }
                    .frame(height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack(spacing: 8) {
                    Radio(isOn: isSelected)
                    Text(title).font(.onest(14, .semibold))
                }
                .padding(.top, 10)
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(isSelected ? 0.2 : 0.1)))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(.white, lineWidth: 2).padding(-2)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct Radio: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .strokeBorder(.white.opacity(isOn ? 1 : 0.6), lineWidth: isOn ? 5.5 : 1.5)
            .frame(width: 18, height: 18)
    }
}

/// Desktop wallpaper in miniature, as in the mockups.
struct MiniWallpaper: View {
    var body: some View {
        ZStack {
            Color(hex: 0x4B56C8)
            blob(0x7B5CF0, x: 0.2, y: 0.9, radius: 0.55)
            blob(0xFF9A55, x: 0.7, y: 0.9, radius: 0.55)
            blob(0xF39BD0, x: 0.78, y: 0.22, radius: 0.45)
            blob(0x6BB7FF, x: 0.18, y: 0.28, radius: 0.5)
        }
    }

    private func blob(_ hex: UInt32, x: CGFloat, y: CGFloat, radius: CGFloat) -> some View {
        EllipticalGradient(colors: [Color(hex: hex), Color(hex: hex, opacity: 0)], center: UnitPoint(x: x, y: y), startRadiusFraction: 0, endRadiusFraction: radius * 1.4)
    }
}

private struct PreviewWindow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: 0x14141E, opacity: 0.5))
            .frame(width: 110, height: 70)
    }
}

private struct IslandPreview: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            PreviewWindow().offset(x: 16, y: 34)
            IslandShape(ear: 6, radius: 12)
                .fill(.black)
                .frame(width: 152, height: 34)
                .overlay(alignment: .bottom) {
                    SpeechBars(count: 10, seed: 5, minHeight: 2, maxHeight: 10)
                        .foregroundStyle(Color(hex: 0xFFB37A))
                        .padding(.bottom, 7)
                }
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PillPreview: View {
    let light: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            PreviewWindow().offset(x: 16, y: 12)
            HStack(spacing: 6) {
                Circle()
                    .fill(.white.opacity(light ? 0 : 0.1))
                    .frame(width: 16, height: 16)
                    .overlay {
                        Circle().fill(Color(hex: 0xFF7A45)).frame(width: 5, height: 5).shadow(color: Color(hex: 0xFF7A45), radius: 3)
                    }
                SpeechBars(count: 10, seed: 7, minHeight: 2, maxHeight: 10)
                    .foregroundStyle(light ? Color(hex: 0x17151B) : .white)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(height: 24)
            .background {
                Capsule()
                    .fill(light ? AnyShapeStyle(.white.opacity(0.82)) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x28262C, opacity: 0.85), Color(hex: 0x121016, opacity: 0.92)], startPoint: .top, endPoint: .bottom)))
                    .overlay(Capsule().strokeBorder(.white.opacity(light ? 0.7 : 0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: After recording

private struct AfterRecordingPanel: View {
    @Environment(AppModel.self) private var model
    let world: World

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("После записи")
                .padding(.horizontal, 20)
            HStack(spacing: 12) {
                ModeCard(icon: .returnKey, title: "Вставить", detail: "в активное поле", isSelected: settings.value.outputMode == .paste) {
                    settings.value.outputMode = .paste
                }
                ModeCard(icon: .card, title: "Карточка", detail: "остаётся в плашке", isSelected: settings.value.outputMode == .card) {
                    settings.value.outputMode = .card
                }
                ModeCard(icon: .clipboard, title: "Буфер обмена", detail: "без вставки", isSelected: settings.value.outputMode == .clipboard) {
                    settings.value.outputMode = .clipboard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            SettingsRow("Enter после вставки", detail: "команда сразу уходит агенту") {
                AutoEnterApps()
            }
            .opacity(settings.value.outputMode == .paste ? 1 : 0.5)
            .padding(.top, 14)
        }
        .padding(.top, 18)
    }
}

private struct ModeCard: View {
    let icon: Icon.Name
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(icon, size: 20)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.onest(15, .semibold))
                    Text(detail).font(.onest(13)).foregroundStyle(.white.opacity(0.74))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(isSelected ? 0.22 : 0.1)))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(.white, lineWidth: 2).padding(-2)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Enter after paste

private struct AutoEnterApps: View {
    @Environment(AppModel.self) private var model

    /// Agents and terminals offered as one-click chips when installed.
    private static let suggested = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.todesktop.230313mzl4w4u92",
        "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
    ]

    var body: some View {
        let apps = model.settings.value.autoEnterApps
        let suggestions = Self.suggested.filter { !apps.contains($0) && InstalledApps.url(for: $0) != nil }.prefix(2)
        HStack(spacing: 8) {
            ForEach(apps, id: \.self) { bundleID in
                Button {
                    model.settings.value.autoEnterApps.removeAll { $0 == bundleID }
                } label: {
                    HStack(spacing: 6) {
                        Icon(.check, size: 14, stroke: 2.4)
                        Text(InstalledApps.name(for: bundleID))
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(suggestions), id: \.self) { bundleID in
                Button {
                    add(bundleID)
                } label: {
                    HStack(spacing: 6) {
                        Icon(.plus, size: 14, stroke: 2)
                        Text(InstalledApps.name(for: bundleID))
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .frame(height: 30)
                    .background(ChipFill())
                }
                .buttonStyle(.plain)
            }
            Button(action: chooseApp) {
                Icon(.plus, size: 14, stroke: 2)
                    .frame(width: 30, height: 30)
                    .background(ChipFill())
            }
            .buttonStyle(.plain)
        }
        .font(.onest(13, .medium))
        .fixedSize()
    }

    private func add(_ bundleID: String) {
        guard !model.settings.value.autoEnterApps.contains(bundleID) else { return }
        model.settings.value.autoEnterApps.append(bundleID)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        let delegate = ApplicationsFolderOnly()
        panel.delegate = delegate
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Добавить"
        let response = panel.runModal()
        withExtendedLifetime(delegate) {}
        guard response == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        add(bundleID)
    }
}

/// Keeps the open panel inside the application folders.
private final class ApplicationsFolderOnly: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return ["/Applications", "/System/Applications"].contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

enum InstalledApps {
    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Localised app name, e.g. "Терминал"; the bundle id when the app is not installed.
    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else {
            return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") {
            name.removeLast(4)
        }
        return name
    }
}
