import UIKit

// The paper image sits behind paint in the same transformed sheet.
final class ImagePaperStrategy {
    let view: UIImageView

    init(size: CGSize) {
        guard let image = UIImage(named: "WatercolourWhisper") else {
            fatalError("Missing bundled WatercolourWhisper image")
        }
        view = UIImageView(image: image)
        view.frame = CGRect(origin: .zero, size: size)
        view.isUserInteractionEnabled = false
        view.layer.shadowPath = UIBezierPath(rect: view.bounds).cgPath
        view.layer.shadowColor = UIColor(red: 0.29, green: 0.25, blue: 0.19, alpha: 1).cgColor
        view.layer.shadowOpacity = 0.22
        view.layer.shadowOffset = CGSize(width: 0, height: 13)
        view.layer.shadowRadius = 28
        view.layer.minificationFilter = .trilinear
        view.layer.magnificationFilter = .linear
    }
}
