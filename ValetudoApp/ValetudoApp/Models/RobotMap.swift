import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valetudio", category: "RobotMap")

struct RobotMap: Codable {
    let size: MapSize?
    let pixelSize: Int?
    let layers: [MapLayer]?
    let entities: [MapEntity]?

    enum CodingKeys: String, CodingKey {
        case size, pixelSize, layers, entities
    }
}

// Declared in an extension so the memberwise initializer stays available.
extension RobotMap {
    /// Decodes layers and entities one by one, so one unreadable element does not empty the whole map.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(MapSize.self, forKey: .size)
        pixelSize = try container.decodeIfPresent(Int.self, forKey: .pixelSize)
        layers = try container.decodeSkippingUnreadable([MapLayer].self, forKey: .layers)
        entities = try container.decodeSkippingUnreadable([MapEntity].self, forKey: .entities)
    }
}

private extension KeyedDecodingContainer {
    /// Like `decodeIfPresent` for an array, but drops elements that fail to decode.
    func decodeSkippingUnreadable<Element: Decodable>(_ type: [Element].Type, forKey key: Key) throws -> [Element]? {
        guard let elements = try decodeIfPresent([SkippableElement<Element>].self, forKey: key) else {
            return nil
        }
        return elements.compactMap { element in
            switch element.result {
            case .success(let value):
                return value
            case .failure(let error):
                logger.warning("Skipped unreadable map element in \(key.stringValue, privacy: .public): \(error, privacy: .public)")
                return nil
            }
        }
    }
}

/// One array element, decoded without throwing so the surrounding array still decodes.
private struct SkippableElement<Element: Decodable>: Decodable {
    let result: Result<Element, Error>

    init(from decoder: Decoder) throws {
        result = Result { try decoder.singleValueContainer().decode(Element.self) }
    }
}

struct MapSize: Codable {
    let x: Int
    let y: Int
}

/// Pixel cache as a class, because `lazy var` does not compile on structs used in Canvas closures.
final class MapLayerCache {
    private var cachedPixels: [Int]?

    func decompressedPixels(from layer: MapLayer) -> [Int] {
        if let cached = cachedPixels { return cached }
        let result = layer.computeDecompressedPixels()
        cachedPixels = result
        return result
    }

    func invalidate() { cachedPixels = nil }
}

struct MapLayer: Codable {
    let `__class`: String?
    let type: String?
    let pixels: [Int]?
    let compressedPixels: [Int]?
    let metaData: LayerMetaData?
    let dimensions: LayerDimensions?
    let cache = MapLayerCache()

    enum CodingKeys: String, CodingKey {
        case `__class`, type, pixels, compressedPixels, metaData, dimensions
    }

    /// Decompressed pixels, cached per MapLayer instance.
    var decompressedPixels: [Int] {
        cache.decompressedPixels(from: self)
    }

    /// Decodes Valetudo's run-length encoding `[x, y, count, …]` into horizontal pixel runs.
    fileprivate func computeDecompressedPixels() -> [Int] {
        if let pixels = pixels, !pixels.isEmpty {
            return pixels
        }

        guard let compressed = compressedPixels, !compressed.isEmpty else {
            return []
        }

        var result: [Int] = []
        var i = 0

        while i < compressed.count - 2 {
            let x = compressed[i]
            let y = compressed[i + 1]
            let count = compressed[i + 2]

            for offset in 0..<count {
                result.append(x + offset)
                result.append(y)
            }

            i += 3
        }

        return result
    }
}

struct LayerMetaData: Codable {
    let segmentId: String?
    let name: String?
    let active: Bool?
    let material: String?  // Floor material, see FloorMaterial
}

// MARK: - Floor Material Types
enum FloorMaterial: String, CaseIterable, Codable {
    case generic = "generic"
    case tile = "tile"
    case wood = "wood"
    case woodHorizontal = "wood_horizontal"
    case woodVertical = "wood_vertical"
    case carpet = "carpet"
    case carpetLow = "carpet_low"
    case carpetHigh = "carpet_high"

    var displayName: String {
        switch self {
        case .generic: return String(localized: "material.generic")
        case .tile: return String(localized: "material.tile")
        case .wood: return String(localized: "material.wood")
        case .woodHorizontal: return String(localized: "material.wood_horizontal")
        case .woodVertical: return String(localized: "material.wood_vertical")
        case .carpet: return String(localized: "material.carpet")
        case .carpetLow: return String(localized: "material.carpet_low")
        case .carpetHigh: return String(localized: "material.carpet_high")
        }
    }

    var icon: String {
        switch self {
        case .generic: return "square.fill"
        case .tile: return "square.grid.2x2.fill"
        case .wood: return "line.3.horizontal"
        case .woodHorizontal: return "line.3.horizontal"
        case .woodVertical: return "line.3.horizontal"
        case .carpet, .carpetLow, .carpetHigh: return "square.grid.3x3.fill"
        }
    }

