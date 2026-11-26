import Foundation

/// Reads the mobile (`ANDROID_MUSIC`) lyrics answer through a narrow `Decodable`; the rest of the answer is huge and unused.
enum TimedLyricsParser {
    /// `nil` is "no timed lyrics": a message, no lines, or lines without times.
    static func parse(_ data: Data) throws(InnerTubeError) -> TimedLyrics? {
        let model: Response.Model
        do {
            model = try JSONDecoder().decode(Response.self, from: data).model
        } catch {
            throw .unexpectedResponse
        }
        if model.musicMessageModel != nil { return nil }
        guard let lyricsData = model.timedLyricsModel?.lyricsData else { throw .unexpectedResponse }
        var cues: [(text: String, start: TimeInterval, end: TimeInterval?)] = []
        for raw in lyricsData.timedLyricsData {
            guard let cue = raw.cueRange else { return nil }
            guard let milliseconds = Int(cue.startTimeMilliseconds), milliseconds >= 0 else { throw .unexpectedResponse }
            let text = raw.lyricLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = cue.endTimeMilliseconds.flatMap { Int($0) }.map { Double($0) / 1000 }
            if !text.isEmpty { cues.append((text, Double(milliseconds) / 1000, end)) }
        }
        guard !cues.isEmpty else { return nil }
        cues.sort { $0.start < $1.start }
        let lines = cues.enumerated().map { index, cue in
            let next = index + 1 < cues.count ? cues[index + 1].start : nil
            var end = cue.end.flatMap { $0 > cue.start ? $0 : nil } ?? next
            if let limit = next, let value = end, value > limit { end = limit }
            return WordTiming.line(cue.text, start: cue.start, end: end)
        }
        return TimedLyrics(lines: lines, source: lyricsData.sourceMessage)
    }

    private struct Response: Decodable {
        struct Model: Decodable {
            struct Timed: Decodable {
                struct LyricsData: Decodable {
                    struct Line: Decodable {
                        struct Cue: Decodable {
                            let startTimeMilliseconds: String
                            let endTimeMilliseconds: String?

                            private enum CodingKeys: String, CodingKey { case startTimeMilliseconds, endTimeMilliseconds }

                            init(from decoder: Decoder) throws {
                                let container = try decoder.container(keyedBy: CodingKeys.self)
                                startTimeMilliseconds = try container.decode(String.self, forKey: .startTimeMilliseconds)
                                endTimeMilliseconds = try? container.decodeIfPresent(String.self, forKey: .endTimeMilliseconds)
                            }
                        }
                        let lyricLine: String
                        let cueRange: Cue?
                    }
                    let timedLyricsData: [Line]
                    let sourceMessage: String?
                }
                let lyricsData: LyricsData
            }
            struct Message: Decodable {}
            let timedLyricsModel: Timed?
            let musicMessageModel: Message?
        }
        struct Contents: Decodable {
            struct Element: Decodable {
                struct NewElement: Decodable {
                    struct Kind: Decodable {
                        struct Component: Decodable { let model: Model }
                        let componentType: Component
                    }
                    let type: Kind
                }
                let newElement: NewElement
            }
            let elementRenderer: Element
        }
        let contents: Contents
        var model: Model { contents.elementRenderer.newElement.type.componentType.model }
    }
}
