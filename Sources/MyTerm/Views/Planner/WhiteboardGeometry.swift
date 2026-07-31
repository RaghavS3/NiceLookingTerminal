import SwiftUI

func sketchyLine(from start: CGPoint, to end: CGPoint, roughness: CGFloat = 1.2) -> Path {
    var path = Path()
    let length = CGPointDistance(start, end)
    if length < 1 { return path }

    for _ in 0..<2 {
        let offset1 = CGFloat.random(in: -roughness...roughness)
        let offset2 = CGFloat.random(in: -roughness...roughness)
        let offset3 = CGFloat.random(in: -roughness...roughness)
        let offset4 = CGFloat.random(in: -roughness...roughness)

        let p1 = CGPoint(x: start.x + offset1, y: start.y + offset2)
        let p2 = CGPoint(x: end.x + offset3, y: end.y + offset4)

        let mid = CGPoint(
            x: (p1.x + p2.x) / 2 + CGFloat.random(in: -roughness...roughness),
            y: (p1.y + p2.y) / 2 + CGFloat.random(in: -roughness...roughness)
        )

        path.move(to: p1)
        path.addQuadCurve(to: p2, control: mid)
    }
    return path
}

func sketchyRect(rect: CGRect, roughness: CGFloat = 1.2) -> Path {
    var path = Path()
    let tl = rect.origin
    let tr = CGPoint(x: rect.maxX, y: rect.minY)
    let br = CGPoint(x: rect.maxX, y: rect.maxY)
    let bl = CGPoint(x: rect.minX, y: rect.maxY)

    path.addPath(sketchyLine(from: tl, to: tr, roughness: roughness))
    path.addPath(sketchyLine(from: tr, to: br, roughness: roughness))
    path.addPath(sketchyLine(from: br, to: bl, roughness: roughness))
    path.addPath(sketchyLine(from: bl, to: tl, roughness: roughness))

    return path
}

func sketchyCircle(rect: CGRect, roughness: CGFloat = 1.2) -> Path {
    var path = Path()
    let cx = rect.midX
    let cy = rect.midY
    let rx = rect.width / 2
    let ry = rect.height / 2

    for _ in 0..<2 {
        let segments = 16
        var points: [CGPoint] = []
        for i in 0...segments {
            let angle = (CGFloat(i) / CGFloat(segments)) * CGFloat.pi * 2
            let rOffsetFactor = CGFloat.random(in: -roughness...roughness)
            let curRx = rx + rOffsetFactor
            let curRy = ry + rOffsetFactor
            let px = cx + cos(angle) * curRx
            let py = cy + sin(angle) * curRy
            points.append(CGPoint(x: px, y: py))
        }
        if points.count > 1 {
            path.move(to: points[0])
            for k in 1..<points.count {
                path.addLine(to: points[k])
            }
        }
    }
    return path
}

func sketchyHachure(rect: CGRect, spacing: CGFloat = 10, roughness: CGFloat = 1.0) -> Path {
    var path = Path()
    let width = rect.width
    let height = rect.height
    if width < 5 || height < 5 { return path }

    let startX = rect.minX
    let startY = rect.minY

    var offset: CGFloat = 0
    while offset < (width + height) {
        let x1 = max(startX, startX + offset - height)
        let y1 = min(rect.maxY, startY + offset)
        let x2 = min(rect.maxX, startX + offset)
        let y2 = max(startY, startY + offset - width)

        if x1 != x2 && y1 != y2 {
            path.addPath(sketchyLine(from: CGPoint(x: x1, y: y1), to: CGPoint(x: x2, y: y2), roughness: roughness))
        }
        offset += spacing
    }
    return path
}
