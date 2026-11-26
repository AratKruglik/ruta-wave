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
        var lines: [TimedLyrics.Line] = []
        for raw in lyricsData.timedLyricsData {
            guard let cue = raw.cueRange else { return nil }
            guard let milliseconds = Int(cue.startTimeMilliseconds), milliseconds >= 0 else { throw .unexpectedResponse }
            let text = raw.lyricLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { lines.append(.init(text: text, start: Double(milliseconds) / 1000)) }
        }
        guard !lines.isEmpty else { return nil }
        return TimedLyrics(lines: lines.sorted { $0.start < $1.start }, source: lyricsData.sourceMessage)
    }

    private struct Response: Decodable {
        struct Model: Decodable {
            struct Timed: Decodable {
                struct LyricsData: Decodable {
                    struct Line: Decodable {
                        struct Cue: Decodable { let startTimeMilliseconds: String }
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
