import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingDirPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.title3).bold()
            Text("Choose a project directory and name. Outputs are written under `Project/samples/<sample>/checkpoint/`.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Project name", text: $model.projectName)
                    .frame(width: 240)
            }

            HStack(spacing: 10) {
                TextField("Project directory", text: $model.outputDirectory)
                Button("Browse…") { showingDirPicker = true }
            }

            if model.outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Project directory is required.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 640, height: 260)
        .fileImporter(
            isPresented: $showingDirPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.outputDirectory = url.path
            }
        }
    }
}
