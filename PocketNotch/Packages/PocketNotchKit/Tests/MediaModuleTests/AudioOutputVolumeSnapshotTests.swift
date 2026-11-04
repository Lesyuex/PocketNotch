import CoreAudio
import XCTest
@testable import MediaModule

final class AudioOutputVolumeSnapshotTests: XCTestCase {
    func testAudioOutputNotificationUsesDefaultDuration() {
        XCTAssertEqual(AudioOutputDeviceSnapshot.notificationDisplayDuration, 2)
    }

    func testAirPodsModelRotationUsesSixSecondCycle() {
        XCTAssertEqual(AudioOutputDeviceSnapshot.airPodsProRotationDuration, 6)
    }

    func testAirPodsNotificationDisplaysForSixSeconds() {
        let snapshot = AudioOutputDeviceSnapshot(
            deviceName: "Jobeth 的 AirPods Pro",
            deviceSymbolName: "airpodspro"
        )

        XCTAssertEqual(snapshot.displayDuration, 6)
    }

    func testGenericHeadphoneNotificationKeepsDefaultDuration() {
        let snapshot = AudioOutputDeviceSnapshot(
            deviceName: "Studio Headphones",
            deviceSymbolName: "headphones"
        )

        XCTAssertEqual(snapshot.displayDuration, 2)
    }

    func testGenericBrandInferenceTreatsSonyBoseAsBluetoothHeadphones() {
        XCTAssertTrue(
            AudioOutputDeviceSnapshot(
                deviceName: "Sony WH-1000XM5",
                deviceSymbolName: "hifispeaker.fill"
            ).isBluetoothHeadphones
        )
        XCTAssertTrue(
            AudioOutputDeviceSnapshot(
                deviceName: "Bose QuietComfort 45",
                deviceSymbolName: "hifispeaker.fill"
            ).isBluetoothHeadphones
        )
        XCTAssertTrue(
            AudioOutputDeviceSnapshot(
                deviceName: "Soundcore Liberty 4",
                deviceSymbolName: "hifispeaker.fill"
            ).isBluetoothHeadphones
        )
        XCTAssertTrue(
            AudioOutputDeviceSnapshot(
                deviceName: "Huawei FreeBuds Pro",
                deviceSymbolName: "hifispeaker.fill"
            ).isBluetoothHeadphones
        )
    }

    func testGenericBrandInferenceDoesNotClassifyUnrelatedBluetoothAudio() {
        XCTAssertFalse(
            AudioOutputDeviceSnapshot(
                deviceName: "SONOS Play:5",
                deviceSymbolName: "hifispeaker.fill"
            ).isBluetoothHeadphones
        )
    }

    func testVolumeSymbolReflectsDisplayedVolumeLevel() {
        XCTAssertEqual(snapshot(volume: 0).volumeSymbolName, "speaker.slash.fill")
        XCTAssertEqual(snapshot(volume: 0.2).volumeSymbolName, "speaker.wave.1.fill")
        XCTAssertEqual(snapshot(volume: 0.5).volumeSymbolName, "speaker.wave.2.fill")
        XCTAssertEqual(snapshot(volume: 0.9).volumeSymbolName, "speaker.wave.3.fill")
    }

    func testMutedVolumeUsesMutedSymbolRegardlessOfStoredVolume() {
        XCTAssertEqual(
            snapshot(volume: 0.8, isMuted: true).volumeSymbolName,
            "speaker.slash.fill"
        )
    }

    func testOutputDeviceSymbolsCoverCommonRouteTypes() {
        XCTAssertEqual(
            AudioOutputDeviceSymbol.name(
                deviceName: "MacBook Pro Speakers",
                transportType: kAudioDeviceTransportTypeBuiltIn
            ),
            "macbook"
        )
        XCTAssertEqual(
            AudioOutputDeviceSymbol.name(
                deviceName: "Studio Display",
                transportType: kAudioDeviceTransportTypeDisplayPort
            ),
            "display"
        )
        XCTAssertEqual(
            AudioOutputDeviceSymbol.name(
                deviceName: "Living Room",
                transportType: kAudioDeviceTransportTypeAirPlay
            ),
            "airplayaudio"
        )
        XCTAssertEqual(
            AudioOutputDeviceSymbol.name(
                deviceName: "Studio Headphones",
                transportType: kAudioDeviceTransportTypeBluetooth
            ),
            "headphones"
        )
    }

    func testBluetoothHeadphoneFlagCanBeProvidedByCoreAudioTransport() {
        let snapshot = AudioOutputDeviceSnapshot(
            deviceName: "External Audio",
            deviceSymbolName: "headphones",
            isBluetoothHeadphones: false
        )

        XCTAssertFalse(snapshot.isBluetoothHeadphones)
        XCTAssertFalse(snapshot.supportsBatteryStatus)
    }

    func testWiredHeadphoneSnapshotIsHeadphonesButHasNoBattery() {
        let snapshot = AudioOutputDeviceSnapshot(
            deviceName: "External Headphones",
            deviceSymbolName: "headphones",
            isBluetoothHeadphones: false,
            isWiredHeadphones: true
        )

        XCTAssertTrue(snapshot.isHeadphones)
        XCTAssertFalse(snapshot.isBluetoothHeadphones)
        XCTAssertFalse(snapshot.supportsBatteryStatus)
    }

