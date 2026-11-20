import SwiftUI

struct ChartsScreen: View {
    let model: BrowseModel

    var body: some View {
        BrowseScreen(model: model) { page in
            if !page.countries.isEmpty {
                Picker(
                    "Country",
                    selection: Binding(get: { page.selectedCountry ?? "" }, set: model.selectCountry)
                ) {
                    ForEach(page.countries, id: \.code) { Text($0.name).tag($0.code) }
                }
                .pickerStyle(.menu)
                .font(.rwButton)
                .fixedSize()
            }
        }
    }
}
