import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    @State private var showOpenPicker = false
    @State private var showCreatePicker = false
    @State private var createProjectDir: URL?
    @State private var showClearCacheConfirm: Bool = false
    @State private var showSettings: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: branding
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                Text("scGUI")
                    .font(.system(size: 44, weight: .bold))
                Text("Single-cell pipelines for non-coders.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("scGUI, formerly scAnWr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(minWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            Divider()

            // Right: actions
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome")
                    .font(.largeTitle).bold()

                HStack(spacing: 12) {
                    Button {
                        showOpenPicker = true
                    } label: {
                        Label("Open Project…", systemImage: "folder")
                    }

                    Button {
                        showCreatePicker = true
                    } label: {
                        Label("New Project…", systemImage: "plus.rectangle.on.folder")
                    }

                    Spacer()

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")

                    Button {
                        showClearCacheConfirm = true
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help("Clear app cache")
                }
                .alert("Clear app cache?", isPresented: $showClearCacheConfirm) {
                    Button("Clear", role: .destructive) {
                        Task { await model.clearAppCache() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This clears cached files (matplotlib/fontconfig/numba) and restarts the backend.")
                }

                if let dir = createProjectDir {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Initialize project in:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(dir.path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Create") {
                            model.createProject(at: dir)
                            createProjectDir = nil
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Divider()

                Text("Recent")
                    .font(.headline)

                if model.recentProjects.isEmpty {
                    Text("No recent projects yet.")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(model.recentProjects, id: \.self) { path in
                            HStack {
                                Button {
                                    model.openProject(at: URL(fileURLWithPath: path))
                                } label: {
                                    Text(path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button(role: .destructive) {
                                    model.removeRecent(path)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }

                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { model.loadRecents() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .fileImporter(
            isPresented: $showOpenPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.openProject(at: url)
            }
        }
        .fileImporter(
            isPresented: $showCreatePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                createProjectDir = url
            }
        }
    }
}
