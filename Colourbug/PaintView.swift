import UIKit
import Observation

// Touches arrive from PaperCanvasView, while paint coordinates stay fixed to the sheet.
final class PaintView: UIView {
    private struct BrushResponse {
        let width: CGFloat
        let pigment: Float
        let water: Float

        static let neutral = BrushResponse(width: 1, pigment: 1, water: 1)

        func blended(with other: BrushResponse, fraction: CGFloat) -> BrushResponse {
            let t = Float(fraction)
            return BrushResponse(width: width + (other.width - width) * fraction,
                                 pigment: pigment + (other.pigment - pigment) * t,
                                 water: water + (other.water - water) * t)
        }
    }

    private struct PendingDeposit {
        let point: CGPoint
        let direction: CGVector
        let tipRadius: CGFloat
        let fullRadius: CGFloat
        let pigment: Float
        let water: Float
    }

    private let brushWidth: CGFloat = 24
    private let firstContactRadius: CGFloat = 16
    private let tipRadius: CGFloat = 10
    private let startTaperLength: CGFloat = 14
    private let deferredPigment: Float = 0.032
    private let pendingCount = 8
    private var activeTouches = Set<UITouch>()
    private var paintingTouch: UITouch?
    private var lastPoint: CGPoint?
    private var pendingDeposits: [PendingDeposit] = []
    private var distanceSinceDeposit: CGFloat = 0
    private var strokeDistance: CGFloat = 0
    private var hasPainted = false
    private var smoothedForce: CGFloat = 1
    private var smoothedTilt: CGFloat = 0
    private var lastResponse = BrushResponse.neutral
    private var strokeColour = PaintColour.palette[0]
    private let template: PaintingTemplate
    private let session: PaintingSession
    private var activeOutlines: [CAShapeLayer] = []
    private lazy var paint = WatercolourRenderer(size: bounds.size, host: self, template: template)
    private let contactSheen = CAGradientLayer()
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval?

    init(size: CGSize, template: PaintingTemplate, session: PaintingSession) {
        self.template = template
        self.session = session
        super.init(frame: CGRect(origin: .zero, size: size))
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
        _ = paint // Prepare the paper field before the first touch.
        contactSheen.type = .radial
        contactSheen.colors = [UIColor.white.withAlphaComponent(0.23).cgColor,
                               UIColor(red: 0.5, green: 0.73, blue: 1, alpha: 0.1).cgColor,
                               UIColor.clear.cgColor]
        contactSheen.locations = [0, 0.62, 1]
        contactSheen.startPoint = CGPoint(x: 0.5, y: 0.5)
        contactSheen.endPoint = CGPoint(x: 1, y: 1)
        contactSheen.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        contactSheen.zPosition = 1
        contactSheen.isHidden = true
        layer.addSublayer(contactSheen)
        for area in template.paintableAreas {
            let outline = CAShapeLayer()
            outline.path = area.path
            outline.fillColor = UIColor.clear.cgColor
            outline.lineWidth = 6
            outline.lineJoin = .round
            outline.zPosition = 0.5
            layer.addSublayer(outline)
            activeOutlines.append(outline)
        }
        observeSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func observeSelection() {
        withObservationTracking {
            let colour = session.selectedColour
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (area, outline) in zip(template.paintableAreas, activeOutlines) {
                outline.isHidden = area.colourID != colour.id
                outline.strokeColor = UIColor(red: CGFloat(colour.red), green: CGFloat(colour.green),
                                              blue: CGFloat(colour.blue), alpha: 0.5).cgColor
            }
            CATransaction.commit()
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeSelection() }
        }
    }

    func handleTouchesBegan(_ touches: Set<UITouch>) {
        activeTouches.formUnion(touches)
        if let pencil = touches.first(where: { $0.type == .pencil }) {
            finishPainting(discardDot: true)
            startPainting(with: pencil)
            paint.renderDirtyTiles()
            return
        }
        if paintingTouch?.type == .pencil { return }
        let fingers = activeTouches.filter { $0.type == .direct }
        guard fingers.count == 1, let touch = touches.first(where: { $0.type == .direct }) else {
            finishPainting(discardDot: true)
            paint.renderDirtyTiles()
            return
        }
        startPainting(with: touch)
    }

