import SwiftUI
import UniformTypeIdentifiers

private struct CanvasContentFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct CanvasView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isDropTarget: Bool

    @State private var linkingFromNodeId: UUID?
    @State private var isLinking: Bool = false
    @State private var linkingDragPoint: CGPoint = .zero
    @State private var dragStartCenter: [UUID: CGPoint] = [:]
    @State private var dragOverrideCenter: [UUID: CGPoint] = [:]
    @FocusState private var canvasFocused: Bool

    private enum CanvasConstants {
        static let gridSpacing: CGFloat = AppModel.canvasGridSpacing
        static let snapSpacing: CGFloat = AppModel.canvasGridSpacing
        static let canvasSize = CGSize(width: 4000, height: 2400)

        static let nodeSize = AppModel.canvasNodeSize
        static let anchorInsetX: CGFloat = AppModel.canvasPortInsetX
        static let snapThreshold: CGFloat = 7
    }

    var body: some View {
        let renderNodes: [PipelineNode] = model.nodes.map { n in
            guard let override = dragOverrideCenter[n.id] else { return n }
            var updated = n
            updated.position = CGPointCodable(override)
            return updated
        }

        GeometryReader { outerGeo in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                DotGridBackground(spacing: CanvasConstants.gridSpacing)

                LinksLayer(
                    links: model.links,
                    nodes: renderNodes,
                    linkingFrom: linkingFromNodeId,
                    linkingDragPoint: linkingDragPoint,
                    nodeSize: CanvasConstants.nodeSize,
                    anchorInsetX: CanvasConstants.anchorInsetX
                )

                ForEach(model.nodes) { node in
                    NodeBubble(
                        node: node,
                        nodeSize: CanvasConstants.nodeSize,
                        isSelected: model.selectedNodeId == node.id,
                        isLinking: isLinking,
                        isLinkTarget: isLinking && linkingFromNodeId != nil && linkingFromNodeId != node.id,
                        spec: model.spec(for: node.specId),
                        onSelect: {
                            canvasFocused = true
                            if let from = linkingFromNodeId, from != node.id {
                                model.addLink(from: from, to: node.id)
                                linkingFromNodeId = nil
                                isLinking = false
                            } else {
                                model.selectedNodeId = node.id
                            }
                        },
                        onDrag: { delta in
                            dragChanged(nodeId: node.id, translation: delta)
                        },
                        onDragEnded: {
                            dragEnded(nodeId: node.id)
                        },
                        onStartLink: { startPoint in
                            canvasFocused = true
                            linkingFromNodeId = node.id
                            linkingDragPoint = startPoint
                            isLinking = true
                        },
                        onUpdateLink: { p in
                            linkingDragPoint = p
                        },
                        onEndLink: { dropPoint in
                            defer { linkingFromNodeId = nil }
                            defer { isLinking = false }
                            guard let from = linkingFromNodeId else { return }
                            if let target = nearestInputNode(at: dropPoint, excluding: from) {
                                model.addLink(from: from, to: target)
                            }
                        }
                    )
                    .position(dragOverrideCenter[node.id] ?? node.position.cgPoint)
                }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: CanvasContentFrameKey.self, value: proxy.frame(in: .named("scroll")))
                    }
                )
                .coordinateSpace(name: "canvas")
                .contentShape(Rectangle())
                .onDrop(of: [UTType.plainText], isTargeted: $isDropTarget) { providers, location in
                    handleModuleDrop(providers: providers, at: location)
                }
                .onTapGesture {
                    canvasFocused = true
                    if isLinking {
                        linkingFromNodeId = nil
                        isLinking = false
                    } else {
                        model.selectedNodeId = nil
                    }
                }
                .focusable(true)
                .focused($canvasFocused)
                .onDeleteCommand {
                    model.removeSelectedNode()
                }
                .onExitCommand {
                    // ESC: close inspector / cancel linking
                    if isLinking {
                        linkingFromNodeId = nil
                        isLinking = false
                    } else {
                        model.selectedNodeId = nil
                    }
                }
                .frame(width: CanvasConstants.canvasSize.width, height: CanvasConstants.canvasSize.height, alignment: .topLeading)
            }
            .coordinateSpace(name: "scroll")
            .scrollIndicators(.visible)
            .onPreferenceChange(CanvasContentFrameKey.self) { contentFrame in
                updateVisibleRect(containerSize: outerGeo.size, contentFrame: contentFrame)
            }
            .overlay(alignment: .topLeading) {
                if isLinking {
                    HStack(spacing: 10) {
                        Text("Link mode: click a target module (or drag the port).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Cancel") {
                            linkingFromNodeId = nil
                            isLinking = false
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(14)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let selected = model.selectedNodeId,
                   let binding = model.nodeBinding(id: selected) {
                    NodeInspector(node: binding)
                        .frame(width: 360)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(radius: 10)
                        .padding(14)
                }
            }
        }
    }

    private func updateVisibleRect(containerSize: CGSize, contentFrame: CGRect) {
        let rawOrigin = CGPoint(x: -contentFrame.minX, y: -contentFrame.minY)
        let origin = CGPoint(
            x: max(0, min(CanvasConstants.canvasSize.width - containerSize.width, rawOrigin.x)),
            y: max(0, min(CanvasConstants.canvasSize.height - containerSize.height, rawOrigin.y))
        )
        let rect = CGRect(origin: origin, size: containerSize)
        if model.canvasVisibleRect != rect {
            model.canvasVisibleRect = rect
        }
    }

    private func handleModuleDrop(providers: [NSItemProvider], at point: CGPoint) -> Bool {
        guard let provider = providers.first else { return false }
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

    private func nearestInputNode(at point: CGPoint, excluding: UUID) -> UUID? {
        // Simple hit-test: pick the nearest input port within a radius.
        let radius: CGFloat = 64
        var best: (id: UUID, d: CGFloat)?
        for n in model.nodes where n.id != excluding {
            let anchor = inputAnchor(for: n)
            let dx = anchor.x - point.x
            let dy = anchor.y - point.y
            let d = sqrt(dx * dx + dy * dy)
            if d <= radius && (best == nil || d < best!.d) {
                best = (n.id, d)
            }
        }
        return best?.id
    }

    private func inputAnchor(for node: PipelineNode) -> CGPoint {
        let c = node.position.cgPoint
        return CGPoint(
            x: c.x - CanvasConstants.nodeSize.width / 2 + CanvasConstants.anchorInsetX,
            y: c.y
        )
    }

    private func snappedCenter(_ center: CGPoint) -> CGPoint {
        let spacing = CanvasConstants.snapSpacing
        let size = CanvasConstants.nodeSize
        let topLeft = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        let snappedTopLeft = CGPoint(
            x: (topLeft.x / spacing).rounded() * spacing,
            y: (topLeft.y / spacing).rounded() * spacing
        )
        return CGPoint(x: snappedTopLeft.x + size.width / 2, y: snappedTopLeft.y + size.height / 2)
    }

    private func dragChanged(nodeId: UUID, translation: CGSize) {
        if dragStartCenter[nodeId] == nil {
            dragStartCenter[nodeId] = model.nodes.first(where: { $0.id == nodeId })?.position.cgPoint
        }
        guard let start = dragStartCenter[nodeId] else { return }

        let proposed = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let snapped = snappedCenter(proposed)
        let sticky = CGPoint(
            x: abs(snapped.x - proposed.x) <= CanvasConstants.snapThreshold ? snapped.x : proposed.x,
            y: abs(snapped.y - proposed.y) <= CanvasConstants.snapThreshold ? snapped.y : proposed.y
        )
        dragOverrideCenter[nodeId] = sticky
    }

    private func dragEnded(nodeId: UUID) {
        defer { dragStartCenter[nodeId] = nil }
        defer { dragOverrideCenter[nodeId] = nil }

        guard let idx = model.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        let endCenter = dragOverrideCenter[nodeId] ?? model.nodes[idx].position.cgPoint
        let snapped = snappedCenter(endCenter)
        guard snapped != model.nodes[idx].position.cgPoint else { return }
        withAnimation(.snappy(duration: 0.12)) {
            model.nodes[idx].position = CGPointCodable(snapped)
        }
    }
}

private struct DotGridBackground: View {
    var spacing: CGFloat
    private static var tileCache: [Int: NSImage] = [:]

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            Rectangle()
                .fill(ImagePaint(image: Image(nsImage: dotTileImage(spacing: spacing)), scale: 1))
        }
    }

    private func dotTileImage(spacing: CGFloat) -> NSImage {
        let tileSize = max(6, Int(round(spacing)))
        if let cached = Self.tileCache[tileSize] {
            return cached
        }
        let size = NSSize(width: tileSize, height: tileSize)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let dotRadius: CGFloat = 1.0
        let fill = NSColor.labelColor.withAlphaComponent(0.08)
        fill.setFill()
        let rect = NSRect(
            x: size.width / 2 - dotRadius,
            y: size.height / 2 - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        NSBezierPath(ovalIn: rect).fill()
        Self.tileCache[tileSize] = image
        return image
    }
}

