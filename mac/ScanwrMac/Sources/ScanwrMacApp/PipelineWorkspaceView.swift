import SwiftUI
import UniformTypeIdentifiers

struct PipelineWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showSettings: Bool
    @Binding var showConsole: Bool
    @State private var isDropTarget = false

    var body: some View {
        HSplitView {
            PipelineCanvasDropView(isDropTarget: $isDropTarget)
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

private struct PipelineCanvasDropView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isDropTarget: Bool

    var body: some View {
        ZStack {
            CanvasView()
        }
        .onDrop(of: [UTType.plainText], delegate: ModuleDropDelegate(model: model, isDropTarget: $isDropTarget))
    }
}

private struct ModuleDropDelegate: DropDelegate {
    @MainActor var model: AppModel
    @Binding var isDropTarget: Bool

    func dropEntered(info: DropInfo) {
        isDropTarget = true
    }

    func dropExited(info: DropInfo) {
        isDropTarget = false
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func performDrop(info: DropInfo) -> Bool {
        isDropTarget = false
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        let point = info.location

        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _error in
            let text: String? = {
                if let s = item as? String { return s }
                if let data = item as? Data { return String(data: data, encoding: .utf8) }
                if let ns = item as? NSString { return ns as String }
                return nil
            }()
            let specId = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !specId.isEmpty else { return }

            Task { @MainActor in
                guard let spec = model.availableModules.first(where: { $0.id == specId }) else {
                    model.appendLog("Drop ignored: unknown module id \(specId)")
                    return
                }
                model.addNode(spec: spec, at: point)
            }
        }
        return true
    }
}
