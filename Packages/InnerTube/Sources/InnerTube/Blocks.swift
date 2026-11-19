import os

let parserLog = Logger(subsystem: "dev.kruhlyk.redwave", category: "parser")

func parseBlocks<T>(_ blocks: [JSONValue], _ transform: (JSONValue) -> T?) -> [T] {
    blocks.compactMap { block in
        let parsed = transform(block)
        if parsed == nil, block["continuationItemRenderer"] == nil {
            parserLog.notice("Skipped block \(blockKey(block), privacy: .public)")
        }
        return parsed
    }
}

// Only the renderer name is ever logged, never a value.
func blockKey(_ block: JSONValue) -> String {
    guard let key = block.object?.keys.min() else { return "non-object" }
    return String(key.prefix(64))
}
