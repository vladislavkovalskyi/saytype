import AppKit
import SwiftUI

struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("About", subtitle: "Audio and text never leave this Mac. The network is used only to download models and check for updates.")
                .frame(height: 84, alignment: .topLeading)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    AppCard()
                        .frame(width: 620, alignment: .topLeading)
                        .frame(maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .frost(hot: true)
                    ProjectPanel()
                        .frame(width: 620)
                        .frost()
                }
                VStack(spacing: 16) {
                    AuthorPanel()
                        .frame(width: 432, alignment: .topLeading)
                        .frost()
                    CreditsPanel()
                        .frame(width: 432, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .frost()
                }
            }
            .frame(height: 584)
        }
    }
}

enum AboutLinks {
    static let github = URL(string: "https://github.com/vladislavkovalskyi")!
    static let telegram = URL(string: "https://t.me/yxuxo")!
    static let repository = URL(string: "https://github.com/vladislavkovalskyi/saytype")!
    static let issues = URL(string: "https://github.com/vladislavkovalskyi/saytype/issues")!
    static let releases = URL(string: "https://github.com/vladislavkovalskyi/saytype/releases")!
    static let license = URL(string: "https://github.com/vladislavkovalskyi/saytype/blob/main/LICENSE")!

    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// "github.com/vladislavkovalskyi/saytype".
    static func display(_ url: URL) -> String {
        (url.host() ?? "") + url.path()
    }
}

// MARK: App

private struct AppCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("ObjectAppicon")
                .resizable()
                .scaledToFit()
                .frame(width: 290, height: 290)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                // Clears the update row, where the Russian status line runs longest.
                .offset(x: 34, y: 14)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                VersionBadge(text: version)
                Text(verbatim: "saytype")
                    .font(.onest(52, .bold))
                    .tracking(-1.56)
                    .padding(.top, 14)
                Text("Voice typing for macOS. Speech is recognized on this Mac.")
                    .font(.onest(15))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineSpacing(2)
                    .frame(width: 290, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                Spacer(minLength: 0)
                updates
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }

    private var version: String {
        let info = Bundle.main
        let short = info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = info.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return String(localized: "Version \(short) (\(build))", comment: "App version, then the build number in parentheses")
    }

    private var updates: some View {
        let updater = model.updater
        let enabled = updater?.isEnabled ?? false
        let canCheck = enabled && (updater?.canCheckForUpdates ?? false)
        return HStack(spacing: 14) {
            Button("Check for Updates…") {
                updater?.checkForUpdates()
            }
            .buttonStyle(WhiteButtonStyle())
            .disabled(!canCheck)
            .opacity(canCheck ? 1 : 0.5)
            if !enabled {
                Text("Updates are off in this build")
                    .font(.onest(13))
                    .foregroundStyle(.white.opacity(0.74))
            }
        }
    }
}

private struct VersionBadge: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.onest(12.5, .semibold))
            .foregroundStyle(Color(hex: 0xB23F1E))
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(.white))
            .fixedSize()
    }
}

// MARK: Author

private struct AuthorPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Author")
            Text(verbatim: "Vladislav Kovalskyi")
                .font(.onest(21, .semibold))
                .tracking(-0.2)
                .padding(.top, 8)
            HStack(spacing: 8) {
                Button {
                    AboutLinks.open(AboutLinks.github)
                } label: {
                    Text(verbatim: "GitHub")
                }
                .help(AboutLinks.display(AboutLinks.github))
                Button {
                    AboutLinks.open(AboutLinks.telegram)
                } label: {
                    Text(verbatim: "Telegram @yxuxo")
                }
                .help(AboutLinks.display(AboutLinks.telegram))
            }
            .buttonStyle(ChipButtonStyle())
            .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }
}

// MARK: Project

private struct ProjectPanel: View {
    var body: some View {
        VStack(spacing: 0) {
            link("Source code", url: AboutLinks.repository)
            RowDivider()
            link("Report an issue", url: AboutLinks.issues)
            RowDivider()
            link("Releases", url: AboutLinks.releases)
            RowDivider()
            SettingsRow("License", detailText: Text(verbatim: "© 2026 Vladislav Kovalskyi")) {
                Button {
                    AboutLinks.open(AboutLinks.license)
                } label: {
                    Text(verbatim: "MIT")
                }
                .buttonStyle(ChipButtonStyle())
                .help(AboutLinks.display(AboutLinks.license))
            }
        }
    }

    private func link(_ title: LocalizedStringKey, url: URL) -> some View {
        SettingsRow(title, detailText: Text(verbatim: AboutLinks.display(url))) {
            Button("Open") { AboutLinks.open(url) }
                .buttonStyle(ChipButtonStyle())
        }
    }
}

// MARK: Credits

private struct Credit: Identifiable {
    let name: String
    let detail: String
    let url: URL
    var id: String { name }
}

private struct CreditsPanel: View {
    private var credits: [Credit] {
        let font = String(localized: "font · OFL", comment: "Credit detail for a typeface under the SIL Open Font License")
        return [
            Credit(name: "WhisperKit", detail: "Argmax", url: URL(string: "https://github.com/argmaxinc/WhisperKit")!),
            Credit(name: "MLX", detail: "Apple", url: URL(string: "https://github.com/ml-explore/mlx-swift")!),
            Credit(name: "swift-transformers", detail: "Hugging Face", url: URL(string: "https://github.com/huggingface/swift-transformers")!),
            Credit(name: "Sparkle", detail: "Sparkle Project", url: URL(string: "https://sparkle-project.org")!),
            Credit(name: "Whisper", detail: "OpenAI", url: URL(string: "https://github.com/openai/whisper")!),
            Credit(name: "Qwen3", detail: "Alibaba Cloud", url: URL(string: "https://github.com/QwenLM/Qwen3")!),
            Credit(name: "Onest", detail: font, url: URL(string: "https://fonts.google.com/specimen/Onest")!),
            Credit(name: "JetBrains Mono", detail: font, url: URL(string: "https://www.jetbrains.com/lp/mono/")!),
        ]
    }

    var body: some View {
        let credits = credits
        VStack(alignment: .leading, spacing: 0) {
            PanelLabel("Built with")
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 6)
            ForEach(Array(credits.enumerated()), id: \.element.id) { index, credit in
                if index > 0 {
                    RowDivider(opacity: 0.1)
                        .padding(.horizontal, 24)
                }
                CreditRow(credit: credit)
            }
        }
    }
}

private struct CreditRow: View {
    let credit: Credit

    var body: some View {
        Button {
            AboutLinks.open(credit.url)
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: credit.name)
                    .font(.onest(14.5, .medium))
                Spacer(minLength: 8)
                Text(verbatim: credit.detail)
                    .font(.onest(13))
                    .foregroundStyle(.white.opacity(0.7))
                Icon(.arrowRight, size: 14, stroke: 2)
                    .rotationEffect(.degrees(-45))
                    .opacity(0.55)
            }
            .padding(.horizontal, 24)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(AboutLinks.display(credit.url))
    }
}
