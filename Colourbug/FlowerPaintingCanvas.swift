import SwiftUI
import UIKit

// A single story object above the continuous watercolour paper.
struct FlowerPaintingCanvas: UIViewRepresentable {
    func makeUIView(context: Context) -> FlowerPaintingView { FlowerPaintingView() }
    func updateUIView(_ uiView: FlowerPaintingView, context: Context) {}
}

final class FlowerPaintingView: UIView {
    private enum RevealStyle {
        case water
        case pressedPaper
        case gatheringInk
    }

    private let session = PaintingSession()
    private var paper: UIImageView?
    private var castShadow: UIImageView?
    private var paint: PaintView?
    private var flower: UIImageView?
    private var shadows: UIView?
    private var highlights: UIView?
    private var revealAnimation: FlowerLineReveal?
    private var completionCheck: DispatchWorkItem?
    private var paletteSwatches: [FlowerPaletteSwatch] = []
    private var selectedRegion: FlowerRegion = .bell
    private var depthRevealed = false
    private var revealStyle: RevealStyle = .water
    private var canvasSize = CGSize.zero
    private lazy var waterButton: UIButton = makeRevealButton(
        title: "Water", symbol: "drop", action: #selector(playWaterReveal))
    private lazy var pressedButton: UIButton = makeRevealButton(
        title: "Pressed paper", symbol: "square.stack", action: #selector(playPressedReveal))
    private lazy var gatheringButton: UIButton = makeRevealButton(
        title: "Gathering ink", symbol: "scribble.variable", action: #selector(playGatheringReveal))

    private func makeRevealButton(title: String, symbol: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol,
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        configuration.imagePadding = 7
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        configuration.baseForegroundColor = UIColor(red: 0.23, green: 0.21, blue: 0.19, alpha: 1)
        button.configuration = configuration
        button.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 0.9)
        button.layer.cornerRadius = 22
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(white: 0.3, alpha: 0.15).cgColor
        button.accessibilityLabel = "Play \(title) reveal"
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1)
        isMultipleTouchEnabled = true
        session.selectedColour = selectedRegion.colour
        let clear = UITapGestureRecognizer(target: self, action: #selector(clearPaint))
        clear.numberOfTouchesRequired = 2
        clear.numberOfTapsRequired = 2
        clear.cancelsTouchesInView = false
        addGestureRecognizer(clear)
        addSubview(waterButton)
        addSubview(pressedButton)
        addSubview(gatheringButton)
        // The other reveal studies remain in code as drafts for later comparison.
        pressedButton.isHidden = true
        gatheringButton.isHidden = true
        for region in FlowerRegion.allCases {
            let swatch = FlowerPaletteSwatch(region: region)
            swatch.isSelected = region == selectedRegion
            swatch.addTarget(self, action: #selector(selectPaletteColour(_:)), for: .touchUpInside)
            addSubview(swatch)
            paletteSwatches.append(swatch)
        }
        updateButtonAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let buttonY = max(20, safeAreaInsets.top + 8)
        gatheringButton.frame = CGRect(x: bounds.maxX - 184, y: buttonY, width: 164, height: 44)
        pressedButton.frame = CGRect(x: gatheringButton.frame.minX - 180,
                                     y: buttonY, width: 170, height: 44)
        waterButton.frame = CGRect(x: bounds.maxX - 118, y: buttonY,
                                   width: 98, height: 44)
        let swatchSize = min(CGFloat(90), (bounds.width - 84) / 4)
        let spacing = min(CGFloat(22), max(CGFloat(12), (bounds.width - 4 * swatchSize - 32) / 3))
        let paletteWidth = 4 * swatchSize + 3 * spacing
        let paletteX = (bounds.width - paletteWidth) / 2
        let paletteY = bounds.maxY - safeAreaInsets.bottom - swatchSize - 18
        for (index, swatch) in paletteSwatches.enumerated() {
            swatch.frame = CGRect(x: paletteX + CGFloat(index) * (swatchSize + spacing),
                                  y: paletteY, width: swatchSize, height: swatchSize)
        }
        let size = CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        guard size.width > 0, size.height > 0, size != canvasSize else { return }
        canvasSize = size
        completionCheck?.cancel()
        completionCheck = nil
        depthRevealed = false
        revealAnimation?.stop()
        revealAnimation = nil
        paper?.removeFromSuperview()
        castShadow?.removeFromSuperview()
        paint?.stopAnimating()
        paint?.removeFromSuperview()
        shadows?.removeFromSuperview()
        highlights?.removeFromSuperview()
        flower?.removeFromSuperview()

        let texture = ImagePaperStrategy(size: size).view
        texture.layer.shadowOpacity = 0
        addSubview(texture)
        paper = texture

        guard let ink = UIImage(named: "StoryFlowerInk") else {
            fatalError("Missing StoryFlowerInk image")
        }
        let flowerFrame = PaintingTemplate.flowerFrame(in: size, imageSize: ink.size)
        let paddingX = flowerFrame.width * FlowerDepthArtwork.castShadowPadding / 1360
        let paddingY = flowerFrame.height * FlowerDepthArtwork.castShadowPadding / 1156
        let paperShadow = UIImageView(image: FlowerDepthArtwork.castShadowImage)
        paperShadow.frame = flowerFrame.insetBy(dx: -paddingX, dy: -paddingY)
        paperShadow.alpha = 0
        paperShadow.isUserInteractionEnabled = false
        addSubview(paperShadow)
        castShadow = paperShadow

        let watercolour = PaintView(size: size,
                                    template: .flower(size: size),
                                    session: session, behaviour: .fluid)
        addSubview(watercolour)
        paint = watercolour
        watercolour.onPaintingChanged = { [weak self] painting in
            if painting { self?.completionCheck?.cancel() }
        }
        watercolour.onStrokeFinished = { [weak self] in self?.scheduleCompletionCheck() }

        let linework = UIImageView(image: ink)
        linework.frame = flowerFrame
        linework.isUserInteractionEnabled = false
        guard let silhouette = UIImage(named: "StoryFlowerMask") else {
            fatalError("Missing StoryFlowerMask image")
        }
        let shadowLayer = makeDepthLayer(image: FlowerDepthArtwork.shadowImage,
                                         silhouette: silhouette, frame: linework.frame)
        let highlightLayer = makeDepthLayer(image: FlowerDepthArtwork.highlightImage,
                                            silhouette: silhouette, frame: linework.frame)
        addSubview(shadowLayer)
        addSubview(highlightLayer)
        shadows = shadowLayer
        highlights = highlightLayer
        addSubview(linework)
        flower = linework
        playReveal()
        bringSubviewToFront(waterButton)
        bringSubviewToFront(pressedButton)
        bringSubviewToFront(gatheringButton)
        for swatch in paletteSwatches { bringSubviewToFront(swatch) }
    }

    @objc private func selectPaletteColour(_ sender: FlowerPaletteSwatch) {
        selectedRegion = sender.region
        session.selectedColour = sender.region.colour
        for swatch in paletteSwatches { swatch.isSelected = swatch.region == selectedRegion }
    }

    private func makeDepthLayer(image: UIImage, silhouette: UIImage, frame: CGRect) -> UIView {
        let view = UIView(frame: frame)
        view.frame = frame
        view.alpha = 0
        view.isUserInteractionEnabled = false
        let artwork = UIImageView(image: image)
        artwork.frame = view.bounds
        view.addSubview(artwork)
        let clip = CALayer()
        clip.frame = view.bounds
        clip.contents = silhouette.cgImage
        clip.contentsGravity = .resize
        view.layer.mask = clip
        return view
    }

    private func scheduleCompletionCheck() {
        guard !depthRevealed else { return }
        completionCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self, !self.depthRevealed,
                  let paint = self.paint,
                  paint.hasCompletedFlower() else { return }
            self.revealDepth()
        }
        completionCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: check)
    }

    private func revealDepth() {
        guard let shadows, let highlights, let castShadow else { return }
        depthRevealed = true
        if UIAccessibility.isReduceMotionEnabled {
            castShadow.alpha = 1
            shadows.alpha = 1
            highlights.alpha = 1
            return
        }
        castShadow.transform = CGAffineTransform(translationX: -3, y: -5)
        UIView.animate(withDuration: 1.9, delay: 0.05,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            castShadow.alpha = 1
            castShadow.transform = .identity
        }
        animateDepthWash(on: shadows, duration: 1.65, delay: 0, origin: CGPoint(x: 0.47, y: 0.33))
        animateDepthWash(on: highlights, duration: 1.45, delay: 0.55,
                         origin: CGPoint(x: 0.64, y: 0.39))
    }

    private func animateDepthWash(on view: UIView, duration: TimeInterval,
                                  delay: TimeInterval, origin: CGPoint) {
        guard let artwork = view.subviews.first as? UIImageView else { return }
        let bloom = CAGradientLayer()
        bloom.type = .radial
        bloom.frame = artwork.bounds
        bloom.startPoint = origin
        bloom.endPoint = CGPoint(x: origin.x + 0.72, y: origin.y + 0.72)
        bloom.colors = [UIColor.white.cgColor, UIColor.white.cgColor,
                        UIColor.clear.cgColor]
        bloom.locations = [0, 0.72, 1]
        bloom.transform = CATransform3DMakeScale(2.5, 2.5, 1)
        // Outer mask holds the silhouette; the inner mask lets light travel through it.
        artwork.layer.mask = bloom
        let expansion = CABasicAnimation(keyPath: "transform.scale")
        expansion.fromValue = 0.02
        expansion.toValue = 2.5
        expansion.duration = duration
        expansion.beginTime = CACurrentMediaTime() + delay
        expansion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bloom.add(expansion, forKey: "depthBloom")
        UIView.animate(withDuration: duration, delay: delay,
                       options: [.curveEaseInOut, .allowUserInteraction]) {
            view.alpha = 1
        } completion: { _ in
            artwork.layer.mask = nil
        }
    }

    @objc private func playWaterReveal() {
        revealStyle = .water
        playReveal()
    }

    @objc private func playPressedReveal() {
        revealStyle = .pressedPaper
        playReveal()
    }

    @objc private func playGatheringReveal() {
        revealStyle = .gatheringInk
        playReveal()
    }

    private func updateButtonAppearance() {
        for (button, selected) in [(waterButton, revealStyle == .water),
                                   (pressedButton, revealStyle == .pressedPaper),
                                   (gatheringButton, revealStyle == .gatheringInk)] {
            button.backgroundColor = selected
                ? UIColor(red: 0.88, green: 0.84, blue: 0.76, alpha: 0.95)
                : UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 0.9)
            button.layer.borderColor = UIColor(white: 0.3, alpha: selected ? 0.3 : 0.15).cgColor
        }
    }

