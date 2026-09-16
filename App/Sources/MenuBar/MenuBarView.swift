import SwiftUI
import VMCore
import VMSystem

struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let dictation = model.dictation
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 4)
                .padding(.bottom, 12)

            if let last = dictation.history.first {
                LastDictationCard(record: last) { insert(last) }
            } else {
                EmptyCard(keyName: model.settings.value.recordKey.menuName)
            }

            if dictation.history.count > 1 {
                Text("Сегодня · \(dictation.stats.wordsToday.formatted()) \(wordsLabel(dictation.stats.wordsToday))")
                    .font(.onest(12, .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                ForEach(dictation.history.dropFirst().prefix(5)) { record in
                    HistoryRow(record: record)
                }
            }

            Rectangle().fill(.white.opacity(0.1)).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 8)

            MenuRow(icon: "slider.horizontal.3", title: "Открыть voicemode", shortcut: "⌘,") {
                model.windows.showMain()
            }
            .keyboardShortcut(",")
            MenuRow(icon: "power", title: "Выйти", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 380)
        .focusEffectDisabled()
        .foregroundStyle(.white)
        .background {
            LinearGradient(colors: [Color(hex: 0x2C2830, opacity: 0.74), Color(hex: 0x18161C, opacity: 0.84)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("ObjectAppicon").resizable().scaledToFit().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("voicemode").font(.onest(15, .semibold))
                Text(subtitle).font(.onest(12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            StatusChip(status: status)
        }
    }

    private var status: StatusChip.Status {
        let missing = Permission.allCases.contains { model.state(of: $0) != .granted }
        switch model.dictation.modelState {
        case .ready: return missing ? .attention("Нет доступа") : .ready
        case .loading, .downloading: return .busy
        case .missing: return .attention("Нет модели")
        case .failed: return .attention("Ошибка")
        }
    }

    private var subtitle: String {
        switch model.dictation.modelState {
        case .ready: "Whisper turbo · офлайн"
        case .loading: "Готовим модель"
        case .downloading(let fraction): "Загрузка модели · \(Int(fraction * 100))%"
        case .missing: "Модель не скачана"
        case .failed: "Модель не загрузилась"
        }
    }

    /// The popover owns focus while open; give it back to the previous app before pasting.
    private func insert(_ record: DictationRecord) {
        NSApp.keyWindow?.close()
        NSApp.deactivate()
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            model.dictation.insertAgain(record)
        }
    }

    private func wordsLabel(_ count: Int) -> String {
        let tens = count % 100
        let ones = count % 10
        if (11...14).contains(tens) { return "слов" }
        switch ones {
        case 1: return "слово"
        case 2...4: return "слова"
        default: return "слов"
        }
    }
}

private struct LastDictationCard: View {
    let record: DictationRecord
    let insert: () -> Void
    @State private var showRaw = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(meta)
                Spacer()
                Image(systemName: "line.3.horizontal").font(.system(size: 11, weight: .semibold))
            }
            .font(.onest(12))
            .opacity(0.85)

            Text(AttributedString.dictated(showRaw ? record.raw : record.text, size: 14.5))
                .lineSpacing(3)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            HStack(spacing: 6) {
                CardButton(title: copied ? "Скопировано" : "Копировать", icon: "doc.on.doc", prominent: true) {
                    Paster.copy(record.text)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                }
                if !record.raw.isEmpty, record.raw != record.text {
                    CardButton(title: showRaw ? "Оформлено" : "Как сказал") { showRaw.toggle() }
                }
                Spacer(minLength: 0)
                CardButton(title: "Вставить", action: insert)
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [World.ember.top, World.ember.upperMid, World.ember.lowerMid], startPoint: UnitPoint(x: 0.15, y: 0), endPoint: UnitPoint(x: 0.85, y: 1)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onDrag { NSItemProvider(object: record.text as NSString) }
    }

    private var meta: String {
        let time = record.date.formatted(date: .omitted, time: .shortened)
        return [record.appName, time].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct EmptyCard: View {
    let keyName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Диктовок пока нет").font(.onest(14.5, .semibold))
            Text("\(keyName) — запись").font(.onest(12.5)).opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.08))
        }
    }
}

private struct CardButton: View {
    let title: String
    var icon: String?
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.onest(12.5, prominent ? .semibold : .medium))
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .foregroundStyle(prominent ? Color(hex: 0xB3402E) : .white)
            .background(Capsule().fill(prominent ? .white : .white.opacity(0.2)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryRow: View {
    let record: DictationRecord
    @State private var hovered = false
    @State private var copied = false

    var body: some View {
        Button {
            Paster.copy(record.text)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            HStack(spacing: 10) {
                Text(record.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.onest(13.5))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LengthBars(duration: record.duration)
                Text(copied ? "Скопировано" : record.date.formatted(date: .omitted, time: .shortened))
                    .font(.onest(12))
                    .foregroundStyle(.white.opacity(0.45))
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hovered ? 0.08 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .onDrag { NSItemProvider(object: record.text as NSString) }
        .help(record.text)
    }
}

/// Four bars; lit bars show how long the dictation was, one per ~8 seconds.
private struct LengthBars: View {
    let duration: Double
    private let heights: [CGFloat] = [5, 9, 12, 7]

    var body: some View {
        let lit = min(4, max(1, Int((duration / 8).rounded(.up))))
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Color(hex: 0xFFA56A).opacity(index < lit ? 1 : 0.25))
                    .frame(width: 2, height: heights[index])
            }
        }
        .frame(height: 12)
    }
}

private struct StatusChip: View {
    enum Status: Equatable {
        case ready
        case busy
        case attention(String)
    }

    let status: Status

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.onest(12, .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(color.opacity(0.16)))
    }

    private var title: String {
        switch status {
        case .ready: "Готов"
        case .busy: "Загрузка"
        case .attention(let text): text
        }
    }

    private var color: Color {
        switch status {
        case .ready: Color(hex: 0x9EF0BD)
        case .busy: Color(hex: 0xBEE1FF)
        case .attention: Color(hex: 0xFFC58A)
        }
    }
}

private struct MenuRow: View {
    let icon: String
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 18).opacity(0.7)
                Text(title).font(.onest(14))
                Spacer()
                Text(shortcut).font(.onest(12.5)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hovered ? 0.08 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

extension AppSettings.RecordKey {
    var menuName: String {
        switch self {
        case .fn: "Fn"
        case .rightOption: "Правый ⌥"
        case .rightCommand: "Правый ⌘"
        }
    }
}
