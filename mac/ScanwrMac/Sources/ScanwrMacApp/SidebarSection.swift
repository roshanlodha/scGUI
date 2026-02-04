import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case metadata = "Metadata"
    case pipelineBuilder = "Pipeline Builder"
    case visualization = "Visualization"
    case cohortAnalysis = "Cohort Analysis"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .metadata:
            "tablecells"
        case .visualization:
            "chart.bar.xaxis"
        case .pipelineBuilder:
            "flowchart"
        case .cohortAnalysis:
            "person.3"
        }
    }
}
