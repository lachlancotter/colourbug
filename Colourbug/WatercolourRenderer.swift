import UIKit

// Water moves on a coarse grid; the image is reconstructed at one paper point per pixel.
final class WatercolourRenderer {
    // RGB is stored as colour weighted by pigment mass; w is the mass.
    private typealias Pigment = SIMD4<Float>
    private static let cellSize: CGFloat = 2
    private static let tileSide = 64
    private static let pixelsPerCell = 2
    private static let wetThreshold: Float = 0.015
    private static let edgeFeather: Float = 8
    private static let edgeSettlingRate: Float = 0.3
    private static let pigmentMixingRate: Float = 3.0
    private static let evaporationRate: Float = 0.42
    private static let outsidePigmentFadeRate: Float = 1.0
    private static let visiblePigmentThreshold: Float = 0.001
    private static let reworkWindow: CFTimeInterval = 2.5
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
        var mobile: [Pigment]
        var settled: [Pigment]
        var dry: [Pigment]
        var recentDry: [Pigment]
        var driedAt: [CFTimeInterval]

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            let count = width * height
            water = Array(repeating: 0, count: count)
            mobile = Array(repeating: .zero, count: count)
            settled = Array(repeating: .zero, count: count)
            dry = Array(repeating: .zero, count: count)
            recentDry = Array(repeating: .zero, count: count)
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
    private let paperHeight: Int
    private let template: PaintingTemplate
    // Each bit represents an area touched by one of the cell's rendered pixels.
    // Shared cells blend their areas' pigments; -1 means unresolved.
    private var cellAreaMasks: [Int]
    private let colourAreaMasks: [PaintColourID: Int]
    private var pixelAreaIndices: [Int16]

    var hasActivePaint: Bool { !active.isEmpty }

    init(size: CGSize, host: UIView, template: PaintingTemplate) {
        width = Int(ceil(size.width / Self.cellSize))
        height = Int(ceil(size.height / Self.cellSize))
        tilesAcross = Int(ceil(Double(width) / Double(Self.tileSide)))
        self.host = host
        self.template = template
        cellAreaMasks = Array(repeating: -1, count: width * height)
        var colourMasks: [PaintColourID: Int] = [:]
        for (index, area) in template.paintableAreas.enumerated() {
            colourMasks[area.colourID, default: 0] |= 1 << index
        }
        colourAreaMasks = colourMasks
        paperWidth = Int(ceil(size.width))
        paperHeight = Int(ceil(size.height))
        pixelAreaIndices = Array(repeating: -2, count: paperWidth * paperHeight)
        let texture = Self.makeGrain(width: paperWidth, height: paperHeight)
        grain = texture
        absorption = Self.makeAbsorption(width: width, height: height, grain: texture,
                                         paperWidth: paperWidth)
        tooth = Self.makeTooth(width: width, height: height, grain: texture,
                               paperWidth: paperWidth)
    }

