import UIKit

enum PaintBehaviour {
    case classic
    case fluid
    case paperBloom
}

// Water moves on a coarse grid; the image is reconstructed at one paper point per pixel.
final class WatercolourRenderer {
    // RGB is stored as colour weighted by pigment mass; w is the mass.
    private typealias Pigment = SIMD4<Float>
    private struct Eddy {
        let centre: SIMD2<Float> // Grid coordinates.
        let spin: Float
        let createdAt: CFTimeInterval
    }
    private struct AreaMask: Equatable {
        var low: UInt64 = 0
        var high: UInt64 = 0

        var isEmpty: Bool { low == 0 && high == 0 }

        mutating func insert(_ index: Int) {
            if index < 64 { low |= UInt64(1) << index }
            else { high |= UInt64(1) << (index - 64) }
        }

        func intersects(_ other: AreaMask) -> Bool {
            low & other.low != 0 || high & other.high != 0
        }
    }
    private static let cellSize: CGFloat = 2
    private static let tileSide = 64
    private static let pixelsPerCell = 2
    private static let wetThreshold: Float = 0.015
    private static let edgeFeather: Float = 14
    private static let edgeSettlingRate: Float = 0.2
    private static let pigmentMixingRate: Float = 1.2
    private static let evaporationRate: Float = 0.32
    private static let waterDepositMultiplier: Float = 1.1
    private static let brushFlowSpeed: Float = 5.2 // Grid cells per second.
    private static let maximumFlowSpeed: Float = 6.0
    private static let flowDrag: Float = 0.9
    private static let eddyRadius: Float = 14 // Grid cells, or 28 paper points.
    private static let eddyLifetime: CFTimeInterval = 3
    private static let eddyStrength: Float = 32 // Peak flow is about 12 cells per second.
    private static let outsidePigmentFadeRate: Float = 1.0
    private static let visiblePigmentThreshold: Float = 0.001
    private static let reworkWindow: CFTimeInterval = 2.5
    private static let surroundingCells = [(-1, -1), (0, -1), (1, -1),
                                            (-1, 0),            (1, 0),
                                            (-1, 1),  (0, 1),   (1, 1)]
    private static let flowNeighbours = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    private static let bloomNeighbours = [(-1, -1), (0, -1), (1, -1),
                                          (-1, 0),           (1, 0),
                                          (-1, 1),  (0, 1),  (1, 1)]
    private static let bloomReach: Float = 28

