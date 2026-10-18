import CoreGraphics

struct PaintingTemplate {
    struct Area {
        let id: String
        let colourID: PaintColourID
        let path: CGPath
    }

    let size: CGSize
    let paintableAreas: [Area]

    func areaIndex(at point: CGPoint) -> Int? {
        paintableAreas.indices.reversed().first { paintableAreas[$0].path.contains(point) }
    }

    func area(at point: CGPoint) -> Area? {
        areaIndex(at: point).map { paintableAreas[$0] }
    }

    // A simple flower with separate petals, centre, stem, and leaves.
    static let sampleFlower: PaintingTemplate = {
        func petal(_ id: String, colourID: PaintColourID,
                   center: CGPoint, angle: CGFloat) -> Area {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -60))
            path.addCurve(to: CGPoint(x: 0, y: -260),
                          control1: CGPoint(x: -85, y: -90),
                          control2: CGPoint(x: -95, y: -205))
            path.addCurve(to: CGPoint(x: 0, y: -60),
                          control1: CGPoint(x: 95, y: -205),
                          control2: CGPoint(x: 85, y: -90))
            path.closeSubpath()
            var transform = CGAffineTransform(rotationAngle: angle)
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            return Area(id: id, colourID: colourID, path: path.copy(using: &transform)!)
        }

        func leaf(_ id: String, colourID: PaintColourID, base: CGPoint, tip: CGPoint,
                  upper: CGPoint, lower: CGPoint) -> Area {
            let path = CGMutablePath()
            path.move(to: base)
            path.addQuadCurve(to: tip, control: upper)
            path.addQuadCurve(to: base, control: lower)
            path.closeSubpath()
            return Area(id: id, colourID: colourID, path: path)
        }

        let stem = CGMutablePath()
        stem.move(to: CGPoint(x: 584, y: 520))
        stem.addCurve(to: CGPoint(x: 552, y: 815),
                      control1: CGPoint(x: 605, y: 650), control2: CGPoint(x: 552, y: 750))
        stem.addLine(to: CGPoint(x: 586, y: 815))
        stem.addCurve(to: CGPoint(x: 614, y: 520),
                      control1: CGPoint(x: 587, y: 745), control2: CGPoint(x: 637, y: 630))
        stem.closeSubpath()

        return PaintingTemplate(size: CGSize(width: 1_200, height: 900), paintableAreas: [
            Area(id: "stem", colourID: .green, path: stem),
            petal("top", colourID: .blue, center: CGPoint(x: 600, y: 420), angle: 0),
            petal("upper-right", colourID: .coral, center: CGPoint(x: 600, y: 420), angle: .pi * 2 / 5),
            petal("lower-right", colourID: .orange, center: CGPoint(x: 600, y: 420), angle: .pi * 4 / 5),
            petal("lower-left", colourID: .violet, center: CGPoint(x: 600, y: 420), angle: -.pi * 4 / 5),
            petal("upper-left", colourID: .coral, center: CGPoint(x: 600, y: 420), angle: -.pi * 2 / 5),
            leaf("left-leaf", colourID: .green,
                 base: CGPoint(x: 588, y: 698), tip: CGPoint(x: 390, y: 678),
                 upper: CGPoint(x: 490, y: 620), lower: CGPoint(x: 490, y: 760)),
            leaf("right-leaf", colourID: .green,
                 base: CGPoint(x: 578, y: 755), tip: CGPoint(x: 795, y: 725),
                 upper: CGPoint(x: 680, y: 670), lower: CGPoint(x: 700, y: 815)),
            Area(id: "centre", colourID: .gold,
                 path: CGPath(ellipseIn: CGRect(x: 532, y: 352, width: 136, height: 136), transform: nil))
        ])
    }()
}
