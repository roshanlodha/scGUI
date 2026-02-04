import SwiftUI

struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var section: SidebarSection

    var body: some View {
        VStack(spacing: 0) {
            List(SidebarSection.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.systemImage)
                    .tag(s)
            }

            Spacer(minLength: 0)

            Divider()

            Button {
                model.closeProject()
            } label: {
                Label("Home", systemImage: "house")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .navigationTitle("scGUI")
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .panelChrome()
        .padding(10)
    }
}