    private func playReveal() {
        guard let linework = flower else { return }
        revealAnimation?.stop()
        updateButtonAppearance()
        let effect: UIView
        let mode: FlowerLineReveal.Mode
        switch revealStyle {
        case .water:
            effect = makeWaterEffect(frame: linework.frame)
            mode = .water
        case .pressedPaper:
            effect = makePressedPaperEffect(ink: linework.image!, frame: linework.frame)
            mode = .pressedPaper
        case .gatheringInk:
            let flecks = UIImageView(frame: linework.frame)
            flecks.isUserInteractionEnabled = false
            effect = flecks
            mode = .gatheringInk
        }
        let reveal = FlowerLineReveal(ink: linework, effect: effect, mode: mode)
        if mode == .gatheringInk {
            insertSubview(effect, aboveSubview: linework)
        } else {
            insertSubview(effect, belowSubview: linework)
        }
        revealAnimation = reveal
        reveal.start()
    }

    private func makeWaterEffect(frame: CGRect) -> UIView {
        guard let silhouette = UIImage(named: "StoryFlowerMask") else {
            fatalError("Missing StoryFlowerMask image")
        }
        let dampPaper = UIImageView(image: silhouette.withTintColor(
            UIColor(red: 0.40, green: 0.34, blue: 0.27, alpha: 1),
            renderingMode: .alwaysOriginal))
        dampPaper.frame = frame
        dampPaper.alpha = 0.13
        dampPaper.isUserInteractionEnabled = false
        return dampPaper
    }

