import Foundation

enum LyricsParser {
    /// `nil` is "Lyrics not available".
    static func parse(_ json: JSONValue) throws(InnerTubeError) -> Lyrics? {
        let shelf = json["contents"]?["sectionListRenderer"]?["contents"]?[0]?["musicDescriptionShelfRenderer"]
        if let body = shelf?["description"].flatMap(text) {
            return Lyrics(
                text: body.replacingOccurrences(of: "\r\n", with: "\n"),
                source: shelf?["footer"].flatMap(text))
        }
        if json["contents"]?["messageRenderer"] != nil { return nil }
        throw .unexpectedResponse
    }
}