private struct LinksLayer: View {
    var links: [PipelineLink]
    var nodes: [PipelineNode]
    var linkingFrom: UUID?
    var linkingDragPoint: CGPoint
    var nodeSize: CGSize
    var anchorInsetX: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            func outputAnchor(_ id: UUID) -> CGPoint? {
                guard let c = nodes.first(where: { $0.id == id })?.position.cgPoint else { return nil }
                return CGPoint(x: c.x + nodeSize.width / 2 - anchorInsetX, y: c.y)
            }

            func inputAnchor(_ id: UUID) -> CGPoint? {
                guard let c = nodes.first(where: { $0.id == id })?.position.cgPoint else { return nil }
                return CGPoint(x: c.x - nodeSize.width / 2 + anchorInsetX, y: c.y)
            }

            for l in links {
                guard let a = outputAnchor(l.fromNodeId), let b = inputAnchor(l.toNodeId) else { continue }
                let p = curvedPath(from: a, to: b)
                ctx.stroke(p, with: .color(Color.primary.opacity(0.35)), lineWidth: 2)
            }

            if let from = linkingFrom, let a = outputAnchor(from) as CGPoint? {
                let p = curvedPath(from: a, to: linkingDragPoint)
                ctx.stroke(p, with: .color(Color.accentColor.opacity(0.7)), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }
        }
    }

    private func curvedPath(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        path.move(to: from)
        let dx = max(40, abs(to.x - from.x) * 0.45)
        let c1 = CGPoint(x: from.x + dx, y: from.y)
        let c2 = CGPoint(x: to.x - dx, y: to.y)
        path.addCurve(to: to, control1: c1, control2: c2)
        return path
    }
}

