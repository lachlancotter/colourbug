import UIKit

// Receives touches forwarded by PaperCanvasView so touches outside the sheet
// can also end a stroke and two-finger navigation can take over immediately.
final class PaintView: UIView {
    // CAShapeLayer copies its path on assignment, so keep each path bounded.
    private let maxPointsPerSegment = 64
    private let brushWidth: CGFloat = 24
    private let brushColor = UIColor(red: 0.13, green: 0.37, blue: 0.86, alpha: 1).cgColor
    private var activePath: UIBezierPath?
    private var lastPoint: CGPoint?
    private var pointCount = 0
    private var segmentPointCount = 0
    private var activeLayer: CAShapeLayer?
    private var activeTouches = Set<UITouch>()
    private var paintingTouch: UITouch?

    init(size: CGSize) {
        super.init(frame: CGRect(origin: .zero, size: size))
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func handleTouchesBegan(_ touches: Set<UITouch>) {
        activeTouches.formUnion(touches)

        if let pencil = touches.first(where: { $0.type == .pencil }) {
            finishPainting(discardDot: true)
            startPainting(with: pencil)
            return
        }
        if paintingTouch?.type == .pencil { return }

        let fingerTouches = activeTouches.filter { $0.type == .direct }
        guard fingerTouches.count == 1, let touch = touches.first(where: { $0.type == .direct }) else {
            finishPainting(discardDot: true)
            return
        }
        startPainting(with: touch)
    }

    private func startPainting(with touch: UITouch) {
        let point = touch.location(in: self)
        guard bounds.contains(point) else { return }
        paintingTouch = touch
        beginStroke(at: point)
    }

    func handleTouchesMoved(_ touches: Set<UITouch>, event: UIEvent?) {
        guard let touch = paintingTouch,
              (touch.type == .pencil || activeTouches.filter { $0.type == .direct }.count == 1),
              touches.contains(touch) else { return }
        addSamples(for: touch, event: event)
    }

    func handleTouchesEnded(_ touches: Set<UITouch>, event: UIEvent?) {
        if let touch = paintingTouch, touches.contains(touch) {
            addSamples(for: touch, event: event)
            finishPainting()
        }
        activeTouches.subtract(touches)
    }

    func handleTouchesCancelled(_ touches: Set<UITouch>) {
        if let touch = paintingTouch, touches.contains(touch) { finishPainting() }
        activeTouches.subtract(touches)
    }

    private func finishPainting(discardDot: Bool = false) {
        guard paintingTouch != nil else { return }
        finishStroke(discardDot: discardDot)
        paintingTouch = nil
    }

    private func addSamples(for touch: UITouch, event: UIEvent?) {
        var points: [CGPoint] = []
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            let point = sample.location(in: self)
            points.append(point)
            guard bounds.contains(point) else {
                append(points)
                finishPainting()
                return
            }
        }
        append(points)
    }

    private func beginStroke(at point: CGPoint) {
        let path = UIBezierPath()
        path.move(to: point)
        let strokeLayer = makeStrokeLayer()
        activePath = path
        lastPoint = point
        pointCount = 1
        segmentPointCount = 1
        activeLayer = strokeLayer
        strokeLayer.fillColor = brushColor
        strokeLayer.strokeColor = UIColor.clear.cgColor
        strokeLayer.path = UIBezierPath(ovalIn: CGRect(x: point.x - brushWidth / 2,
                                                       y: point.y - brushWidth / 2,
                                                       width: brushWidth, height: brushWidth)).cgPath
    }

    private func makeStrokeLayer() -> CAShapeLayer {
        let strokeLayer = CAShapeLayer()
        strokeLayer.frame = bounds
        strokeLayer.fillColor = UIColor.clear.cgColor
        strokeLayer.strokeColor = brushColor
        strokeLayer.lineWidth = brushWidth
        strokeLayer.lineCap = .round
        strokeLayer.lineJoin = .round
        layer.addSublayer(strokeLayer)
        return strokeLayer
    }

    private func append(_ points: [CGPoint]) {
        guard activePath != nil else { return }
        for point in points where point != lastPoint {
            if segmentPointCount == maxPointsPerSegment, let lastPoint {
                let path = UIBezierPath()
                path.move(to: lastPoint)
                activePath = path
                activeLayer = makeStrokeLayer()
                segmentPointCount = 1
            }
            if pointCount == 1 {
                activeLayer?.fillColor = UIColor.clear.cgColor
                activeLayer?.strokeColor = brushColor
            }
            activePath?.addLine(to: point)
            lastPoint = point
            pointCount += 1
            segmentPointCount += 1
            activeLayer?.path = activePath?.cgPath
        }
    }

    private func finishStroke(discardDot: Bool = false) {
        guard activePath != nil else { return }
        if discardDot && pointCount == 1 {
            activeLayer?.removeFromSuperlayer()
        }
        activePath = nil
        lastPoint = nil
        pointCount = 0
        segmentPointCount = 0
        activeLayer = nil
    }
}
