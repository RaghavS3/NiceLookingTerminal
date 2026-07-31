import SwiftUI

struct WhiteboardView: View {
    @Binding var shapes: [DrawingShape]
    @State private var currentShape: DrawingShape?
    @State private var activeTool: DrawingTool = .select
    @State private var strokeColor: Color = .black
    @State private var strokeWidth: CGFloat = 4
    @State private var strokeStyle: StrokePattern = .solid
    @State private var fillStyle: FillStyle = .hachure
    @State private var fontSize: CGFloat = 18

    // Interactive Selection & Dragging States
    @State private var selectedShapeID: UUID? = nil
    @State private var isDraggingShape = false
    @State private var dragStartPoint: CGPoint = .zero
    @State private var shapeOriginalPoints: [CGPoint] = []
    @State private var shapeOriginalRect: CGRect = .zero

    // Text Spawning & Double-Click Editor Setup
    @State private var showTextInput = false
    @State private var textInputVal = ""
    @State private var textSpawnPoint: CGPoint = .zero

    func shouldEraseShape(_ shape: DrawingShape, at point: CGPoint) -> Bool {
        if shape.tool == .rect || shape.tool == .circle {
            return shape.rect.insetBy(dx: -10, dy: -10).contains(point)
        }
        return shape.points.contains { CGPointDistance($0, point) < 14 }
    }

    // Check if user clicked close enough to select a shape
    func findHitShape(at point: CGPoint) -> DrawingShape? {
        // Search backwards to select the topmost drawn shape first
        for shape in shapes.reversed() {
            switch shape.tool {
            case .rect, .circle:
                if shape.rect.insetBy(dx: -8, dy: -8).contains(point) {
                    return shape
                }
            case .text:
                if shape.bounds.insetBy(dx: -8, dy: -8).contains(point) {
                    return shape
                }
            case .pen:
                if shape.points.contains(where: { CGPointDistance($0, point) < 12 }) {
                    return shape
                }
            default:
                break
            }
        }
        return nil
    }

