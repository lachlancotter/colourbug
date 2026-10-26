import UIKit

// Authored light and shade for this one flower, in the source image's coordinates.
// The canvas clips each pass to StoryFlowerMask and keeps the ink above both passes.
enum FlowerDepthArtwork {
    enum Pass { case shadow, highlight }

    static let shadowImage = makeImage(.shadow)
    static let highlightImage = makeImage(.highlight)
    static let castShadowImage = makeCastShadow()

    static let castShadowPadding: CGFloat = 90

    private static func makeCastShadow() -> UIImage {
        guard let silhouette = UIImage(named: "StoryFlowerMask") else {
            fatalError("Missing StoryFlowerMask image")
        }
        let padding = castShadowPadding
        let imageFrame = CGRect(x: padding, y: padding, width: 1360, height: 1156)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 1360 + padding * 2,
                                                    height: 1156 + padding * 2),
                                       format: format).image { output in
            let context = output.cgContext
            // Two soft scales of shade anchor the bloom without a hard cardboard edge.
            for (offset, blur, opacity) in [
                (CGSize(width: 30, height: 37), CGFloat(48), CGFloat(0.36)),
                (CGSize(width: 11, height: 15), CGFloat(18), CGFloat(0.24))
            ] {
                context.saveGState()
                context.setShadow(offset: offset, blur: blur,
                                  color: UIColor(red: 0.13, green: 0.10, blue: 0.25,
                                                 alpha: opacity).cgColor)
                silhouette.draw(in: imageFrame)
                context.restoreGState()
            }
            // Retain only the cast shade on paper, not a tinted fill under the paint.
            context.setBlendMode(.destinationOut)
            silhouette.draw(in: imageFrame)
        }
    }

    static func makeImage(_ pass: Pass) -> UIImage {
        let size = CGSize(width: 1360, height: 1156)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            let context = output.cgContext
            let dark = UIColor(red: 0.05, green: 0.09, blue: 0.29, alpha: 1)
            let violet = UIColor(red: 0.18, green: 0.07, blue: 0.39, alpha: 1)
            let blueLight = UIColor(red: 0.35, green: 0.74, blue: 1, alpha: 1)
            let lilacLight = UIColor(red: 0.64, green: 0.54, blue: 1, alpha: 1)
            let goldLight = UIColor(red: 1, green: 0.71, blue: 0.35, alpha: 1)

            func glow(_ centre: CGPoint, radius: CGFloat, colour: UIColor, opacity: CGFloat) {
                let space = CGColorSpaceCreateDeviceRGB()
                let colors = [colour.withAlphaComponent(opacity).cgColor,
                              colour.withAlphaComponent(0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: space, colors: colors,
                                                locations: [0, 1]) else { return }
                context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                           endCenter: centre, endRadius: radius,
                                           options: [])
            }

            func sweep(_ start: CGPoint, _ curves: [(CGPoint, CGPoint, CGPoint)],
                       width: CGFloat, colour: UIColor, opacity: CGFloat, blur: CGFloat) {
                let path = UIBezierPath()
                path.move(to: start)
                for (control1, control2, end) in curves {
                    path.addCurve(to: end, controlPoint1: control1, controlPoint2: control2)
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.lineWidth = width
                context.saveGState()
                context.setShadow(offset: .zero, blur: blur,
                                  color: colour.withAlphaComponent(opacity * 0.55).cgColor)
                context.setStrokeColor(colour.withAlphaComponent(opacity).cgColor)
                context.addPath(path.cgPath)
                context.setLineWidth(width)
                context.setLineCap(.round)
                context.strokePath()
                context.restoreGState()
            }

            switch pass {
            case .shadow:
                // The throat, overlapping petals and lower folds carry the depth.
                glow(CGPoint(x: 943, y: 590), radius: 290, colour: dark, opacity: 0.57)
                glow(CGPoint(x: 814, y: 818), radius: 395, colour: violet, opacity: 0.35)
                glow(CGPoint(x: 640, y: 605), radius: 180, colour: violet, opacity: 0.31)
                glow(CGPoint(x: 218, y: 634), radius: 215, colour: dark, opacity: 0.30)
                glow(CGPoint(x: 491, y: 525), radius: 105, colour: violet, opacity: 0.32)
                sweep(CGPoint(x: 681, y: 372),
                      [(CGPoint(x: 805, y: 456), CGPoint(x: 891, y: 526), CGPoint(x: 966, y: 551))],
                      width: 76, colour: dark, opacity: 0.39, blur: 27)
                sweep(CGPoint(x: 963, y: 571),
                      [(CGPoint(x: 1051, y: 635), CGPoint(x: 1124, y: 703), CGPoint(x: 1166, y: 756))],
                      width: 86, colour: dark, opacity: 0.45, blur: 29)
                sweep(CGPoint(x: 755, y: 661),
                      [(CGPoint(x: 788, y: 782), CGPoint(x: 908, y: 932), CGPoint(x: 974, y: 1012))],
                      width: 100, colour: dark, opacity: 0.41, blur: 36)
                sweep(CGPoint(x: 591, y: 372),
                      [(CGPoint(x: 579, y: 508), CGPoint(x: 604, y: 668), CGPoint(x: 653, y: 779))],
                      width: 66, colour: violet, opacity: 0.34, blur: 24)
                sweep(CGPoint(x: 355, y: 360),
                      [(CGPoint(x: 291, y: 490), CGPoint(x: 242, y: 658), CGPoint(x: 176, y: 797))],
                      width: 54, colour: dark, opacity: 0.28, blur: 21)
                sweep(CGPoint(x: 475, y: 430),
                      [(CGPoint(x: 448, y: 484), CGPoint(x: 448, y: 530), CGPoint(x: 467, y: 572))],
                      width: 31, colour: violet, opacity: 0.38, blur: 13)
                // Contact shade at overlapping petal edges makes their order clear.
                sweep(CGPoint(x: 736, y: 712),
                      [(CGPoint(x: 838, y: 657), CGPoint(x: 916, y: 583), CGPoint(x: 983, y: 565))],
                      width: 28, colour: dark, opacity: 0.52, blur: 13)
                sweep(CGPoint(x: 979, y: 564),
                      [(CGPoint(x: 1062, y: 605), CGPoint(x: 1114, y: 650), CGPoint(x: 1200, y: 665))],
                      width: 28, colour: violet, opacity: 0.45, blur: 14)
            case .highlight:
                // Coloured light brightens the indigo rather than whitening it out.
                glow(CGPoint(x: 790, y: 422), radius: 245, colour: blueLight, opacity: 0.44)
                glow(CGPoint(x: 1135, y: 471), radius: 172, colour: goldLight, opacity: 0.44)
                glow(CGPoint(x: 1142, y: 634), radius: 187, colour: blueLight, opacity: 0.38)
                glow(CGPoint(x: 674, y: 946), radius: 188, colour: lilacLight, opacity: 0.30)
                glow(CGPoint(x: 248, y: 433), radius: 156, colour: blueLight, opacity: 0.37)
                glow(CGPoint(x: 493, y: 478), radius: 86, colour: goldLight, opacity: 0.28)
                sweep(CGPoint(x: 674, y: 331),
                      [(CGPoint(x: 791, y: 375), CGPoint(x: 859, y: 486), CGPoint(x: 1010, y: 505))],
                      width: 40, colour: blueLight, opacity: 0.48, blur: 20)
                sweep(CGPoint(x: 1130, y: 387),
                      [(CGPoint(x: 1182, y: 419), CGPoint(x: 1159, y: 493), CGPoint(x: 1106, y: 534))],
                      width: 38, colour: goldLight, opacity: 0.60, blur: 18)
                sweep(CGPoint(x: 1216, y: 531),
                      [(CGPoint(x: 1293, y: 588), CGPoint(x: 1266, y: 660), CGPoint(x: 1192, y: 672))],
                      width: 39, colour: blueLight, opacity: 0.50, blur: 18)
                sweep(CGPoint(x: 608, y: 405),
                      [(CGPoint(x: 622, y: 551), CGPoint(x: 672, y: 683), CGPoint(x: 675, y: 765))],
                      width: 39, colour: blueLight, opacity: 0.45, blur: 20)
                sweep(CGPoint(x: 844, y: 665),
                      [(CGPoint(x: 939, y: 743), CGPoint(x: 1024, y: 849), CGPoint(x: 1090, y: 897))],
                      width: 39, colour: lilacLight, opacity: 0.42, blur: 19)
                sweep(CGPoint(x: 285, y: 385),
                      [(CGPoint(x: 227, y: 480), CGPoint(x: 145, y: 606), CGPoint(x: 118, y: 700))],
                      width: 33, colour: blueLight, opacity: 0.43, blur: 18)
            }
        }
    }
}
