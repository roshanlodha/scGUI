import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAddModule = false
    @State private var showSettings = false
    @State private var showExplore = false
    @State private var section: SidebarSection = .pipelineBuilder

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                onExplore: { showExplore = true },
                onAddModule: { showAddModule = true },
                onSettings: { showSettings = true },
                onRun: { model.startRun() },
                onStop: { Task { await model.stopRun() } }
            )
            Divider()
            VSplitView {
                NavigationSplitView {
                    Sidebar(section: $section)
                } detail: {
                    Detail(section: section)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .navigationSplitViewStyle(.balanced)

                ConsolePanel(lines: model.logs)
                    .frame(minHeight: 160, idealHeight: 240)
            }
        }
        .task { await model.loadModules() }
        .sheet(isPresented: $showExplore) {
            ExploreDataView()
                .frame(minWidth: 1020, minHeight: 720)
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .popover(isPresented: $showAddModule, arrowEdge: .top) {
            AddModulePopover { spec in
                // Drop near center; user can drag anywhere.
                model.addNode(spec: spec, at: CGPoint(x: 300, y: 220))
                showAddModule = false
            }
            .frame(width: 420, height: 420)
        }
    }
}

private struct TopBar: View {
    @EnvironmentObject private var model: AppModel

    var onExplore: () -> Void
    var onAddModule: () -> Void
    var onSettings: () -> Void
    var onRun: () -> Void
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    onExplore()
                } label: {
                    Label("Explore Data", systemImage: "chart.xyaxis.line")
                }
                .disabled(!model.hasProject)

                Button {
                    onAddModule()
                } label: {
                    Label("Add Module", systemImage: "plus.circle")
                }
                .disabled(model.isRunning)

                Spacer()

                Button {
                    onSettings()
                } label: {
                    Image(systemName: "info.circle")
                        .imageScale(.large)
                }
                .help("Settings")
                .disabled(model.isRunning)

                if model.isRunning {
                    Button {
                        onStop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .imageScale(.large)
                    }
                    .help("Stop run")
                } else {
                    Button {
                        onRun()
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .imageScale(.large)
                    }
                    .help("Run pipeline")
                    .disabled(
                        model.outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.samples.isEmpty
                        || model.nodes.isEmpty
                    )
                }
            }

            if model.isRunning {
                HStack(spacing: 10) {
                    ProgressView(value: model.progressPercent)
                        .frame(maxWidth: .infinity)
                    Text(model.progressMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 260, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct AddModulePopover: View {
    @EnvironmentObject private var model: AppModel
    var onPick: (ModuleSpec) -> Void

    @State private var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a module").font(.headline)
            TextField("Search modules…", text: $query)
            if model.isLoadingModules {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView("Loading modules…")
                    Text("Starting Python backend (first launch may take ~10–30s).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                    Spacer()
                }
            } else if model.availableModules.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No modules available.")
                        .font(.headline)
                    if let err = model.moduleLoadError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .textSelection(.enabled)
                    } else {
                        Text("If this is your first launch, open the Console for backend logs and retry.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    }
                    Button("Retry") {
                        Task { await model.loadModules() }
                    }
                    Spacer()
                }
            } else {
                List {
                    ForEach(ModuleGroup.allCases, id: \.self) { grp in
                        Section(grp.title) {
                            ForEach(filtered(group: grp)) { spec in
                                Button {
                                    onPick(spec)
                                } label: {
                                    HStack {
                                        Text(spec.title)
                                        Spacer()
                                        if let ns = spec.namespace, ns != "core" {
                                            Text(ns == "experimental" ? "exp" : "ext")
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.primary.opacity(0.10))
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        Text(grp.badge)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(hex: grp.colorHex).opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func filtered(group: ModuleGroup) -> [ModuleSpec] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = model.availableModules.filter { $0.group == group }
        if q.isEmpty { return base }
        return base.filter { spec in
            spec.title.lowercased().contains(q)
                || spec.scanpyQualname.lowercased().contains(q)
                || (spec.namespace ?? "").lowercased().contains(q)
        }
    }
}

private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