    var body: some View {
        ZStack {
            // Pure white whiteboard canvas background
            Color.white
                .ignoresSafeArea()

            // Dotted canvas grid.
            DotGridView()
                .opacity(0.55)

            // Vector Rendering Canvas (Spans 100% of Screen width & height!)
            Canvas { context, size in
                for shape in shapes {
                    if shape.tool == .rect || shape.tool == .circle {
                        if shape.fillStyle == .hachure {
                            let fillPath = shape.hachurePath ?? sketchyHachure(rect: shape.rect, spacing: 10, roughness: 1.0)
                            context.stroke(fillPath, with: .color(shape.color.opacity(0.45)), lineWidth: 1.5)
                        } else if shape.fillStyle == .solid {
                            let fillPath = shape.tool == .rect ? Path(shape.rect) : Path(ellipseIn: shape.rect)
                            context.fill(fillPath, with: .color(shape.color.opacity(0.2)))
                        }
                    }

                    if let cachedPath = shape.sketchyPath {
                        let strokeStyle =
                            shape.strokeStyle == .dashed
                            ? StrokeStyle(lineWidth: shape.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: shape.lineWidth)
                        context.stroke(cachedPath, with: .color(shape.color), style: strokeStyle)
                    } else {
                        // Fallback for shapes without cache (e.g. legacy or during creation)
                        var outlinePath = Path()
                        switch shape.tool {
                        case .pen:
                            if shape.points.count > 1 {
                                outlinePath.addLines(shape.points)
                                let strokeStyle =
                                    shape.strokeStyle == .dashed
                                    ? StrokeStyle(lineWidth: shape.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: shape.lineWidth)
                                context.stroke(outlinePath, with: .color(shape.color), style: strokeStyle)
                            }
                        case .rect:
                            outlinePath = sketchyRect(rect: shape.rect, roughness: 1.2)
                            let strokeStyle =
                                shape.strokeStyle == .dashed
                                ? StrokeStyle(lineWidth: shape.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: shape.lineWidth)
                            context.stroke(outlinePath, with: .color(shape.color), style: strokeStyle)
                        case .circle:
                            outlinePath = sketchyCircle(rect: shape.rect, roughness: 1.2)
                            let strokeStyle =
                                shape.strokeStyle == .dashed
                                ? StrokeStyle(lineWidth: shape.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: shape.lineWidth)
                            context.stroke(outlinePath, with: .color(shape.color), style: strokeStyle)
                        default: break
                        }
                    }

                    if shape.tool == .text {
                        if let textPoint = shape.points.first {
                            context.draw(
                                Text(shape.text)
                                    .font(.system(size: shape.fontSize, weight: .bold, design: .rounded))
                                    .foregroundColor(shape.color),
                                at: textPoint,
                                anchor: .topLeading
                            )
                        }
                    }

                    if selectedShapeID == shape.id {
                        let bounds = shape.bounds.insetBy(dx: -6, dy: -6)
                        let boundingPath = Path(roundedRect: bounds, cornerRadius: 6)
                        context.stroke(
                            boundingPath,
                            with: .color(Color.cyan.opacity(0.65)),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                        )
                    }
                }

                // Live drawing preview
                if let current = currentShape {
                    if current.tool == .rect || current.tool == .circle {
                        if current.fillStyle == .hachure {
                            let fillPath = sketchyHachure(rect: current.rect, spacing: 10, roughness: 1.0)
                            context.stroke(fillPath, with: .color(current.color.opacity(0.4)), lineWidth: 1.2)
                        } else if current.fillStyle == .solid {
                            let fillPath = current.tool == .rect ? Path(current.rect) : Path(ellipseIn: current.rect)
                            context.fill(fillPath, with: .color(current.color.opacity(0.15)))
                        }
                    }

                    var outlinePath = Path()
                    switch current.tool {
                    case .pen:
                        if current.points.count > 1 {
                            outlinePath.addLines(current.points)
                            let strokeStyle =
                                current.strokeStyle == .dashed
                                ? StrokeStyle(lineWidth: current.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: current.lineWidth)
                            context.stroke(outlinePath, with: .color(current.color), style: strokeStyle)
                        }
                    case .rect:
                        outlinePath = sketchyRect(rect: current.rect, roughness: 1.2)
                        let strokeStyle =
                            current.strokeStyle == .dashed
                            ? StrokeStyle(lineWidth: current.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: current.lineWidth)
                        context.stroke(outlinePath, with: .color(current.color), style: strokeStyle)
                    case .circle:
                        outlinePath = sketchyCircle(rect: current.rect, roughness: 1.2)
                        let strokeStyle =
                            current.strokeStyle == .dashed
                            ? StrokeStyle(lineWidth: current.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: current.lineWidth)
                        context.stroke(outlinePath, with: .color(current.color), style: strokeStyle)
                    default:
                        break
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let pt = value.location

                        // --- 1. Selection & Repositioning/Dragging Tool Mode ---
                        if activeTool == .select {
                            if !isDraggingShape {
                                if let hit = findHitShape(at: value.startLocation) {
                                    selectedShapeID = hit.id
                                    isDraggingShape = true
                                    dragStartPoint = value.startLocation
                                    shapeOriginalPoints = hit.points
                                    shapeOriginalRect = hit.rect
                                    if hit.tool == .text {
                                        fontSize = hit.fontSize
                                    }
                                } else {
                                    selectedShapeID = nil
                                }
                            }

                            // Offset from the original geometry to avoid cumulative drift.
                            if isDraggingShape, let selectedID = selectedShapeID,
                                let idx = shapes.firstIndex(where: { $0.id == selectedID })
                            {
                                let dx = pt.x - dragStartPoint.x
                                let dy = pt.y - dragStartPoint.y

                                if shapes[idx].tool == .rect || shapes[idx].tool == .circle {
                                    shapes[idx].rect = CGRect(
                                        x: shapeOriginalRect.origin.x + dx,
                                        y: shapeOriginalRect.origin.y + dy,
                                        width: shapeOriginalRect.width,
                                        height: shapeOriginalRect.height
                                    )
                                } else {
                                    shapes[idx].points = shapeOriginalPoints.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                                }
                                shapes[idx].sketchyPath = nil
                                shapes[idx].hachurePath = nil
                            }
                            return
                        }

                        // --- 2. Eraser Mode ---
                        if activeTool == .eraser {
                            shapes.removeAll { shouldEraseShape($0, at: pt) }
                            selectedShapeID = nil
                            return
                        }

                        // --- 3. Drawing Mode ---
                        if activeTool == .text { return }

                        if currentShape == nil {
                            selectedShapeID = nil
                            currentShape = DrawingShape(
                                tool: activeTool,
                                points: [value.startLocation],
                                rect: CGRect(origin: value.startLocation, size: .zero),
                                color: strokeColor,
                                lineWidth: strokeWidth,
                                fillStyle: fillStyle,
                                strokeStyle: strokeStyle
                            )
                        } else {
                            if activeTool == .pen {
                                if let lastPt = currentShape?.points.last {
                                    if CGPointDistance(lastPt, pt) > 2 {
                                        currentShape?.points.append(pt)
                                    }
                                } else {
                                    currentShape?.points.append(pt)
                                }
                            } else if activeTool == .rect || activeTool == .circle {
                                let origin = CGPoint(
                                    x: min(value.startLocation.x, pt.x),
                                    y: min(value.startLocation.y, pt.y)
                                )
                                let size = CGSize(
                                    width: abs(pt.x - value.startLocation.x),
                                    height: abs(pt.y - value.startLocation.y)
                                )
                                currentShape?.rect = CGRect(origin: origin, size: size)
                            }
                        }
                    }
                    .onEnded { value in
                        if activeTool == .select {
                            isDraggingShape = false
                            // Update cache after drag ends
                            if let selectedID = selectedShapeID, let idx = shapes.firstIndex(where: { $0.id == selectedID }) {
                                var updated = shapes[idx]
                                if updated.tool == .rect {
                                    updated.sketchyPath = sketchyRect(rect: updated.rect)
                                    if updated.fillStyle == .hachure { updated.hachurePath = sketchyHachure(rect: updated.rect) }
                                } else if updated.tool == .circle {
                                    updated.sketchyPath = sketchyCircle(rect: updated.rect)
                                    if updated.fillStyle == .hachure { updated.hachurePath = sketchyHachure(rect: updated.rect) }
                                } else if updated.tool == .pen {
                                    var path = Path()
                                    if updated.points.count > 1 { path.addLines(updated.points) }
                                    updated.sketchyPath = path
                                }
                                shapes[idx] = updated
                            }
                            return
                        }
                        if activeTool == .text {
                            textSpawnPoint = value.location
                            if let hitShape = findHitShape(at: value.location), hitShape.tool == .text {
                                selectedShapeID = hitShape.id
                                textInputVal = hitShape.text
                            } else {
                                textInputVal = ""
                            }
                            showTextInput = true
                            return
                        }
                        if var current = currentShape {
                            // Bake deterministic sketchy geometry on completion
                            if current.tool == .rect {
                                current.sketchyPath = sketchyRect(rect: current.rect)
                                if current.fillStyle == .hachure { current.hachurePath = sketchyHachure(rect: current.rect) }
                            } else if current.tool == .circle {
                                current.sketchyPath = sketchyCircle(rect: current.rect)
                                if current.fillStyle == .hachure { current.hachurePath = sketchyHachure(rect: current.rect) }
                            } else if current.tool == .pen {
                                var p = Path()
                                if current.points.count > 1 { p.addLines(current.points) }
                                current.sketchyPath = p
                            }
                            shapes.append(current)
                            currentShape = nil
                        }
                    }
            )

            VStack {
                Spacer()
                HStack {
                    WhiteboardSettingsSidebar(
                        strokeWidth: $strokeWidth, strokeStyle: $strokeStyle, fillStyle: $fillStyle, fontSize: $fontSize
                    )
                    .padding(20)
                    Spacer()
                }
            }
            .allowsHitTesting(true)

            // Drawing toolbar.
            VStack {
                HStack(spacing: 12) {
                    ToolButton(icon: "arrow.up.and.down.and.arrow.left.and.right", tool: .select, activeTool: activeTool) {
                        activeTool = .select
                    }
                    ToolButton(icon: "pencil", tool: .pen, activeTool: activeTool) {
                        activeTool = .pen
                        selectedShapeID = nil
                    }
                    ToolButton(icon: "square", tool: .rect, activeTool: activeTool) {
                        activeTool = .rect
                        selectedShapeID = nil
                    }
                    ToolButton(icon: "circle", tool: .circle, activeTool: activeTool) {
                        activeTool = .circle
                        selectedShapeID = nil
                    }
                    ToolButton(icon: "textformat", tool: .text, activeTool: activeTool) { activeTool = .text }
                    ToolButton(icon: "eraser", tool: .eraser, activeTool: activeTool) {
                        activeTool = .eraser
                        selectedShapeID = nil
                    }

                    Divider().frame(height: 18).background(Color.white.opacity(0.12))

                    HStack(spacing: 6) {
                        ColorDot(color: .white, selected: strokeColor == .white) { strokeColor = .white }
                        ColorDot(color: .red, selected: strokeColor == .red) { strokeColor = .red }
                        ColorDot(color: .blue, selected: strokeColor == .blue) { strokeColor = .blue }
                        ColorDot(color: .green, selected: strokeColor == .green) { strokeColor = .green }
                    }

                    Divider().frame(height: 18).background(Color.white.opacity(0.12))

                    Button(action: {
                        shapes.removeAll()
                        selectedShapeID = nil
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Color.red.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                .padding(.top, 16)

                Spacer()
            }
            .allowsHitTesting(true)

            // Text editor overlay.
            if showTextInput {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { showTextInput = false }

                    VStack(spacing: 16) {
                        Text(selectedShapeID != nil ? "Edit Whiteboard Text" : "Add Text to Whiteboard")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))

                        HStack(spacing: 8) {
                            TextField(
                                "Type something beautiful...", text: $textInputVal,
                                onCommit: {
                                    commitTextAction()
                                }
                            )
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))

                            Button(action: {
                                if textInputVal.hasPrefix("• ") {
                                    textInputVal.removeFirst(2)
                                } else {
                                    textInputVal = "• " + textInputVal
                                }
                            }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help("Toggle Bullet Point")
                        }
                        .frame(width: 320)

                        HStack(spacing: 12) {
                            Button(action: {
                                showTextInput = false
                                textInputVal = ""
                                selectedShapeID = nil
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                commitTextAction()
                            }) {
                                Text("Save & Insert")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 7)
                                    .background(Color.blue.opacity(0.85))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(22)
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.4), radius: 25, x: 0, y: 12)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .onAppear {
            for index in shapes.indices where shapes[index].sketchyPath == nil {
                switch shapes[index].tool {
                case .rect:
                    shapes[index].sketchyPath = sketchyRect(rect: shapes[index].rect)
                    if shapes[index].fillStyle == .hachure {
                        shapes[index].hachurePath = sketchyHachure(rect: shapes[index].rect)
                    }
                case .circle:
                    shapes[index].sketchyPath = sketchyCircle(rect: shapes[index].rect)
                    if shapes[index].fillStyle == .hachure {
                        shapes[index].hachurePath = sketchyHachure(rect: shapes[index].rect)
                    }
                case .pen:
                    var path = Path()
                    if shapes[index].points.count > 1 { path.addLines(shapes[index].points) }
                    shapes[index].sketchyPath = path
                default:
                    break
                }
            }
        }
    }

    private func commitTextAction() {
        if !textInputVal.isEmpty {
            if let selectedID = selectedShapeID, let idx = shapes.firstIndex(where: { $0.id == selectedID }) {
                shapes[idx].text = textInputVal
            } else {
                shapes.append(
                    DrawingShape(
                        tool: .text,
                        points: [textSpawnPoint],
                        text: textInputVal,
                        color: strokeColor,
                        fontSize: fontSize
                    )
                )
            }
        }
        textInputVal = ""
        showTextInput = false
        selectedShapeID = nil
    }
}
