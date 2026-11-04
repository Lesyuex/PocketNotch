import XCTest
@testable import MediaModule

final class HeadphoneBatteryReaderTests: XCTestCase {
    func testReadsNestedCombinedPercentage() {
        let properties: [String: Any] = [
            "DeviceProperties": [
                "BatteryPercentCombined": NSNumber(value: 82)
            ]
        ]

        XCTAssertEqual(HeadphoneBatteryReader.batteryPercentage(in: properties), 82)
    }

    func testUsesLowerEarLevelAndNormalizesFractions() {
        let properties: [String: Any] = [
            "BatteryData": [
                "BatteryLevelLeft": NSNumber(value: 0.86),
                "BatteryLevelRight": NSNumber(value: 0.72)
            ]
        ]

        XCTAssertEqual(HeadphoneBatteryReader.batteryPercentage(in: properties), 72)
    }

    func testMatchesBatteryKeysIgnoringSeparatorsAndCase() {
        let properties: [String: Any] = [
            "status": [
                "LEFT battery percent": "64%",
                "right-battery-percent": "59"
            ]
        ]

        XCTAssertEqual(HeadphoneBatteryReader.batteryPercentage(in: properties), 59)
    }

    func testReadsIORegistryDataEncodedPercentage() {
        XCTAssertEqual(
            HeadphoneBatteryReader.batteryPercentage(in: ["BatteryPercent": Data([82, 0, 0, 0])]),
            82
        )
        XCTAssertEqual(
            HeadphoneBatteryReader.batteryPercentage(in: ["BatteryPercent": Data([0, 0, 0, 73])]),
            73
        )
    }

    func testReadsHexEncodedPercentageString() {
        XCTAssertEqual(
            HeadphoneBatteryReader.batteryPercentage(in: ["BatteryPercent": "0x58"]),
            88
        )
    }

