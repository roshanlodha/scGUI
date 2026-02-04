import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MenuCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                if let dir = pickDirectory(title: "Choose a folder to use as the project") {
                    model.createProject(at: dir)
                }
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Open Project…") {
                if let dir = pickDirectory(title: "Open scGUI project") {
                    model.openProject(at: dir)
                }
            }
            .keyboardShortcut("o", modifiers: [.command])
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Back to Welcome") {
                model.closeProject()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Button("Close Project") {
                model.closeProject()
            }
            .disabled(!model.hasProject)

            Divider()
            Menu("Templates") {
                Button("Import Template…") {
                    if let url = pickFile(title: "Import template", allowedExtensions: ["json"]) {
                        model.importTemplate(from: url)
                    }
                }
                .disabled(!model.hasProject)
                Button("Save Current as Template…") {
                    if let url = saveFile(title: "Save template", defaultName: "template.json") {
                        model.saveCurrentTemplate(to: url)
                    }
                }
                .disabled(!model.hasProject || model.nodes.isEmpty)

                Divider()

                ForEach(model.availableTemplates, id: \.id) { t in
                    Button("Apply: \(t.name)") {
                        model.applyTemplate(t)
                    }
                }
                if model.availableTemplates.isEmpty {
                    Text("No templates found")
                }
            }
            .disabled(!model.hasProject)
        }
    }

    private func pickDirectory(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func pickFile(title: String, allowedExtensions: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func saveFile(title: String, defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [UTType.json]
        return panel.runModal() == .OK ? panel.url : nil
    }
}
