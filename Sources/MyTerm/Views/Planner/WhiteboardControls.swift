import AppKit
import SwiftUI

struct WidthOption: View {
    let width: CGFloat
    let label: String
    let current: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(current == width ? .white : .white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(current == width ? Color.white.opacity(0.15) : Color.white.opacity(0.03))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(current == width ? 0.2 : 0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct StyleOption: View {
    let icon: String
    let style: StrokePattern
    let current: StrokePattern
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(current == style ? .white : .white.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(current == style ? Color.white.opacity(0.15) : Color.white.opacity(0.03))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(current == style ? 0.2 : 0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct FillOption: View {
    let icon: String
    let style: FillStyle
    let current: FillStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(current == style ? .white : .white.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(current == style ? Color.white.opacity(0.15) : Color.white.opacity(0.03))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(current == style ? 0.2 : 0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct FontSizeOption: View {
    let size: CGFloat
    let label: String
    let current: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(current == size ? .white : .white.opacity(0.5))
                .frame(width: 32, height: 26)
                .background(current == size ? Color.blue.opacity(0.85) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(current == size ? 0.15 : 0.04), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct WhiteboardSettingsSidebar: View {
    @Binding var strokeWidth: CGFloat
    @Binding var strokeStyle: StrokePattern
    @Binding var fillStyle: FillStyle
    @Binding var fontSize: CGFloat
    @State private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PROPERTIES")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isCollapsed ? "chevron.right.circle.fill" : "chevron.left.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 14) {
                    // Stroke Width
                    VStack(alignment: .leading, spacing: 5) {
                        Text("STROKE WIDTH")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            WidthOption(width: 2, label: "Thin", current: strokeWidth) { strokeWidth = 2 }
                            WidthOption(width: 4, label: "Medium", current: strokeWidth) { strokeWidth = 4 }
                            WidthOption(width: 7, label: "Thick", current: strokeWidth) { strokeWidth = 7 }
                        }
                    }

                    // Stroke Style
                    VStack(alignment: .leading, spacing: 5) {
                        Text("STROKE STYLE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            StyleOption(icon: "line.3.horizontal", style: .solid, current: strokeStyle) { strokeStyle = .solid }
                            StyleOption(icon: "line.dashed", style: .dashed, current: strokeStyle) { strokeStyle = .dashed }
                        }
                    }

                    // Fill Style
                    VStack(alignment: .leading, spacing: 5) {
                        Text("FILL STYLE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            FillOption(icon: "circle", style: .empty, current: fillStyle) { fillStyle = .empty }
                            FillOption(icon: "circle.dashed", style: .hachure, current: fillStyle) { fillStyle = .hachure }
                            FillOption(icon: "circle.fill", style: .solid, current: fillStyle) { fillStyle = .solid }
                        }
                    }

                    // Font Size Options
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TEXT SIZE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            FontSizeOption(size: 14, label: "S", current: fontSize) { fontSize = 14 }
                            FontSizeOption(size: 18, label: "M", current: fontSize) { fontSize = 18 }
                            FontSizeOption(size: 24, label: "L", current: fontSize) { fontSize = 24 }
                            FontSizeOption(size: 36, label: "XL", current: fontSize) { fontSize = 36 }
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(14)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .frame(width: isCollapsed ? 120 : 200)
    }
}

// MARK: - Whiteboard Gray Dotted Background Pattern

func generateDotTileImage() -> NSImage {
    let size = NSSize(width: 24, height: 24)
    let image = NSImage(size: size)
    image.lockFocus()

    let dotRect = NSRect(x: 11, y: 11, width: 2, height: 2)
    NSColor.gray.withAlphaComponent(0.35).set()
    let path = NSBezierPath(ovalIn: dotRect)
    path.fill()

    image.unlockFocus()
    return image
}

struct DotGridView: View {
    private static let tileImage = generateDotTileImage()

    var body: some View {
        Color.clear
            .background(
                Image(nsImage: Self.tileImage)
                    .resizable(resizingMode: .tile)
            )
    }
}

// MARK: - Whiteboard Tool Buttons

struct ToolButton: View {
    let icon: String
    let tool: DrawingTool
    let activeTool: DrawingTool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: activeTool == tool ? "\(icon).fill" : icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(activeTool == tool ? .white : .white.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(activeTool == tool ? Color.blue.opacity(0.8) : Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(activeTool == tool ? 0.2 : 0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ColorDot: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: selected ? 2 : 0)
                )
                .scaleEffect(selected ? 1.25 : 1.0)
                .shadow(color: Color.black.opacity(0.2), radius: 3)
        }
        .buttonStyle(.plain)
    }
}
