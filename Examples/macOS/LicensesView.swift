import SwiftUI

private struct LicenseNotice: Decodable, Identifiable {
    let name: String
    let version: String
    let url: URL
    let text: String
    var id: String { name }
}

struct LicensesView: View {
    @State private var search = ""
    private let notices: [LicenseNotice]

    init() {
        if let url = Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([LicenseNotice].self, from: data) {
            notices = decoded
        } else {
            notices = []
        }
    }

    var body: some View {
        List {
            Section {
                Text(String(localized: "This app includes the following open-source software. Original license and source-availability notices are included below."))
                    .foregroundStyle(.secondary)
            }
            if notices.isEmpty {
                Text(String(localized: "License notices could not be loaded."))
            }
            ForEach(notices.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }) { notice in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent(String(localized: "Package version"), value: notice.version)
                        Link(String(localized: "Source and project website"), destination: notice.url)
                        Text(verbatim: notice.text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.vertical, 8)
                } label: {
                    Text(verbatim: notice.name).font(.headline)
                }
            }
        }
        .searchable(text: $search, prompt: Text(String(localized: "Search licenses")))
        .navigationTitle(String(localized: "Licenses"))
    }
}
