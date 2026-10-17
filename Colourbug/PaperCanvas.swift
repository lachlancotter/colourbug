import SwiftUI
import UIKit

struct PaperCanvas: UIViewRepresentable {
    func makeUIView(context: Context) -> PaperCanvasView { PaperCanvasView() }
    func updateUIView(_ uiView: PaperCanvasView, context: Context) {}
}

final class PaperCanvasView: UIView, UIGestureRecognizerDelegate {
    private let template = PaintingTemplate.sampleStar
    private var paperSize: CGSize { template.size }
    private let sheet = UIView()
    private lazy var paint = PaintView(size: paperSize, template: template)
    private var scale: CGFloat = 1
    private var minimumScale: CGFloat = 0.3
    private var offset: CGPoint = .zero
    private var hasLaidOut = false
    private lazy var paper = ImagePaperStrategy(size: paperSize)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.88, green: 0.86, blue: 0.82, alpha: 1)
        isOpaque = true
        isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.delegate = self
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.delegate = self
        addGestureRecognizer(pinch)

        sheet.bounds = CGRect(origin: .zero, size: paperSize)
        sheet.isUserInteractionEnabled = false
        sheet.addSubview(paper.view)
        sheet.addSubview(paint)
        for area in template.paintableAreas {
            let outline = CAShapeLayer()
            outline.path = area.path
            outline.fillColor = UIColor.clear.cgColor
            outline.strokeColor = UIColor(red: 0.38, green: 0.33, blue: 0.29, alpha: 0.65).cgColor
            outline.lineWidth = 2
            sheet.layer.addSublayer(outline)
        }
        addSubview(sheet)
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
        updateSheet()
    }

    private func updateSheet() {
        sheet.transform = CGAffineTransform(scaleX: scale, y: scale)
        sheet.center = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        paint.handleTouchesBegan(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        paint.handleTouchesMoved(touches, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        paint.handleTouchesEnded(touches, event: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        paint.handleTouchesCancelled(touches)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        let translation = gesture.translation(in: self)
        offset.x += translation.x
        offset.y += translation.y
        gesture.setTranslation(.zero, in: self)
        updateSheet()
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
        updateSheet()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
