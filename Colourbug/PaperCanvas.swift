import SwiftUI
import UIKit
import Observation

typealias PaintColourID = String

struct PaintColour: Identifiable, Equatable {
    let id: PaintColourID
    let name: String
    let red: Float
    let green: Float
    let blue: Float

    var displayColour: Color { Color(red: Double(red), green: Double(green), blue: Double(blue)) }
    var pigment: SIMD4<Float> { SIMD4(red, green, blue, 1) }

}

@Observable
final class PaintingSession {
    var selectedColour = PaintingTemplate.puppyGod.palette[0]
}

struct PaintingScreen: View {
    @State private var session = PaintingSession()
    private let template = PaintingTemplate.puppyGod

    var body: some View {
        VStack(spacing: 0) {
            PaperCanvas(session: session)
            VStack(spacing: 6) {
                Text(session.selectedColour.name)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.29, green: 0.26, blue: 0.23))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(template.palette) { colour in
                            Button {
                                session.selectedColour = colour
                            } label: {
                                Circle()
                                    .fill(colour.displayColour)
                                    .frame(width: 42, height: 42)
                                    .padding(5)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(session.selectedColour == colour
                                                ? Color(red: 0.29, green: 0.26, blue: 0.23) : .clear,
                                                lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(colour.name) paint")
                            .accessibilityValue(session.selectedColour == colour ? "Selected" : "")
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
    private let template = PaintingTemplate.puppyGod
    private let session: PaintingSession
    private var paperSize: CGSize { template.size }
    private let sheet = UIView()
    private lazy var paint = PaintView(size: paperSize, template: template, session: session)
    private lazy var focusGuide = ColourFocusGuide(template: template, session: session)
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
        sheet.addSubview(focusGuide.veilView)
        let ink = UIImageView(image: UIImage(named: template.inkImageName))
        ink.frame = sheet.bounds
        ink.contentMode = .scaleToFill
        ink.isUserInteractionEnabled = false
        sheet.addSubview(ink)
        sheet.addSubview(focusGuide.outlinesView)
        paint.onPaintingChanged = { [weak self] painting in
            self?.focusGuide.setPainting(painting)
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
