import CoreGraphics

struct PaintingTemplate {
    struct Area {
        let id: String
        let path: CGPath
    }

    let size: CGSize
    let paintableAreas: [Area]

    func isPaintable(at point: CGPoint) -> Bool {
        paintableAreas.contains { $0.path.contains(point) }
    }

    // A single paintable star, centered on the 1200 × 900 paper sheet.
    static let sampleStar: PaintingTemplate = {
        let vertices = [
            CGPoint(x: 600, y: 150),
            CGPoint(x: 679, y: 341),
            CGPoint(x: 885, y: 357),
            CGPoint(x: 728, y: 492),
            CGPoint(x: 776, y: 693),
            CGPoint(x: 600, y: 585),
            CGPoint(x: 424, y: 693),
            CGPoint(x: 472, y: 492),
            CGPoint(x: 315, y: 357),
            CGPoint(x: 521, y: 341)
        ]
        let path = CGMutablePath()
        path.addLines(between: vertices)
        path.closeSubpath()
        return PaintingTemplate(
            size: CGSize(width: 1_200, height: 900),
            paintableAreas: [Area(id: "star", path: path)]
        )
    }()
}
