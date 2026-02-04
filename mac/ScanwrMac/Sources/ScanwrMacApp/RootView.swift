import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var section: SidebarSection = .pipelineBuilder
    @State private var showConsole = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                NavigationSplitView {
                    Sidebar(section: $section)
                } detail: {
                    switch section {
                    case .metadata:
                        MetadataView()
                    case .pipelineBuilder:
                        PipelineWorkspaceView(
                            showSettings: $showSettings,
                            showConsole: $showConsole
                        )
                    case .visualization:
                        VisualizationWorkspaceView(showSettings: $showSettings)
                    case .cohortAnalysis:
                        CohortAnalysisView()
                    }
                }
                .navigationSplitViewStyle(.balanced)

                if showConsole && section == .pipelineBuilder {
                    Divider()
                    ConsolePanel(lines: model.logs)
                        .frame(height: 240)
                        .padding(10)
                }
            }
        }
        .task { await model.loadModules() }
        .onChange(of: section) { _, new in
            if new != .pipelineBuilder {
                showConsole = false
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }
}
