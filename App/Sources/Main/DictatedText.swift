import AppKit
import SwiftUI

/// Dictated text laid out word by word, with identifiers on code chips.
struct DictatedText: View {
    let text: String
    var size: CGFloat = 17
    var lineHeight: CGFloat = 1.9
    var codeOpacity: Double = 0.2
    /// Words set as code even when they do not look like identifiers.
    var codeWords: Set<String> = []
    /// Indices of picked words, as in `Words.split`; set to let a click pick words.
    var selection: Binding<ClosedRange<Int>?>?

    var body: some View {
        let words = WordDiff.tokens(text).map { WordDiff.Word(segments: [.init(text: $0.word, kind: .same)], startsParagraph: $0.startsParagraph) }
        WordParagraphs(words: words, size: size, lineHeight: lineHeight, codeOpacity: codeOpacity, codeWords: codeWords, selection: selection)
    }
}

/// Inserted text with the changes against the raw transcript marked.
struct DiffText: View {
    let raw: String
    let text: String
    var size: CGFloat = 17
    var lineHeight: CGFloat = 1.9

    var body: some View {
        WordParagraphs(words: WordDiff.compare(raw: raw, text: text), size: size, lineHeight: lineHeight, codeOpacity: 0.2, codeWords: [])
    }
}

private struct WordParagraphs: View {
    let words: [WordDiff.Word]
    let size: CGFloat
    let lineHeight: CGFloat
    let codeOpacity: Double
    let codeWords: Set<String>
    var selection: Binding<ClosedRange<Int>?>?

    var body: some View {
        let lineSpacing = max(0, size * (lineHeight - 1.3))
        VStack(alignment: .leading, spacing: lineSpacing + 10) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                FlowLayout(spacing: size * 0.27, lineSpacing: lineSpacing) {
                    ForEach(paragraph, id: \.index) { item in
                        if let selection {
                            PickableWord(index: item.index, selection: selection) {
                                WordView(word: item.word, size: size, codeOpacity: codeOpacity, codeWords: codeWords)
                            }
                        } else {
                            WordView(word: item.word, size: size, codeOpacity: codeOpacity, codeWords: codeWords)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Item {
        let index: Int
        let word: WordDiff.Word
    }

    private var paragraphs: [[Item]] {
        var result: [[Item]] = []
        for (index, word) in words.enumerated() {
            if word.startsParagraph || result.isEmpty {
                result.append([Item(index: index, word: word)])
            } else {
                result[result.count - 1].append(Item(index: index, word: word))
            }
        }
        return result
    }
}

/// A word that a click picks and a shift-click adds to the picked range.
private struct PickableWord<Content: View>: View {
    let index: Int
    @Binding var selection: ClosedRange<Int>?
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        let isPicked = selection?.contains(index) ?? false
        content
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(isPicked ? 0.24 : isHovered ? 0.12 : 0))
                    .overlay {
                        if isPicked {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                        }
                    }
                    .padding(.horizontal, -4)
                    .padding(.vertical, -2)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .help(Text("Fix spelling", comment: "Tooltip of a word in the history: a click picks it for a dictionary entry"))
            .onTapGesture { pick(extending: NSEvent.modifierFlags.contains(.shift)) }
    }

    private func pick(extending: Bool) {
        guard let current = selection else {
            selection = index...index
            return
        }
        if extending {
            selection = min(current.lowerBound, index)...max(current.upperBound, index)
        } else {
            selection = current == index...index ? nil : index...index
        }
    }
}

private struct WordView: View {
    let word: WordDiff.Word
    let size: CGFloat
    let codeOpacity: Double
    let codeWords: Set<String>

    var body: some View {
        let parts = CodeWords.split(word.text)
        if word.isUnchanged, codeWords.contains(parts.core) || CodeWords.isCode(parts.core) {
            HStack(spacing: 0) {
                Text(parts.leading)
                CodeSpan(text: parts.core, size: size * 0.88, opacity: codeOpacity)
                Text(parts.trailing)
            }
            .font(.onest(size))
        } else {
            HStack(spacing: 0) {
                ForEach(Array(word.segments.enumerated()), id: \.offset) { _, segment in
                    SegmentView(segment: segment, size: size)
                }
            }
        }
    }
}

private struct SegmentView: View {
    let segment: WordDiff.Segment
    let size: CGFloat

    var body: some View {
        switch segment.kind {
        case .same:
            Text(segment.text).font(.onest(size))
        case .removed:
            Text(segment.text)
                .font(.onest(size))
                .strikethrough(color: .white.opacity(0.8))
                .foregroundStyle(.white.opacity(0.5))
        case .added:
            Text(segment.text)
                .font(.onest(size, .bold))
                .padding(.horizontal, 2)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.white.opacity(0.3))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(.white).frame(height: 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
        }
    }
}
