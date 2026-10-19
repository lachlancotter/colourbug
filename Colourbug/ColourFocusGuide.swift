import CoreGraphics
import Foundation
import Observation
import UIKit

/// Guidance lives between the paint and ink. It never deposits colour on the paper.
final class ColourFocusGuide {
    let veilView: UIImageView
    let outlinesView: UIView

    private let template: PaintingTemplate
    private let session: PaintingSession
    private let cache = NSCache<NSString, UIImage>()
    private let renderQueue = DispatchQueue(label: "colourbug.focus-guide", qos: .userInitiated)
    private var selectedColourID = ""
    private var isPainting = false
    private var outlines: [(PaintingTemplate.Area, CAShapeLayer)] = []

    init(template: PaintingTemplate, session: PaintingSession) {
        self.template = template
        self.session = session
        let frame = CGRect(origin: .zero, size: template.size)
        veilView = UIImageView(frame: frame)
        veilView.isUserInteractionEnabled = false
        veilView.contentMode = .scaleToFill
        outlinesView = UIView(frame: frame)
        outlinesView.isUserInteractionEnabled = false
        outlinesView.backgroundColor = .clear
        cache.totalCostLimit = 24 * 1024 * 1024

        for area in template.paintableAreas where area.boundary == "ink" {
            let outline = CAShapeLayer()
            outline.path = area.path
            outline.fillColor = UIColor.clear.cgColor
            outline.strokeColor = UIColor(red: 0.52, green: 0.38, blue: 0.25, alpha: 0.62).cgColor
            outline.lineWidth = 4
            outline.lineJoin = .round
            outline.lineCap = .round
            outline.isHidden = true
            outlinesView.layer.addSublayer(outline)
            outlines.append((area, outline))
        }
        observeSelection()
    }

    func setPainting(_ painting: Bool) {
        guard isPainting != painting else { return }
        isPainting = painting
        UIView.animate(withDuration: painting ? 0.12 : 0.25) {
            self.veilView.alpha = painting ? 0 : 1
            self.outlinesView.alpha = painting ? 0 : 1
        }
    }

    private func observeSelection() {
        withObservationTracking {
            let colourID = session.selectedColour.id
            guard colourID != selectedColourID else { return }
            selectedColourID = colourID
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (area, outline) in outlines {
                outline.isHidden = area.colourID != colourID
            }
            CATransaction.commit()

            veilView.alpha = 0
            if let cached = cache.object(forKey: colourID as NSString) {
                show(cached, for: colourID)
            } else {
                // Path rasterisation and feathering happen only once for each swatch.
                renderQueue.async { [weak self] in
                    guard let self, let image = Self.makeVeil(for: colourID, template: self.template) else { return }
                    self.cache.setObject(image, forKey: colourID as NSString,
                                         cost: image.cgImage.map { $0.width * $0.height * 4 } ?? 0)
                    DispatchQueue.main.async { self.show(image, for: colourID) }
                }
            }
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeSelection() }
        }
    }

    private func show(_ image: UIImage, for colourID: String) {
        guard selectedColourID == colourID else { return }
        veilView.image = image
        UIView.animate(withDuration: 0.24) {
            self.veilView.alpha = self.isPainting ? 0 : 1
        }
    }

    private static func makeVeil(for colourID: String, template: PaintingTemplate) -> UIImage? {
        // Half resolution is enough for a soft guide and keeps each cached image small.
        let reduction: CGFloat = 0.5
        let width = Int(template.size.width * reduction)
        let height = Int(template.size.height * reduction)
        let areas = template.paintableAreas.filter { $0.colourID == colourID }
        guard !areas.isEmpty else { return nil }

        var clearAmount = [UInt8](repeating: 0, count: width * height)
        let hardAreas = areas.filter { $0.featherPixels <= 0 }
        if let hard = rasterise(hardAreas, width: width, height: height, reduction: reduction) {
            clearAmount = hard
        }
        let featherWidths = Set(areas.filter { $0.featherPixels > 0 }.map { Int($0.featherPixels) })
        for feather in featherWidths {
            let softAreas = areas.filter { Int($0.featherPixels) == feather }
            guard let soft = rasterise(softAreas, width: width, height: height,
                                       reduction: reduction) else { continue }
            let blurred = boxBlur(soft, width: width, height: height,
                                  radius: max(1, Int(CGFloat(feather) * reduction / 2)))
            for index in clearAmount.indices {
                clearAmount[index] = max(clearAmount[index], blurred[index])
            }
        }

        // The veil is a neutral translucent shade. Its alpha vanishes in the
        // suggested regions, leaving untouched paper and existing paint visible.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in clearAmount.indices {
            let alpha = Int(43) * (255 - Int(clearAmount[index])) / 255
            let base = index * 4
            pixels[base] = UInt8(alpha * 75 / 255)
            pixels[base + 1] = UInt8(alpha * 66 / 255)
            pixels[base + 2] = UInt8(alpha * 56 / 255)
            pixels[base + 3] = UInt8(alpha)
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func rasterise(_ areas: [PaintingTemplate.Area], width: Int,
                                  height: Int, reduction: CGFloat) -> [UInt8]? {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: reduction, y: -reduction)
        context.setFillColor(gray: 1, alpha: 1)
        for area in areas {
            context.addPath(area.path)
            context.fillPath()
        }
        guard let data = context.data else { return nil }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                         count: width * height))
    }

    /// A separable box blur gives unlined colour zones a gradual focus edge.
    private static func boxBlur(_ source: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        guard radius > 0 else { return source }
        var horizontal = [UInt8](repeating: 0, count: source.count)
        var result = [UInt8](repeating: 0, count: source.count)
        for y in 0..<height {
            let row = y * width
            var sum = 0
            for x in 0..<width {
                if x == 0 {
                    for sample in 0...min(radius, width - 1) { sum += Int(source[row + sample]) }
                } else {
                    if x + radius < width { sum += Int(source[row + x + radius]) }
                    if x - radius - 1 >= 0 { sum -= Int(source[row + x - radius - 1]) }
                }
                let count = min(width - 1, x + radius) - max(0, x - radius) + 1
                horizontal[row + x] = UInt8(sum / count)
            }
        }
        for x in 0..<width {
            var sum = 0
            for y in 0..<height {
                if y == 0 {
                    for sample in 0...min(radius, height - 1) { sum += Int(horizontal[sample * width + x]) }
                } else {
                    if y + radius < height { sum += Int(horizontal[(y + radius) * width + x]) }
                    if y - radius - 1 >= 0 { sum -= Int(horizontal[(y - radius - 1) * width + x]) }
                }
                let count = min(height - 1, y + radius) - max(0, y - radius) + 1
                result[y * width + x] = UInt8(sum / count)
            }
        }
        return result
    }
}