private struct NodeBubble: View {
    var node: PipelineNode
    var nodeSize: CGSize
    var isSelected: Bool
    var isLinking: Bool
    var isLinkTarget: Bool
    var spec: ModuleSpec?

    var onSelect: () -> Void
    var onDrag: (CGSize) -> Void
    var onDragEnded: () -> Void
    var onStartLink: (CGPoint) -> Void
    var onUpdateLink: (CGPoint) -> Void
    var onEndLink: (CGPoint) -> Void

    var body: some View {
        let group = spec?.group ?? .pp
        let title = spec?.title ?? node.specId
        let badge = group.badge

        ZStack {
            RoundedRectangle(cornerRadius: 999)
                .fill(Color(hex: group.colorHex).opacity(isSelected ? 0.26 : (isLinkTarget ? 0.22 : 0.16)))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(
                            isSelected ? Color(hex: group.colorHex).opacity(0.95) :
                                (isLinkTarget ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.15)),
                            lineWidth: isLinkTarget ? 3 : 2
                        )
                )

            HStack(spacing: 6) {
                InputPort()

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(spec?.scanpyQualname ?? node.specId)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: group.colorHex).opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                OutputPort(
                    onTapStart: {
                        // Start link mode with a reasonable starting point.
                        onStartLink(.zero)
                    },
                    onStart: onStartLink,
                    onUpdate: onUpdateLink,
                    onEnd: onEndLink
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: nodeSize.width, height: nodeSize.height)
        .onTapGesture {
            onSelect()
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in
                    onDrag(v.translation)
                }
                .onEnded { _ in
                    onDragEnded()
                }
        )
    }
}

private struct InputPort: View {
    var body: some View {
        Circle()
            .fill(Color.primary.opacity(0.18))
            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
            .frame(width: 8, height: 8)
            .help("Input")
    }
}

private struct OutputPort: View {
    var onTapStart: () -> Void
    var onStart: (CGPoint) -> Void
    var onUpdate: (CGPoint) -> Void
    var onEnd: (CGPoint) -> Void

    @State private var started = false

    var body: some View {
        GeometryReader { geo in
            Circle()
                .fill(Color.accentColor.opacity(0.9))
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                .frame(width: 12, height: 12)
                .contentShape(Circle())
                .onTapGesture {
                    // Click-to-link (more obvious than drag).
                    let base = geo.frame(in: .named("canvas"))
                    onTapStart()
                    onStart(CGPoint(x: base.midX, y: base.midY))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let base = geo.frame(in: .named("canvas"))
                            let p = CGPoint(
                                x: base.midX + v.translation.width,
                                y: base.midY + v.translation.height
                            )
                            if !started {
                                started = true
                                onStart(p)
                            }
                            onUpdate(p)
                        }
                        .onEnded { v in
                            let base = geo.frame(in: .named("canvas"))
                            let p = CGPoint(
                                x: base.midX + v.translation.width,
                                y: base.midY + v.translation.height
                            )
                            onEnd(p)
                            started = false
                        }
                )
        }
        .frame(width: 14, height: 14)
    }
}
