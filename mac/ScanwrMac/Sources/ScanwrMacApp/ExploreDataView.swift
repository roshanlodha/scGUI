import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExploreDataView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var showsHeader: Bool = true
    var showsClose: Bool = true
    var showsPreview: Bool = true
    var plotURL: Binding<URL?>? = nil

    @State private var selectedSample: String = ""
    @State private var plotType: PlotType = .scatter

    @State private var inspect: AdataInspectResult?
    @State private var isInspecting: Bool = false
    @State private var inspectError: String?

    // Key refs (encoded as "obs:<col>" or "gene:<name>")
    @State private var xRef: String = ""
    @State private var yRef: String = ""
    @State private var colorRef: String = ""

    // Expression source
    @State private var useRaw: Bool = false
    @State private var layer: String = ""

    // Generic styling
    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var legendTitle: String = ""
    @State private var xLabel: String = ""
    @State private var yLabel: String = ""
    @State private var xTickRotation: String = ""

    // Scatter styling
    @State private var pointSize: String = "10"
    @State private var alpha: String = "0.8"

    // Density styling
    @State private var densityFill: Bool = true

    // Output (internal)
    @State private var lastSVGURL: URL?
    @State private var plotError: String?
    @State private var isPlotting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Divider()
            }
            if showsPreview {
                HSplitView {
                    editorScroll
                        .frame(minWidth: 520, idealWidth: 560)

                    previewSection
                        .frame(minWidth: 420, idealWidth: 460)
                }
            } else {
                editorScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedSample.isEmpty, let first = model.samples.first?.sample {
                selectedSample = first
            }
            Task { await loadInspectIfPossible() }
        }
        .onChange(of: selectedSample) { _, _ in
            resetForSelection()
            Task { await loadInspectIfPossible() }
        }
        .onChange(of: plotType) { _, _ in
            plotError = nil
            applyPlotTypeDefaults()
        }
    }

    private var editorScroll: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                dataSection
                plotSection
                labelsSection
                outputSection
            }
            .padding(12)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Visualization")
                    .font(.title2)
                if let p = model.projectPath?.path {
                    Text(p)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
            }
            Spacer()
            if showsClose {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
        }
        .padding(12)
    }

    private var dataSection: some View {
        GroupBox("Data") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Sample", selection: $selectedSample) {
                    Text("Select…").tag("")
                    ForEach(model.samples.map(\.sample), id: \.self) { s in
                        Text(s).tag(s)
                    }
                }

                Picker("Plot type", selection: $plotType) {
                    ForEach(PlotType.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("h5ad") {
                    Text(h5adPathForSelection() ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button("Reload keys") { Task { await loadInspectIfPossible(force: true) } }
                        .disabled(selectedSample.isEmpty || isInspecting)
                    if isInspecting { ProgressView().controlSize(.small) }
                    Spacer()
                }

                if let inspectError {
                    Text(inspectError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding(6)
        }
    }

    private var plotSection: some View {
        GroupBox("Plot") {
            VStack(alignment: .leading, spacing: 10) {
                if let inspect {
                    switch plotType {
                    case .scatter:
                        keyPicker("x", selection: $xRef, options: xOptions(inspect: inspect))
                        keyPicker("y", selection: $yRef, options: yOptions(inspect: inspect))
                        keyPicker(
                            "color (optional)",
                            selection: $colorRef,
                            options: colorOptions(inspect: inspect),
                            allowNone: true
                        )

                        HStack(spacing: 10) {
                            TextField("point size", text: $pointSize)
                                .frame(width: 120)
                            TextField("alpha (0–1)", text: $alpha)
                                .frame(width: 120)
                            Spacer()
                        }

                    case .violin, .box:
                        keyPicker(
                            "x (category, optional)",
                            selection: $xRef,
                            options: xOptions(inspect: inspect),
                            allowNone: true
                        )
                        keyPicker("y (value)", selection: $yRef, options: yOptions(inspect: inspect))
                        keyPicker(
                            "color (optional)",
                            selection: $colorRef,
                            options: colorOptions(inspect: inspect),
                            allowNone: true
                        )
                    case .density:
                        keyPicker(
                            "group (optional)",
                            selection: $xRef,
                            options: xOptions(inspect: inspect),
                            allowNone: true
                        )
                        keyPicker("value", selection: $yRef, options: yOptions(inspect: inspect))
                        Toggle("fill", isOn: $densityFill)
                    }

                    Divider()

                    HStack(spacing: 10) {
                        Toggle("use raw", isOn: $useRaw)
                            .disabled(!inspect.hasRaw)

                        Picker("layer", selection: $layer) {
                            Text("(default)").tag("")
                            ForEach(inspect.layers, id: \.self) { l in
                                Text(l).tag(l)
                            }
                        }
                        .frame(width: 220)

                        Spacer()
                    }
                } else {
                    Text("Select a sample to load keys.")
                        .foregroundStyle(.secondary)
                }

                if let plotError {
                    Text(plotError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding(6)
        }
    }

    private var labelsSection: some View {
        GroupBox("Labels") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                TextField("Subtitle", text: $subtitle)

                HStack(spacing: 10) {
                    TextField("Legend title", text: $legendTitle)
                    Spacer()
                }

                HStack(spacing: 10) {
                    TextField("X-axis label", text: $xLabel)
                    TextField("Y-axis label", text: $yLabel)
                }

                HStack(spacing: 10) {
                    TextField("X tick rotation (deg)", text: $xTickRotation)
                        .frame(width: 180)
                    Spacer()
                }
            }
            .padding(6)
        }
    }

    private var outputSection: some View {
        GroupBox("Actions") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(isPlotting ? "Plotting…" : "Plot") {
                        Task { await plot() }
                    }
                    .disabled(!canPlot() || isPlotting)
                    if isPlotting { ProgressView().controlSize(.small) }

                    Button("Download…") { downloadLastPlot() }
                        .disabled(lastSVGURL == nil)
                    Spacer()
                }
            }
            .padding(6)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
            }

            Divider()

            if let url = lastSVGURL, FileManager.default.fileExists(atPath: url.path) {
                SVGWebView(fileURL: url)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )

                HStack {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
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
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func keyPicker(
        _ label: String,
        selection: Binding<String>,
        options: [KeyOption],
        allowNone: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                if allowNone {
                    Text("(none)").tag("")
                } else {
                    Text("Select…").tag("")
                }
                ForEach(options) { opt in
                    Text(opt.label).tag(opt.id)
                }
            }
        }
    }

    private func keyOptions(inspect: AdataInspectResult) -> [KeyOption] {
        var out: [KeyOption] = []
        out.append(contentsOf: inspect.obsColumns.map { KeyOption(id: "obs:\($0)", label: "obs.\($0)") })
        out.append(contentsOf: inspect.varNames.map { KeyOption(id: "gene:\($0)", label: "gene.\($0)") })
        return out
    }

    private func obsNumericOptions(inspect: AdataInspectResult) -> [KeyOption] {
        inspect.numericObsColumns.map { KeyOption(id: "obs:\($0)", label: "obs.\($0)") }
    }

    private func obsCategoricalOptions(inspect: AdataInspectResult) -> [KeyOption] {
        let setNumeric = Set(inspect.numericObsColumns)
        let items = inspect.groupbyCandidates + inspect.obsColumns.filter { !setNumeric.contains($0) }
        var seen: Set<String> = []
        return items.compactMap { k in
            if seen.contains(k) { return nil }
            seen.insert(k)
            return KeyOption(id: "obs:\(k)", label: "obs.\(k)")
        }
    }

    private func geneOptions(inspect: AdataInspectResult) -> [KeyOption] {
        inspect.varNames.map { KeyOption(id: "gene:\($0)", label: "gene.\($0)") }
    }

    private func xOptions(inspect: AdataInspectResult) -> [KeyOption] {
        switch plotType {
        case .scatter:
            return obsNumericOptions(inspect: inspect) + geneOptions(inspect: inspect)
        case .violin, .box:
            return obsCategoricalOptions(inspect: inspect)
        case .density:
            return obsCategoricalOptions(inspect: inspect)
        }
    }

    private func yOptions(inspect: AdataInspectResult) -> [KeyOption] {
        switch plotType {
        case .scatter:
            return obsNumericOptions(inspect: inspect) + geneOptions(inspect: inspect)
        case .violin, .box:
            return obsNumericOptions(inspect: inspect) + geneOptions(inspect: inspect)
        case .density:
            return obsNumericOptions(inspect: inspect) + geneOptions(inspect: inspect)
        }
    }

    private func colorOptions(inspect: AdataInspectResult) -> [KeyOption] {
        switch plotType {
        case .scatter:
            return obsCategoricalOptions(inspect: inspect) + obsNumericOptions(inspect: inspect) + geneOptions(inspect: inspect)
        case .violin, .box:
            return obsCategoricalOptions(inspect: inspect)
        case .density:
            return []
        }
    }

    private func ensureKeySelectionsValid(inspect: AdataInspectResult) {
        let allowedX = Set(xOptions(inspect: inspect).map(\.id))
        let allowedY = Set(yOptions(inspect: inspect).map(\.id))
        let allowedC = Set(colorOptions(inspect: inspect).map(\.id))

        if !xRef.isEmpty, !allowedX.contains(xRef) { xRef = "" }
        if !yRef.isEmpty, !allowedY.contains(yRef) { yRef = "" }
        if !colorRef.isEmpty, !allowedC.contains(colorRef) { colorRef = "" }
    }

    private func applyPlotTypeDefaults() {
        if plotType == .scatter {
            if pointSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pointSize = "10" }
            if alpha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { alpha = "0.8" }
        }
        if let inspect {
            ensureKeySelectionsValid(inspect: inspect)
        }
    }

    private func resetForSelection() {
        inspect = nil
        inspectError = nil
        plotError = nil
        xRef = ""
        yRef = ""
        colorRef = ""
        lastSVGURL = nil
    }

    private func h5adPathForSelection() -> String? {
        guard !selectedSample.isEmpty, let project = model.projectPath else { return nil }
        let safe = AppModel.sanitizeFilename(selectedSample)
        let url = project.appendingPathComponent(".scanwr/checkpoints/\(safe).h5ad")
        return url.path
    }

    private func loadInspectIfPossible(force: Bool = false) async {
        plotError = nil
        inspectError = nil
        guard let path = h5adPathForSelection() else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            inspectError = "Missing .h5ad for sample. Run the pipeline first (expected at: \(path))"
            return
        }
        if inspect != nil, !force { return }
        isInspecting = true
        defer { isInspecting = false }
        do {
            let res = try await model.inspectH5ad(path: path, varNamesLimit: 5000)
            inspect = res
            ensureKeySelectionsValid(inspect: res)
        } catch {
            inspectError = String(describing: error)
        }
    }

    private func defaultDownloadFilename() -> String {
        let s = selectedSample.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = AppModel.sanitizeFilename(s.isEmpty ? "plot" : s)
        return "\(safe)_\(plotType.rawValue).svg"
    }

    private func downloadLastPlot() {
        guard let src = lastSVGURL, FileManager.default.fileExists(atPath: src.path) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultDownloadFilename()
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: src, to: dest)
            } catch {
                plotError = "Download failed: \(error)"
            }
        }
    }

    private func canPlot() -> Bool {
        guard !selectedSample.isEmpty else { return false }
        switch plotType {
        case .scatter:
            guard !xRef.isEmpty, !yRef.isEmpty else { return false }
        case .violin, .box, .density:
            guard !yRef.isEmpty else { return false }
        }
        guard h5adPathForSelection() != nil else { return false }
        return true
    }

    private func plot() async {
        plotError = nil
        guard let h5ad = h5adPathForSelection() else { return }
        guard FileManager.default.fileExists(atPath: h5ad) else {
            plotError = "Missing .h5ad for sample. Run the pipeline first."
            return
        }
        isPlotting = true
        defer { isPlotting = false }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("scgui-plot-\(UUID().uuidString).svg")
            .path

        let req = CustomPlotRequest(
            h5adPath: h5ad,
            plotType: plotType.rawValue,
            x: xRef.isEmpty ? nil : xRef,
            y: yRef.isEmpty ? nil : yRef,
            color: colorRef.isEmpty ? nil : colorRef,
            layer: layer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : layer,
            useRaw: useRaw ? true : nil,
            title: title,
            subtitle: subtitle,
            legendTitle: legendTitle,
            xLabel: xLabel,
            yLabel: yLabel,
            xTickRotation: Double(xTickRotation.trimmingCharacters(in: .whitespacesAndNewlines)),
            pointSize: Double(pointSize.trimmingCharacters(in: .whitespacesAndNewlines)),
            alpha: Double(alpha.trimmingCharacters(in: .whitespacesAndNewlines)),
            densityFill: (plotType == .density ? densityFill : nil),
            outputPath: out
        )

        do {
            let res = try await model.plotCustom(req: req)
            let url = URL(fileURLWithPath: res.svgPath)
            lastSVGURL = url
            plotURL?.wrappedValue = url
        } catch {
            plotError = String(describing: error)
        }
    }
}

private struct KeyOption: Identifiable, Hashable {
    var id: String
    var label: String
}

private enum PlotType: String, CaseIterable, Identifiable {
    case scatter
    case violin
    case box
    case density

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scatter: "Scatter"
        case .violin: "Violin"
        case .box: "Box"
        case .density: "Density"
        }
    }
}
