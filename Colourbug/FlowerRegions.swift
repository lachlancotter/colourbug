import UIKit

// Colour suggestions for the flower's four authored parts. They are guidance:
// the fluid paint can still cross their boundaries and mix on the paper.
enum FlowerRegion: Int, CaseIterable {
    case bell, leaf, stem, bud

    var title: String {
        switch self {
        case .bell: "Bell"
        case .leaf: "Leaf"
        case .stem: "Stem"
        case .bud: "Bud"
        }
    }

    var colour: PaintColour {
        switch self {
        case .bell: PaintColour(id: "bell", name: "Bell blue",
                                red: 0.25, green: 0.38, blue: 0.69)
        case .leaf: PaintColour(id: "leaf", name: "Leaf green",
                                red: 0.27, green: 0.57, blue: 0.39)
        case .stem: PaintColour(id: "stem", name: "Stem jade",
                                red: 0.18, green: 0.45, blue: 0.48)
        case .bud: PaintColour(id: "bud", name: "Bud rose",
                               red: 0.83, green: 0.39, blue: 0.43)
        }
    }

    var uiColour: UIColor {
        let paint = colour
        return UIColor(red: CGFloat(paint.red), green: CGFloat(paint.green),
                       blue: CGFloat(paint.blue), alpha: 1)
    }

    // Small, deliberately simple silhouettes for the pigment wells.
    // Coordinates fit a 48 by 48 square, independent of the artwork paths.
    var palettePath: CGPath {
        let shape = UIBezierPath()
        switch self {
        case .bell:
            shape.move(to: CGPoint(x: 4, y: 13))
            shape.addCurve(to: CGPoint(x: 18, y: 16), controlPoint1: CGPoint(x: 8, y: 9),
                           controlPoint2: CGPoint(x: 14, y: 12))
            shape.addCurve(to: CGPoint(x: 34, y: 13), controlPoint1: CGPoint(x: 24, y: 18),
                           controlPoint2: CGPoint(x: 29, y: 16))
            shape.addCurve(to: CGPoint(x: 43, y: 5), controlPoint1: CGPoint(x: 39, y: 10),
                           controlPoint2: CGPoint(x: 39, y: 5))
            shape.addCurve(to: CGPoint(x: 40, y: 19), controlPoint1: CGPoint(x: 47, y: 10),
                           controlPoint2: CGPoint(x: 45, y: 15))
            shape.addCurve(to: CGPoint(x: 46, y: 29), controlPoint1: CGPoint(x: 48, y: 21),
                           controlPoint2: CGPoint(x: 48, y: 26))
            shape.addCurve(to: CGPoint(x: 41, y: 34), controlPoint1: CGPoint(x: 46, y: 34),
                           controlPoint2: CGPoint(x: 43, y: 34))
            shape.addCurve(to: CGPoint(x: 34, y: 42), controlPoint1: CGPoint(x: 41, y: 41),
                           controlPoint2: CGPoint(x: 37, y: 44))
            shape.addCurve(to: CGPoint(x: 24, y: 40), controlPoint1: CGPoint(x: 31, y: 42),
                           controlPoint2: CGPoint(x: 27, y: 43))
            shape.addCurve(to: CGPoint(x: 12, y: 29), controlPoint1: CGPoint(x: 18, y: 39),
                           controlPoint2: CGPoint(x: 15, y: 34))
            shape.addCurve(to: CGPoint(x: 4, y: 13), controlPoint1: CGPoint(x: 8, y: 24),
                           controlPoint2: CGPoint(x: 6, y: 18))
        case .leaf:
            shape.move(to: CGPoint(x: 5, y: 39))
            shape.addCurve(to: CGPoint(x: 41, y: 7), controlPoint1: CGPoint(x: 7, y: 16),
                           controlPoint2: CGPoint(x: 24, y: 6))
            shape.addCurve(to: CGPoint(x: 5, y: 39), controlPoint1: CGPoint(x: 43, y: 25),
                           controlPoint2: CGPoint(x: 27, y: 43))
        case .stem:
            shape.move(to: CGPoint(x: 10, y: 44))
            shape.addCurve(to: CGPoint(x: 30, y: 8), controlPoint1: CGPoint(x: 9, y: 28),
                           controlPoint2: CGPoint(x: 24, y: 23))
            shape.addCurve(to: CGPoint(x: 36, y: 3), controlPoint1: CGPoint(x: 32, y: 5),
                           controlPoint2: CGPoint(x: 33, y: 3))
            shape.addCurve(to: CGPoint(x: 29, y: 27), controlPoint1: CGPoint(x: 38, y: 12),
                           controlPoint2: CGPoint(x: 32, y: 21))
            shape.addCurve(to: CGPoint(x: 17, y: 45), controlPoint1: CGPoint(x: 25, y: 35),
                           controlPoint2: CGPoint(x: 20, y: 40))
            shape.close()
            // A little offshoot makes this read as a stem rather than a slash.
            let branch = UIBezierPath()
            branch.move(to: CGPoint(x: 23, y: 30))
            branch.addCurve(to: CGPoint(x: 39, y: 22), controlPoint1: CGPoint(x: 29, y: 25),
                            controlPoint2: CGPoint(x: 35, y: 23))
            branch.addLine(to: CGPoint(x: 37, y: 28))
            branch.addCurve(to: CGPoint(x: 23, y: 35), controlPoint1: CGPoint(x: 32, y: 29),
                            controlPoint2: CGPoint(x: 27, y: 32))
            branch.close()
            shape.append(branch)
        case .bud:
            shape.move(to: CGPoint(x: 26, y: 5))
            shape.addCurve(to: CGPoint(x: 39, y: 25), controlPoint1: CGPoint(x: 34, y: 10),
                           controlPoint2: CGPoint(x: 39, y: 17))
            shape.addCurve(to: CGPoint(x: 26, y: 41), controlPoint1: CGPoint(x: 39, y: 34),
                           controlPoint2: CGPoint(x: 32, y: 41))
            shape.addCurve(to: CGPoint(x: 11, y: 26), controlPoint1: CGPoint(x: 17, y: 42),
                           controlPoint2: CGPoint(x: 10, y: 35))
            shape.addCurve(to: CGPoint(x: 26, y: 5), controlPoint1: CGPoint(x: 11, y: 15),
                           controlPoint2: CGPoint(x: 20, y: 8))
        }
        shape.close()
        return shape.cgPath
    }