    private final class Tile {
        let width: Int
        let height: Int
        let dryLayer = CALayer()
        let wetLayer = CALayer()
        var water: [Float]
        // Water-weighted velocity keeps a stroke moving after the brush lifts.
        var momentum: [SIMD2<Float>]
        var mobile: [Pigment]
        var settled: [Pigment]
        var dry: [Pigment]
        var recentDry: [Pigment]
        var driedAt: [CFTimeInterval]
        // Off-group brush pigment is displayed above the paint, then fades away.
        var spill: [Pigment]
        var spillWater: [Float]
        // Rendering state can fade after the simulation has declared a cell dry.
        var visualWetness: [Float]
        var waterDelta: [Float]
        var momentumDelta: [SIMD2<Float>]
        var pigmentDelta: [Pigment]
        var settledDelta: [Pigment]
        var bloomDepth: [Float]
        var bloomStrength: [Float]
        var lastRewetStroke: [Int]

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            let count = width * height
            water = Array(repeating: 0, count: count)
            momentum = Array(repeating: .zero, count: count)
            mobile = Array(repeating: .zero, count: count)
            settled = Array(repeating: .zero, count: count)
            dry = Array(repeating: .zero, count: count)
            recentDry = Array(repeating: .zero, count: count)
            driedAt = Array(repeating: 0, count: count)
            spill = Array(repeating: .zero, count: count)
            spillWater = Array(repeating: 0, count: count)
            visualWetness = Array(repeating: 0, count: count)
            waterDelta = Array(repeating: 0, count: count)
            momentumDelta = Array(repeating: .zero, count: count)
            pigmentDelta = Array(repeating: .zero, count: count)
            settledDelta = Array(repeating: .zero, count: count)
            bloomDepth = Array(repeating: .infinity, count: count)
            bloomStrength = Array(repeating: 0, count: count)
            lastRewetStroke = Array(repeating: -1, count: count)
        }
    }

    private let width: Int
    private let height: Int
    private let gridCellSize: CGFloat
    private let tilesAcross: Int
    private weak var host: UIView?
    private var tiles: [Int: Tile] = [:]
    private var active = Set<Int>()
    private var activeSpill = Set<Int>()
    private var visuallyDrying = Set<Int>()
    private var bloomFront = Set<Int>()
    private var bloomElapsed: Float = 0
    private var strokeID = 0
    private var eddies: [Eddy] = []
    private var dirtyTiles = Set<Int>()
    private var dirtyDryTiles = Set<Int>()
    private let absorption: [Float]
    private let tooth: [Float]
    // Broad fibres and fine paper grain make one wet edge advance unevenly.
    private let wicking: [Float]
    private let grain: [UInt8]
    private let paperWidth: Int
    private let paperHeight: Int
    private let template: PaintingTemplate
    private let behaviour: PaintBehaviour
    private let blankPaper: Bool
    private let flowerClipping: Bool
    private let optimizedFluidCanvas: Bool
    private var livingFlow: Bool { behaviour == .fluid }
    private var paperBloom: Bool { behaviour == .paperBloom }
    private var wetThreshold: Float {
        livingFlow ? 0.008 : paperBloom ? 0.008 : Self.wetThreshold
    }
    private var evaporationRate: Float {
        livingFlow ? 0.18 : paperBloom ? 0.26 : Self.evaporationRate
    }
    private var flowDrag: Float {
        livingFlow ? 0.55 : paperBloom ? 1.3 : Self.flowDrag
    }
    private var eddyRadius: Float { livingFlow ? 14 : Self.eddyRadius }
    private var eddyLifetime: CFTimeInterval {
        livingFlow ? 4.3 : Self.eddyLifetime
    }
    private var eddyStrength: Float { livingFlow ? 24 : Self.eddyStrength }
    private var pigmentDepositMultiplier: Float { livingFlow ? 1.12 : 1 }
    private var waterDepositMultiplier: Float {
        paperBloom ? 0.98 : Self.waterDepositMultiplier
    }
    // A cell can straddle several regions. Shared paint groups have one bit,
    // which lets unlined sky and fur colours blend without an artificial seam.
    private var cellAreaMasks: [AreaMask?]
    private let colourAreaMasks: [PaintColourID: AreaMask]

    var hasActivePaint: Bool {
        !active.isEmpty || !activeSpill.isEmpty || !bloomFront.isEmpty
            || !visuallyDrying.isEmpty
    }

    // Each authored part needs paint before the flower-wide depth reveal.
    // Count pigment of any colour so the palette remains a suggestion.
    // This runs after a stroke, outside the simulation's render path.
    func hasCompletedFlower() -> Bool {
        guard let mask = template.dryClipMask else { return false }
        let strideLength = 2
        let frame = PaintingTemplate.flowerFrame(
            in: CGSize(width: paperWidth, height: paperHeight),
            imageSize: CGSize(width: 1360, height: 1156))
        let leafPath = FlowerRegion.leaf.path
        let stemPath = FlowerRegion.stem.path
        let budPath = FlowerRegion.bud.path
        var eligible = Array(repeating: 0, count: FlowerRegion.allCases.count)
        var coloured = Array(repeating: 0, count: FlowerRegion.allCases.count)
        for y in stride(from: 0, to: height, by: strideLength) {
            let paperY = min(paperHeight - 1, Int((CGFloat(y) + 0.5) * gridCellSize))
            for x in stride(from: 0, to: width, by: strideLength) {
                let paperX = min(paperWidth - 1, Int((CGFloat(x) + 0.5) * gridCellSize))
                guard mask[paperY * paperWidth + paperX] >= 160 else { continue }
                let point = CGPoint(x: (CGFloat(paperX) - frame.minX) * 1360 / frame.width,
                                    y: (CGFloat(paperY) - frame.minY) * 1156 / frame.height)
                let region: FlowerRegion
                if leafPath.contains(point) { region = .leaf }
                else if budPath.contains(point) { region = .bud }
                else if stemPath.contains(point) { region = .stem }
                else { region = .bell }
                eligible[region.rawValue] += 1
                guard let (tile, local, _) = cell(x: x, y: y, create: false) else { continue }
                let mass = tile.mobile[local].w + tile.settled[local].w
                    + tile.dry[local].w + tile.recentDry[local].w
                if mass >= 0.055 { coloured[region.rawValue] += 1 }
            }
        }
        let totalEligible = eligible.reduce(0, +)
        let totalColoured = coloured.reduce(0, +)
        guard totalEligible > 0,
              Float(totalColoured) / Float(totalEligible) >= 0.82 else { return false }
        return FlowerRegion.allCases.allSatisfy { region in
            let index = region.rawValue
            return eligible[index] > 0 && Float(coloured[index]) / Float(eligible[index]) >= 0.75
        }
    }
#if DEBUG
    var activeCellCount: Int { active.count }
    var dirtyTileCount: Int { dirtyTiles.count + dirtyDryTiles.count }
    var allocatedTileCount: Int { tiles.count }
