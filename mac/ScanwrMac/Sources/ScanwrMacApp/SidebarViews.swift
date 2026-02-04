import SwiftUI

struct Sidebar: View {
    @Binding var section: SidebarSection

    var body: some View {
        List(SidebarSection.allCases, selection: $section) { s in
            Label(s.rawValue, systemImage: s.systemImage)
                .tag(s)
        }
        .navigationTitle("scGUI")
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .panelChrome()
        .padding(10)
    }
}