    func deposit(at point: CGPoint, pigment: Float, water: Float, radius: CGFloat,
                 direction: CGVector = .zero, settledFraction: Float = 0,
                 colour: PaintColour) {
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
                let areaMask = areaMask(x: x, y: y)
                if areaMask != 0 && areaMask & (colourAreaMasks[colour.id] ?? 0) == 0 { continue }
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
                let wetPigment = tile.mobile[local].w + tile.settled[local].w
                let acceptedPigment = min(pigmentAmount,
                                          max(pigmentAmount * 0.08,
                                              concentration * tile.water[local] - wetPigment))
                let fixedFraction = areaMask != 0
                    ? settledFraction * (1 - wetness) : 0
                tile.mobile[local] += colour.pigment * (acceptedPigment * (1 - fixedFraction))
                tile.settled[local] += colour.pigment * (acceptedPigment * fixedFraction)
                active.insert(y * width + x)
                markDirty(x: x, y: y, dry: false)
            }
        }
    }

    func step(dt: Float) {
        guard !active.isEmpty else { return }
        let now = CACurrentMediaTime()
        var waterDelta: [Int: Float] = [:]
        var pigmentDelta: [Int: Pigment] = [:]
        var settledDelta: [Int: Pigment] = [:]
        var affected = active
        let current = Array(active)

        for key in current {
            let x = key % width
            let y = key / width
            guard let (tile, local, _) = cell(x: x, y: y, create: false) else { continue }
            let water = tile.water[local]
            guard water > 0 else { continue }
            let sourceAreaMask = areaMask(x: x, y: y)
            let paintable = sourceAreaMask != 0
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
            let settling = paintable
                ? min(1, dt * (0.12 + 0.15 * paper + 0.35 * paperTooth
                                 + 0.25 * (1 - min(water, 1))
                                 + Self.edgeSettlingRate * boundary)) : 0
            let amount = tile.mobile[local] * settling
            pigmentDelta[key, default: .zero] -= amount
            settledDelta[key, default: .zero] += amount
            markDirty(x: x, y: y, dry: false)

            var remainingWater = water - evaporation
            var remainingPigment = tile.mobile[local].w - amount.w
            let concentration = tile.mobile[local].w / max(water, 0.1)
            for (offsetX, offsetY) in Self.flowNeighbours {
                let nx = x + offsetX
                let ny = y + offsetY
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                // Keep the blended boundary cell from carrying pigment into either area.
                guard areaMask(x: nx, y: ny) == sourceAreaMask else { continue }
                let neighbour = cell(x: nx, y: ny, create: false)
                let otherWater = neighbour.map { $0.0.water[$0.1] } ?? 0
                let otherPigment = neighbour.map { $0.0.mobile[$0.1].w } ?? 0
                let otherIsWet = otherWater >= Self.wetThreshold
                let gradient = max(0, water - otherWater)
                let rate: Float = otherIsWet ? 1.3 + 0.5 * (1 - paper) : 0.95
                let flow = min(remainingWater, water * 0.16, gradient * dt * rate)
                // A small transfer to dry paper evaporates immediately; avoid a dry halo.
                if !otherIsWet && flow < Self.wetThreshold { continue }
                let otherConcentration = otherPigment / max(otherWater, 0.1)
                let mixing = otherIsWet ? dt * Self.pigmentMixingRate * min(water, otherWater)
                    * max(0, concentration - otherConcentration) : 0
                let carried = min(remainingPigment, tile.mobile[local].w * 0.22,
                                  concentration * flow * 0.8 + mixing
                                  + dt * 0.2 * tile.mobile[local].w
                                  * max(0, tooth[ny * width + nx] - paperTooth)
                                  * min(1, otherWater))
                guard flow > 0.0001 || carried > 0.0001 else { continue }
                _ = cell(x: nx, y: ny, create: true)
                let target = ny * width + nx
                waterDelta[key, default: 0] -= flow
                waterDelta[target, default: 0] += flow
                let movedPigment = tile.mobile[local] * (carried / max(tile.mobile[local].w, 0.0001))
                pigmentDelta[key, default: .zero] -= movedPigment
                pigmentDelta[target, default: .zero] += movedPigment
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
            let mobile = tile.mobile[local] + pigmentDelta[key, default: .zero]
            tile.mobile[local] = mobile.w > 0 ? mobile : .zero
            tile.settled[local] += settledDelta[key, default: .zero]
            if wasDry && tile.water[local] >= Self.wetThreshold {
                reworkRecentDry(in: tile, at: local, x: x, y: y, now: now)
            }
            if areaMask(x: x, y: y) == 0 {
                // Pigment on the masked surface remains visible briefly, then vanishes.
                // It never enters the permanent dry layer, even after its water is gone.
                let fade = exp(-Self.outsidePigmentFadeRate * dt)
                tile.mobile[local] = (tile.mobile[local] + tile.settled[local]) * fade
                tile.settled[local] = .zero
                if tile.mobile[local].w < Self.visiblePigmentThreshold {
                    tile.mobile[local] = .zero
                }
                if tile.water[local] < Self.wetThreshold {
                    tile.water[local] = 0
                }
                if tile.mobile[local].w > 0 || tile.water[local] > 0 {
                    active.insert(key)
                }
            } else if tile.water[local] < Self.wetThreshold {
                if tile.recentDry[local].w > 0,
                   now - tile.driedAt[local] > Self.reworkWindow {
                    tile.dry[local] += tile.recentDry[local]
                    tile.recentDry[local] = .zero
                }
                tile.recentDry[local] += tile.mobile[local] + tile.settled[local]
                tile.driedAt[local] = now
                tile.mobile[local] = .zero
                tile.settled[local] = .zero
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
        guard pigment.w > 0 else { return }
        if now - tile.driedAt[local] <= Self.reworkWindow {
            tile.mobile[local] += pigment
            markDirty(x: x, y: y, dry: true)
        } else {
            tile.dry[local] += pigment
        }
        tile.recentDry[local] = .zero
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
        var massField = [Pigment](repeating: .zero, count: paddedWidth * (tile.height + 2))
        var settledField = [Float](repeating: 0, count: massField.count)
        var waterField = [Float](repeating: 0, count: massField.count)
        var ownerField = [Int](repeating: -1, count: massField.count)
        for y in -1...tile.height {
            for x in -1...tile.width {
                let sheetX = originX + x
                let sheetY = originY + y
                guard sheetX >= 0, sheetX < width, sheetY >= 0, sheetY < height else { continue }
                let position = (y + 1) * paddedWidth + x + 1
                ownerField[position] = areaMask(x: sheetX, y: sheetY)
                guard let (sampleTile, local, _) = cell(x: sheetX, y: sheetY, create: false) else { continue }
                let dilution = 1 - 0.32 * min(1, sampleTile.water[local])
                let settled = wet ? sampleTile.settled[local]
                    : sampleTile.dry[local] + sampleTile.recentDry[local]
                let mobile: Pigment = wet ? sampleTile.mobile[local] * dilution : .zero
                massField[position] = mobile + settled
                settledField[position] = settled.w
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
                let sheetX = originX * Self.pixelsPerCell + x
                let sheetY = originY * Self.pixelsPerCell + y
                guard sheetX < paperWidth, sheetY < paperHeight else { continue }
                let owner = pixelAreaIndex(x: sheetX, y: sheetY)
                if !wet && owner == -1 { continue }
                let ownerBit = owner >= 0 ? 1 << owner : 0
                let topLeftMatches = owner == -1 ? ownerField[topLeft] == 0
                    : ownerField[topLeft] >= 0 && ownerField[topLeft] & ownerBit != 0
                let topRightMatches = owner == -1 ? ownerField[topRight] == 0
                    : ownerField[topRight] >= 0 && ownerField[topRight] & ownerBit != 0
                let bottomLeftMatches = owner == -1 ? ownerField[bottomLeft] == 0
                    : ownerField[bottomLeft] >= 0 && ownerField[bottomLeft] & ownerBit != 0
                let bottomRightMatches = owner == -1 ? ownerField[bottomRight] == 0
                    : ownerField[bottomRight] >= 0 && ownerField[bottomRight] & ownerBit != 0
                let topMass = (topLeftMatches ? massField[topLeft] : .zero) * (1 - fx)
                    + (topRightMatches ? massField[topRight] : .zero) * fx
                let bottomMass = (bottomLeftMatches ? massField[bottomLeft] : .zero) * (1 - fx)
                    + (bottomRightMatches ? massField[bottomRight] : .zero) * fx
                let mass = topMass * (1 - fy) + bottomMass * fy
                guard mass.w > 0 else { continue }
                let topSettled = (topLeftMatches ? settledField[topLeft] : 0) * (1 - fx)
                    + (topRightMatches ? settledField[topRight] : 0) * fx
                let bottomSettled = (bottomLeftMatches ? settledField[bottomLeft] : 0) * (1 - fx)
                    + (bottomRightMatches ? settledField[bottomRight] : 0) * fx
                let settled = topSettled * (1 - fy) + bottomSettled * fy
                let topWater = (topLeftMatches ? waterField[topLeft] : 0) * (1 - fx)
                    + (topRightMatches ? waterField[topRight] : 0) * fx
                let bottomWater = (bottomLeftMatches ? waterField[bottomLeft] : 0) * (1 - fx)
                    + (bottomRightMatches ? waterField[bottomRight] : 0) * fx
                let water = topWater * (1 - fy) + bottomWater * fy
                let paper = Float(grain[sheetY * paperWidth + sheetX]) / 255
                // Mobile paint reads as a smooth wash; paper tooth appears as it settles.
                let wash = max(0, mass.w - settled) * (0.9 + 0.12 * paper)
                let granulated = settled * (0.72 + 0.55 * paper)
                let opacity = min(0.93, 1 - exp(-2.0 * (wash + granulated)))
                let sheen = wet ? min(1, water) : 0
                let red = min(1, mass.x / mass.w + 0.07 * sheen)
                let green = min(1, mass.y / mass.w + 0.09 * sheen)
                let blue = min(1, mass.z / mass.w + 0.05 * sheen)
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

    private func areaMask(x: Int, y: Int) -> Int {
        let index = y * width + x
        if cellAreaMasks[index] != -1 {
            return cellAreaMasks[index]
        }
        var mask = 0
        for pixelY in 0..<Self.pixelsPerCell {
            for pixelX in 0..<Self.pixelsPerCell {
                let sheetX = x * Self.pixelsPerCell + pixelX
                let sheetY = y * Self.pixelsPerCell + pixelY
                guard sheetX < paperWidth, sheetY < paperHeight else { continue }
                let owner = pixelAreaIndex(x: sheetX, y: sheetY)
                if owner >= 0 { mask |= 1 << owner }
            }
        }
        cellAreaMasks[index] = mask
        return mask
    }

    private func pixelAreaIndex(x: Int, y: Int) -> Int {
        let index = y * paperWidth + x
        if pixelAreaIndices[index] != -2 { return Int(pixelAreaIndices[index]) }
        let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
        let owner = template.areaIndex(at: point) ?? -1
        pixelAreaIndices[index] = Int16(owner)
        return owner
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
