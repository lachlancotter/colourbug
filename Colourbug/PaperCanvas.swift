import SwiftUI
import UIKit

struct PaperCanvas: UIViewRepresentable {
    func makeUIView(context: Context) -> PaperCanvasView { PaperCanvasView() }
    func updateUIView(_ uiView: PaperCanvasView, context: Context) {}
}

final class PaperCanvasView: UIView, UIGestureRecognizerDelegate {
    private let paperSize = CGSize(width: 1_200, height: 900)
    private var scale: CGFloat = 1
    private var minimumScale: CGFloat = 0.3
    private var offset: CGPoint = .zero
    private var hasLaidOut = false
    private lazy var paper = ImagePaperStrategy(size: paperSize)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.88, green: 0.86, blue: 0.82, alpha: 1)
        isOpaque = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        addSubview(paper.view)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !hasLaidOut && bounds.width > 0 && bounds.height > 0 {
            scale = min((bounds.width - 64) / paperSize.width,
                        (bounds.height - 64) / paperSize.height)
            minimumScale = min(0.3, scale)
            hasLaidOut = true
        }
        paper.view.frame = bounds
        paper.update(in: bounds, scale: scale, offset: offset)
    }

    private func updatePaper() {
        paper.update(in: bounds, scale: scale, offset: offset)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        offset.x += translation.x
        offset.y += translation.y
        gesture.setTranslation(.zero, in: self)
        updatePaper()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let nextScale = min(max(scale * gesture.scale, minimumScale), 3.5)
        let ratio = nextScale / scale
        let anchor = gesture.location(in: self)
        let viewportCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        offset = CGPoint(
            x: anchor.x - viewportCenter.x - (anchor.x - viewportCenter.x - offset.x) * ratio,
            y: anchor.y - viewportCenter.y - (anchor.y - viewportCenter.y - offset.y) * ratio
        )
        scale = nextScale
        gesture.scale = 1
        updatePaper()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
