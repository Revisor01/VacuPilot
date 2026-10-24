import XCTest
@testable import ValetudoApp

final class MapLayerTests: XCTestCase {

    // MARK: - Helpers

    private func makeLayer(json: String) throws -> MapLayer {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(MapLayer.self, from: data)
    }

    // MARK: - decompressedPixels

    func testDecompressEmptyCompressedPixels() throws {
        let layer = try makeLayer(json: #"{"compressedPixels": []}"#)
        XCTAssertEqual(layer.decompressedPixels, [])
    }

    func testDecompressSingleRun() throws {
        // [5, 10, 3] means: starting at (5, 10), draw 3 horizontal pixels
        // => (5,10), (6,10), (7,10) = [5, 10, 6, 10, 7, 10]
        let layer = try makeLayer(json: #"{"compressedPixels": [5, 10, 3]}"#)
        XCTAssertEqual(layer.decompressedPixels, [5, 10, 6, 10, 7, 10])
    }

    func testDecompressMultipleRuns() throws {
        // [0, 0, 2, 10, 5, 1]
        // Run 1: (0,0) count=2 => (0,0),(1,0) = [0,0,1,0]
        // Run 2: (10,5) count=1 => (10,5) = [10,5]
        let layer = try makeLayer(json: #"{"compressedPixels": [0, 0, 2, 10, 5, 1]}"#)
        XCTAssertEqual(layer.decompressedPixels, [0, 0, 1, 0, 10, 5])
    }

    func testPlainPixelsUsedWhenAvailable() throws {
        // When pixels is set, it takes priority over compressedPixels
        let layer = try makeLayer(json: #"{"pixels": [1, 2, 3, 4], "compressedPixels": [99, 99, 1]}"#)
        XCTAssertEqual(layer.decompressedPixels, [1, 2, 3, 4])
    }

    func testDecompressNilCompressedPixels() throws {
        // No compressedPixels and no pixels: should return []
        let layer = try makeLayer(json: #"{}"#)
        XCTAssertEqual(layer.decompressedPixels, [])
    }

    func testDecompressSinglePixel() throws {
        // [3, 7, 1] => (3,7) = [3, 7]
        let layer = try makeLayer(json: #"{"compressedPixels": [3, 7, 1]}"#)
        XCTAssertEqual(layer.decompressedPixels, [3, 7])
    }

    // MARK: - FloorMaterial

    func testCarpetMaterialsAreKnown() {
        // Carpet variants were added to the firmware in 2026.07.0
        XCTAssertEqual(FloorMaterial(rawValue: "carpet"), .carpet)
        XCTAssertEqual(FloorMaterial(rawValue: "carpet_low"), .carpetLow)
        XCTAssertEqual(FloorMaterial(rawValue: "carpet_high"), .carpetHigh)
    }

    func testKnownMaterialUsesLocalizedName() {
        // A known value must never fall through to the humanized raw value
        XCTAssertEqual(FloorMaterial.displayName(for: "carpet"), FloorMaterial.carpet.displayName)
        XCTAssertEqual(FloorMaterial.displayName(for: "wood_horizontal"), FloorMaterial.woodHorizontal.displayName)
    }

    func testUnknownMaterialIsHumanizedRatherThanDropped() {
        // Newer firmware may introduce materials this build has never seen.
        // They must stay visible instead of vanishing from the UI.
        XCTAssertEqual(FloorMaterial.displayName(for: "carpet_extra_high"), "Carpet Extra High")
        XCTAssertEqual(FloorMaterial.displayName(for: "linoleum"), "Linoleum")
    }

    func testUnknownMaterialFallsBackToNeutralIcon() {
        XCTAssertEqual(FloorMaterial.icon(for: "linoleum"), "square.fill")
        XCTAssertEqual(FloorMaterial.icon(for: "carpet"), FloorMaterial.carpet.icon)
    }

    // MARK: - Map Annotations

    private func makeEntity(json: String) throws -> MapEntity {
        try JSONDecoder().decode(MapEntity.self, from: json.data(using: .utf8)!)
    }

    func testThresholdParsesFromFlatPointArray() throws {
        // Annotations arrive as regular map entities with a flat [x,y,x,y] array
        let entity = try makeEntity(json: #"{"__class": "LineMapEntity", "type": "threshold", "points": [100, 200, 300, 400]}"#)
        let annotation = MapAnnotation(entity: entity)

        XCTAssertEqual(annotation?.type, .threshold)
        XCTAssertEqual(annotation?.points, [ZonePoint(x: 100, y: 200), ZonePoint(x: 300, y: 400)])
    }

    func testRampParsesFourCorners() throws {
        let entity = try makeEntity(json: #"{"__class": "PolygonMapEntity", "type": "ramp", "points": [10, 20, 30, 20, 30, 40, 10, 40]}"#)
        let annotation = MapAnnotation(entity: entity)

        XCTAssertEqual(annotation?.type, .ramp)
        XCTAssertEqual(annotation?.points.count, 4)
        XCTAssertEqual(annotation?.points.last, ZonePoint(x: 10, y: 40))
    }

    func testNonAnnotationEntityIsIgnored() throws {
        // virtual_wall has the same shape but is not an annotation
        let entity = try makeEntity(json: #"{"__class": "LineMapEntity", "type": "virtual_wall", "points": [1, 2, 3, 4]}"#)
        XCTAssertNil(MapAnnotation(entity: entity))
    }

    func testAnnotationWithWrongPointCountIsRejected() throws {
        // A ramp needs 4 points; 2 would silently render as a broken shape
        let entity = try makeEntity(json: #"{"__class": "PolygonMapEntity", "type": "ramp", "points": [1, 2, 3, 4]}"#)
        XCTAssertNil(MapAnnotation(entity: entity))

        let truncated = try makeEntity(json: #"{"__class": "LineMapEntity", "type": "curtain", "points": [1, 2, 3]}"#)
        XCTAssertNil(MapAnnotation(entity: truncated))
    }

    func testAnnotationEncodesAsObjectPoints() throws {
        // Writing uses {x, y} objects, not the flat array used for reading
        let annotation = MapAnnotation(type: .curtain, points: [ZonePoint(x: 5, y: 6), ZonePoint(x: 7, y: 8)])
        let data = try JSONEncoder().encode([MapAnnotationRequest(annotation)])
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        XCTAssertEqual(decoded?.count, 1)
        XCTAssertEqual(decoded?.first?["type"] as? String, "curtain")
        let points = decoded?.first?["points"] as? [[String: Any]]
        XCTAssertEqual(points?.count, 2)
        XCTAssertEqual(points?.first?["x"] as? Int, 5)
        XCTAssertEqual(points?.first?["y"] as? Int, 6)
    }

    func testUnsupportedAnnotationTypeIsDroppedFromProperties() throws {
        // A firmware newer than this build may report kinds we cannot draw
        let json = #"{"supportedAnnotationTypes": ["threshold", "skylight", "ramp"]}"#
        let props = try JSONDecoder().decode(MapAnnotationsProperties.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(props.supportedTypes, [.threshold, .ramp])
    }

    func testUnknownMaterialDecodesWithoutFailing() throws {
        // metaData.material is a free-form String, so an unknown value must not
        // break decoding of the whole layer.
        let layer = try makeLayer(json: #"{"compressedPixels": [1, 1, 1], "metaData": {"material": "carpet_extra_high"}}"#)
        XCTAssertEqual(layer.metaData?.material, "carpet_extra_high")
        XCTAssertEqual(layer.decompressedPixels, [1, 1])
    }

    // MARK: - Map Decoding

    private func makeMap(json: String) throws -> RobotMap {
        try JSONDecoder().decode(RobotMap.self, from: json.data(using: .utf8)!)
    }

    /// Reduced map of a Eureka J15 Pro Ultra (Midea, firmware 2026.10.0), see
    /// PR #4. Midea sends the carpet id as a number, which used to fail
    /// decoding and leave the whole map empty.
    private let mideaMapWithCarpet = #"""
    {
      "__class": "ValetudoMap",
      "size": {"x": 1000, "y": 1000},
      "pixelSize": 5,
      "layers": [
        {"__class": "MapLayer", "type": "segment", "compressedPixels": [10, 10, 3],
         "metaData": {"segmentId": "1", "name": "Living room", "active": false, "area": 75}}
      ],
      "entities": [
        {"__class": "PointMapEntity", "type": "robot_position", "points": [60, 60], "metaData": {"angle": 90}},
        {"__class": "PolygonMapEntity", "type": "carpet", "points": [100, 100, 130, 100, 130, 130, 100, 130], "metaData": {"id": 1}}
      ]
    }
    """#

    func testMapWithNumericCarpetIdDecodes() throws {
        let map = try makeMap(json: mideaMapWithCarpet)

        XCTAssertEqual(map.layers?.count, 1)
        XCTAssertEqual(map.entities?.map { $0.type }, ["robot_position", "carpet"])
        XCTAssertEqual(map.entities?.last?.metaData?.id, "1")
    }

    func testTextCarpetIdDecodes() throws {
        // Dreame sends the same carpet id as text
        let entity = try makeEntity(json: #"{"__class": "PolygonMapEntity", "type": "carpet", "points": [1, 2, 3, 2, 3, 4, 1, 4], "metaData": {"id": "1"}}"#)
        XCTAssertEqual(entity.metaData?.id, "1")
    }

    func testUnreadableEntityIsSkippedInsteadOfEmptyingMap() throws {
        // A value of unexpected type must only cost the entity it belongs to
        let map = try makeMap(json: #"""
        {"pixelSize": 5, "layers": [], "entities": [
          {"type": "robot_position", "points": [60, 60], "metaData": {"angle": 90}},
          {"type": "charger_location", "points": [10, 10], "metaData": {"angle": "north"}}
        ]}
        """#)

        XCTAssertEqual(map.pixelSize, 5)
        XCTAssertEqual(map.entities?.map { $0.type }, ["robot_position"])
    }

    func testUnreadableLayerIsSkippedInsteadOfEmptyingMap() throws {
        let map = try makeMap(json: #"""
        {"pixelSize": 5, "entities": [], "layers": [
          {"type": "floor", "compressedPixels": [1, 1, 2]},
          {"type": "segment", "compressedPixels": "unexpected", "metaData": {"segmentId": "2"}}
        ]}
        """#)

        XCTAssertEqual(map.layers?.map { $0.type }, ["floor"])
        XCTAssertEqual(map.layers?.first?.decompressedPixels, [1, 1, 2, 1])
    }

    func testObstaclesLeaveOutCarpets() throws {
        // Carpets carry an id too, but only obstacles have a photo behind it
        let map = try makeMap(json: #"""
        {"entities": [
          {"type": "obstacle", "points": [50, 50], "metaData": {"id": "6f0c1b9e-1d1b-5c51-9d0a-2f6b8c3e4a10", "label": "Pedestal (89%)"}},
          {"type": "carpet", "points": [100, 100, 130, 100, 130, 130, 100, 130], "metaData": {"id": 1}},
          {"type": "carpet", "points": [200, 200, 230, 200, 230, 230, 200, 230], "metaData": {"id": "2"}}
        ]}
        """#)

        XCTAssertEqual(map.obstacles.map { $0.id }, ["6f0c1b9e-1d1b-5c51-9d0a-2f6b8c3e4a10"])
        XCTAssertEqual(map.obstacles.first?.label, "Pedestal (89%)")
    }

    func testMapWithCarpetSurvivesCacheRoundTrip() throws {
        // MapCacheService writes the decoded map to disk and reads it back
        let map = try makeMap(json: mideaMapWithCarpet)
        let cached = try JSONDecoder().decode(RobotMap.self, from: JSONEncoder().encode(map))

        XCTAssertEqual(cached.entities?.count, 2)
        XCTAssertEqual(cached.entities?.last?.metaData?.id, "1")
    }
}
