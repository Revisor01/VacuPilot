import XCTest
@testable import ValetudoApp

final class ValetudoAPITests: XCTestCase {

    // MARK: - APIError Tests

    func testAPIErrorInvalidURLDescription() {
        XCTAssertEqual(APIError.invalidURL.errorDescription, "Invalid URL")
    }

    func testAPIErrorHTTPErrorDescription() {
        XCTAssertEqual(APIError.httpError(401).errorDescription, "HTTP Error: 401")
        XCTAssertEqual(APIError.httpError(500).errorDescription, "HTTP Error: 500")
    }

    func testAPIErrorInvalidResponseDescription() {
        XCTAssertEqual(APIError.invalidResponse.errorDescription, "Invalid response")
    }

    func testAPIErrorNetworkErrorDescription() {
        let nsError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection refused"])
        XCTAssertEqual(APIError.networkError(nsError).errorDescription, "Connection refused")
    }

    // MARK: - RobotConfig.baseURL Tests

    func testBaseURLHTTP() {
        let config = RobotConfig(id: UUID(), name: "Test", host: "192.168.1.10", username: nil, password: nil, useSSL: false, ignoreCertificateErrors: false)
        XCTAssertEqual(config.baseURL?.scheme, "http")
        XCTAssertEqual(config.baseURL?.host, "192.168.1.10")
    }

    func testBaseURLHTTPS() {
        let config = RobotConfig(id: UUID(), name: "Test", host: "192.168.1.10", username: nil, password: nil, useSSL: true, ignoreCertificateErrors: false)
        XCTAssertEqual(config.baseURL?.scheme, "https")
    }

    func testBaseURLInvalidHost() {
        let config = RobotConfig(id: UUID(), name: "Test", host: "", username: nil, password: nil, useSSL: false, ignoreCertificateErrors: false)
        // URL(string: "http://") returns a URL with no host — baseURL is non-nil but host is empty/nil
        let url = config.baseURL
        let isInvalidHost = url == nil || url?.host == nil || url?.host == ""
        XCTAssertTrue(isInvalidHost, "baseURL should have no valid host for empty host string")
    }

    // MARK: - JSON Decoding Tests

    func testDecodeCapabilities() throws {
        let json = #"["FanSpeedControlCapability","WaterUsageControlCapability"]"#
        let data = Data(json.utf8)
        let capabilities = try JSONDecoder().decode(Capabilities.self, from: data)
        XCTAssertEqual(capabilities.count, 2)
        XCTAssertTrue(capabilities.contains("FanSpeedControlCapability"))
    }

    func testDecodeConsumable() throws {
        let json = #"{"type":"filter","subType":null,"remaining":{"value":85,"unit":"percent"}}"#
        let data = Data(json.utf8)
        let consumable = try JSONDecoder().decode(Consumable.self, from: data)
        XCTAssertEqual(consumable.type, "filter")
        XCTAssertEqual(consumable.remaining.value, 85)
    }

    func testDecodeRobotInfoFromJSON() throws {
        let json = #"{"manufacturer":"Dreame","modelName":"X40","implementation":"ValetudoDreameGen2LidarRobot"}"#
        let data = Data(json.utf8)
        let info = try JSONDecoder().decode(RobotInfo.self, from: data)
        XCTAssertEqual(info.modelName, "X40")
        XCTAssertEqual(info.manufacturer, "Dreame")
    }

    func testDecodeConsumableRemainingUnit() throws {
        let json = #"{"type":"brush","subType":"main","remaining":{"value":9000,"unit":"minutes"}}"#
        let data = Data(json.utf8)
        let consumable = try JSONDecoder().decode(Consumable.self, from: data)
        XCTAssertEqual(consumable.remaining.unit, "minutes")
        XCTAssertEqual(consumable.remaining.value, 9000)
    }

