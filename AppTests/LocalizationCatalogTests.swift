import Foundation
import Testing

struct LocalizationCatalogTests {
    private func catalog() -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../App/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let strings = root["strings"] as? [String: [String: Any]] else { return [:] }
        return strings
    }

    private func hasValue(_ unit: Any?) -> Bool {
        guard let unit = unit as? [String: Any], let value = unit["value"] as? String else { return false }
        return !value.isEmpty
    }

    private func hasTranslation(_ entry: [String: Any]) -> Bool {
        guard let localizations = entry["localizations"] as? [String: Any], let uk = localizations["uk"] as? [String: Any] else { return false }
        if hasValue(uk["stringUnit"]) { return true }
        guard let variations = uk["variations"] as? [String: [String: Any]] else { return false }
        let units = variations.values.flatMap { $0.values }
        return !units.isEmpty && units.allSatisfy { hasValue(($0 as? [String: Any])?["stringUnit"]) }
    }

    @Test func catalogLoads() {
        #expect(!catalog().isEmpty)
    }

    @Test func everyTranslatableKeyHasANonEmptyUkrainianValue() {
        let missing = catalog().filter { $0.value["shouldTranslate"] as? Bool != false && !hasTranslation($0.value) }.keys.sorted()
        #expect(missing.isEmpty, "Missing uk translation: \(missing)")
    }

    @Test func selectionBarAndRemoveKeysAreTranslated() {
        let strings = catalog()
        for key in ["Play next (short)", "Queue", "Remove"] {
            #expect(strings[key].map(hasTranslation) == true, "Missing uk translation: \(key)")
        }
    }

    @Test func retiredWordmarkKeysAreGone() {
        let strings = catalog()
        #expect(strings["RutaWave"] == nil)
        #expect(strings["RutaWave, go to Home"] == nil)
    }
}
