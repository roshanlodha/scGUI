import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var availableModules: [ModuleSpec] = []
    @Published var isLoadingModules: Bool = false
    @Published var moduleLoadError: String? = nil

    // Pipeline canvas state
    @Published var nodes: [PipelineNode] = [] {
        didSet { schedulePersistCurrentWorkflow() }
    }
    @Published var links: [PipelineLink] = [] {
        didSet { schedulePersistCurrentWorkflow() }
    }
    @Published var selectedNodeId: UUID?

    // Project + metadata
    @Published var samples: [SampleMetadata] = []
    @Published var outputDirectory: String = ""
    @Published var projectName: String = "scGUI-project"
    @Published var recentProjects: [String] = []

    // Templates
    @Published var availableTemplates: [WorkflowTemplate] = []

    // Logs
    @Published var logs: [String] = []

    // Progress
    @Published var isRunning: Bool = false
    @Published var progressPercent: Double = 0
    @Published var progressMessage: String = ""

    // App settings
    @Published var verbosity: Int = 3

    private let rpc = PythonRPCClient()
    private var workflowSaveWorkItem: DispatchWorkItem?
    private var runTask: Task<Void, Never>?

    init() {
        loadAppSettings()
        Task { await loadModules() }
    }

    var hasProject: Bool {
        !outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var projectPath: URL? {
        let base = outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty || name.isEmpty { return nil }
        return URL(fileURLWithPath: base).appendingPathComponent(name)
    }

    static func sanitizeFilename(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "step" }
        var out: [Character] = []
        for ch in trimmed {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "." {
                out.append(ch)
            } else {
                out.append("_")
            }
        }
        let joined = String(out)
        let stripped = joined.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return stripped.isEmpty ? "step" : stripped
    }

    // MARK: Logging / progress

    func appendLog(_ line: String) {
        logs.append(line)
    }

    func setProgress(_ ev: PythonRPCClient.ProgressEvent) {
        progressPercent = max(0, min(1, ev.percent))
        progressMessage = ev.message
    }

    // MARK: Backend

    func ensureBackendStarted() async {
        if rpc.isRunning { return }
        do {
            try await rpc.start(
                verbosity: verbosity,
                onLog: { [weak self] msg in
                    await self?.appendLog(msg)
                },
                onProgress: { [weak self] ev in
                    await self?.setProgress(ev)
                }
            )
            appendLog("Backend: started")
        } catch {
            appendLog("Backend ERROR: \(error)")
        }
    }

    private func loadAppSettings() {
        if let v = UserDefaults.standard.object(forKey: "scgui.verbosity") as? Int {
            verbosity = max(0, min(4, v))
        } else {
            verbosity = 3
        }
    }

    func setVerbosity(_ level: Int) {
        let clamped = max(0, min(4, level))
        verbosity = clamped
        UserDefaults.standard.set(clamped, forKey: "scgui.verbosity")
        Task {
            await ensureBackendStarted()
            do {
                struct Params: Codable { var level: Int }
                struct Res: Codable { var ok: Bool }
                let res: Res = try await rpc.call(method: "set_verbosity", params: Params(level: clamped))
                if res.ok {
                    appendLog("Verbosity set to \(clamped)")
                }
            } catch {
                appendLog("set_verbosity ERROR: \(error)")
            }
        }
    }

    func loadModules() async {
        if isLoadingModules { return }
        isLoadingModules = true
        moduleLoadError = nil
        await ensureBackendStarted()
        do {
            let specs: [ModuleSpec] = try await rpc.call(method: "list_modules", params: [:])
            availableModules = specs
            appendLog("Modules: loaded \(specs.count)")
        } catch {
            let msg = "list_modules ERROR: \(error)"
            moduleLoadError = msg
            appendLog(msg)
        }
        isLoadingModules = false
    }

    // MARK: Cache

    func clearAppCache() async {
        appendLog("Clearing app cache…")
        await rpc.stop()

        for dir in Self.appCacheDirsToClear() {
            do {
                if FileManager.default.fileExists(atPath: dir.path) {
                    try FileManager.default.removeItem(at: dir)
                }
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                appendLog("Cleared: \(dir.path)")
            } catch {
                appendLog("ERROR: clear cache failed (\(dir.path)): \(error)")
            }
        }

        await loadModules()
    }

    private static func appCacheDirsToClear() -> [URL] {
        var dirs: [URL] = []

        if let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            dirs.append(base.appendingPathComponent("scGUI", isDirectory: true))
        }
        dirs.append(FileManager.default.temporaryDirectory.appendingPathComponent("scgui-cache", isDirectory: true))

        // Clear dupes while preserving order.
        var seen: Set<String> = []
        return dirs.filter { url in
            let key = url.standardizedFileURL.path
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    func detectReader(for path: String) async -> ReaderSuggestion? {
        await ensureBackendStarted()
        struct Params: Codable { var path: String }
        do {
            return try await rpc.call(method: "detect_reader", params: Params(path: path))
        } catch {
            appendLog("detect_reader ERROR: \(error)")
            return nil
        }
    }

    // MARK: Explore (plots)

    func inspectH5ad(path: String, varNamesLimit: Int = 5000) async throws -> AdataInspectResult {
        await ensureBackendStarted()
        struct Params: Codable { var path: String; var varNamesLimit: Int }
        return try await rpc.call(method: "inspect_h5ad", params: Params(path: path, varNamesLimit: varNamesLimit))
    }

    func plotViolin(req: ViolinPlotRequest) async throws -> ViolinPlotResult {
        await ensureBackendStarted()
        return try await rpc.call(method: "plot_violin", params: req)
    }

    func plotCustom(req: CustomPlotRequest) async throws -> CustomPlotResult {
        await ensureBackendStarted()
        return try await rpc.call(method: "plot_custom", params: req)
    }

    // MARK: Project open/create/close + recents

    func loadRecents() {
        recentProjects = UserDefaults.standard.array(forKey: "scgui.recentProjects") as? [String] ?? []
    }

    func addRecent(_ path: String) {
        var items = recentProjects
        items.removeAll(where: { $0 == path })
        items.insert(path, at: 0)
        recentProjects = Array(items.prefix(12))
        UserDefaults.standard.set(recentProjects, forKey: "scgui.recentProjects")
    }

    func removeRecent(_ path: String) {
        recentProjects.removeAll(where: { $0 == path })
        UserDefaults.standard.set(recentProjects, forKey: "scgui.recentProjects")
    }

    func openProject(at url: URL) {
        let fm = FileManager.default
        var projectURL = url
        if url.lastPathComponent == ".scanwr" {
            projectURL = url.deletingLastPathComponent()
        } else if fm.fileExists(atPath: url.appendingPathComponent(".scanwr").path) {
            projectURL = url
        } else {
            appendLog("ERROR: Selected folder is not a scGUI project (missing .scanwr/).")
            return
        }

        outputDirectory = projectURL.deletingLastPathComponent().path
        projectName = projectURL.lastPathComponent
        addRecent(projectURL.path)

        loadTemplatesForCurrentProject()
        loadOrInitCurrentWorkflow()

        let metaURL = projectURL.appendingPathComponent(".scanwr/metadata.txt")
        if let text = try? String(contentsOf: metaURL) {
            samples = Self.parseMetadata(text)
            appendLog("Loaded project: \(projectURL.path)")
        } else {
            samples = []
            appendLog("Opened project (no metadata): \(projectURL.path)")
        }
    }

    func createProject(baseDir: URL, name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let projectURL = baseDir.appendingPathComponent(clean)
        let scanwrURL = projectURL.appendingPathComponent(".scanwr")
        let checkpointsURL = scanwrURL.appendingPathComponent("checkpoints")
        let historyURL = scanwrURL.appendingPathComponent("history")
        let templatesURL = scanwrURL.appendingPathComponent("templates")

        do {
            try FileManager.default.createDirectory(at: checkpointsURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: templatesURL, withIntermediateDirectories: true)

            let metaURL = scanwrURL.appendingPathComponent("metadata.txt")
            if !FileManager.default.fileExists(atPath: metaURL.path) {
                try "sample\tgroup\tpath\treader\n".write(to: metaURL, atomically: true, encoding: .utf8)
            }

            let currentTemplateURL = scanwrURL.appendingPathComponent("template.json")
            if !FileManager.default.fileExists(atPath: currentTemplateURL.path) {
                try Self.emptyCurrentWorkflow().write(to: currentTemplateURL, atomically: true, encoding: .utf8)
            }

            outputDirectory = baseDir.path
            projectName = clean
            samples = []
            nodes = []
            links = []
            selectedNodeId = nil

            addRecent(projectURL.path)
            loadTemplatesForCurrentProject()
            loadOrInitCurrentWorkflow()
            appendLog("Created project: \(projectURL.path)")
        } catch {
            appendLog("ERROR: Create project failed: \(error)")
        }
    }

    func closeProject() {
        workflowSaveWorkItem?.cancel()
        workflowSaveWorkItem = nil
        samples = []
        nodes = []
        links = []
        selectedNodeId = nil
        outputDirectory = ""
        projectName = "scGUI-project"
        availableTemplates = []
    }

    private static func parseMetadata(_ text: String) -> [SampleMetadata] {
        var out: [SampleMetadata] = []
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return [] }
        for (idx, raw) in lines.enumerated() {
            if idx == 0 { continue }
            let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if parts.count < 3 { continue }
            let sample = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let group = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let path = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let reader = (parts.count >= 4 ? parts[3] : "").trimmingCharacters(in: .whitespacesAndNewlines)
            if sample.isEmpty || group.isEmpty || path.isEmpty { continue }
            out.append(SampleMetadata(sample: sample, group: group, path: path, reader: reader))
        }
        return out
    }

    // MARK: Canvas helpers

    func addNode(spec: ModuleSpec, at position: CGPoint) {
        let defaults = defaultParams(for: spec.id)
        nodes.append(PipelineNode(specId: spec.id, position: CGPointCodable(position), params: defaults))
    }

    func defaultParams(for specId: String) -> [String: JSONValue] {
        switch specId {
        case "scanpy.pp.filter_cells":
            return ["min_genes": .number(100)]
        case "scanpy.pp.filter_genes":
            return ["min_cells": .number(3)]
        case "scanpy.pp.scrublet":
            return ["batch_key": .string("sample")]
        case "scanpy.pp.calculate_qc_metrics":
            return [
                "use_mt": .bool(true),
                "use_ribo": .bool(true),
                "use_hb": .bool(true),
                "percent_top": .string(""),
                "log1p": .bool(true),
            ]
        case "scanpy.pp.normalize_total":
            return ["target_sum": .string("")]
        default:
            return [:]
        }
    }

    func spec(for specId: String) -> ModuleSpec? {
        availableModules.first(where: { $0.id == specId })
    }

    func nodeBinding(id: UUID) -> Binding<PipelineNode>? {
        guard nodes.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                self.nodes.first(where: { $0.id == id })
                    ?? PipelineNode(specId: "", position: CGPointCodable(.zero), params: [:])
            },
            set: { updated in
                if let idx = self.nodes.firstIndex(where: { $0.id == id }) {
                    self.nodes[idx] = updated
                }
            }
        )
    }

    func addLink(from: UUID, to: UUID) {
        guard from != to else { return }
        if links.contains(where: { $0.fromNodeId == from && $0.toNodeId == to }) { return }
        links.append(PipelineLink(fromNodeId: from, toNodeId: to))
    }

    func removeSelectedNode() {
        guard let id = selectedNodeId else { return }
        nodes.removeAll(where: { $0.id == id })
        links.removeAll(where: { $0.fromNodeId == id || $0.toNodeId == id })
        selectedNodeId = nil
    }

    // MARK: Current workflow persistence (.scanwr/template.json)

    private func currentWorkflowURL() -> URL? {
        projectPath?.appendingPathComponent(".scanwr/template.json")
    }

    private static func emptyCurrentWorkflow() throws -> String {
        let t = WorkflowTemplate(id: "current", name: "Current workflow", nodes: [], links: [])
        let data = try JSONEncoder.pretty.encode(t)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private func loadOrInitCurrentWorkflow() {
        guard let projectURL = projectPath else { return }
        let scanwrDir = projectURL.appendingPathComponent(".scanwr")
        let url = scanwrDir.appendingPathComponent("template.json")

        do {
            try FileManager.default.createDirectory(at: scanwrDir, withIntermediateDirectories: true)
        } catch {
            appendLog("ERROR: create .scanwr dir failed: \(error)")
            return
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try Self.emptyCurrentWorkflow().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                appendLog("ERROR: init template.json failed: \(error)")
            }
        }

        if let t = WorkflowTemplate.load(from: url) {
            nodes = t.nodes.map { $0.toNode() }
            links = t.links.map { $0.toLink() }
            selectedNodeId = nil
            appendLog("Loaded workflow: .scanwr/template.json")
        } else {
            nodes = []
            links = []
            selectedNodeId = nil
        }
    }

    private func schedulePersistCurrentWorkflow() {
        guard currentWorkflowURL() != nil else { return }
        workflowSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.persistCurrentWorkflow()
        }
        workflowSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func persistCurrentWorkflow() {
        guard let url = currentWorkflowURL() else { return }
        let t = WorkflowTemplate(id: "current", name: "Current workflow", nodes: nodes.map { WorkflowNode(from: $0) }, links: links.map { WorkflowLink(from: $0) })
        do {
            let data = try JSONEncoder.pretty.encode(t)
            try data.write(to: url)
        } catch {
            appendLog("ERROR: write template.json failed: \(error)")
        }
    }

    // MARK: Templates

    func loadTemplatesForCurrentProject() {
        guard let projectURL = projectPath else { return }
        let templatesDir = projectURL.appendingPathComponent(".scanwr/templates")
        do {
            try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        } catch {
            appendLog("ERROR: create templates dir failed: \(error)")
        }

        var templates: [WorkflowTemplate] = []

        // Bundled templates
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "templates") {
            for u in urls {
                if let t = WorkflowTemplate.load(from: u) { templates.append(t) }
            }
        }

        // Project templates
        if let files = try? FileManager.default.contentsOfDirectory(at: templatesDir, includingPropertiesForKeys: nil) {
            for u in files where u.pathExtension.lowercased() == "json" {
                if let t = WorkflowTemplate.load(from: u) { templates.append(t) }
            }
        }

        var seen: Set<String> = []
        availableTemplates = templates.filter { t in
            if seen.contains(t.id) { return false }
            seen.insert(t.id)
            return true
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func importTemplate(from url: URL) {
        guard let projectURL = projectPath else {
            appendLog("ERROR: Open or create a project first.")
            return
        }
        let destDir = projectURL.appendingPathComponent(".scanwr/templates")
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let dest = destDir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            loadTemplatesForCurrentProject()
            appendLog("Imported template: \(dest.lastPathComponent)")
        } catch {
            appendLog("ERROR: import template failed: \(error)")
        }
    }

    func saveCurrentTemplate(to url: URL) {
        let t = WorkflowTemplate.fromCurrent(nodes: nodes, links: links)
        do {
            let data = try JSONEncoder.pretty.encode(t)
            try data.write(to: url)
            appendLog("Saved template: \(url.lastPathComponent)")
        } catch {
            appendLog("ERROR: save template failed: \(error)")
        }
    }

    func applyTemplate(_ t: WorkflowTemplate) {
        nodes = t.nodes.map { $0.toNode() }
        links = t.links.map { $0.toLink() }
        selectedNodeId = nil
        appendLog("Applied template: \(t.name)")
    }

    // MARK: Run

    func runPipeline() async {
        let outDir = outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let projName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !samples.isEmpty else { appendLog("ERROR: Add at least one sample first"); return }
        guard !outDir.isEmpty else { appendLog("ERROR: Select an output directory first"); return }
        guard !projName.isEmpty else { appendLog("ERROR: Set a project name"); return }

        let ordered = orderedPipeline()
        guard !ordered.isEmpty else { appendLog("ERROR: Add at least one module"); return }

        await ensureBackendStarted()
        appendLog("Running \(ordered.count) step(s) on \(samples.count) sample(s)…")

        isRunning = true
        progressPercent = 0
        progressMessage = "Starting…"
        defer { isRunning = false }

        struct RunParams: Codable {
            var outputDir: String
            var projectName: String
            var samples: [SampleMetadata]
            var steps: [PipelineStep]
        }
        struct PipelineStep: Codable {
            var specId: String
            var params: [String: JSONValue]
        }

        do {
            if Task.isCancelled { throw CancellationError() }
            let steps = ordered.map { PipelineStep(specId: $0.specId, params: $0.params) }
            let summary: PipelineRunSummary = try await rpc.call(
                method: "run_pipeline",
                params: RunParams(outputDir: outDir, projectName: projName, samples: samples, steps: steps)
            )
            if Task.isCancelled { throw CancellationError() }
            appendLog("OK: wrote outputs to \(summary.outputDir)")
            for r in summary.results {
                appendLog("OK: \(r.sample) via \(r.reader) final=\(r.finalPath) shape=\(r.shape)")
            }
            progressPercent = 1
            progressMessage = "Done."
        } catch is CancellationError {
            appendLog("Stopped.")
            progressMessage = "Stopped."
        } catch {
            appendLog("run_pipeline ERROR: \(error)")
        }
    }

    func startRun() {
        guard runTask == nil else { return }
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runPipeline()
            self.runTask = nil
        }
    }

    func stopRun() async {
        guard isRunning else { return }
        appendLog("Stopping…")
        runTask?.cancel()
        runTask = nil
        await rpc.stop()
        isRunning = false
        progressMessage = "Stopped."
        progressPercent = 0
    }

    // Topological ordering for a simple DAG. For now we enforce a linear chain.
    func orderedPipeline() -> [PipelineNode] {
        if nodes.isEmpty { return [] }

        var inCount: [UUID: Int] = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 0) })
        var outCount: [UUID: Int] = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 0) })
        var next: [UUID: UUID] = [:]

        for l in links {
            inCount[l.toNodeId, default: 0] += 1
            outCount[l.fromNodeId, default: 0] += 1
            next[l.fromNodeId] = l.toNodeId
        }

        if inCount.values.filter({ $0 == 0 }).count != 1 { return nodes }
        if inCount.values.contains(where: { $0 > 1 }) { return nodes }
        if outCount.values.contains(where: { $0 > 1 }) { return nodes }

        guard let start = inCount.first(where: { $0.value == 0 })?.key else { return nodes }

        var ordered: [PipelineNode] = []
        var seen: Set<UUID> = []
        var cur: UUID? = start
        while let id = cur, !seen.contains(id) {
            seen.insert(id)
            if let node = nodes.first(where: { $0.id == id }) {
                ordered.append(node)
            }
            cur = next[id]
        }

        if ordered.count != nodes.count { return nodes }
        return ordered
    }
}

