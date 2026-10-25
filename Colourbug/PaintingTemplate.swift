import CoreGraphics
import Foundation

struct PaintingTemplate {
    struct Area {
        let id: String
        let colourID: PaintColourID
        let boundary: String
        let featherPixels: CGFloat
        let paintGroup: String
        let maskIndex: Int
        let path: CGPath
    }

    let size: CGSize
    let palette: [PaintColour]
    let paintableAreas: [Area]
    // Zero means unpaintable; otherwise the byte is the area's one-based order
    // in paintableAreas. It is exported alongside the SVG paths from one source.
    let owners: [UInt8]
    let inkImageName: String

    func areaIndex(at point: CGPoint) -> Int? {
        let x = Int(floor(point.x))
        let y = Int(floor(point.y))
        let width = Int(size.width)
        guard x >= 0, x < width, y >= 0, y < Int(size.height) else { return nil }
        let owner = Int(owners[y * width + x])
        return owner > 0 ? owner - 1 : nil
    }

    func area(at point: CGPoint) -> Area? {
        areaIndex(at: point).map { paintableAreas[$0] }
    }

    static let puppyGod: PaintingTemplate = {
        struct Size: Decodable {
            let width: Int
            let height: Int
        }
        struct Region: Decodable {
            let id: String
            let colourID: String
            let boundary: String
            let featherPixels: CGFloat
            let paintGroup: String
            let path: String
        }
        struct Asset: Decodable {
            let size: Size
            let palette: [String: String]
            let paletteOrder: [String]
            let regions: [Region]
        }

        let jsonURL = Bundle.main.url(forResource: "puppy-god-regions", withExtension: "json")!
        let ownerURL = Bundle.main.url(forResource: "puppy-god-owners", withExtension: "bin")!
        let asset = try! JSONDecoder().decode(Asset.self, from: Data(contentsOf: jsonURL))
        let owners = [UInt8](try! Data(contentsOf: ownerURL))
        precondition(owners.count == asset.size.width * asset.size.height)
        precondition(asset.regions.count < 256)

        let palette = asset.paletteOrder.map { id -> PaintColour in
            let hex = asset.palette[id]!
            let value = UInt32(hex.dropFirst(), radix: 16)!
            let name = id == "sky_peach" ? "Dusk Violet" :
                id.replacingOccurrences(of: "_", with: " ").capitalized
            return PaintColour(id: id,
                               name: name,
                               red: Float((value >> 16) & 0xff) / 255,
                               green: Float((value >> 8) & 0xff) / 255,
                               blue: Float(value & 0xff) / 255)
        }
        var maskIndices: [String: Int] = [:]
        let areas = asset.regions.map { region -> Area in
            let maskIndex: Int
            if let existing = maskIndices[region.paintGroup] {
                maskIndex = existing
            } else {
                maskIndex = maskIndices.count
                maskIndices[region.paintGroup] = maskIndex
            }
            return Area(id: region.id, colourID: region.colourID,
                        boundary: region.boundary, featherPixels: region.featherPixels,
                        paintGroup: region.paintGroup,
                        maskIndex: maskIndex, path: parsePath(region.path))
        }
        precondition(maskIndices.count <= 128)
        precondition(areas.allSatisfy { asset.palette[$0.colourID] != nil })
        return PaintingTemplate(size: CGSize(width: asset.size.width, height: asset.size.height),
                                palette: palette, paintableAreas: areas, owners: owners,
                                inkImageName: "puppy-god-ink")
    }()

    // One continuous area allows pigment and water to travel anywhere on the sheet.
    static func blankPaper(size: CGSize) -> PaintingTemplate {
        let colour = PaintColour(id: "ink", name: "Indigo",
                                 red: 0.25, green: 0.38, blue: 0.69)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        let area = Area(id: "paper", colourID: colour.id, boundary: "none",
                        featherPixels: 0, paintGroup: "paper", maskIndex: 0, path: path)
        return PaintingTemplate(size: size, palette: [colour], paintableAreas: [area],
                                owners: Array(repeating: 1, count: Int(size.width * size.height)),
                                inkImageName: "")
    }

    // Exported paths use only M, L, and Z with integer source-image coordinates.
    private static func parsePath(_ source: String) -> CGPath {
        let tokens = source.split(whereSeparator: \.isWhitespace)
        let result = CGMutablePath()
        var index = 0
        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M", "L":
                precondition(index + 1 < tokens.count)
                let x = CGFloat(Double(tokens[index])!)
                let y = CGFloat(Double(tokens[index + 1])!)
                index += 2
                if command == "M" { result.move(to: CGPoint(x: x, y: y)) }
                else { result.addLine(to: CGPoint(x: x, y: y)) }
            case "Z":
                result.closeSubpath()
            default:
                preconditionFailure("Unsupported template path command: \(command)")
            }
        }
        return result
    }
}
