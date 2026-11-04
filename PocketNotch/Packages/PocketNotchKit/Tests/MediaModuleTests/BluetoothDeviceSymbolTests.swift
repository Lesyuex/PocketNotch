import IOBluetooth
import XCTest
@testable import MediaModule

final class BluetoothDeviceSymbolTests: XCTestCase {
    func testAirPodsProductsUseTheirSpecificSymbols() {
        XCTAssertEqual(symbol(for: "Jobeth 的 AirPods Pro"), "airpodspro")
        XCTAssertEqual(symbol(for: "AirPods Max"), "airpodsmax")
        XCTAssertEqual(symbol(for: "AirPods"), "airpods")
    }

    func testAppleInputDeviceNamesUseMatchingSymbols() {
        XCTAssertEqual(symbol(for: "Magic Keyboard"), "keyboard.fill")
        XCTAssertEqual(symbol(for: "Magic Mouse"), "computermouse.fill")
        XCTAssertEqual(
            symbol(for: "Magic Trackpad"),
            "rectangle.and.hand.point.up.left.fill"
        )
    }

    func testAudioClassDistinguishesSpeakerFromHeadphonesByMinorClass() {
        XCTAssertEqual(
            BluetoothDeviceSymbol.name(
                deviceName: "Unknown Audio",
                majorClass: UInt32(kBluetoothDeviceClassMajorAudio),
                minorClass: UInt32(kBluetoothDeviceClassMinorAudioLoudspeaker)
            ),
            "hifispeaker.fill"
        )
        XCTAssertEqual(
            BluetoothDeviceSymbol.name(
                deviceName: "Unknown Audio",
                majorClass: UInt32(kBluetoothDeviceClassMajorAudio),
                minorClass: UInt32(kBluetoothDeviceClassMinorAudioHeadphones)
            ),
            "headphones"
        )
        XCTAssertEqual(
            BluetoothDeviceSymbol.name(
                deviceName: "Unknown Audio",
                majorClass: UInt32(kBluetoothDeviceClassMajorAudio),
                minorClass: UInt32(kBluetoothDeviceClassMinorAudioVideoDisplayAndLoudspeaker)
            ),
            "hifispeaker.fill"
        )
    }

    func testPeripheralClassFallsBackToKeyboardOrMouse() {
        XCTAssertEqual(
            BluetoothDeviceSymbol.name(
                deviceName: "Unknown Device",
                majorClass: UInt32(kBluetoothDeviceClassMajorPeripheral),
                minorClass: 0x10
            ),
            "keyboard.fill"
        )
        XCTAssertEqual(
            BluetoothDeviceSymbol.name(
                deviceName: "Unknown Device",
                majorClass: UInt32(kBluetoothDeviceClassMajorPeripheral),
                minorClass: 0x20
            ),
            "computermouse.fill"
        )
    }

    private func symbol(for deviceName: String) -> String {
        BluetoothDeviceSymbol.name(deviceName: deviceName, majorClass: 0, minorClass: 0)
    }
}
