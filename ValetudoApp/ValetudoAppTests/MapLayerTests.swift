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

    func testUnknownMaterialDecodesWithoutFailing() throws {
        // metaData.material is a free-form String, so an unknown value must not
        // break decoding of the whole layer.
        let layer = try makeLayer(json: #"{"compressedPixels": [1, 1, 1], "metaData": {"material": "carpet_extra_high"}}"#)
        XCTAssertEqual(layer.metaData?.material, "carpet_extra_high")
        XCTAssertEqual(layer.decompressedPixels, [1, 1])
    }
}
