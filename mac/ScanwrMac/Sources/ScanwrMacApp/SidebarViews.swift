import SwiftUI

struct Sidebar: View {
    @Binding var section: SidebarSection

    var body: some View {
        List(SidebarSection.allCases, selection: $section) { s in
            Label(s.rawValue, systemImage: s.systemImage)
                .tag(s)
        }
        .navigationTitle("scanwr")
        .listStyle(.sidebar)
    }
}

struct Detail: View {
    var section: SidebarSection

    var body: some View {
        switch section {
        case .metadata:
            MetadataView()
        case .visualization:
            VisualizationView()
        case .pipelineBuilder:
            CanvasView()
        case .cohortAnalysis:
            CohortAnalysisView()
        }
    }
}

