import SwiftUI

/// Dictated text laid out word by word, with identifiers on code chips.
struct DictatedText: View {
    let text: String
    var size: CGFloat = 17
    var lineHeight: CGFloat = 1.9
    var codeOpacity: Double = 0.2
    /// Words set as code even when they do not look like identifiers.
    var codeWords: Set<String> = []

    var body: some View {
        let words = WordDiff.tokens(text).map { WordDiff.Word(segments: [.init(text: $0.word, kind: .same)], startsParagraph: $0.startsParagraph) }
        WordParagraphs(words: words, size: size, lineHeight: lineHeight, codeOpacity: codeOpacity, codeWords: codeWords)
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

    var body: some View {
        let lineSpacing = max(0, size * (lineHeight - 1.3))
        VStack(alignment: .leading, spacing: lineSpacing + 10) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                FlowLayout(spacing: size * 0.27, lineSpacing: lineSpacing) {
                    ForEach(Array(paragraph.enumerated()), id: \.offset) { _, word in
                        WordView(word: word, size: size, codeOpacity: codeOpacity, codeWords: codeWords)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paragraphs: [[WordDiff.Word]] {
        var result: [[WordDiff.Word]] = []
        for word in words {
            if word.startsParagraph || result.isEmpty {
                result.append([word])
            } else {
                result[result.count - 1].append(word)
            }
        }
        return result
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