    func testPrefersCombinedOverEarLevelsToMatchSystem() throws {
        let json: [String: Any] = [
            "SPBluetoothDataType": [[
                "device_connected": [[
                    "70-AE-2A-6C-C6-5B": [
                        "_name": "Jobeth 的 AirPods Pro",
                        "device_batteryLevelCombined": "94%",
                        "device_batteryLevelLeft": "100%",
                        "device_batteryLevelRight": "100%",
                        "device_batteryLevelCase": "94%"
                    ]
                ]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertEqual(
            HeadphoneBatteryReader.batteryPercentage(
                inSystemProfilerJSON: data,
                deviceName: "Jobeth 的 AirPods Pro"
            ),
            94
        )
    }

    func testReadsAirPodsBatteryFromSystemProfilerJSONByName() throws {
        let json: [String: Any] = [
            "SPBluetoothDataType": [[
                "device_connected": [[
                    "70-AE-2A-6C-C6-5B": [
                        "_name": "Jobeth 的 AirPods Pro",
                        "device_batteryLevelLeft": "81%",
                        "device_batteryLevelRight": "76%",
                        "device_batteryLevelCase": "54%"
                    ]
                ]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertEqual(
            HeadphoneBatteryReader.batteryPercentage(
                inSystemProfilerJSON: data,
                deviceName: "Jobeth 的 AirPods Pro"
            ),
            76
        )
    }

    func testReadsAirPodsBatteryWhenDeviceNameIsDictionaryKey() throws {
        let json: [String: Any] = [
            "SPBluetoothDataType": [[
                "device_connected": [[
                    "大古的AirPods Pro": [
                        "device_address": "70:AE:2A:6C:C6:5B",
                        "device_batteryLevelLeft": "56%",
                        "device_batteryLevelRight": "61%",
                        "device_batteryLevelCase": "99%"
                    ]
                ]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertEqual(
            HeadphoneBatteryReader.batteryPercentage(
                inSystemProfilerJSON: data,
                deviceName: "大古的AirPods Pro"
            ),
            56
        )
    }

    func testReadsAirPodsBatteryFromSystemProfilerJSONByAddress() throws {
        let json: [String: Any] = [
            "SPBluetoothDataType": [[
                "device_connected": [[
                    "70-AE-2A-6C-C6-5B": [
                        "_name": "AirPods Pro",
                        "device_batteryLevelMain": "83%"
                    ],
                    "11-22-33-44-55-66": [
                        "_name": "Other Headphones",
                        "device_batteryLevelMain": "41%"
                    ]
                ]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertEqual(
            HeadphoneBatteryReader.batteryPercentage(
                inSystemProfilerJSON: data,
                deviceName: "自定义耳机名称",
                deviceUID: "BluetoothDevice_70:AE:2A:6C:C6:5B:output"
            ),
            83
        )
    }

    func testReadsBatteryForGenericBrandedEarphonesByName() throws {
        let json: [String: Any] = [
            "SPBluetoothDataType": [[
                "device_connected": [[
                    "0F-1A-2B-3C-4D-5E": [
                        "_name": "WH-1000XM5",
                        "device_batteryLevelMain": "67%"
                    ]
                ]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertEqual(
            HeadphoneBatteryReader.batteryPercentage(
                inSystemProfilerJSON: data,
                deviceName: "WH-1000XM5"
            ),
            67
        )
    }

    func testReadsBatteryForSonyBudsBySharedBrandToken() throws {
        let json: [String: Any] = [
            "SPBluetoothDataType": [[
                "device_connected": [[
                    "0F-1A-2B-3C-4D-5E": [
                        "_name": "Sony WF-1000XM4",
                        "device_batteryLevelMain": "58%"
                    ]
                ]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertEqual(
            HeadphoneBatteryReader.batteryPercentage(
                inSystemProfilerJSON: data,
                deviceName: "Sony WF-1000XM4"
            ),
            58
        )
    }

    func testGATTMatchesExactHeadphoneName() {
        XCTAssertTrue(
            HeadphoneGATTBatteryReader.matches(
                deviceName: "OPPO Enco Free3",
                peripheralName: "OPPO Enco Free3"
            )
        )
    }

    func testGATTMatchesPeripheralSubsumedByAudioDeviceName() {
        XCTAssertTrue(
            HeadphoneGATTBatteryReader.matches(
                deviceName: "OPPO Enco Free3",
                peripheralName: "Enco Free3"
            )
        )
    }

    func testGATTMatchesByNameSharingBrandToken() {
        XCTAssertTrue(
            HeadphoneGATTBatteryReader.matches(
                deviceName: "Enco Free3",
                peripheralName: "OPPO Enco Free3"
            )
        )
    }

    func testGATTDoesNotMatchUnrelatedHeadphone() {
        XCTAssertFalse(
            HeadphoneGATTBatteryReader.matches(
                deviceName: "OPPO Enco Free3",
                peripheralName: "Xiaomi Buds 6"
            )
        )
    }

    func testGATTDoesNotMatchNilOrEmptyName() {
        XCTAssertFalse(
            HeadphoneGATTBatteryReader.matches(deviceName: "OPPO Enco Free3", peripheralName: nil)
        )
        XCTAssertFalse(HeadphoneGATTBatteryReader.matches(deviceName: "", peripheralName: "Dev"))
    }

    func testGATTNormalizesWhitespaceAndCase() {
        XCTAssertEqual(
            HeadphoneGATTBatteryReader.normalized(" oppo  enco free3 "),
            "oppo enco free3"
        )
        XCTAssertEqual(HeadphoneGATTBatteryReader.normalized("OPPO ENCO"), "oppo enco")
    }

    func testOPOParsesObservedEncoFree3Frame() {
        let frame: [UInt8] = [0xAA, 0x0D, 0x00, 0x00, 0x06, 0x81, 0x43, 0x06, 0x00, 0x00,
                              0x02, 0x01, 0x14, 0x02, 0x14]
        XCTAssertEqual(HeadphoneGATTBatteryReader.opoBatteryPercentage(in: frame), 20)
    }

    func testOPOParsesLongerLeftRightCaseFrame() {
        let frame: [UInt8] = [0xAA, 0x0F, 0x00, 0x00, 0x06, 0x81, 0x43, 0x06, 0x00, 0x00,
                              0x03, 0x01, 0x32, 0x02, 0x28, 0x03, 0x64]
        XCTAssertEqual(HeadphoneGATTBatteryReader.opoBatteryPercentage(in: frame), 40)
    }

    func testOPOParsesAllEqualPairValues() {
        let frame: [UInt8] = [0xAA, 0x0D, 0x00, 0x00, 0x06, 0x81, 0x43, 0x06, 0x00, 0x00,
                              0x02, 0x01, 0x05, 0x02, 0x05]
        XCTAssertEqual(HeadphoneGATTBatteryReader.opoBatteryPercentage(in: frame), 5)
    }

    func testOPODoesNotParseHelloOrRandomFrames() {
        XCTAssertNil(
            HeadphoneGATTBatteryReader.opoBatteryPercentage(
                in: [0xAA, 0x10, 0x00, 0x00, 0x00, 0x81, 0x23, 0x09, 0x00, 0x00,
                     0xFF, 0x77, 0x5A, 0xEE, 0x23, 0x0E, 0x00, 0x00]
            )
        )
        XCTAssertNil(HeadphoneGATTBatteryReader.opoBatteryPercentage(in: [0x01, 0x02, 0x03]))
    }

}
