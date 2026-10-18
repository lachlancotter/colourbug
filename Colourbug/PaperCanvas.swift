import SwiftUI
import UIKit
import Observation

enum PaintColourID: String, Hashable {
    case blue, coral, orange, gold, green, violet
}

struct PaintColour: Identifiable, Equatable {
    let id: PaintColourID
    let name: String
    let red: Float
    let green: Float
    let blue: Float

    var displayColour: Color { Color(red: Double(red), green: Double(green), blue: Double(blue)) }
    var pigment: SIMD4<Float> { SIMD4(red, green, blue, 1) }

    static let palette: [PaintColour] = [
        PaintColour(id: .blue, name: "Blue", red: 0.13, green: 0.37, blue: 0.86),
        PaintColour(id: .coral, name: "Coral", red: 0.85, green: 0.28, blue: 0.28),
        PaintColour(id: .orange, name: "Orange", red: 0.92, green: 0.47, blue: 0.16),
        PaintColour(id: .gold, name: "Gold", red: 0.80, green: 0.62, blue: 0.12),
        PaintColour(id: .green, name: "Green", red: 0.20, green: 0.55, blue: 0.34),
        PaintColour(id: .violet, name: "Violet", red: 0.52, green: 0.34, blue: 0.70)
    ]
}

@Observable
final class PaintingSession {
    var selectedColour = PaintColour.palette[0]
}

struct PaintingScreen: View {
    @State private var session = PaintingSession()

    var body: some View {
        VStack(spacing: 0) {
            PaperCanvas(session: session)
            HStack(spacing: 18) {
                ForEach(PaintColour.palette) { colour in
                    Button {
                        session.selectedColour = colour
                    } label: {
                        Circle()
                            .fill(colour.displayColour)
                            .frame(width: 46, height: 46)
                            .padding(5)
                            .overlay {
                                Circle()
                                    .strokeBorder(session.selectedColour == colour ? Color(red: 0.29, green: 0.26, blue: 0.23) : .clear,
                                                  lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(colour.name) paint")
                    .accessibilityValue(session.selectedColour == colour ? "Selected" : "")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(red: 0.96, green: 0.94, blue: 0.90))
        }
        .ignoresSafeArea(edges: .top)
    }
}

struct PaperCanvas: UIViewRepresentable {
    let session: PaintingSession

    func makeUIView(context: Context) -> PaperCanvasView {
        PaperCanvasView(session: session)
    }

    func updateUIView(_ uiView: PaperCanvasView, context: Context) {}
}

final class PaperCanvasView: UIView, UIGestureRecognizerDelegate {
    private let template = PaintingTemplate.sampleFlower
    private let session: PaintingSession
    private var paperSize: CGSize { template.size }
    private let sheet = UIView()
    private lazy var paint = PaintView(size: paperSize, template: template, session: session)
    private var scale: CGFloat = 1
    private var minimumScale: CGFloat = 0.3
    private var offset: CGPoint = .zero
    private var hasLaidOut = false
    private lazy var paper = ImagePaperStrategy(size: paperSize)

    init(session: PaintingSession) {
        self.session = session
        super.init(frame: .zero)
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
