import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case home, keys, text, dictionary, history, model, permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Главная"
        case .keys: "Клавиша и плашка"
        case .text: "Текст"
        case .dictionary: "Словарь"
        case .history: "История"
        case .model: "Модель"
        case .permissions: "Разрешения"
        }
    }

    var object: String {
        switch self {
        case .home: "ObjectAppicon"
        case .keys: "ObjectKeycap"
        case .text: "ObjectTextcard"
        case .dictionary: "ObjectAa"
        case .history: "ObjectStack"
        case .model: "ObjectChip"
        case .permissions: "ObjectLock"
        }
    }

    var world: World {
        switch self {
        case .home: .ember
        case .keys: .blue
        case .text: .teal
        case .dictionary: .pink
        case .history: .violet
        case .model: .cyan
        case .permissions: .green
        }
    }
}

struct MainWindow: View {
    @State private var section = MainSection.home

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorldBackground(world: section.world)
                .animation(.smooth(duration: 0.35), value: section)

            HStack(alignment: .top, spacing: 18) {
                SectionRail(selection: $section)
                SectionContent(section: section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.top, 52)
            .padding([.leading, .bottom, .trailing], 16)

            Text(section.title)
                .font(.onest(13, .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
        .frame(width: 1180, height: 740)
        .foregroundStyle(.white)
    }
}

private struct SectionRail: View {
    @Binding var selection: MainSection

    var body: some View {
        VStack(spacing: 10) {
            ForEach(MainSection.allCases.filter { $0 != .permissions }) { item(for: $0) }
            Spacer()
            item(for: .permissions)
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
    let section: MainSection

    var body: some View {
        switch section {
        case .home:
            HomeSection()
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(section.title).font(.onest(30, .bold))
            }
            .padding(.top, 10)
        }
    }
}