// MARK: Template model

struct WorkflowTemplate: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var nodes: [WorkflowNode]
    var links: [WorkflowLink]

    static func load(from url: URL) -> WorkflowTemplate? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkflowTemplate.self, from: data)
    }

    static func fromCurrent(nodes: [PipelineNode], links: [PipelineLink]) -> WorkflowTemplate {
        WorkflowTemplate(
            id: UUID().uuidString,
            name: "Template",
            nodes: nodes.map { WorkflowNode(from: $0) },
            links: links.map { WorkflowLink(from: $0) }
        )
    }
}

struct WorkflowNode: Codable, Hashable {
    var id: UUID
    var specId: String
    var x: Double
    var y: Double
    var params: [String: JSONValue]

    init(from n: PipelineNode) {
        id = n.id
        specId = n.specId
        x = n.position.x
        y = n.position.y
        params = n.params
    }

    func toNode() -> PipelineNode {
        PipelineNode(id: id, specId: specId, position: CGPointCodable(CGPoint(x: x, y: y)), params: params)
    }
}

struct WorkflowLink: Codable, Hashable {
    var id: UUID
    var fromNodeId: UUID
    var toNodeId: UUID

    init(from l: PipelineLink) {
        id = l.id
        fromNodeId = l.fromNodeId
        toNodeId = l.toNodeId
    }

    func toLink() -> PipelineLink {
        PipelineLink(id: id, fromNodeId: fromNodeId, toNodeId: toNodeId)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
