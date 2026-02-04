import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingDirPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.title3).bold()

            GroupBox("App") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Verbosity")
                        Spacer()
                        Text("\(model.verbosity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(model.verbosity) },
                            set: { model.setVerbosity(Int($0.rounded())) }
                        ),
                        in: 0...4,
                        step: 1
                    )
                    Text("Lower = quieter console, higher = more details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }

            GroupBox("Project") {
                VStack(alignment: .leading, spacing: 10) {
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
                }
                .padding(10)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 680, height: 420)
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