    // Source image coordinates, before the shared silhouette clip is applied.
    var path: CGPath {
        let path = UIBezierPath()
        switch self {
        case .bell:
            path.move(to: CGPoint(x: 554, y: 286))
            path.addLine(to: CGPoint(x: 1360, y: 286))
            path.addLine(to: CGPoint(x: 1360, y: 1156))
            path.addLine(to: CGPoint(x: 452, y: 1156))
            path.addCurve(to: CGPoint(x: 554, y: 286),
                          controlPoint1: CGPoint(x: 571, y: 965),
                          controlPoint2: CGPoint(x: 523, y: 492))
        case .leaf:
            path.move(to: CGPoint(x: 39, y: 557))
            path.addCurve(to: CGPoint(x: 393, y: 313),
                          controlPoint1: CGPoint(x: 74, y: 399),
                          controlPoint2: CGPoint(x: 263, y: 311))
            path.addCurve(to: CGPoint(x: 388, y: 622),
                          controlPoint1: CGPoint(x: 409, y: 423),
                          controlPoint2: CGPoint(x: 419, y: 528))
            path.addCurve(to: CGPoint(x: 203, y: 882),
                          controlPoint1: CGPoint(x: 318, y: 792),
                          controlPoint2: CGPoint(x: 231, y: 868))
            path.addCurve(to: CGPoint(x: 39, y: 557),
                          controlPoint1: CGPoint(x: 74, y: 820),
                          controlPoint2: CGPoint(x: 29, y: 681))
        case .stem:
            path.move(to: CGPoint(x: 340, y: 359))
            path.addCurve(to: CGPoint(x: 474, y: 60),
                          controlPoint1: CGPoint(x: 413, y: 233),
                          controlPoint2: CGPoint(x: 447, y: 89))
            path.addCurve(to: CGPoint(x: 434, y: 297),
                          controlPoint1: CGPoint(x: 472, y: 116),
                          controlPoint2: CGPoint(x: 390, y: 270))
            path.addCurve(to: CGPoint(x: 710, y: 177),
                          controlPoint1: CGPoint(x: 493, y: 210),
                          controlPoint2: CGPoint(x: 626, y: 154))
            path.addCurve(to: CGPoint(x: 769, y: 323),
                          controlPoint1: CGPoint(x: 777, y: 208),
                          controlPoint2: CGPoint(x: 774, y: 289))
            path.addCurve(to: CGPoint(x: 632, y: 319),
                          controlPoint1: CGPoint(x: 708, y: 368),
                          controlPoint2: CGPoint(x: 654, y: 330))
            path.addCurve(to: CGPoint(x: 504, y: 408),
                          controlPoint1: CGPoint(x: 573, y: 249),
                          controlPoint2: CGPoint(x: 479, y: 313))
            path.addCurve(to: CGPoint(x: 449, y: 429),
                          controlPoint1: CGPoint(x: 506, y: 446),
                          controlPoint2: CGPoint(x: 470, y: 448))
            path.addCurve(to: CGPoint(x: 340, y: 359),
                          controlPoint1: CGPoint(x: 433, y: 364),
                          controlPoint2: CGPoint(x: 380, y: 344))
        case .bud:
            path.move(to: CGPoint(x: 461, y: 386))
            path.addCurve(to: CGPoint(x: 551, y: 410),
                          controlPoint1: CGPoint(x: 492, y: 379),
                          controlPoint2: CGPoint(x: 536, y: 385))
            path.addCurve(to: CGPoint(x: 555, y: 528),
                          controlPoint1: CGPoint(x: 583, y: 440),
                          controlPoint2: CGPoint(x: 567, y: 505))
            path.addCurve(to: CGPoint(x: 471, y: 608),
                          controlPoint1: CGPoint(x: 546, y: 570),
                          controlPoint2: CGPoint(x: 494, y: 595))
            path.addCurve(to: CGPoint(x: 410, y: 508),
                          controlPoint1: CGPoint(x: 436, y: 581),
                          controlPoint2: CGPoint(x: 399, y: 539))
            path.addCurve(to: CGPoint(x: 461, y: 386),
                          controlPoint1: CGPoint(x: 400, y: 454),
                          controlPoint2: CGPoint(x: 432, y: 397))
        }
        path.close()
        return path.cgPath
    }
}
