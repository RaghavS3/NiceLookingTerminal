import AppKit
import SwiftUI

enum DrawingTool: String, CaseIterable, Codable {
    case select = "arrow"
    case pen = "pencil"
    case rect = "square"
    case circle = "circle"
    case text = "textformat"
    case eraser = "eraser"
}

enum FillStyle: String, Codable {
    case empty
    case hachure
    case solid
}

enum StrokePattern: String, Codable {
    case solid
    case dashed
}

struct DrawingShape: Identifiable, Codable {
    let id: UUID
    var tool: DrawingTool
    var points: [CGPoint] = []
    var rect: CGRect = .zero
    var text: String = ""
    var color: Color = .black
    var lineWidth: CGFloat = 3
    var fillStyle: FillStyle = .empty
    var strokeStyle: StrokePattern = .solid
    var fontSize: CGFloat = 18

    // Cached geometry keeps rendering deterministic and avoids rebuilding paths per frame.
    var sketchyPath: Path? = nil
    var hachurePath: Path? = nil

    init(
        id: UUID = UUID(),
        tool: DrawingTool,
        points: [CGPoint] = [],
        rect: CGRect = .zero,
        text: String = "",
        color: Color = .black,
        lineWidth: CGFloat = 3,
        fillStyle: FillStyle = .empty,
        strokeStyle: StrokePattern = .solid,
        fontSize: CGFloat = 18,
        sketchyPath: Path? = nil,
        hachurePath: Path? = nil
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.rect = rect
        self.text = text
        self.color = color
        self.lineWidth = lineWidth
        self.fillStyle = fillStyle
        self.strokeStyle = strokeStyle
        self.fontSize = fontSize
        self.sketchyPath = sketchyPath
        self.hachurePath = hachurePath
    }

    private enum CodingKeys: String, CodingKey {
        case id, tool, points, rect, text, color, lineWidth, fillStyle, strokeStyle, fontSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        tool = try container.decode(DrawingTool.self, forKey: .tool)
        points = try container.decode([CGPoint].self, forKey: .points)
        rect = try container.decode(CGRect.self, forKey: .rect)
        text = try container.decode(String.self, forKey: .text)
        color = try container.decode(CodableColor.self, forKey: .color).color
        lineWidth = try container.decode(CGFloat.self, forKey: .lineWidth)
        fillStyle = try container.decode(FillStyle.self, forKey: .fillStyle)
        strokeStyle = try container.decode(StrokePattern.self, forKey: .strokeStyle)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        sketchyPath = nil
        hachurePath = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tool, forKey: .tool)
        try container.encode(points, forKey: .points)
        try container.encode(rect, forKey: .rect)
        try container.encode(text, forKey: .text)
        try container.encode(CodableColor(color), forKey: .color)
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encode(fillStyle, forKey: .fillStyle)
        try container.encode(strokeStyle, forKey: .strokeStyle)
        try container.encode(fontSize, forKey: .fontSize)
    }

    // Bounds tracking for selection & dragging
    var bounds: CGRect {
        switch tool {
        case .rect, .circle:
            return rect
        case .text:
            // Estimate a text hit target from the configured font size.
            let countFactor = CGFloat(text.count)
            let sizeFactor = fontSize * 0.55
            let width = (countFactor * sizeFactor) + 20.0
            let height = fontSize + 12.0
            if let p = points.first {
                return CGRect(x: p.x, y: p.y - 4, width: width, height: height)
            }
            return .zero
        case .pen:
            if points.isEmpty { return .zero }
            let xs = points.map { $0.x }
            let ys = points.map { $0.y }
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 0
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        default:
            return .zero
        }
    }
}

private struct CodableColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
        red = Double(converted.redComponent)
        green = Double(converted.greenComponent)
        blue = Double(converted.blueComponent)
        alpha = Double(converted.alphaComponent)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

func CGPointDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
}