    private func startPainting(with touch: UITouch) {
        let point = touch.location(in: self)
        guard bounds.contains(point) else { return }
        paintingTouch = touch
        strokeColour = session.selectedColour
        lastPoint = point
        pendingDeposits.removeAll(keepingCapacity: true)
        distanceSinceDeposit = 0
        strokeDistance = 0
        hasPainted = false
        smoothedForce = 1
        smoothedTilt = 0
        lastResponse = brushResponse(for: touch)
        moveContact(to: point)
    }

    func handleTouchesMoved(_ touches: Set<UITouch>, event: UIEvent?) {
        guard let touch = paintingTouch,
              (touch.type == .pencil || activeTouches.filter { $0.type == .direct }.count == 1),
              touches.contains(touch) else { return }
        addSamples(for: touch, event: event)
        paint.renderDirtyTiles()
    }

    func handleTouchesEnded(_ touches: Set<UITouch>, event: UIEvent?) {
        if let touch = paintingTouch, touches.contains(touch) {
            addSamples(for: touch, event: event)
            finishPainting()
            paint.renderDirtyTiles()
        }
        activeTouches.subtract(touches)
    }

    func handleTouchesCancelled(_ touches: Set<UITouch>) {
        if let touch = paintingTouch, touches.contains(touch) {
            finishPainting()
            paint.renderDirtyTiles()
        }
        activeTouches.subtract(touches)
    }