#endif

    func beginStroke() { strokeID += 1 }

    init(size: CGSize, host: UIView, template: PaintingTemplate,
         behaviour: PaintBehaviour = .classic) {
        let isBlankPaper = template.paintableAreas.count == 1
            && template.paintableAreas[0].id == "paper"
        let optimized = behaviour == .fluid && isBlankPaper
        let cellSize = optimized ? CGFloat(3) : Self.cellSize
        gridCellSize = cellSize
        width = Int(ceil(size.width / cellSize))
        height = Int(ceil(size.height / cellSize))
        tilesAcross = Int(ceil(Double(width) / Double(Self.tileSide)))
        self.host = host
        self.template = template
        self.behaviour = behaviour
        blankPaper = isBlankPaper
        flowerClipping = template.dryClipMask != nil
        optimizedFluidCanvas = optimized
        cellAreaMasks = Array(repeating: nil, count: width * height)
        var colourMasks: [PaintColourID: AreaMask] = [:]
        for area in template.paintableAreas {
            colourMasks[area.colourID, default: AreaMask()].insert(area.maskIndex)
        }
        if isBlankPaper {
            // A continuous sheet accepts every swatch, including the flower's
            // region suggestions, so colours can mingle across drawn parts.
            for colour in template.palette {
                colourMasks[colour.id, default: AreaMask()].insert(0)
            }
        }
        colourAreaMasks = colourMasks
        paperWidth = Int(ceil(size.width))
        paperHeight = Int(ceil(size.height))
        let texture = Self.makeGrain(width: paperWidth, height: paperHeight)
        grain = texture
        absorption = Self.makeAbsorption(width: width, height: height, grain: texture,
                                         paperWidth: paperWidth, cellSize: Int(cellSize))
        tooth = Self.makeTooth(width: width, height: height, grain: texture,
                               paperWidth: paperWidth, cellSize: Int(cellSize))
        let gridWidth = width
        let paperAbsorption = absorption
        wicking = (0..<(width * height)).map { index in
            let x = Float(index % gridWidth)
            let y = Float(index / gridWidth)
            let broad = sin(x * 0.19 + 0.9 * sin(y * 0.11))
                * sin(y * 0.17 - 0.7 * sin(x * 0.09))
            let fine = sin(x * 0.67 + y * 0.31) * sin(y * 0.53 - x * 0.27)
            return max(0.32, min(1.75,
                1 + 0.43 * broad + 0.18 * fine + 0.22 * (paperAbsorption[index] - 0.5)))
        }
    }

    func deposit(at point: CGPoint, pigment: Float, water: Float, radius: CGFloat,
                 direction: CGVector = .zero, settledFraction: Float = 0,
                 colour: PaintColour) {
        let now = CACurrentMediaTime()
        seedEddy(at: point, direction: direction, colour: colour, now: now)
        let feather: Float = paperBloom ? 21 : Self.edgeFeather
        let reach = radius + CGFloat(feather) / 2 + 2
        let minX = max(0, Int(floor((point.x - reach) / gridCellSize)))
        let maxX = min(width - 1, Int(floor((point.x + reach) / gridCellSize)))
        let minY = max(0, Int(floor((point.y - reach) / gridCellSize)))
        let maxY = min(height - 1, Int(floor((point.y + reach) / gridCellSize)))
        guard minX <= maxX, minY <= maxY else { return }
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = (CGFloat(x) + 0.5) * gridCellSize - point.x
                let dy = (CGFloat(y) + 0.5) * gridCellSize - point.y
                let distance = hypot(dx, dy)
                guard distance <= reach else { continue }
                let areaMask = areaMask(x: x, y: y)
                let belongsToColour = areaMask.intersects(colourAreaMasks[colour.id] ?? AreaMask())
                let paper = absorption[y * width + x]
                let wave = sin(Float(x) * 0.29 + sin(Float(y) * 0.11))
                         * sin(Float(y) * 0.23 - Float(x) * 0.13)
                let edge = Float(radius) + 0.9 * wave + 0.7 * (paper - 0.5)
                let t = max(0, min(1, (edge - Float(distance)) / feather + 0.5))
                let coverage = t * t * (3 - 2 * t)
                guard coverage > 0 else { continue }
                // Water reaches the soft fringe first; pigment follows as it spreads.
                let pigmentCoverage = coverage * (0.45 + 0.55 * coverage)
                let (tile, local, _) = cell(x: x, y: y, create: true)!
                let ahead = max(0, Float((dx * direction.dx + dy * direction.dy) / radius))
                let leadingWater = 0.82 + 0.55 * min(1, ahead)
                if !belongsToColour {
                    let addedWater = water * waterDepositMultiplier * coverage * leadingWater
                    let pigmentAmount = pigment * pigmentDepositMultiplier
                        * pigmentCoverage * (1.12 - 0.35 * paper)
                    tile.spillWater[local] = min(1.5, tile.spillWater[local] + addedWater)
                    let concentration = pigmentAmount / max(addedWater, 0.001)
                    let acceptedPigment = min(pigmentAmount,
                                              max(pigmentAmount * 0.08,
                                                  concentration * tile.spillWater[local] - tile.spill[local].w))
                    tile.spill[local] += colour.pigment * acceptedPigment
                    activeSpill.insert(y * width + x)
                    markDirty(x: x, y: y, dry: false)
                    continue
                }
                let previousWater = tile.water[local]
                let addedWater = water * waterDepositMultiplier * coverage * leadingWater
                let firstRewet = paperBloom && coverage > 0.65
                    && tile.lastRewetStroke[local] != strokeID
                if previousWater + addedWater >= wetThreshold,
                   !paperBloom || firstRewet {
                    reworkRecentDry(in: tile, at: local, x: x, y: y, now: now)
                }
                if paperBloom {
                    if firstRewet {
                        // A cell releases a limited share of its old colour once
                        // per stroke; closely spaced brush samples cannot strip it.
                        tile.lastRewetStroke[local] = strokeID
                        let lifted = tile.settled[local] * 0.22
                        tile.settled[local] -= lifted
                        tile.mobile[local] += lifted
                        let liftedDry = tile.dry[local] * 0.12
                        tile.dry[local] -= liftedDry
                        tile.mobile[local] += liftedDry
                        if liftedDry.w > 0 { markDirty(x: x, y: y, dry: true) }
                    }
                } else if previousWater >= wetThreshold {
                    // A pass through the same wash loosens pigment that has not dried yet.
                    let lifted = tile.settled[local] * min(0.85, water * coverage * 3)
                    tile.settled[local] -= lifted
                    tile.mobile[local] += lifted
                }
                tile.water[local] = min(1.5, previousWater + addedWater)
                if livingFlow {
                    tile.visualWetness[local] = max(tile.visualWetness[local],
                                                    min(1, tile.water[local] / 0.35))
                }
                let brushDirection = SIMD2(Float(direction.dx), Float(direction.dy))
                if brushDirection != .zero {
                    tile.momentum[local] += addedWater * brushDirection
                        * (livingFlow ? 5.3 : paperBloom ? 3.3 : Self.brushFlowSpeed)
                    let momentum = tile.momentum[local]
                    let speed = sqrt(momentum.x * momentum.x + momentum.y * momentum.y)
                    let limit = tile.water[local]
                        * (livingFlow ? 6 : paperBloom ? 4 : Self.maximumFlowSpeed)
                    if speed > limit { tile.momentum[local] *= limit / speed }
                }
                let wetness = min(1, previousWater / 0.5)
                let pigmentAmount = pigment * pigmentDepositMultiplier
                    * pigmentCoverage * (1.12 - 0.35 * paper)
                // A wet wash accepts pigment up to the brush's concentration instead
                // of building a fresh opaque ridge on every overlapping stamp.
                let concentration = pigmentAmount / max(addedWater, 0.001)
                let wetPigment = tile.mobile[local].w + tile.settled[local].w
                    + (paperBloom ? tile.dry[local].w * 0.75 : 0)
                let acceptedPigment = min(pigmentAmount,
                                          max(pigmentAmount * (paperBloom ? 0.02 : 0.08),
                                              concentration * tile.water[local] - wetPigment))
                let fixedFraction = paperBloom
                    ? max(0.08, max(0.28, settledFraction) * (1 - wetness))
                    : settledFraction * (1 - wetness)
                tile.mobile[local] += colour.pigment * (acceptedPigment * (1 - fixedFraction))
                tile.settled[local] += colour.pigment * (acceptedPigment * fixedFraction)
                if paperBloom && coverage > 0.58 {
                    tile.bloomDepth[local] = 0
                    tile.bloomStrength[local] = max(tile.bloomStrength[local], coverage)
                    bloomFront.insert(y * width + x)
                }
                active.insert(y * width + x)
                markDirty(x: x, y: y, dry: false)
            }
        }
    }

    private func seedEddy(at point: CGPoint, direction: CGVector, colour: PaintColour,
                          now: CFTimeInterval) {
        guard direction != .zero else { return }
        let x = Int(floor(point.x / gridCellSize))
        let y = Int(floor(point.y / gridCellSize))
        guard x >= 0, x < width, y >= 0, y < height,
              areaMask(x: x, y: y).intersects(colourAreaMasks[colour.id] ?? AreaMask()),
              let (tile, local, _) = cell(x: x, y: y, create: false),
              tile.water[local] > 0.12 else { return }
        let existing = tile.mobile[local] + tile.settled[local]
        guard existing.w > 0.025 else { return }
        let colourDifference = abs(existing.x / existing.w - colour.red)
            + abs(existing.y / existing.w - colour.green)
            + abs(existing.z / existing.w - colour.blue)
        guard livingFlow || colourDifference > 0.2 else { return }
        let centre = SIMD2(Float(point.x / gridCellSize), Float(point.y / gridCellSize))
        let minimumSpacing = eddyRadius * 0.8
        guard !eddies.contains(where: { eddy in
            let offset = eddy.centre - centre
            return now - eddy.createdAt < eddyLifetime
                && offset.x * offset.x + offset.y * offset.y < minimumSpacing * minimumSpacing
        }) else { return }
        // Reverse strokes can turn the little whirlpools the other way.
        let spin: Float = direction.dx + direction.dy >= 0 ? 1 : -1
        if eddies.count >= 8 { eddies.removeFirst() }
        eddies.append(Eddy(centre: centre, spin: spin, createdAt: now))
    }

    private func eddyVelocity(x: Int, y: Int, now: CFTimeInterval) -> SIMD2<Float> {
        var velocity = SIMD2<Float>.zero
        let radiusSquared = eddyRadius * eddyRadius
        for eddy in eddies {
            let dx = Float(x) + 0.5 - eddy.centre.x
            let dy = Float(y) + 0.5 - eddy.centre.y
            if abs(dx) >= eddyRadius || abs(dy) >= eddyRadius { continue }
            let distanceSquared = dx * dx + dy * dy
            if distanceSquared >= radiusSquared { continue }
            let fade = Float(max(0, 1 - (now - eddy.createdAt) / eddyLifetime))
            let scale = eddy.spin * eddyStrength * fade
                * (1 - distanceSquared / radiusSquared) / eddyRadius
            velocity += SIMD2(-dy, dx) * scale
        }
        let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        let limit: Float = livingFlow ? 9.3 : 14
        if speed > limit { velocity *= limit / speed }
        return velocity
    }

    func step(dt: Float) {
        guard hasActivePaint else { return }
        let now = CACurrentMediaTime()
        eddies.removeAll { now - $0.createdAt >= eddyLifetime }
        for key in activeSpill {
            let x = key % width
            let y = key / width
            guard let (tile, local, _) = cell(x: x, y: y, create: false) else { continue }
            tile.spillWater[local] = max(0, tile.spillWater[local] - dt * evaporationRate)
            tile.spill[local] *= exp(-Self.outsidePigmentFadeRate * dt)
            if tile.spill[local].w < Self.visiblePigmentThreshold {
                tile.spill[local] = .zero
                tile.spillWater[local] = 0
            }
            markDirty(x: x, y: y, dry: false)
        }
        activeSpill = activeSpill.filter { key in
            let x = key % width
            let y = key / width
            guard let (tile, local, _) = cell(x: x, y: y, create: false) else { return false }
            return tile.spill[local].w > 0
        }
        var affected = active
        let current = Array(active)

        for key in current {
            let x = key % width
            let y = key / width
            guard let (tile, local, _) = cell(x: x, y: y, create: false) else { continue }
            let water = tile.water[local]
            guard water > 0 else { continue }
            let sourceAreaMask = areaMask(x: x, y: y)
            let paintable = !sourceAreaMask.isEmpty
            let paper = absorption[key]
            let paperTooth = tooth[key]
            let evaporation = min(water, dt * evaporationRate * (0.72 + 0.38 * paper))
            tile.waterDelta[local] -= evaporation
            let momentum = tile.momentum[local]
            let velocity = momentum / water + eddyVelocity(x: x, y: y, now: now)
            tile.momentumDelta[local] -= momentum * (evaporation / water)

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
            // Fix pigment gradually as the last water evaporates, so drying
            // does not move a whole mobile cell into the dry layer at once.
            let dryingProgress: Float = livingFlow
                ? max(0, min(1, (0.09 - water) / 0.08)) : 0
            let settling = paintable
                ? min(1, dt * (0.10 + 0.15 * paper + 0.27 * paperTooth
                                 + 0.18 * (1 - min(water, 1))
                                 + (livingFlow ? 0.11 : paperBloom ? 0.62
                                    : Self.edgeSettlingRate) * boundary
                                 + 5 * dryingProgress)) : 0
            let adjustedSettling = paperBloom ? min(1, settling * 1.25) : settling
            let amount = tile.mobile[local] * adjustedSettling
            tile.pigmentDelta[local] -= amount
            tile.settledDelta[local] += amount
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
                let otherIsWet = otherWater >= wetThreshold
                let gradient = max(0, water - otherWater)
                let rate: Float = livingFlow
                    ? (otherIsWet ? 1.16 + 0.22 * (1 - paper) : 1.02)
                    : paperBloom ? (otherIsWet ? 3.4 : 8.0) * wicking[ny * width + nx]
                    : (otherIsWet ? 1.7 + 0.5 * (1 - paper) : 1.3)
                let drift = max(0, velocity.x * Float(offsetX)
                                    + velocity.y * Float(offsetY))
                let flow = min(remainingWater, water * 0.42,
                               gradient * dt * rate + water * drift * dt)
                // A small transfer to dry paper evaporates immediately; avoid a dry halo.
                if !otherIsWet && flow < wetThreshold { continue }
                let otherConcentration = otherPigment / max(otherWater, 0.1)
                let mixing = otherIsWet ? dt * (livingFlow ? 1.6
                    : paperBloom ? 2.1 : Self.pigmentMixingRate)
                    * min(water, otherWater)
                    * max(0, concentration - otherConcentration) : 0
                let carried = min(remainingPigment,
                                  tile.mobile[local].w * (paperBloom ? 0.62 : 0.48),
                                  concentration * flow * 0.95 + mixing
                                  + dt * 0.2 * tile.mobile[local].w
                                  * max(0, tooth[ny * width + nx] - paperTooth)
                                  * min(1, otherWater))
                guard flow > 0.0001 || carried > 0.0001 else { continue }
                let (targetTile, targetLocal, _) = cell(x: nx, y: ny, create: true)!
                let target = ny * width + nx
                tile.waterDelta[local] -= flow
                targetTile.waterDelta[targetLocal] += flow
                let movedMomentum = momentum * (flow / water)
                tile.momentumDelta[local] -= movedMomentum
                targetTile.momentumDelta[targetLocal] += movedMomentum
                let movedPigment = tile.mobile[local] * (carried / max(tile.mobile[local].w, 0.0001))
                tile.pigmentDelta[local] -= movedPigment
                targetTile.pigmentDelta[targetLocal] += movedPigment
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
            tile.water[local] = max(0, tile.water[local] + tile.waterDelta[local])
            tile.momentum[local] = (tile.momentum[local] + tile.momentumDelta[local])
                * exp(-flowDrag * dt)
            let mobile = tile.mobile[local] + tile.pigmentDelta[local]
            tile.mobile[local] = mobile.w > 0 ? mobile : .zero
            tile.settled[local] += tile.settledDelta[local]
            tile.waterDelta[local] = 0
            tile.momentumDelta[local] = .zero
            tile.pigmentDelta[local] = .zero
            tile.settledDelta[local] = .zero
            if wasDry && tile.water[local] >= wetThreshold {
                reworkRecentDry(in: tile, at: local, x: x, y: y, now: now)
            }
            if tile.water[local] < wetThreshold {
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
                tile.momentum[local] = .zero
                if livingFlow && tile.visualWetness[local] > 0.001 {
                    visuallyDrying.insert(key)
                }
                markDirty(x: x, y: y, dry: true)
            } else {
                active.insert(key)
                if livingFlow {
                    tile.visualWetness[local] = max(tile.visualWetness[local],
                                                    min(1, tile.water[local] / 0.35))
                }
            }
            markDirty(x: x, y: y, dry: false)
        }
        if livingFlow {
            var stillDrying = Set<Int>()
            for key in visuallyDrying {
                let x = key % width
                let y = key / width
                guard let (tile, local, _) = cell(x: x, y: y, create: false) else { continue }
                guard tile.water[local] < wetThreshold else { continue }
                let current = tile.visualWetness[local]
                let target = min(1, tile.water[local] / 0.35)
                let next = target >= current ? target : max(target, current - 2.8 * dt)
                if abs(next - current) > 0.001 {
                    tile.visualWetness[local] = next
                    markDirty(x: x, y: y, dry: false)
                }
                if next > 0.001 {
                    stillDrying.insert(key)
                } else if flowerClipping && !insideDryClip(x: x, y: y) {
                    tile.recentDry[local] = .zero
                    tile.dry[local] = .zero
                    markDirty(x: x, y: y, dry: true)
                }
            }
            visuallyDrying = stillDrying
        }
        if paperBloom && !bloomFront.isEmpty {
            bloomElapsed += dt
            if bloomElapsed >= 0.055 {
                bloomElapsed = 0
                advanceBloomFront()
            }
        }
    }

    // A single front grows from the joined painted area. Its old positions
    // retain pigment, making tide lines rather than stamped circles.
    private func advanceBloomFront() {
        guard !bloomFront.isEmpty else { return }
        var nextFront = Set<Int>()
        for key in bloomFront {
            let x = key % width
            let y = key / width
            guard let (source, position, _) = cell(x: x, y: y, create: false) else { continue }
            let depth = source.bloomDepth[position]
            let strength = source.bloomStrength[position]
            guard depth < Self.bloomReach, strength > 0.1 else { continue }
            let sourcePigment = source.mobile[position] + source.settled[position]
                + source.recentDry[position] + source.dry[position]
            guard sourcePigment.w > 0.001 else { continue }
            let sourceMask = areaMask(x: x, y: y)
            for (offsetX, offsetY) in Self.bloomNeighbours {
                let nx = x + offsetX
                let ny = y + offsetY
                guard nx >= 0, nx < width, ny >= 0, ny < height,
                      areaMask(x: nx, y: ny) == sourceMask else { continue }
                let diagonal = offsetX != 0 && offsetY != 0
                let nextDepth = depth + (diagonal ? 1.41 : 1)
                guard nextDepth <= Self.bloomReach else { continue }
                let targetKey = ny * width + nx
                let (target, targetPosition, _) = cell(x: nx, y: ny, create: true)!
                guard target.bloomDepth[targetPosition] > nextDepth else { continue }
                let fibre = wicking[targetKey]
                let nextStrength = min(1, strength * (0.982 + 0.028 * (fibre - 1))
                    * (diagonal ? 0.985 : 1))
                guard nextStrength > 0.1 else { continue }
                target.bloomDepth[targetPosition] = nextDepth
                target.bloomStrength[targetPosition] = nextStrength

                // A broad wash bridges the dense brush mark and the pale fringe.
                // Tide lines build gradually farther out, rather than making
                // a hard contour immediately beside the brush.
                let phase = nextDepth * 0.72 + 2.2 * fibre
                let tide = pow(max(0, sin(phase)), 2)
                let wash = 0.085 + 0.22 * exp(-nextDepth / 28)
                let tideStrength = min(1, nextDepth / 10)
                let existingMass = target.mobile[targetPosition].w
                    + target.settled[targetPosition].w
                    + target.recentDry[targetPosition].w
                    + target.dry[targetPosition].w
                // An overlapping front travels through existing colour without
                // erasing it or printing a second set of tide lines on top.
                let refill = max(0, min(1, (0.3 - existingMass) / 0.3))
                let outerFade = min(1, max(0, (Self.bloomReach - nextDepth) / 7))
                let mass = nextStrength * (wash + 0.14 * tide * tideStrength)
                    * refill * outerFade
                let separation = (nextDepth - depth) / Self.bloomReach
                let colour = Pigment(min(1, sourcePigment.x / sourcePigment.w
                                            + 0.16 * separation),
                                     max(0, sourcePigment.y / sourcePigment.w
                                            - 0.07 * separation),
                                     min(1, sourcePigment.z / sourcePigment.w
                                            + 0.06 * separation), 1)
                if mass > 0.001 {
                    target.settled[targetPosition] += colour * mass * 0.78
                    target.mobile[targetPosition] += colour * mass * 0.22
                    target.water[targetPosition] = max(target.water[targetPosition],
                                                        0.025 * nextStrength)
                    active.insert(targetKey)
                    markDirty(x: nx, y: ny, dry: false)
                }
                nextFront.insert(targetKey)
            }
        }
        bloomFront = nextFront
    }

    private func reworkRecentDry(in tile: Tile, at local: Int, x: Int, y: Int,
                                 now: CFTimeInterval) {
        let pigment = tile.recentDry[local]
        guard pigment.w > 0 else { return }
        if now - tile.driedAt[local] <= Self.reworkWindow {
            if livingFlow {
                guard tile.lastRewetStroke[local] != strokeID else { return }
                tile.lastRewetStroke[local] = strokeID
            }
            let lifted = pigment * (livingFlow ? 0.3 : paperBloom ? 0.24 : 1)
            tile.mobile[local] += lifted
            tile.recentDry[local] -= lifted
            markDirty(x: x, y: y, dry: true)
        } else {
            tile.dry[local] += pigment
            tile.recentDry[local] = .zero
        }
    }

    func renderDirtyTiles() {
        if optimizedFluidCanvas {
            for key in dirtyTiles.union(dirtyDryTiles) {
                guard let tile = tiles[key] else { continue }
                tile.wetLayer.contents = image(for: tile, tileKey: key, wet: true)
            }
            dirtyDryTiles.removeAll(keepingCapacity: true)
            dirtyTiles.removeAll(keepingCapacity: true)
            return
        }
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
        // The blank painting study can shade at the simulation grid's resolution;
        // Core Animation interpolates it over the full-resolution paper texture.
        let samplesPerCell = optimizedFluidCanvas ? 1 : Self.pixelsPerCell
        let unifiedPaint = optimizedFluidCanvas
        let pointScale = Int(gridCellSize) / samplesPerCell
        let imageWidth = tile.width * samplesPerCell
        let imageHeight = tile.height * samplesPerCell
        var pixels = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        let originX = (tileKey % tilesAcross) * Self.tileSide
        let originY = (tileKey / tilesAcross) * Self.tileSide
        let paddedWidth = tile.width + 2
        var massField = [Pigment](repeating: .zero, count: paddedWidth * (tile.height + 2))
        var settledField = [Float](repeating: 0, count: massField.count)
        var waterField = [Float](repeating: 0, count: massField.count)
        var spillField = [Pigment](repeating: .zero, count: massField.count)
        var spillWaterField = [Float](repeating: 0, count: massField.count)
        var ownerField = [AreaMask](repeating: AreaMask(), count: massField.count)
        for y in -1...tile.height {
            for x in -1...tile.width {
                let sheetX = originX + x
                let sheetY = originY + y
                guard sheetX >= 0, sheetX < width, sheetY >= 0, sheetY < height else { continue }
                let position = (y + 1) * paddedWidth + x + 1
                ownerField[position] = areaMask(x: sheetX, y: sheetY)
                guard let (sampleTile, local, _) = cell(x: sheetX, y: sheetY, create: false) else { continue }
                if unifiedPaint {
                    massField[position] = sampleTile.mobile[local]
                        + sampleTile.settled[local] + sampleTile.recentDry[local]
                        + sampleTile.dry[local]
                    waterField[position] = sampleTile.visualWetness[local]
                } else {
                    let dilution = 1 - (paperBloom ? 0.12 : 0.32)
                        * min(1, sampleTile.water[local])
                    let settled = wet ? sampleTile.settled[local]
                        : sampleTile.dry[local] + sampleTile.recentDry[local]
                    let mobile: Pigment = wet ? sampleTile.mobile[local] * dilution : .zero
                    massField[position] = mobile + settled
                    settledField[position] = settled.w
                    waterField[position] = sampleTile.water[local]
                }
                if wet {
                    spillField[position] = sampleTile.spill[local]
                    spillWaterField[position] = sampleTile.spillWater[local]
                }
            }
        }

        for y in 0..<imageHeight {
            let sourceY = (Float(y) + 0.5) / Float(samplesPerCell) - 0.5
            let y0 = Int(floor(sourceY))
            let fy = sourceY - Float(y0)
            for x in 0..<imageWidth {
                let sourceX = (Float(x) + 0.5) / Float(samplesPerCell) - 0.5
                let x0 = Int(floor(sourceX))
                let fx = sourceX - Float(x0)
                let topLeft = (y0 + 1) * paddedWidth + x0 + 1
                let topRight = topLeft + 1
                let bottomLeft = topLeft + paddedWidth
                let bottomRight = bottomLeft + 1
                let sheetX = (originX * samplesPerCell + x) * pointScale
                    + pointScale / 2
                let sheetY = (originY * samplesPerCell + y) * pointScale
                    + pointScale / 2
                guard sheetX < paperWidth, sheetY < paperHeight else { continue }
                let owner = blankPaper ? 0 : pixelAreaIndex(x: sheetX, y: sheetY)
                if !wet && owner == -1 { continue }
                var topLeftMatches = true
                var topRightMatches = true
                var bottomLeftMatches = true
                var bottomRightMatches = true
                if !blankPaper {
                    var ownerBit = AreaMask()
                    if owner >= 0 { ownerBit.insert(template.paintableAreas[owner].maskIndex) }
                    topLeftMatches = owner == -1 ? ownerField[topLeft].isEmpty
                        : ownerField[topLeft].intersects(ownerBit)
                    topRightMatches = owner == -1 ? ownerField[topRight].isEmpty
                        : ownerField[topRight].intersects(ownerBit)
                    bottomLeftMatches = owner == -1 ? ownerField[bottomLeft].isEmpty
                        : ownerField[bottomLeft].intersects(ownerBit)
                    bottomRightMatches = owner == -1 ? ownerField[bottomRight].isEmpty
                        : ownerField[bottomRight].intersects(ownerBit)
                }
                let topMass = (topLeftMatches ? massField[topLeft] : .zero) * (1 - fx)
                    + (topRightMatches ? massField[topRight] : .zero) * fx
                let bottomMass = (bottomLeftMatches ? massField[bottomLeft] : .zero) * (1 - fx)
                    + (bottomRightMatches ? massField[bottomRight] : .zero) * fx
                let mass = topMass * (1 - fy) + bottomMass * fy
                let topSpill = spillField[topLeft] * (1 - fx) + spillField[topRight] * fx
                let bottomSpill = spillField[bottomLeft] * (1 - fx) + spillField[bottomRight] * fx
                let spill = topSpill * (1 - fy) + bottomSpill * fy
                guard mass.w > 0 || spill.w > 0 else { continue }
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
                var nativeOpacity: Float = 0
                var nativeRed: Float = 0
                var nativeGreen: Float = 0
                var nativeBlue: Float = 0
                if mass.w > 0 {
                    let sheen: Float
                    if unifiedPaint {
                        // All pigment stays visible while only its surface changes.
                        // The visual wetness is interpolated across grid cells.
                        let wetTexture = 0.9 + 0.12 * paper
                        let dryTexture = 0.72 + 0.55 * paper
                        let texture = dryTexture + (wetTexture - dryTexture) * water
                        nativeOpacity = min(0.93, 1 - exp(-2.0 * mass.w
                            * (1 - 0.18 * water) * texture))
                        if let clipMask = template.dryClipMask {
                            let inside = Float(clipMask[sheetY * paperWidth + sheetX]) / 255
                            let outsideVisibility = pow(max(0, min(1, water)), 0.45)
                            nativeOpacity *= inside + (1 - inside) * outsideVisibility
                        }
                        sheen = water
                    } else {
                        // Mobile paint reads as a smooth wash; paper tooth appears as it settles.
                        let wash = max(0, mass.w - settled) * (0.9 + 0.12 * paper)
                        let granulated = settled * (0.72 + 0.55 * paper)
                        nativeOpacity = min(0.93, 1 - exp(-2.0 * (wash + granulated)))
                        sheen = wet ? min(1, water) : 0
                    }
                    nativeRed = min(1, mass.x / mass.w + 0.07 * sheen)
                    nativeGreen = min(1, mass.y / mass.w + 0.09 * sheen)
                    nativeBlue = min(1, mass.z / mass.w + 0.05 * sheen)
                }
                let spillOpacity = min(0.93, 1 - exp(-2.0 * spill.w * (0.9 + 0.12 * paper)))
                let spillSheen = min(1, (spillWaterField[topLeft] * (1 - fx)
                    + spillWaterField[topRight] * fx) * (1 - fy)
                    + (spillWaterField[bottomLeft] * (1 - fx)
                    + spillWaterField[bottomRight] * fx) * fy)
                let remaining = 1 - spillOpacity
                let opacity = spillOpacity + nativeOpacity * remaining
                let red = (spill.w > 0 ? min(1, spill.x / spill.w + 0.07 * spillSheen) * spillOpacity : 0)
                    + nativeRed * nativeOpacity * remaining
                let green = (spill.w > 0 ? min(1, spill.y / spill.w + 0.09 * spillSheen) * spillOpacity : 0)
                    + nativeGreen * nativeOpacity * remaining
                let blue = (spill.w > 0 ? min(1, spill.z / spill.w + 0.05 * spillSheen) * spillOpacity : 0)
                    + nativeBlue * nativeOpacity * remaining
                let base = (y * imageWidth + x) * 4
                pixels[base] = UInt8(clamping: Int(255 * red))
                pixels[base + 1] = UInt8(clamping: Int(255 * green))
                pixels[base + 2] = UInt8(clamping: Int(255 * blue))
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

    private func insideDryClip(x: Int, y: Int) -> Bool {
        guard let clipMask = template.dryClipMask else { return true }
        let side = Int(gridCellSize)
        for offsetY in 0..<side {
            let paperY = y * side + offsetY
            guard paperY < paperHeight else { continue }
            for offsetX in 0..<side {
                let paperX = x * side + offsetX
                if paperX < paperWidth,
                   clipMask[paperY * paperWidth + paperX] >= 64 { return true }
            }
        }
        return false
    }

    private func areaMask(x: Int, y: Int) -> AreaMask {
        if blankPaper { return AreaMask(low: 1) }
        let index = y * width + x
        if let cached = cellAreaMasks[index] { return cached }
        var mask = AreaMask()
        let pointsPerCell = Int(gridCellSize)
        for pixelY in 0..<pointsPerCell {
            for pixelX in 0..<pointsPerCell {
                let sheetX = x * pointsPerCell + pixelX
                let sheetY = y * pointsPerCell + pixelY
                guard sheetX < paperWidth, sheetY < paperHeight else { continue }
                let owner = pixelAreaIndex(x: sheetX, y: sheetY)
                if owner >= 0 { mask.insert(template.paintableAreas[owner].maskIndex) }
            }
        }
        cellAreaMasks[index] = mask
        return mask
    }

    private func pixelAreaIndex(x: Int, y: Int) -> Int {
        Int(template.owners[y * paperWidth + x]) - 1
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
            let frame = CGRect(x: CGFloat(tileX * Self.tileSide) * gridCellSize,
                               y: CGFloat(tileY * Self.tileSide) * gridCellSize,
                               width: CGFloat(tileWidth) * gridCellSize,
                               height: CGFloat(tileHeight) * gridCellSize)
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
                                       paperWidth: Int, cellSize: Int) -> [Float] {
        return (0..<(width * height)).map { index in
            let x = Float(index % width)
            let y = Float(index / width)
            let paperX = min(paperWidth - 1, Int(x) * cellSize)
            let paperY = Int(y) * cellSize
            let tone = Float(grain[paperY * paperWidth + paperX]) / 255
            let broad = sin(x * 0.035 + y * 0.012) * sin(y * 0.041 - x * 0.015)
            return max(0, min(1, 0.5 + (0.5 - tone) * 0.45 + broad * 0.2))
        }
    }

    private static func makeTooth(width: Int, height: Int, grain: [UInt8],
                                  paperWidth: Int, cellSize: Int) -> [Float] {
        let paperHeight = grain.count / paperWidth
        return (0..<(width * height)).map { index in
            let x = min(paperWidth - 1, index % width * cellSize)
            let y = min(paperHeight - 1, index / width * cellSize)
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
