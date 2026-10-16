import UIKit

// Pan and zoom move the existing image layer without redrawing the canvas.
final class ImagePaperStrategy {
    let view: UIView = UIView()
    private let paper: UIImageView

    init(size: CGSize) {
        guard let image = UIImage(named: "WatercolourWhisper") else {
            fatalError("Missing bundled WatercolourWhisper image")
        }
        paper = UIImageView(image: image)
        paper.bounds = CGRect(origin: .zero, size: size)
        paper.isUserInteractionEnabled = false
        paper.layer.shadowPath = UIBezierPath(rect: paper.bounds).cgPath
        paper.layer.shadowColor = UIColor(red: 0.29, green: 0.25, blue: 0.19, alpha: 1).cgColor
        paper.layer.shadowOpacity = 0.22
        paper.layer.shadowOffset = CGSize(width: 0, height: 13)
        paper.layer.shadowRadius = 28
        paper.layer.minificationFilter = .trilinear
        paper.layer.magnificationFilter = .linear
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.addSubview(paper)
    }

    func update(in bounds: CGRect, scale: CGFloat, offset: CGPoint) {
        paper.transform = CGAffineTransform(scaleX: scale, y: scale)
        paper.center = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
    }
}
