import Foundation

/// Spreads a line's duration over its words, weighted by character count.
enum WordTiming {
    static func estimate(_ text: String, start: TimeInterval, end: TimeInterval) -> [TimedLyrics.Word] {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let total = tokens.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        var consumed = 0
        return tokens.enumerated().map { index, token in
            let wordStart = start + (end - start) * Double(consumed) / Double(total)
            consumed += token.count
            let wordEnd = index == tokens.count - 1 ? end : start + (end - start) * Double(consumed) / Double(total)
            return TimedLyrics.Word(text: token, start: wordStart, end: wordEnd)
        }
    }

    /// A line whose end is unknown or not after its start stays line-only.
    static func line(_ text: String, start: TimeInterval, end: TimeInterval?) -> TimedLyrics.Line {
        guard let end, end > start else { return .init(text: text, start: start, end: end) }
        return .init(text: text, start: start, end: end, words: estimate(text, start: start, end: end))
    }
}
