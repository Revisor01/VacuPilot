import Foundation

struct RobotMap: Codable {
    let size: MapSize?
    let pixelSize: Int?
    let layers: [MapLayer]?
    let entities: [MapEntity]?
}

struct MapSize: Codable {
    let x: Int
    let y: Int
}

/// Cache class for MapLayer pixel decompression.
/// Using a class (reference type) allows caching on structs passed as `let` in SwiftUI Canvas closures,
/// where `lazy var` (mutating) would not compile.
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

    /// Returns decompressed pixels - cached via MapLayerCache to avoid recomputation per frame.
    /// Cache is naturally invalidated when new map data arrives (new MapLayer instances = fresh cache).
    var decompressedPixels: [Int] {
        cache.decompressedPixels(from: self)
    }

    /// Computes decompressed pixels from raw data. Called only by MapLayerCache on first access.
    /// Valetudo uses run-length encoding: [x1, y1, count1, x2, y2, count2, ...]
    /// Each entry means: starting at (x,y), draw 'count' pixels horizontally.
    fileprivate func computeDecompressedPixels() -> [Int] {
        // If regular pixels exist, use them
        if let pixels = pixels, !pixels.isEmpty {
            return pixels
        }

        // Otherwise decompress
        guard let compressed = compressedPixels, !compressed.isEmpty else {
            return []
        }

        var result: [Int] = []
        var i = 0

        while i < compressed.count - 2 {
            let x = compressed[i]
            let y = compressed[i + 1]
            let count = compressed[i + 2]

            // Generate pixels for this run
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

    /// Anzeigename für einen Materialwert der Firmware. Unbekannte Werte, wie sie
    /// neuere Firmware liefern kann, werden lesbar aufbereitet statt verworfen —
    /// aus `carpet_extra_high` wird so "Carpet extra high".
    static func displayName(for rawValue: String) -> String {
        if let known = FloorMaterial(rawValue: rawValue) {
            return known.displayName
        }
        return rawValue
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }

    /// Symbol für einen Materialwert der Firmware, mit neutralem Rückfallwert
    /// für unbekannte Werte.
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
    let id: String?       // UUID fuer ObstacleImagesCapability/img/{id}
    let label: String?    // z.B. "Pedestal (89%)"
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
    // Map annotations, added in firmware 2026.07.0. These are plain map
    // entities like the ones above, not a separate kind of object.
    case threshold
    case curtain
    case ramp
}

// MARK: - Map Annotations

/// Kinds of map annotation. Which ones a robot accepts is reported by
/// `MapAnnotationsCapability/properties`.
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

/// A map annotation as the app works with it.
///
/// Note the asymmetry in the firmware API: annotations are *read* from the map
/// entities as a flat `[x, y, x, y, …]` array, but *written* back as an array
/// of `{x, y}` objects. `init(entity:)` handles the former, `points` the latter.
struct MapAnnotation: Identifiable, Equatable {
    var id = UUID()
    var type: MapAnnotationType
    var points: [ZonePoint]

    init(type: MapAnnotationType, points: [ZonePoint]) {
        self.type = type
        self.points = points
    }

    /// Builds an annotation from a map entity, or returns nil if the entity is
    /// not an annotation or carries an unusable number of coordinates.
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

/// Request body for `PUT …/MapAnnotationsCapability`.
///
/// The endpoint replaces the entire set, so every annotation that should
/// survive has to be part of the request.
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
