import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case home, keys, text, modes, dictionary, history, model, permissions, about

    /// Sections pinned to the bottom of the rail.
    static let footer: [MainSection] = [.permissions, .about]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Home", comment: "Main window section")
        case .keys: String(localized: "Key and overlay", comment: "Main window section: record key and the recording overlay")
        case .text: String(localized: "Text", comment: "Main window section")
        case .modes: String(localized: "Modes", comment: "Main window section: text rules per app")
        case .dictionary: String(localized: "Dictionary", comment: "Main window section")
        case .history: String(localized: "History", comment: "Main window section")
        case .model: String(localized: "Model", comment: "Main window section")
        case .permissions: String(localized: "Permissions", comment: "Main window section")
        case .about: String(localized: "About", comment: "Main window section: version, author and links")
        }
    }

    var object: String {
        switch self {
        case .home: "ObjectAppicon"
        case .keys: "ObjectKeycap"
        case .text: "ObjectTextcard"
        case .modes: "ObjectSwitches"
        case .dictionary: "ObjectAa"
        case .history: "ObjectStack"
        case .model: "ObjectChip"
        case .permissions: "ObjectLock"
        case .about: "ObjectCapsule"
        }
    }

    var world: World {
        switch self {
        case .home: .ember
        case .keys: .blue
        case .text: .teal
        case .modes: .coral
        case .dictionary: .pink
        case .history: .violet
        case .model: .cyan
        case .permissions: .green
        case .about: .ember
        }
    }
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let section = model.mainSection
        ZStack(alignment: .topLeading) {
            WorldBackground(world: section.world)
                .animation(.smooth(duration: 0.35), value: section)

            HStack(alignment: .top, spacing: 18) {
                SectionRail(selection: $model.mainSection)
                    .padding(.top, 2)
                SectionContent(section: $model.mainSection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.top, 56)
            .padding(.leading, 14)
            .padding([.bottom, .trailing], 16)

            Text(section.title)
                .font(.onest(13, .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .allowsHitTesting(false)
        }
        .frame(width: 1180, height: 740)
        .foregroundStyle(.white)
    }
}

private struct SectionRail: View {
    @Binding var selection: MainSection

    var body: some View {
        VStack(spacing: 10) {
            ForEach(MainSection.allCases.filter { !MainSection.footer.contains($0) }) { item(for: $0) }
            Spacer()
            ForEach(MainSection.footer) { item(for: $0) }
        }
        .frame(width: 64)
    }

    private func item(for section: MainSection) -> some View {
        Button {
            selection = section
        } label: {
            Image(section.object)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .opacity(selection == section ? 1 : 0.85)
                .frame(width: 52, height: 52)
                .background {
                    if selection == section {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(.white.opacity(0.24))
                            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.3)))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(section.title)
    }
}

private struct SectionContent: View {
    @Binding var section: MainSection

    var body: some View {
        switch section {
        case .home: HomeSection(section: $section)
        case .keys: KeysSection()
        case .text: TextSection()
        case .modes: ModesSection()
        case .dictionary: DictionarySection()
        case .history: HistorySection()
        case .model: ModelSection()
        case .permissions: PermissionsSection()
        case .about: AboutSection()
        }
    }
}
