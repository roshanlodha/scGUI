import SwiftUI
import AppKit

struct VisualizationWorkspaceView: View {
    @Binding var showSettings: Bool
    @State private var plotURL: URL?

    var body: some View {
        HSplitView {
            VisualizationPreviewPanel(url: plotURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VisualizationEditorSidebar(showSettings: $showSettings, plotURL: $plotURL)
                .frame(minWidth: 420, idealWidth: 520, maxWidth: 640)
        }
    }
}

private struct VisualizationEditorSidebar: View {
    @Binding var showSettings: Bool
    @Binding var plotURL: URL?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Customize Plot")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.horizontal, 4)

            Divider()

            ExploreDataView(showsHeader: false, showsClose: false, showsPreview: false, plotURL: $plotURL)
        }
        .panelChrome()
        .padding(10)
    }
}

private struct VisualizationPreviewPanel: View {
    var url: URL?

    var body: some View {
        ZStack {
            if let url, FileManager.default.fileExists(atPath: url.path) {
                SVGWebView(fileURL: url)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No plot yet.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .panelChrome()
        .padding(10)
    }
}
