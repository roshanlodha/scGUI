import SwiftUI

struct PipelineWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showSettings: Bool
    @Binding var showConsole: Bool
    @State private var isDropTarget = false

    var body: some View {
        HSplitView {
            CanvasView(isDropTarget: $isDropTarget)
                .overlay(alignment: .topLeading) {
                    if isDropTarget {
                        Text("Drop to add module")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(12)
                    }
                }

            ModulePaletteSidebar(showSettings: $showSettings, showConsole: $showConsole)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
        }
    }
}