    private func addSamples(for touch: UITouch, event: UIEvent?) {
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            let point = sample.location(in: self)
            append(point, response: brushResponse(for: sample))
            if !bounds.contains(point) {
                finishPainting()
                return
            }
        }
        if let point = lastPoint { moveContact(to: point) }
    }

    private func append(_ point: CGPoint, response: BrushResponse) {
        guard let previous = lastPoint else { return }
        let length = hypot(point.x - previous.x, point.y - previous.y)
        guard length > 0 else {
            lastResponse = response
            return
        }
        let direction = CGVector(dx: (point.x - previous.x) / length,
                                 dy: (point.y - previous.y) / length)
        if !hasPainted {
            // A loaded brush makes a slightly fuller, richer first contact.
            paint.deposit(at: previous, pigment: 0.12 * lastResponse.pigment,
                          water: 0.3 * lastResponse.water,
                          radius: firstContactRadius * lastResponse.width, colour: strokeColour)
            hasPainted = true
        }
        var walked: CGFloat = 0
        let spacing: CGFloat = 2
        while walked + spacing - distanceSinceDeposit <= length {
            walked += spacing - distanceSinceDeposit
            let fraction = walked / length
            let position = CGPoint(x: previous.x + (point.x - previous.x) * fraction,
                                   y: previous.y + (point.y - previous.y) * fraction)
            strokeDistance += spacing
            let brush = lastResponse.blended(with: response, fraction: fraction)
            let pigmentLoad = Self.pigmentLoad(at: strokeDistance)
            let waterLoad = Self.waterLoad(at: strokeDistance)
            if strokeDistance <= startTaperLength {
                let progress = strokeDistance / startTaperLength
                let radius = firstContactRadius + (brushWidth / 2 - firstContactRadius) * progress
                paint.deposit(at: position,
                              pigment: 0.06 * pigmentLoad * brush.pigment,
                              water: 0.11 * waterLoad * brush.water,
                              radius: radius * brush.width, direction: direction,
                              colour: strokeColour)
            } else {
                // The narrow, light tip expands to the steady brush width as it moves on.
                let narrowRadius = tipRadius * brush.width
                let fullRadius = brushWidth / 2 * brush.width
                paint.deposit(at: position,
                              pigment: 0.028 * pigmentLoad * brush.pigment,
                              water: 0.09 * waterLoad * brush.water,
                              radius: narrowRadius, direction: direction, colour: strokeColour)
                pendingDeposits.append(PendingDeposit(
                    point: position, direction: direction,
                    tipRadius: narrowRadius, fullRadius: fullRadius,
                    pigment: deferredPigment * pigmentLoad * brush.pigment,
                    water: 0.02 * waterLoad * brush.water))
                if pendingDeposits.count > pendingCount {
                    let oldest = pendingDeposits.removeFirst()
                    paint.deposit(at: oldest.point, pigment: oldest.pigment,
                                  water: oldest.water, radius: oldest.fullRadius,
                                  direction: oldest.direction, colour: strokeColour)
                }
            }
            distanceSinceDeposit = 0
        }
        distanceSinceDeposit += length - walked
        lastPoint = point
        lastResponse = response
        startAnimation()
    }

    private func finishPainting(discardDot: Bool = false) {
        guard paintingTouch != nil else { return }
        if hasPainted {
            let count = pendingDeposits.count
            for (index, deposit) in pendingDeposits.enumerated() {
                let fraction = 1 - Float(index + 1) / Float(count)
                let pigment = deposit.pigment * (discardDot ? 1 : fraction)
                guard pigment > 0 else { continue }
                let radius = discardDot ? deposit.fullRadius
                    : deposit.tipRadius + (deposit.fullRadius - deposit.tipRadius) * CGFloat(fraction)
                paint.deposit(at: deposit.point, pigment: pigment,
                              water: deposit.water * (discardDot ? 1 : fraction),
                              radius: radius, direction: deposit.direction,
                              colour: strokeColour)
            }
            if !discardDot, let point = lastPoint {
                // A little pigment remains at the centre as the contact area lifts away.
                let pigmentLoad = Self.pigmentLoad(at: strokeDistance)
                let waterLoad = Self.waterLoad(at: strokeDistance)
                paint.deposit(at: point,
                              pigment: 0.22 * (0.35 + 0.65 * pigmentLoad) * lastResponse.pigment,
                              water: 0.2 * waterLoad * lastResponse.water,
                              radius: 7 * lastResponse.width, settledFraction: 0.45,
                              colour: strokeColour)
            }
            startAnimation()
        } else if !discardDot, let point = lastPoint {
            paint.deposit(at: point, pigment: 0.16 * lastResponse.pigment,
                          water: 0.8 * lastResponse.water,
                          radius: brushWidth / 2 * lastResponse.width, colour: strokeColour)
            startAnimation()
        }
        pendingDeposits.removeAll(keepingCapacity: true)
        strokeDistance = 0
        contactSheen.isHidden = true
        paintingTouch = nil
        lastPoint = nil
        hasPainted = false
    }

    private func brushResponse(for sample: UITouch) -> BrushResponse {
        guard sample.type == .pencil else { return .neutral }
        // UIKit may revise estimated Pencil properties later. Use the last confirmed
        // reading for those samples so already-deposited paint never needs correction.
        if !sample.estimatedProperties.contains(.force) {
            let force = min(4, max(0, sample.force))
            smoothedForce += (force - smoothedForce) * 0.25
        }
        if !sample.estimatedProperties.contains(.altitude) {
            let tilt = 1 - min(1, max(0, sample.altitudeAngle / (.pi / 2)))
            smoothedTilt += (tilt - smoothedTilt) * 0.25
        }
        let pressure = min(2, max(-1, smoothedForce - 1))
        let width = min(1.08, max(0.95, 1 + 0.04 * pressure + 0.025 * smoothedTilt))
        return BrushResponse(width: width,
                             pigment: Float(1 + 0.13 * pressure),
                             water: Float(1 + 0.06 * pressure + 0.06 * smoothedTilt))
    }

    private static func pigmentLoad(at distance: CGFloat) -> Float {
        0.35 + 0.65 * exp(-Float(distance) / 520)
    }

    private static func waterLoad(at distance: CGFloat) -> Float {
        0.42 + 0.58 * exp(-Float(distance) / 420)
    }

    private func moveContact(to point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contactSheen.position = point
        contactSheen.isHidden = false
        CATransaction.commit()
    }

    private func startAnimation() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(animate(_:)))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTick = nil
    }

    @objc private func animate(_ link: CADisplayLink) {
        let elapsed = lastTick.map { min(0.05, link.timestamp - $0) } ?? (1.0 / 30.0)
        lastTick = link.timestamp
        paint.step(dt: Float(elapsed))
        paint.renderDirtyTiles()
        if !paint.hasActivePaint {
            link.invalidate()
            displayLink = nil
            lastTick = nil
        }
    }
}
