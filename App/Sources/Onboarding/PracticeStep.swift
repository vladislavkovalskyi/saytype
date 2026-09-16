import SwiftUI
import VMCore

/// Step 7: a real text field the user dictates into.
struct PracticeStep: View {
    private enum Mode: Hashable {
        case formatted
        case raw
    }

    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var mode = Mode.formatted
    /// The newest record when the step opened; only dictations after it count.
    @State private var baseline: UUID?
    @State private var opened = false
    @FocusState private var editorFocused: Bool

    private var record: DictationRecord? {
        guard opened, let first = model.dictation.history.first, first.id != baseline else { return nil }
        return first
    }

    var body: some View {
        let key = model.settings.value.recordKey
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                StepTitle("Попробуй")
                HStack(spacing: 6) {
                    Text("Зажми")
                    Kbd(text: key.inlineName, height: 24)
                    Text("и продиктуй пару фраз.")
                }
                .font(.onest(15))
                .foregroundStyle(.white.opacity(0.84))
                .padding(.top, 12)
            }
            .frame(width: 330, alignment: .leading)
            .place(x: 56, y: 118)

            HeroObject(
                name: "ObjectTextcard",
                halo: CGRect(x: 10, y: 250, width: 420, height: 330),
                object: CGRect(x: 52, y: 281, width: 306, height: 231)
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    WorldSegmented(options: [Mode.formatted, .raw], selection: $mode) { mode in
                        switch mode {
                        case .formatted: "Оформлено"
                        case .raw: "Как сказал"
                        }
                    }
                    Spacer(minLength: 0)
                    if let record {
                        Muted(meta(for: record))
                            .monospacedDigit()
                            .transition(.opacity)
                    }
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.onest(17))
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.hidden)
                        .foregroundStyle(.white)
                        .tint(.white)
                        .focused($editorFocused)
                        .padding(.horizontal, -5)
                        .opacity(mode == .formatted ? 1 : 0)
                        .allowsHitTesting(mode == .formatted)

                    if mode == .raw {
                        ScrollView {
                            Text(record?.raw ?? "")
                                .font(.onest(17))
                                .lineSpacing(5)
                                .foregroundStyle(.white.opacity(0.9))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(.top, 22)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .frame(width: 490, height: 400, alignment: .topLeading)
            .frost()
            .place(x: 420, y: 96)
        }
        .stepCanvas()
        .animation(.snappy(duration: 0.2), value: record?.id)
        .onAppear {
            if !opened {
                baseline = model.dictation.history.first?.id
                opened = true
            }
            editorFocused = true
        }
        .onChange(of: record?.id) { _, id in
            // The paste lands in the editor: show it.
            if id != nil { mode = .formatted }
        }
    }

    /// "12 с · 0,9 с": speech length, then processing time when it is known.
    private func meta(for record: DictationRecord) -> String {
        var parts = ["\(max(1, Int(record.duration.rounded()))) с"]
        if let startedAt = model.dictation.startedAt {
            let processing = record.date.timeIntervalSince(startedAt) - record.duration
            if processing > 0, processing < 60 {
                parts.append(processing.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "ru_RU"))) + " с")
            }
        }
        return parts.joined(separator: " · ")
    }
}
