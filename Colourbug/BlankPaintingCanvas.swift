import SwiftUI
import UIKit

// A deliberately empty surface for judging the behaviour of the paint itself.
struct BlankPaintingCanvas: UIViewRepresentable {
    func makeUIView(context: Context) -> BlankPaintingView { BlankPaintingView() }
    func updateUIView(_ uiView: BlankPaintingView, context: Context) {}
}

final class BlankPaintingView: UIView {
    private let session = PaintingSession()
    private var paper: UIImageView?
    private var paint: PaintView?
    private var canvasSize = CGSize.zero
    private var behaviour: PaintBehaviour = .fluid

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1)
        isMultipleTouchEnabled = true
        session.selectedColour = PaintColour(id: "ink", name: "Indigo",
                                              red: 0.25, green: 0.38, blue: 0.69)
        let comparison = UITapGestureRecognizer(target: self,
                                                 action: #selector(swapPaintBehaviour))
        comparison.numberOfTouchesRequired = 2
        comparison.numberOfTapsRequired = 2
        comparison.cancelsTouchesInView = false
        addGestureRecognizer(comparison)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        guard size.width > 0, size.height > 0, size != canvasSize else { return }
        canvasSize = size
        paper?.removeFromSuperview()
        paint?.stopAnimating()
        paint?.removeFromSuperview()

        let texture = ImagePaperStrategy(size: size).view
        texture.layer.shadowOpacity = 0
        addSubview(texture)
        paper = texture

        let template = PaintingTemplate.blankPaper(size: size)
        let surface = PaintView(size: size, template: template,
                                session: session, behaviour: behaviour)
        addSubview(surface)
        paint = surface
    }

    @objc private func swapPaintBehaviour() {
        behaviour = behaviour == .paperBloom ? .fluid : .paperBloom
        canvasSize = .zero
        setNeedsLayout()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        paint?.handleTouchesBegan(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        paint?.handleTouchesMoved(touches, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        paint?.handleTouchesEnded(touches, event: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        paint?.handleTouchesCancelled(touches)
    }
}