    private func makePressedPaperEffect(ink: UIImage, frame: CGRect) -> UIView {
        let impression = UIView(frame: frame)
        impression.isUserInteractionEnabled = false
        let highlight = UIImageView(image: ink.withTintColor(.white, renderingMode: .alwaysOriginal))
        highlight.frame = impression.bounds.offsetBy(dx: -1.3, dy: -1.3)
        highlight.alpha = 0.85
        impression.addSubview(highlight)
        let shadow = UIImageView(image: ink.withTintColor(
            UIColor(red: 0.38, green: 0.34, blue: 0.29, alpha: 1),
            renderingMode: .alwaysOriginal))
        shadow.frame = impression.bounds.offsetBy(dx: 1.4, dy: 1.4)
        shadow.alpha = 0.38
        impression.addSubview(shadow)
        return impression
    }

    @objc private func clearPaint() {
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

private final class FlowerPaletteSwatch: UIControl {
    let region: FlowerRegion
    private let outline = CAShapeLayer()
    private let pigment = CAShapeLayer()

    override var isSelected: Bool {
        didSet {
            outline.lineWidth = isSelected ? 3 : 1.2
            outline.strokeColor = UIColor(red: 0.22, green: 0.19, blue: 0.17,
                                          alpha: isSelected ? 0.9 : 0.3).cgColor
            pigment.shadowOpacity = isSelected ? 0.42 : 0.30
            pigment.shadowRadius = isSelected ? 11 : 8
            pigment.shadowOffset = CGSize(width: 0, height: isSelected ? 9 : 7)
            accessibilityValue = isSelected ? "Selected" : ""
        }
    }

    init(region: FlowerRegion) {
        self.region = region
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(region.title), \(region.colour.name) paint"
        outline.fillColor = UIColor.clear.cgColor
        outline.lineJoin = .round
        layer.addSublayer(outline)
        pigment.fillColor = region.uiColour.cgColor
        pigment.shadowColor = UIColor.black.cgColor
        pigment.shadowOpacity = 0.30
        pigment.shadowRadius = 8
        pigment.shadowOffset = CGSize(width: 0, height: 7)
        layer.addSublayer(pigment)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = (min(bounds.width, bounds.height) - 16) / 48
        var position = CGAffineTransform(translationX: bounds.midX - 24 * scale,
                                         y: bounds.midY - 24 * scale)
        position = position.scaledBy(x: scale, y: scale)
        let path = region.palettePath.copy(using: &position)
        outline.frame = bounds
        outline.path = path
        pigment.frame = bounds
        pigment.path = path
    }
}

// Low resolution arrival fields make the reveals reusable with other linework.
private final class FlowerLineReveal: NSObject {
    enum Mode {
        case water
        case pressedPaper
        case gatheringInk
    }

    private struct InkParticle {
        let target: CGPoint
        let start: CGPoint
        let delay: Float
        let radius: CGFloat
    }

    private struct Frontier {
        private var entries: [(time: Float, index: Int)] = []

        mutating func push(time: Float, index: Int) {
            entries.append((time, index))
            var child = entries.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard entries[child].time < entries[parent].time else { break }
                entries.swapAt(child, parent)
                child = parent
            }
        }

        mutating func pop() -> (time: Float, index: Int)? {
            guard !entries.isEmpty else { return nil }
            let first = entries[0]
            let last = entries.removeLast()
            if !entries.isEmpty {
                entries[0] = last
                var parent = 0
                while true {
                    let left = parent * 2 + 1
                    guard left < entries.count else { break }
                    let right = left + 1
                    let child = right < entries.count && entries[right].time < entries[left].time
                        ? right : left
                    guard entries[child].time < entries[parent].time else { break }
                    entries.swapAt(child, parent)
                    parent = child
                }
            }
            return first
        }
    }

    private weak var ink: UIImageView?
    private weak var effect: UIView?
    private let mode: Mode
    private let inkMask = CALayer()
    private let effectMask = CALayer()
    private let width: Int
    private let height: Int
    private let arrival: [Float]
    private var particles: [InkParticle] = []
    private var deposition: [Float] = []
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval?
    private let duration: CFTimeInterval

    init(ink: UIImageView, effect: UIView, mode: Mode) {
        self.ink = ink
        self.effect = effect
        self.mode = mode
        switch mode {
        case .water: duration = 3.2
        case .pressedPaper: duration = 3.4
        case .gatheringInk: duration = 3.8
        }
        width = mode == .gatheringInk ? 384 : 256
        height = max(1, Int((ink.bounds.height / ink.bounds.width * CGFloat(width)).rounded()))

        var field = [Float](repeating: 0, count: width * height)
        var maximum: Float = 0
        for row in 0..<height {
            let y = Float(row) / Float(max(height - 1, 1))
            for column in 0..<width {
                let x = Float(column) / Float(width - 1)
                let value: Float
                switch mode {
                case .water:
                    let dx = (x - 0.35) * 1.05
                    let dy = (y - 0.10) * 0.90
                    let broad = sin(x * 17 + sin(y * 11) * 1.5) * sin(y * 15 - x * 6)
                    let fine = sin(x * 43 + y * 19) * sin(y * 47 - x * 17)
                    value = max(0, hypot(dx, dy) + 0.055 * broad + 0.017 * fine)
                case .pressedPaper:
                    let uneven = sin(x * 13 + y * 5) * sin(y * 10 - x * 4)
                    value = max(0, y * 0.82 + x * 0.18 + 0.035 * uneven)
                case .gatheringInk:
                    let broad = sin(x * 19 + y * 7) * sin(y * 22 - x * 11)
                    let detail = sin(x * 69 - y * 25) * sin(y * 63 + x * 31)
                    let grain = Self.random(UInt32(row * width + column) &+ 19)
                    value = max(0, 0.34 * y + 0.12 * x
                                + 0.21 * broad + 0.08 * detail + 0.12 * grain)
                }
                field[row * width + column] = value
                maximum = max(maximum, value)
            }
        }
        arrival = field.map { $0 / maximum }
        super.init()

        if mode == .gatheringInk, let image = ink.image {
            let alpha = Self.rasterInkAlpha(from: image, width: width, height: height)
            particles = Self.sampleInkParticles(alpha: alpha, arrival: arrival,
                                                width: width, height: height)
            deposition = Self.makeDepositionField(particles: particles, alpha: alpha,
                                                   width: width, height: height)
        }

        for mask in [inkMask, effectMask] {
            mask.frame = ink.bounds
            mask.contentsGravity = .resize
            mask.magnificationFilter = .linear
            mask.minificationFilter = .linear
        }
        ink.layer.mask = inkMask
        if mode != .gatheringInk { effect.layer.mask = effectMask }
        render(progress: 0)
    }

    func start() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            finish()
            return
        }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        ink?.layer.mask = nil
        effect?.layer.mask = nil
        effect?.removeFromSuperview()
    }

    @objc private func tick(_ link: CADisplayLink) {
        if startTime == nil { startTime = link.timestamp }
        let progress = Float(min((link.timestamp - startTime!) / duration, 1))
        if progress >= 1 {
            finish()
        } else {
            render(progress: progress)
        }
    }

    private func finish() { stop() }

    private func render(progress: Float) {
        let front: Float
        switch mode {
        case .water: front = progress * 1.14
        case .pressedPaper: front = progress * 1.70
        case .gatheringInk: front = progress * 1.50
        }
        var inkPixels = [UInt8](repeating: 0, count: width * height * 4)
        var effectPixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in arrival.indices {
            let distance = front - arrival[index]
            let inkAlpha: Float
            let effectAlpha: Float
            switch mode {
            case .water:
                inkAlpha = smoothstep(0, 0.095, distance)
                let dampDistance = (arrival[index] - front - 0.025) / 0.075
                effectAlpha = exp(-dampDistance * dampDistance)
            case .pressedPaper:
                inkAlpha = smoothstep(0.16, 0.38, distance)
                effectAlpha = smoothstep(0, 0.055, distance)
                    * (1 - smoothstep(0.46, 0.70, distance))
            case .gatheringInk:
                inkAlpha = smoothstep(0, 0.075, progress - deposition[index])
                effectAlpha = 0
            }
            let offset = index * 4
            let inkByte = UInt8((inkAlpha * 255).rounded())
            let effectByte = UInt8((effectAlpha * 255).rounded())
            for channel in 0..<4 {
                inkPixels[offset + channel] = inkByte
                effectPixels[offset + channel] = effectByte
            }
        }
        inkMask.contents = image(pixels: inkPixels)
        if mode == .gatheringInk {
            (effect as? UIImageView)?.image = renderInkParticles(progress: progress)
        } else {
            effectMask.contents = image(pixels: effectPixels)
        }
    }

    private static func random(_ seed: UInt32) -> Float {
        var value = seed &* 747_796_405 &+ 2_891_336_453
        value ^= value >> 16
        value = value &* 2_246_822_519
        value ^= value >> 13
        return Float(value & 0x00ff_ffff) / Float(0x0100_0000)
    }

    private static func rasterInkAlpha(from image: UIImage,
                                       width: Int, height: Int) -> [UInt8] {
        guard let source = image.cgImage else { return [] }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let drewImage = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width,
                                          height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: colourSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(source, in: CGRect(x: 0, y: 0,
                                            width: width, height: height))
            return true
        }
        guard drewImage else { return [] }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    private static func sampleInkParticles(alpha: [UInt8], arrival: [Float],
                                           width: Int, height: Int) -> [InkParticle] {
        guard alpha.count == width * height else { return [] }
        var result: [InkParticle] = []
        for row in 0..<height {
            for column in 0..<width {
                let index = row * width + column
                guard alpha[index] > 25,
                      random(UInt32(index) &+ 31) < 0.055 else { continue }
                let x = Float(column) / Float(width - 1)
                let y = Float(row) / Float(height - 1)
                let seed = UInt32(index)
                let angle = random(seed &+ 71) * 2 * .pi
                let distance = 0.008 + random(seed &+ 103) * 0.020
                let target = CGPoint(x: CGFloat(x), y: CGFloat(y))
                let start = CGPoint(x: CGFloat(x + cos(angle) * distance),
                                    y: CGFloat(y + sin(angle) * distance))
                let localArrival = arrival[index]
                let delay = 0.04 + localArrival * 0.22
                    + random(seed &+ 157) * 0.04
                result.append(InkParticle(target: target, start: start, delay: delay,
                                          radius: CGFloat(0.65 + random(seed &+ 191) * 0.9)))
            }
        }
        guard result.count > 300 else { return result }
        return (0..<300).map { result[$0 * result.count / 300] }
    }

    private static func makeDepositionField(particles: [InkParticle], alpha: [UInt8],
                                            width: Int, height: Int) -> [Float] {
        guard alpha.count == width * height else {
            return [Float](repeating: 0.8, count: width * height)
        }
        var field = [Float](repeating: .infinity, count: width * height)
        var frontier = Frontier()
        for particle in particles {
            let x = min(width - 1, Int(particle.target.x * CGFloat(width - 1)))
            let y = min(height - 1, Int(particle.target.y * CGFloat(height - 1)))
            let index = y * width + x
            guard alpha[index] > 8 else { continue }
            let time = particle.delay + 0.28
            if time < field[index] {
                field[index] = time
                frontier.push(time: time, index: index)
            }
        }

        let neighbors = [(-1, 0, 0.0045 as Float), (1, 0, 0.0045),
                         (0, -1, 0.0045), (0, 1, 0.0045),
                         (-1, -1, 0.0064), (1, -1, 0.0064),
                         (-1, 1, 0.0064), (1, 1, 0.0064)]
        while let current = frontier.pop() {
            guard current.time <= field[current.index] else { continue }
            let x = current.index % width
            let y = current.index / width
            for (dx, dy, cost) in neighbors {
                let nextX = x + dx
                let nextY = y + dy
                guard nextX >= 0, nextX < width, nextY >= 0, nextY < height else { continue }
                let next = nextY * width + nextX
                guard alpha[next] > 8 else { continue }
                let time = current.time + cost
                if time < field[next] {
                    field[next] = time
                    frontier.push(time: time, index: next)
                }
            }
        }
        for index in field.indices where !field[index].isFinite {
            field[index] = 0.82
        }
        return field
    }

    private func renderInkParticles(progress: Float) -> UIImage? {
        guard !particles.isEmpty else { return nil }
        let imageWidth: CGFloat = 384
        let imageHeight = imageWidth * CGFloat(height) / CGFloat(width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: imageWidth, height: imageHeight),
                                               format: format)
        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            for particle in particles {
                let time = progress - particle.delay
                guard time > 0, time < 0.65 else { continue }
                let travel = smoothstep(0, 0.28, time)
                let x = (particle.start.x + (particle.target.x - particle.start.x) * CGFloat(travel))
                    * imageWidth
                let y = (particle.start.y + (particle.target.y - particle.start.y) * CGFloat(travel))
                    * imageHeight
                let visibility = smoothstep(0, 0.05, time)
                    * (1 - smoothstep(0.38, 0.65, time))
                let targetX = particle.target.x * imageWidth
                let targetY = particle.target.y * imageHeight
                context.setStrokeColor(UIColor(red: 0.22, green: 0.18, blue: 0.16,
                                               alpha: CGFloat(visibility) * 0.2).cgColor)
                context.setLineWidth(0.8)
                context.move(to: CGPoint(x: x, y: y))
                context.addLine(to: CGPoint(x: x + (targetX - x) * 0.28,
                                            y: y + (targetY - y) * 0.28))
                context.strokePath()
                let colour = UIColor(red: 0.22, green: 0.18, blue: 0.16,
                                     alpha: CGFloat(visibility) * 0.5).cgColor
                context.setFillColor(colour)
                let radius = particle.radius * (1 + CGFloat(travel) * 0.55)
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
            }
        }
    }

    private func smoothstep(_ low: Float, _ high: Float, _ value: Float) -> Float {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }

    private func image(pixels: [UInt8]) -> CGImage? {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let colourSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: colourSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }
}