    /// Display name for a firmware material; unknown values are made readable instead of dropped.
    static func displayName(for rawValue: String) -> String {
        if let known = FloorMaterial(rawValue: rawValue) {
            return known.displayName
        }
        return rawValue
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }

    /// Symbol for a firmware material, with a neutral fallback.
    static func icon(for rawValue: String) -> String {
        FloorMaterial(rawValue: rawValue)?.icon ?? "square.fill"
    }
}

struct LayerDimensions: Codable {
    let x: DimensionRange?
    let y: DimensionRange?
}

struct DimensionRange: Codable {
    let min: Int?
    let max: Int?
    let mid: Int?
}

struct MapEntity: Codable {
    let `__class`: String?
    let type: String?
    let points: [Int]?
    let metaData: EntityMetaData?

    enum CodingKeys: String, CodingKey {
        case `__class`, type, points, metaData
    }
}

struct EntityMetaData: Codable {
    let angle: Int?
    let id: String?       // UUID fuer ObstacleImagesCapability/img/{id}, bei Teppichen deren Nummer
    let label: String?    // z.B. "Pedestal (89%)"

    enum CodingKeys: String, CodingKey {
        case angle, id, label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.angle = try container.decodeIfPresent(Int.self, forKey: .angle)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        
        // Die Fehlerquelle (id) abfangen: Erst String probieren, dann Int
        if let stringId = try? container.decodeIfPresent(String.self, forKey: .id) {
            self.id = stringId
        } else if let intId = try? container.decodeIfPresent(Int.self, forKey: .id) {
            self.id = String(intId)
        } else {
            self.id = nil
        }
    }
}

// MARK: - Map Layer Types
enum MapLayerType: String {
    case floor, wall, segment
}

// MARK: - Map Entity Types
enum MapEntityType: String {
    case robotPosition = "robot_position"
    case chargerLocation = "charger_location"
    case path
    case predictedPath = "predicted_path"
    case virtualWall = "virtual_wall"
    case noGoArea = "no_go_area"
    case noMopArea = "no_mop_area"
    case goToTarget = "go_to_target"
    case activeZone = "active_zone"
    case obstacle
    // Map annotations (firmware 2026.07.0) are plain map entities.
    case threshold
    case curtain
    case ramp
}

// MARK: - Obstacles

extension RobotMap {
    /// Recognized obstacles with their photo id; only `obstacle` entities count, carpets carry an id too.
    var obstacles: [(id: String, label: String?)] {
        (entities ?? []).compactMap { entity in
            guard entity.type == MapEntityType.obstacle.rawValue,
                  let id = entity.metaData?.id else { return nil }
            return (id: id, label: entity.metaData?.label)
        }
    }
}

// MARK: - Map Annotations

/// Kinds of map annotation; a robot reports the accepted ones in `MapAnnotationsCapability/properties`.
enum MapAnnotationType: String, CaseIterable, Codable {
    case threshold
    case curtain
    case ramp

    var displayName: String {
        switch self {
        case .threshold: return String(localized: "annotation.threshold")
        case .curtain: return String(localized: "annotation.curtain")
        case .ramp: return String(localized: "annotation.ramp")
        }
    }

    var icon: String {
        switch self {
        case .threshold: return "rectangle.split.3x1"
        case .curtain: return "curtains.closed"
        case .ramp: return "triangle"
        }
    }

    /// Thresholds and curtains are lines (2 points), ramps are quads (4 points).
    var pointCount: Int {
        self == .ramp ? 4 : 2
    }
}

/// A map annotation; read as a flat `[x, y, …]` array, written back as `{x, y}` objects.
struct MapAnnotation: Identifiable, Equatable {
    var id = UUID()
    var type: MapAnnotationType
    var points: [ZonePoint]

    init(type: MapAnnotationType, points: [ZonePoint]) {
        self.type = type
        self.points = points
    }

    /// Builds an annotation from a map entity, or nil if it is none or has unusable coordinates.
    init?(entity: MapEntity) {
        guard let rawType = entity.type,
              let type = MapAnnotationType(rawValue: rawType),
              let coords = entity.points,
              coords.count == type.pointCount * 2 else {
            return nil
        }

        self.type = type
        self.points = stride(from: 0, to: coords.count, by: 2).map {
            ZonePoint(x: coords[$0], y: coords[$0 + 1])
        }
    }
}

/// Request body for `PUT …/MapAnnotationsCapability`, which replaces the entire set.
struct MapAnnotationRequest: Codable {
    let type: String
    let points: [ZonePoint]

    init(_ annotation: MapAnnotation) {
        self.type = annotation.type.rawValue
        self.points = annotation.points
    }
}

struct MapAnnotationsProperties: Codable {
    let supportedAnnotationTypes: [String]

    var supportedTypes: [MapAnnotationType] {
        supportedAnnotationTypes.compactMap { MapAnnotationType(rawValue: $0) }
    }
}
