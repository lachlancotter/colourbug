import UIKit

// Water moves on a coarse grid; the image is reconstructed at one paper point per pixel.
final class WatercolourRenderer {
    private static let cellSize: CGFloat = 2
    private static let tileSide = 64
    private static let pixelsPerCell = 2
    private static let wetThreshold: Float = 0.015
    private static let edgeFeather: Float = 8
    private static let edgeSettlingRate: Float = 0.3
    private static let pigmentMixingRate: Float = 3.0
    private static let evaporationRate: Float = 0.85
    private static let reworkWindow: CFTimeInterval = 1.5
    private static let surroundingCells = [(-1, -1), (0, -1), (1, -1),
                                            (-1, 0),            (1, 0),
                                            (-1, 1),  (0, 1),   (1, 1)]
    private static let flowNeighbours = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    private final class Tile {
        let width: Int
        let height: Int
        let dryLayer = CALayer()
        let wetLayer = CALayer()
        var water: [Float]
        var mobile: [Float]
        var settled: [Float]
        var dry: [Float]
        var recentDry: [Float]
        var driedAt: [CFTimeInterval]

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            let count = width * height
            water = Array(repeating: 0, count: count)
            mobile = Array(repeating: 0, count: count)
            settled = Array(repeating: 0, count: count)
            dry = Array(repeating: 0, count: count)
            recentDry = Array(repeating: 0, count: count)
            driedAt = Array(repeating: 0, count: count)
        }
    }

    private let width: Int
    private let height: Int
    private let tilesAcross: Int
    private weak var host: UIView?
    private var tiles: [Int: Tile] = [:]
    private var active = Set<Int>()
    private var dirtyTiles = Set<Int>()
    private var dirtyDryTiles = Set<Int>()
    private let absorption: [Float]
    private let tooth: [Float]
    private let grain: [UInt8]
    private let paperWidth: Int

    var hasWetPaint: Bool { !active.isEmpty }

    init(size: CGSize, host: UIView) {
        width = Int(ceil(size.width / Self.cellSize))
        height = Int(ceil(size.height / Self.cellSize))
        tilesAcross = Int(ceil(Double(width) / Double(Self.tileSide)))
        self.host = host
        paperWidth = Int(ceil(size.width))
        let texture = Self.makeGrain(width: paperWidth, height: Int(ceil(size.height)))
        grain = texture
        absorption = Self.makeAbsorption(width: width, height: height, grain: texture,
                                         paperWidth: paperWidth)
        tooth = Self.makeTooth(width: width, height: height, grain: texture,
                               paperWidth: paperWidth)
    }

    func deposit(at point: CGPoint, pigment: Float, water: Float, radius: CGFloat,
                 direction: CGVector = .zero, settledFraction: Float = 0) {
        let now = CACurrentMediaTime()
        let reach = radius + 6
        let minX = max(0, Int(floor((point.x - reach) / Self.cellSize)))
        let maxX = min(width - 1, Int(floor((point.x + reach) / Self.cellSize)))
        let minY = max(0, Int(floor((point.y - reach) / Self.cellSize)))
        let maxY = min(height - 1, Int(floor((point.y + reach) / Self.cellSize)))
        guard minX <= maxX, minY <= maxY else { return }
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = (CGFloat(x) + 0.5) * Self.cellSize - point.x
                let dy = (CGFloat(y) + 0.5) * Self.cellSize - point.y
                let distance = hypot(dx, dy)
                guard distance <= reach else { continue }
                let paper = absorption[y * width + x]
                let wave = sin(Float(x) * 0.29 + sin(Float(y) * 0.11))
                         * sin(Float(y) * 0.23 - Float(x) * 0.13)
                let edge = Float(radius) + 0.9 * wave + 0.7 * (paper - 0.5)
                let t = max(0, min(1, (edge - Float(distance)) / Self.edgeFeather + 0.5))
                let coverage = t * t * (3 - 2 * t)
                guard coverage > 0 else { continue }
                let (tile, local, _) = cell(x: x, y: y, create: true)!
                let ahead = max(0, Float((dx * direction.dx + dy * direction.dy) / radius))
                let leadingWater = 0.82 + 0.55 * min(1, ahead)
                let previousWater = tile.water[local]
                let addedWater = water * coverage * leadingWater
                if previousWater + addedWater >= Self.wetThreshold {
                    reworkRecentDry(in: tile, at: local, x: x, y: y, now: now)
                }
                if previousWater >= Self.wetThreshold {
                    // A pass through the same wash loosens pigment that has not dried yet.
                    let lifted = tile.settled[local] * min(0.85, water * coverage * 3)
                    tile.settled[local] -= lifted
                    tile.mobile[local] += lifted
                }
                tile.water[local] = min(1.5, previousWater + addedWater)
                let wetness = min(1, previousWater / 0.5)
                let pigmentAmount = pigment * coverage * (1.12 - 0.35 * paper)
                // A wet wash accepts pigment up to the brush's concentration instead
                // of building a fresh opaque ridge on every overlapping stamp.
                let concentration = pigmentAmount / max(addedWater, 0.001)
                let wetPigment = tile.mobile[local] + tile.settled[local]
                let acceptedPigment = min(pigmentAmount,
                                          max(pigmentAmount * 0.08,
                                              concentration * tile.water[local] - wetPigment))
                let fixedFraction = settledFraction * (1 - wetness)
                tile.mobile[local] += acceptedPigment * (1 - fixedFraction)
                tile.settled[local] += acceptedPigment * fixedFraction
                active.insert(y * width + x)
                markDirty(x: x, y: y, dry: false)
            }
        }
    }

    func step(dt: Float) {
        guard !active.isEmpty else { return }
        let now = CACurrentMediaTime()
        var waterDelta: [Int: Float] = [:]
        var pigmentDelta: [Int: Float] = [:]
        var settledDelta: [Int: Float] = [:]
        var affected = active
        let current = Array(active)

        for key in current {
            let x = key % width
            let y = key / width
            guard let (tile, local, _) = cell(x: x, y: y, create: false) else { continue }
            let water = tile.water[local]
            guard water > 0 else { continue }
            let paper = absorption[key]
            let paperTooth = tooth[key]
            let evaporation = min(water, dt * Self.evaporationRate * (0.72 + 0.38 * paper))
            waterDelta[key, default: 0] -= evaporation

            // Only the outside of the joined wet region forms a drying edge.
            var wetNeighbours: Float = 0
            for (offsetX, offsetY) in Self.surroundingCells {
                let nx = x + offsetX
                let ny = y + offsetY
                guard nx >= 0, nx < width, ny >= 0, ny < height,
                      let (other, position, _) = cell(x: nx, y: ny, create: false) else { continue }
                wetNeighbours += min(1, other.water[position] / 0.08)
            }
            let boundary = 1 - wetNeighbours / 8
            let settling = min(1, dt * (0.12 + 0.15 * paper + 0.35 * paperTooth
                                          + 0.25 * (1 - min(water, 1))
                                          + Self.edgeSettlingRate * boundary))
            let amount = tile.mobile[local] * settling
            pigmentDelta[key, default: 0] -= amount
            settledDelta[key, default: 0] += amount
            markDirty(x: x, y: y, dry: false)

            var remainingWater = water - evaporation
            var remainingPigment = tile.mobile[local] - amount
            let concentration = tile.mobile[local] / max(water, 0.1)
            for (offsetX, offsetY) in Self.flowNeighbours {
                let nx = x + offsetX
                let ny = y + offsetY
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let neighbour = cell(x: nx, y: ny, create: false)
                let otherWater = neighbour.map { $0.0.water[$0.1] } ?? 0
                let otherPigment = neighbour.map { $0.0.mobile[$0.1] } ?? 0
                let otherIsWet = otherWater >= Self.wetThreshold
                let gradient = max(0, water - otherWater)
                let rate: Float = otherIsWet ? 1.3 + 0.5 * (1 - paper) : 0.95
                let flow = min(remainingWater, water * 0.16, gradient * dt * rate)
                // A small transfer to dry paper evaporates immediately; avoid a dry halo.
                if !otherIsWet && flow < Self.wetThreshold { continue }
                let otherConcentration = otherPigment / max(otherWater, 0.1)
                let mixing = otherIsWet ? dt * Self.pigmentMixingRate * min(water, otherWater)
                    * max(0, concentration - otherConcentration) : 0
                let carried = min(remainingPigment, tile.mobile[local] * 0.22,
                                  concentration * flow * 0.8 + mixing
                                  + dt * 0.2 * tile.mobile[local]
                                  * max(0, tooth[ny * width + nx] - paperTooth)
                                  * min(1, otherWater))
                guard flow > 0.0001 || carried > 0.0001 else { continue }
                _ = cell(x: nx, y: ny, create: true)
                let target = ny * width + nx
                waterDelta[key, default: 0] -= flow
                waterDelta[target, default: 0] += flow
                pigmentDelta[key, default: 0] -= carried
                pigmentDelta[target, default: 0] += carried
                remainingWater -= flow
                remainingPigment -= carried
                affected.insert(target)
                markDirty(x: nx, y: ny, dry: false)
            }
        }

        active.removeAll(keepingCapacity: true)
        for key in affected {
            let x = key % width
            let y = key / width
            guard let (tile, local, _) = cell(x: x, y: y, create: false) else { continue }
            let wasDry = tile.water[local] == 0
            tile.water[local] = max(0, tile.water[local] + waterDelta[key, default: 0])
            tile.mobile[local] = max(0, tile.mobile[local] + pigmentDelta[key, default: 0])
            tile.settled[local] += settledDelta[key, default: 0]
            if wasDry && tile.water[local] >= Self.wetThreshold {
                reworkRecentDry(in: tile, at: local, x: x, y: y, now: now)
            }
            if tile.water[local] < Self.wetThreshold {
                if tile.recentDry[local] > 0,
                   now - tile.driedAt[local] > Self.reworkWindow {
                    tile.dry[local] += tile.recentDry[local]
                    tile.recentDry[local] = 0
                }
                tile.recentDry[local] += tile.mobile[local] + tile.settled[local]
                tile.driedAt[local] = now
                tile.mobile[local] = 0
                tile.settled[local] = 0
                tile.water[local] = 0
                markDirty(x: x, y: y, dry: true)
            } else {
                active.insert(key)
            }
            markDirty(x: x, y: y, dry: false)
        }
    }

    private func reworkRecentDry(in tile: Tile, at local: Int, x: Int, y: Int,
                                 now: CFTimeInterval) {
        let pigment = tile.recentDry[local]
        guard pigment > 0 else { return }
        if now - tile.driedAt[local] <= Self.reworkWindow {
            tile.mobile[local] += pigment
            markDirty(x: x, y: y, dry: true)
        } else {
            tile.dry[local] += pigment
        }
        tile.recentDry[local] = 0
    }

    func renderDirtyTiles() {
        for key in dirtyDryTiles {
            guard let tile = tiles[key] else { continue }
            tile.dryLayer.contents = image(for: tile, tileKey: key, wet: false)
        }
        for key in dirtyTiles {
            guard let tile = tiles[key] else { continue }
            tile.wetLayer.contents = image(for: tile, tileKey: key, wet: true)
        }
        dirtyDryTiles.removeAll(keepingCapacity: true)
        dirtyTiles.removeAll(keepingCapacity: true)
    }

    private func image(for tile: Tile, tileKey: Int, wet: Bool) -> CGImage? {
        let imageWidth = tile.width * Self.pixelsPerCell
        let imageHeight = tile.height * Self.pixelsPerCell
        var pixels = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        let originX = (tileKey % tilesAcross) * Self.tileSide
        let originY = (tileKey / tilesAcross) * Self.tileSide
        let paddedWidth = tile.width + 2
        var massField = [Float](repeating: 0, count: paddedWidth * (tile.height + 2))
        var settledField = [Float](repeating: 0, count: massField.count)
        var waterField = [Float](repeating: 0, count: massField.count)
        for y in -1...tile.height {
            for x in -1...tile.width {
                let sheetX = originX + x
                let sheetY = originY + y
                guard sheetX >= 0, sheetX < width, sheetY >= 0, sheetY < height,
                      let (sampleTile, local, _) = cell(x: sheetX, y: sheetY, create: false) else { continue }
                let position = (y + 1) * paddedWidth + x + 1
                let dilution = 1 - 0.32 * min(1, sampleTile.water[local])
                let settled = wet ? sampleTile.settled[local]
                    : sampleTile.dry[local] + sampleTile.recentDry[local]
                massField[position] = (wet ? sampleTile.mobile[local] * dilution : 0) + settled
                settledField[position] = settled
                waterField[position] = sampleTile.water[local]
            }
        }

        for y in 0..<imageHeight {
            let sourceY = (Float(y) + 0.5) / Float(Self.pixelsPerCell) - 0.5
            let y0 = Int(floor(sourceY))
            let fy = sourceY - Float(y0)
            for x in 0..<imageWidth {
                let sourceX = (Float(x) + 0.5) / Float(Self.pixelsPerCell) - 0.5
                let x0 = Int(floor(sourceX))
                let fx = sourceX - Float(x0)
                let topLeft = (y0 + 1) * paddedWidth + x0 + 1
                let topRight = topLeft + 1
                let bottomLeft = topLeft + paddedWidth
                let bottomRight = bottomLeft + 1
                let topMass = massField[topLeft] * (1 - fx) + massField[topRight] * fx
                let bottomMass = massField[bottomLeft] * (1 - fx) + massField[bottomRight] * fx
                let mass = topMass * (1 - fy) + bottomMass * fy
                guard mass > 0 else { continue }
                let topSettled = settledField[topLeft] * (1 - fx) + settledField[topRight] * fx
                let bottomSettled = settledField[bottomLeft] * (1 - fx) + settledField[bottomRight] * fx
                let settled = topSettled * (1 - fy) + bottomSettled * fy
                let topWater = waterField[topLeft] * (1 - fx) + waterField[topRight] * fx
                let bottomWater = waterField[bottomLeft] * (1 - fx) + waterField[bottomRight] * fx
                let water = topWater * (1 - fy) + bottomWater * fy
                let sheetX = originX * Self.pixelsPerCell + x
                let sheetY = originY * Self.pixelsPerCell + y
                let paper = Float(grain[sheetY * paperWidth + sheetX]) / 255
                // Mobile paint reads as a smooth wash; paper tooth appears as it settles.
                let wash = max(0, mass - settled) * (0.9 + 0.12 * paper)
                let granulated = settled * (0.72 + 0.55 * paper)
                let opacity = min(0.93, 1 - exp(-2.0 * (wash + granulated)))
                let sheen = wet ? min(1, water) : 0
                let red = 0.13 + 0.07 * sheen
                let green = 0.37 + 0.09 * sheen
                let blue = 0.86 + 0.05 * sheen
                let base = (y * imageWidth + x) * 4
                pixels[base] = UInt8(clamping: Int(255 * red * opacity))
                pixels[base + 1] = UInt8(clamping: Int(255 * green * opacity))
                pixels[base + 2] = UInt8(clamping: Int(255 * blue * opacity))
                pixels[base + 3] = UInt8(clamping: Int(255 * opacity))
            }
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: imageWidth, height: imageHeight, bitsPerComponent: 8,
                       bitsPerPixel: 32, bytesPerRow: imageWidth * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private func markDirty(x: Int, y: Int, dry: Bool) {
        let tileX = x / Self.tileSide
        let tileY = y / Self.tileSide
        let xOffsets = x % Self.tileSide == 0 ? [-1, 0] :
                       x % Self.tileSide == Self.tileSide - 1 ? [0, 1] : [0]
        let yOffsets = y % Self.tileSide == 0 ? [-1, 0] :
                       y % Self.tileSide == Self.tileSide - 1 ? [0, 1] : [0]
        for offsetY in yOffsets {
            for offsetX in xOffsets {
                let nextX = tileX + offsetX
                let nextY = tileY + offsetY
                guard nextX >= 0, nextX < tilesAcross,
                      nextY >= 0, nextY < (height + Self.tileSide - 1) / Self.tileSide else { continue }
                let key = nextY * tilesAcross + nextX
                guard tiles[key] != nil else { continue }
                if dry { dirtyDryTiles.insert(key) }
                else { dirtyTiles.insert(key) }
            }
        }
    }

    private func cell(x: Int, y: Int, create: Bool) -> (Tile, Int, Int)? {
        let tileX = x / Self.tileSide
        let tileY = y / Self.tileSide
        let key = tileY * tilesAcross + tileX
        var tile = tiles[key]
        if tile == nil && create {
            let tileWidth = min(Self.tileSide, width - tileX * Self.tileSide)
            let tileHeight = min(Self.tileSide, height - tileY * Self.tileSide)
            let newTile = Tile(width: tileWidth, height: tileHeight)
            let frame = CGRect(x: CGFloat(tileX * Self.tileSide) * Self.cellSize,
                               y: CGFloat(tileY * Self.tileSide) * Self.cellSize,
                               width: CGFloat(tileWidth) * Self.cellSize,
                               height: CGFloat(tileHeight) * Self.cellSize)
            for layer in [newTile.dryLayer, newTile.wetLayer] {
                layer.frame = frame
                layer.contentsGravity = .resize
                layer.magnificationFilter = .linear
                layer.minificationFilter = .linear
                layer.actions = ["contents": NSNull()]
            }
            host?.layer.addSublayer(newTile.dryLayer)
            host?.layer.addSublayer(newTile.wetLayer)
            tiles[key] = newTile
            tile = newTile
        }
        guard let tile else { return nil }
        let local = (y % Self.tileSide) * tile.width + x % Self.tileSide
        return (tile, local, key)
    }

    private static func makeGrain(width: Int, height: Int) -> [UInt8] {
        var texture = [UInt8](repeating: 0, count: width * height * 4)
        if let image = UIImage(named: "WatercolourWhisper")?.cgImage,
           let context = CGContext(data: &texture, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var tones = [UInt8](repeating: 128, count: width * height)
        var total: Int = 0
        for index in tones.indices {
            let base = index * 4
            let tone = (Int(texture[base]) + Int(texture[base + 1]) + Int(texture[base + 2])) / 3
            tones[index] = UInt8(tone)
            total += tone
        }
        let mean = Float(total) / Float(tones.count)
        return tones.map { tone in
            UInt8(clamping: Int(128 + (Float(tone) - mean) * 5))
        }
    }

    private static func makeAbsorption(width: Int, height: Int, grain: [UInt8],
                                       paperWidth: Int) -> [Float] {
        return (0..<(width * height)).map { index in
            let x = Float(index % width)
            let y = Float(index / width)
            let paperX = min(paperWidth - 1, Int(x) * Self.pixelsPerCell)
            let paperY = Int(y) * Self.pixelsPerCell
            let tone = Float(grain[paperY * paperWidth + paperX]) / 255
            let broad = sin(x * 0.035 + y * 0.012) * sin(y * 0.041 - x * 0.015)
            return max(0, min(1, 0.5 + (0.5 - tone) * 0.45 + broad * 0.2))
        }
    }

    private static func makeTooth(width: Int, height: Int, grain: [UInt8],
                                  paperWidth: Int) -> [Float] {
        let paperHeight = grain.count / paperWidth
        return (0..<(width * height)).map { index in
            let x = min(paperWidth - 1, index % width * Self.pixelsPerCell)
            let y = min(paperHeight - 1, index / width * Self.pixelsPerCell)
            let nextX = min(paperWidth - 1, x + 1)
            let nextY = min(paperHeight - 1, y + 1)
            let tone = Float(Int(grain[y * paperWidth + x])
                           + Int(grain[y * paperWidth + nextX])
                           + Int(grain[nextY * paperWidth + x])
                           + Int(grain[nextY * paperWidth + nextX])) / 1_020
            return 1 - tone
        }
    }
}