    func testDecodeRobotAttribute() throws {
        let json = #"{"__class":"StatusStateAttribute","type":"status","subType":null,"value":"docked","level":null,"flag":"none"}"#
        let data = Data(json.utf8)
        let attribute = try JSONDecoder().decode(RobotAttribute.self, from: data)
        XCTAssertEqual(attribute.__class, "StatusStateAttribute")
        XCTAssertEqual(attribute.value, "docked")
    }

    // MARK: - MQTT-Konfiguration (Firmware vor und nach Entfernen von interfaces/provideMapData)

    private let mqttConfigJSONLegacy = """
    {"enabled":true,
     "connection":{"host":"broker.local","port":1883,
       "tls":{"enabled":false,"ca":"","ignoreCertificateErrors":false},
       "authentication":{"credentials":{"enabled":false,"username":"","password":""}}},
     "identity":{"identifier":"robot"},
     "customizations":{"topicPrefix":"valetudo","provideMapData":false},
     "interfaces":{"homie":{"enabled":true,"cleanAttributesOnShutdown":false},
                   "homeassistant":{"enabled":false,"cleanAutoconfOnShutdown":true}},
     "optionalExposedCapabilities":[]}
    """

    private let mqttConfigJSONCurrent = """
    {"enabled":true,
     "connection":{"host":"broker.local","port":1883,
       "tls":{"enabled":false,"ca":"","ignoreCertificateErrors":false},
       "authentication":{"credentials":{"enabled":false,"username":"","password":""}}},
     "identity":{"identifier":"robot"},
     "customizations":{"topicPrefix":"valetudo"},
     "optionalExposedCapabilities":["SpeakerTestCapability"]}
    """

    func testDecodeMQTTConfigLegacyKeepsInterfaces() throws {
        let config = try JSONDecoder().decode(MQTTConfig.self, from: Data(mqttConfigJSONLegacy.utf8))
        XCTAssertEqual(config.interfaces?.homie.enabled, true)
        XCTAssertEqual(config.interfaces?.homeassistant.enabled, false)
        XCTAssertEqual(config.customizations.provideMapData, false)
    }

    func testDecodeMQTTConfigWithoutInterfacesAndProvideMapData() throws {
        let config = try JSONDecoder().decode(MQTTConfig.self, from: Data(mqttConfigJSONCurrent.utf8))
        XCTAssertNil(config.interfaces)
        XCTAssertNil(config.customizations.provideMapData)
        XCTAssertEqual(config.connection.host, "broker.local")
        XCTAssertEqual(config.customizations.topicPrefix, "valetudo")
    }

    /// Neuere Firmware lehnt unbekannte Felder beim Speichern ab (HTTP 400).
    func testEncodeMQTTConfigOmitsFieldsTheFirmwareDoesNotKnow() throws {
        let config = try JSONDecoder().decode(MQTTConfig.self, from: Data(mqttConfigJSONCurrent.utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        XCTAssertNil(json["interfaces"])
        let customizations = try XCTUnwrap(json["customizations"] as? [String: Any])
        XCTAssertEqual(Set(customizations.keys), ["topicPrefix"])
    }

    /// Ältere Firmware verlangt die Felder weiterhin — sie müssen zurückgeschickt werden.
    func testEncodeMQTTConfigKeepsFieldsForOlderFirmware() throws {
        let config = try JSONDecoder().decode(MQTTConfig.self, from: Data(mqttConfigJSONLegacy.utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        XCTAssertNotNil(json["interfaces"])
        let customizations = try XCTUnwrap(json["customizations"] as? [String: Any])
        XCTAssertEqual(customizations["provideMapData"] as? Bool, false)
    }

    /// Fehlt das Feld beim Speichern, setzt der Server es auf [] — freigegebene Fähigkeiten gingen verloren.
    func testEncodeMQTTConfigKeepsOptionalExposedCapabilities() throws {
        let config = try JSONDecoder().decode(MQTTConfig.self, from: Data(mqttConfigJSONLegacy.utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        XCTAssertEqual(json["optionalExposedCapabilities"] as? [String], ["SpeakerTestCapability"])
    }
}