    func testWiredHeadphoneSymbolRecognizesHeadphoneJackTransport() {
        let headphoneJackTransportType: UInt32 = 0x6864706E
        XCTAssertTrue(
            AudioOutputDeviceSymbol.isWiredHeadphones(
                deviceName: "外部耳机",
                transportType: headphoneJackTransportType
            )
        )
    }

    func testWiredHeadphoneSymbolNamesUSBHeadsetsByDeviceName() {
        XCTAssertTrue(
            AudioOutputDeviceSymbol.isWiredHeadphones(
                deviceName: "USB-C Gaming Headset",
                transportType: kAudioDeviceTransportTypeUSB
            )
        )
        XCTAssertTrue(
            AudioOutputDeviceSymbol.isWiredHeadphones(
                deviceName: "达摩头戴耳机",
                transportType: kAudioDeviceTransportTypeThunderbolt
            )
        )
    }

    func testBuiltInHeadphoneJackIsWiredHeadphonesByModel() {
        XCTAssertTrue(
            AudioOutputDeviceSymbol.isWiredHeadphones(
                deviceName: "外置耳机",
                transportType: kAudioDeviceTransportTypeBuiltIn,
                modelName: "Built-in Headphone"
            )
        )
    }

    func testWiredHeadphoneSymbolDoesNotClassifyBuiltInSpeakersOrBluetooth() {
        XCTAssertFalse(
            AudioOutputDeviceSymbol.isWiredHeadphones(
                deviceName: "MacBook Pro扬声器",
                transportType: kAudioDeviceTransportTypeBuiltIn,
                modelName: "Built-in Speaker"
            )
        )
        XCTAssertFalse(
            AudioOutputDeviceSymbol.isWiredHeadphones(
                deviceName: "USB Audio Device",
                transportType: kAudioDeviceTransportTypeUSB
            )
        )
        XCTAssertFalse(
            AudioOutputDeviceSymbol.isWiredHeadphones(
                deviceName: "Studio Headphones",
                transportType: kAudioDeviceTransportTypeBluetooth
            )
        )
    }

    func testAirPodsOutputSymbolsUseModernSfSymbols() {
        XCTAssertEqual(symbol(deviceName: "AirPods Pro"), "airpods.pro")
        XCTAssertEqual(symbol(deviceName: "AirPods Pro（第 1 代）"), "airpods.pro.gen1")
        XCTAssertEqual(symbol(deviceName: "AirPods (2nd generation)"), "airpods")
        XCTAssertEqual(symbol(deviceName: "AirPods（第 3 代）"), "airpods.gen3")
        XCTAssertEqual(symbol(deviceName: "AirPods Max"), "airpods.max")
    }

    func testUnrecognizedOutputFallsBackToDeviceSpeakerIcon() {
        XCTAssertEqual(
            AudioOutputDeviceSymbol.name(
                deviceName: "USB Audio Device",
                transportType: kAudioDeviceTransportTypeUSB
            ),
            "hifispeaker.fill"
        )
        XCTAssertNotEqual(AudioOutputDeviceSymbol.name(deviceName: "USB Audio Device", transportType: 0), "speaker.wave.2.fill")
    }

    func testRenamedDeviceStillMatchesByModelName() {
        XCTAssertEqual(
            AudioOutputDeviceSymbol.name(
                deviceName: "我改的名字",
                transportType: kAudioDeviceTransportTypeBluetooth,
                modelName: "AirPods Pro"
            ),
            "airpods.pro"
        )
        XCTAssertEqual(
            AudioOutputDeviceSymbol.name(
                deviceName: "el dispositivo",
                transportType: kAudioDeviceTransportTypeBluetooth,
                modelName: "AirPods Max"
            ),
            "airpods.max"
        )
        XCTAssertEqual(
            AudioOutputDeviceSymbol.name(
                deviceName: "客厅音箱",
                transportType: kAudioDeviceTransportTypeBluetooth,
                modelName: "HomePod mini"
            ),
            "homepodmini.fill"
        )
    }

    func testRenamedBluetoothDeviceFallsBackByTransportType() {
        XCTAssertEqual(
            AudioOutputDeviceSymbol.name(
                deviceName: "未知蓝牙设备",
                transportType: kAudioDeviceTransportTypeBluetooth,
                modelName: nil
            ),
            "headphones"
        )
    }

    private func symbol(deviceName: String) -> String {
        AudioOutputDeviceSymbol.name(
            deviceName: deviceName,
            transportType: kAudioDeviceTransportTypeBluetooth
        )
    }

    private func snapshot(volume: Float, isMuted: Bool = false) -> AudioOutputVolumeSnapshot {
        AudioOutputVolumeSnapshot(
            volume: volume,
            isMuted: isMuted,
            deviceName: "Test Output",
            deviceSymbolName: "hifispeaker.fill"
        )
    }
}
