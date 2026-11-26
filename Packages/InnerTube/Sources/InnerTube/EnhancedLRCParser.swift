import Foundation

/// Reads enhanced LRC (`[mm:ss.xx]` line tags, `<mm:ss.xx>` word tags). No production source feeds it yet.
enum EnhancedLRCParser {
    // shortcut: several leading line tags (`[t1][t2]text`) are not expanded, add it if a source needs it.
    static func parse(_ text: String) -> TimedLyrics? {
        var rows: [(start: TimeInterval, body: String)] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]"),
                  let start = time(String(line[line.index(after: line.startIndex)..<close])) else { continue }
            rows.append((start, String(line[line.index(after: close)...])))
        }
        rows.sort { $0.start < $1.start }

        var lines: [TimedLyrics.Line] = []
        var measured = true
        for (index, row) in rows.enumerated() {
            let next = index + 1 < rows.count ? rows[index + 1].start : nil
            let parsed = segments(row.body)
            let plain = parsed.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            guard !plain.isEmpty else { continue }
            guard parsed.contains(where: { $0.start != nil }) else {
                measured = false
                lines.append(WordTiming.line(plain, start: row.start, end: next))
                continue
            }
            lines.append(timedLine(parsed, start: row.start, next: next))
        }
        guard !lines.isEmpty else { return nil }
        return TimedLyrics(lines: lines, source: nil, timing: measured ? .measured : .estimated)
    }

    private typealias Segment = (start: TimeInterval?, text: String)

    /// Splits a body at `<time>` tags. Text before the first tag has no start; a malformed tag joins the text before it.
    private static func segments(_ body: String) -> [Segment] {
        var result: [Segment] = [(nil, "")]
        var rest = Substring(body)
        while let open = rest.firstIndex(of: "<") {
            result[result.count - 1].text += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: ">") else {
                rest = rest[open...]
                break
            }
            if let start = time(String(rest[afterOpen..<close])) {
                result.append((start, ""))
            }
            rest = rest[rest.index(after: close)...]
        }
        result[result.count - 1].text += rest
        return result
    }

    private static func timedLine(_ parsed: [Segment], start: TimeInterval, next: TimeInterval?) -> TimedLyrics.Line {
        var words: [TimedLyrics.Word] = []
        for (index, segment) in parsed.enumerated() {
            let token = segment.text.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty, let wordStart = segment.start ?? (index == 0 ? start : nil) else { continue }
            let wordEnd = (index + 1 < parsed.count ? parsed[index + 1].start : nil) ?? next ?? wordStart
            words.append(.init(text: token, start: wordStart, end: max(wordEnd, wordStart)))
        }
        return .init(text: words.map(\.text).joined(separator: " "), start: start, end: words.last?.end, words: words)
    }

    private static func time(_ tag: String) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count <= 4, let minutes = Int(parts[0]), minutes >= 0 else { return nil }
        let seconds = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int(seconds[0]), (0..<60).contains(whole) else { return nil }
        var fraction = 0.0
        if seconds.count == 2 {
            guard (2...3).contains(seconds[1].count), seconds[1].allSatisfy({ $0.isASCII && $0.isNumber }), let digits = Int(seconds[1]) else { return nil }
            fraction = Double(digits) / (seconds[1].count == 2 ? 100 : 1000)
        } else if seconds.count > 2 { return nil }
        return Double(minutes * 60 + whole) + fraction
    }
}
