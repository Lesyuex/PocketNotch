import XCTest
import PocketNotchCore
@testable import MediaModule

@MainActor
final class NowPlayingViewModelTests: XCTestCase {
    func testPlaybackCapabilitiesAreConservativeBySource() {
        XCTAssertEqual(
            MediaPlaybackCapabilities.resolve(sourceBundleIdentifier: "com.apple.Music"),
            MediaPlaybackCapabilities(canShuffle: true, canFavorite: true)
        )
        XCTAssertEqual(
            MediaPlaybackCapabilities.resolve(sourceBundleIdentifier: "com.spotify.client"),
            MediaPlaybackCapabilities(canShuffle: true, canFavorite: false)
        )
        XCTAssertEqual(
            MediaPlaybackCapabilities.resolve(sourceBundleIdentifier: "com.apple.Safari"),
            MediaPlaybackCapabilities(canShuffle: false, canFavorite: false)
        )
    }

    func testSpectrumProviderRealCaptureFlagDistinguishesPlaceholder() {
        let placeholder = makeSpectrumProvider(isCaptureEnabled: false)
        XCTAssertFalse(placeholder.isRealAudioCapture)
        XCTAssertTrue(placeholder is StaticAudioSpectrumPlaceholder)

        XCTAssertFalse(StubSpectrumProvider().isRealAudioCapture)
    }

    func testFavoriteActionUsesProviderStateForMusic() async {
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(
                    title: "Track",
                    artist: "Artist",
                    sourceBundleIdentifier: "com.apple.Music",
                    isFavorited: false,
                    isPlaying: true
                ),
                status: "playing"
            ),
            favoriteResult: true
        )
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()
        await viewModel.toggleFavorite()

        XCTAssertTrue(viewModel.isCurrentTrackFavorited)
        XCTAssertEqual(provider.toggleFavoriteCallCount, 1)
    }

    func testUnsupportedSourceDoesNotSendShuffleOrFavoriteCommands() async {
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(
                    title: "Video",
                    artist: "",
                    sourceBundleIdentifier: "com.apple.Safari",
                    isPlaying: true
                ),
                status: "playing"
            )
        )
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()
        await viewModel.toggleShuffle()
        await viewModel.toggleFavorite()

        XCTAssertEqual(provider.toggleShuffleCallCount, 0)
        XCTAssertEqual(provider.toggleFavoriteCallCount, 0)
        XCTAssertEqual(provider.shuffleStateCallCount, 0)
    }

    func testInitialSpotifyShuffleStateMatchesProvider() async {
        let provider = StubMediaRemoteProvider(
            snapshot: spotifySnapshot(title: "Track"),
            shuffleStateResult: true
        )
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()

        XCTAssertTrue(viewModel.isShuffleEnabled)
        XCTAssertEqual(provider.shuffleStateCallCount, 1)
    }

    func testChangingTracksInSpotifyKeepsShuffleState() async {
        let provider = StubMediaRemoteProvider(
            snapshot: spotifySnapshot(title: "Track A"),
            shuffleStateResult: true
        )
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()
        provider.snapshot = spotifySnapshot(title: "Track B")
        await viewModel.refresh()

        XCTAssertTrue(viewModel.isShuffleEnabled)
        XCTAssertEqual(provider.shuffleStateCallCount, 1)
    }

    func testExternalSpotifyShuffleChangeUpdatesState() async {
        let provider = StubMediaRemoteProvider(
            snapshot: spotifySnapshot(title: "Track"),
            shuffleStateResult: true
        )
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(),
            shuffleStateRefreshInterval: 0
        )

        await viewModel.refresh()
        provider.shuffleStateResult = false
        await viewModel.refresh()

        XCTAssertFalse(viewModel.isShuffleEnabled)
        XCTAssertEqual(provider.shuffleStateCallCount, 2)
    }

    func testSpotifyShuffleUsesProviderState() async {
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(
                    title: "Track",
                    artist: "Artist",
                    sourceBundleIdentifier: "com.spotify.client",
                    isPlaying: true
                ),
                status: "playing"
            ),
            shuffleResult: true
        )
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()
        await viewModel.toggleShuffle()

        XCTAssertTrue(viewModel.isShuffleEnabled)
        XCTAssertEqual(provider.toggleShuffleCallCount, 1)
    }

    func testSpotifyShuffleDoesNotRefreshPlaybackSnapshot() async {
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(
                    title: "Track",
                    artist: "Artist",
                    sourceBundleIdentifier: "com.spotify.client",
                    elapsedTime: 42,
                    duration: 180,
                    isPlaying: true
                ),
                status: "playing"
            ),
            shuffleResult: true
        )
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()
        await viewModel.toggleShuffle()

        XCTAssertEqual(provider.currentSnapshotCallCount, 1)
        XCTAssertEqual(viewModel.info?.elapsedTime, 42)
    }

    func testSpotifyShuffleNotificationCannotReplaceProgressWithStalePosition() async {
        let now = Date()
        let service = DelayedMediaRemoteProvider(responses: [
            (
                snapshot: MediaRemoteSnapshot(
                    info: NowPlayingInfo(
                        title: "Track",
                        artist: "Artist",
                        sourceBundleIdentifier: "com.spotify.client",
                        elapsedTime: 42,
                        duration: 180,
                        isPlaying: true,
                        updatedAt: now
                    ),
                    status: "playing"
                ),
                delay: .zero
            ),
            (
                snapshot: MediaRemoteSnapshot(
                    info: NowPlayingInfo(
                        title: "Track",
                        artist: "Artist",
                        sourceBundleIdentifier: "com.spotify.client",
                        elapsedTime: 5,
                        duration: 180,
                        isPlaying: true,
                        updatedAt: now
                    ),
                    status: "stale shuffle notification"
                ),
                delay: .zero
            ),
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()
        await viewModel.toggleShuffle()
        await viewModel.refresh()

        XCTAssertGreaterThanOrEqual(viewModel.info?.elapsedTime ?? 0, 42)
    }

    func testPausedSnapshotStillCountsAsMedia() async {
        let pausedInfo = NowPlayingInfo(
            title: "Paused Track",
            artist: "Artist",
            isPlaying: false
        )
        let viewModel = makeViewModel(
            snapshot: MediaRemoteSnapshot(info: pausedInfo, status: "paused")
        )

        await viewModel.refresh()

        XCTAssertTrue(viewModel.hasMedia)
        XCTAssertTrue(viewModel.isCompactMediaDisplayActive)
        XCTAssertEqual(viewModel.info?.isPlaying, false)
    }

    func testPauseAfterPlayingStopsSpectrumImmediately() async {
        let spectrumProvider = StubSpectrumProvider()
        let service = StubMediaRemoteProvider(snapshot: snapshot(title: "Track"))
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: spectrumProvider,
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()
        XCTAssertEqual(spectrumProvider.startCallCount, 1)

        service.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(
                title: "Track",
                artist: "Artist",
                artworkData: Data([0xCA, 0xFE]),
                isPlaying: false
            ),
            status: "paused"
        )
        await viewModel.refresh()

        XCTAssertEqual(viewModel.info?.isPlaying, false)
        XCTAssertEqual(spectrumProvider.stopCallCount, 1)
    }

    func testPeriodicReconciliationStopsAnimationWhenPauseNotificationIsLost() async {
        let spectrumProvider = StubSpectrumProvider()
        let service = StubMediaRemoteProvider(snapshot: snapshot(title: "Track"))
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: spectrumProvider,
            volumeService: StubAudioOutputVolumeProvider(),
            mediaStateReconciliationInterval: 0.02
        )

        viewModel.startObserving()
        defer { viewModel.stopObserving() }
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertTrue(viewModel.info?.isPlaying == true)

        // 模拟暂停通知丢失：只改变底层快照，不调用 sendChange().
        service.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(
                title: "Track",
                artist: "Artist",
                artworkData: Data([0xCA, 0xFE]),
                isPlaying: false
            ),
            status: "paused"
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.info?.isPlaying, false)
        XCTAssertGreaterThanOrEqual(spectrumProvider.stopCallCount, 1)
    }

    func testMissingSnapshotCountsAsNoMedia() async {
        let viewModel = makeViewModel(
            snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
        )

        await viewModel.refresh()

        XCTAssertFalse(viewModel.hasMedia)
        XCTAssertNil(viewModel.info)
    }

    func testMissingMediaReleasesCompactDisplayImmediately() async {
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
                status: "playing"
            )
        )
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()
        XCTAssertTrue(viewModel.isCompactMediaDisplayActive)

        provider.snapshot = MediaRemoteSnapshot(info: nil, status: "idle")
        await viewModel.refresh()
        XCTAssertFalse(viewModel.isCompactMediaDisplayActive)
    }

    func testCompactPresentationIdentityChangesFromNoneToMedia() async {
        let viewModel = makeViewModel(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
                status: "playing"
            )
        )
        XCTAssertEqual(viewModel.compactPresentationIdentity, .none)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.compactPresentationIdentity, .media)
    }

    func testInitialPlaybackDoesNotShowCurrentOutputDevice() async {
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: false),
                status: "paused"
            )
        )
        let airPods = AudioOutputDevice(
            id: 20,
            deviceName: "Jobeth 的 AirPods Pro",
            deviceSymbolName: "airpodspro",
            isCurrent: true
        )
        let bluetoothService = StubBluetoothConnectionProvider(percentage: 82)
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(devices: [airPods]),
            bluetoothConnectionService: bluetoothService
        )

        await viewModel.refresh()
        XCTAssertNil(viewModel.headphoneConnectionPresentation)

        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
            status: "playing"
        )
        await viewModel.refresh()
        await Task.yield()

        XCTAssertNil(viewModel.headphoneConnectionPresentation)
        XCTAssertEqual(bluetoothService.requestCount, 0)
    }

    func testContinuousPlaybackDoesNotRepeatDevicePresentationLookup() async {
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
                status: "playing"
            )
        )
        let airPods = AudioOutputDevice(
            id: 20,
            deviceName: "Jobeth 的 AirPods Pro",
            deviceSymbolName: "airpodspro",
            isCurrent: true
        )
        let bluetoothService = StubBluetoothConnectionProvider(percentage: 82)
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(devices: [airPods]),
            bluetoothConnectionService: bluetoothService
        )

        await viewModel.refresh()
        await Task.yield()
        await viewModel.refresh()
        await Task.yield()

        XCTAssertEqual(bluetoothService.requestCount, 0)
    }

    func testPlaybackResumeAfterDelayShowsDevicePresentation() async {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
                status: "playing"
            )
        )
        let airPods = AudioOutputDevice(
            id: 20,
            deviceName: "Jobeth 的 AirPods Pro",
            deviceSymbolName: "airpodspro",
            isCurrent: true
        )
        let bluetoothService = StubBluetoothConnectionProvider(percentage: 82)
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(devices: [airPods]),
            bluetoothConnectionService: bluetoothService,
            now: { currentDate }
        )

        await viewModel.refresh()
        await Task.yield()
        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: false),
            status: "paused"
        )
        await viewModel.refresh()
        currentDate.addTimeInterval(10.2)
        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
            status: "playing"
        )
        await viewModel.refresh()
        for _ in 0..<20 where viewModel.headphoneConnectionPresentation?.batteryPercentage == nil {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.deviceName, airPods.deviceName)
        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.batteryPercentage, 82)
        XCTAssertEqual(bluetoothService.requestCount, 1)
    }

    func testPlaybackResumeToBuiltInSpeakersIsSilent() async {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
                status: "playing"
            )
        )
        let speakers = AudioOutputDevice(
            id: 10,
            deviceName: "MacBook Pro 扬声器",
            deviceSymbolName: "macbook",
            isCurrent: true
        )
        let bluetoothService = StubBluetoothConnectionProvider(percentage: 82)
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(devices: [speakers]),
            bluetoothConnectionService: bluetoothService,
            now: { currentDate }
        )

        await viewModel.refresh()
        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: false),
            status: "paused"
        )
        await viewModel.refresh()
        currentDate.addTimeInterval(10.2)
        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
            status: "playing"
        )
        await viewModel.refresh()
        await Task.yield()

        XCTAssertNil(viewModel.headphoneConnectionPresentation)
        XCTAssertEqual(bluetoothService.requestCount, 0)
    }

    func testAirPodsPlaybackResumeUsesLongCompactPresentationDuration() async throws {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
                status: "playing"
            )
        )
        let airPods = AudioOutputDevice(
            id: 20,
            deviceName: "Jobeth 的 AirPods Pro",
            deviceSymbolName: "airpodspro",
            isCurrent: true
        )
        let bluetoothService = StubBluetoothConnectionProvider(percentage: 82)
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(devices: [airPods]),
            bluetoothConnectionService: bluetoothService,
            now: { currentDate }
        )

        await viewModel.refresh()
        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: false),
            status: "paused"
        )
        await viewModel.refresh()
        currentDate.addTimeInterval(10.2)
        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
            status: "playing"
        )
        await viewModel.refresh()
        for _ in 0..<20 where viewModel.headphoneConnectionPresentation?.batteryPercentage == nil {
            await Task.yield()
        }

        try await Task.sleep(for: .milliseconds(2_600))

        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.deviceName, airPods.deviceName)
        XCTAssertFalse(viewModel.isHeadphoneConnectionDismissing)
    }

    func testBriefPauseDoesNotShowDevicePresentation() async {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
                status: "playing"
            )
        )
        let airPods = AudioOutputDevice(
            id: 20,
            deviceName: "Jobeth 的 AirPods Pro",
            deviceSymbolName: "airpodspro",
            isCurrent: true
        )
        let bluetoothService = StubBluetoothConnectionProvider(percentage: 82)
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(devices: [airPods]),
            bluetoothConnectionService: bluetoothService,
            now: { currentDate }
        )

        await viewModel.refresh()
        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: false),
            status: "paused"
        )
        await viewModel.refresh()
        currentDate.addTimeInterval(9.4)
        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
            status: "playing"
        )
        await viewModel.refresh()
        await Task.yield()

        XCTAssertNil(viewModel.headphoneConnectionPresentation)
        XCTAssertEqual(bluetoothService.requestCount, 0)
    }

    func testAutomaticNextTrackDoesNotShowDevicePresentation() async {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(
                info: NowPlayingInfo(title: "Track A", artist: "Artist", isPlaying: true),
                status: "playing"
            )
        )
        let airPods = AudioOutputDevice(
            id: 20,
            deviceName: "Jobeth 的 AirPods Pro",
            deviceSymbolName: "airpodspro",
            isCurrent: true
        )
        let bluetoothService = StubBluetoothConnectionProvider(percentage: 82)
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(devices: [airPods]),
            bluetoothConnectionService: bluetoothService,
            now: { currentDate }
        )

        await viewModel.refresh()
        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track B", artist: "Artist", isPlaying: false),
            status: "changing track"
        )
        await viewModel.refresh()
        currentDate.addTimeInterval(10.2)
        provider.snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Track B", artist: "Artist", isPlaying: true),
            status: "playing"
        )
        await viewModel.refresh()
        await Task.yield()

        XCTAssertNil(viewModel.headphoneConnectionPresentation)
        XCTAssertEqual(bluetoothService.requestCount, 0)
    }

    func testCompactPresentationIdentityChangesFromMediaToVolumeAndBack() async {
        let settings = IslandNotificationSettings(defaults: nil)
        let volumeService = StubAudioOutputVolumeProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(
                    info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
                    status: "playing"
                )
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService,
            notificationSettings: settings
        )
        await viewModel.refresh()
        XCTAssertEqual(viewModel.compactPresentationIdentity, .media)

        viewModel.startObserving()
        defer { viewModel.stopObserving() }
        volumeService.sendVolumeChange(
            AudioOutputVolumeSnapshot(
                volume: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro 扬声器",
                deviceSymbolName: "macbook"
            )
        )
        await Task.yield()
        XCTAssertEqual(viewModel.compactPresentationIdentity, .volume)
        XCTAssertTrue(viewModel.hasCompactTransientPresentation)

        settings.isVolumeAdjustmentEnabled = false
        XCTAssertEqual(viewModel.compactPresentationIdentity, .media)
        XCTAssertFalse(viewModel.hasCompactTransientPresentation)
    }

    func testVolumePresentationIconFollowsConfiguredStyle() async {
        let settings = IslandNotificationSettings(defaults: nil)
        let volumeService = StubAudioOutputVolumeProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(
                    info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
                    status: "playing"
                )
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService,
            notificationSettings: settings
        )

        viewModel.startObserving()
        defer { viewModel.stopObserving() }

        let snapshot = AudioOutputVolumeSnapshot(
            volume: 0.5,
            isMuted: false,
            deviceName: "AirPods Pro",
            deviceSymbolName: "airpodspro"
        )
        volumeService.sendVolumeChange(snapshot)
        await Task.yield()

        XCTAssertEqual(viewModel.volumeIconSymbolName, snapshot.volumeSymbolName)

        settings.volumeIconStyle = .device
        await Task.yield()
        XCTAssertEqual(viewModel.volumeIconSymbolName, snapshot.deviceSymbolName)
    }

    func testBuiltInDeviceAlwaysUsesSystemVolumeSymbol() async {
        let settings = IslandNotificationSettings(defaults: nil)
        let volumeService = StubAudioOutputVolumeProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(
                    info: NowPlayingInfo(title: "Track", artist: "Artist", isPlaying: true),
                    status: "playing"
                )
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService,
            notificationSettings: settings
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }

        let snapshot = AudioOutputVolumeSnapshot(
            volume: 0.5,
            isMuted: false,
            deviceName: "MacBook Pro Speakers",
            deviceSymbolName: "macbook",
            isBuiltIn: true
        )
        volumeService.sendVolumeChange(snapshot)
        await Task.yield()

        settings.volumeIconStyle = .device
        await Task.yield()
        XCTAssertEqual(viewModel.volumeIconSymbolName, snapshot.volumeSymbolName)
    }

    func testAirPodsCompactPresentationKeepsConfiguredIslandWidth() {
        XCTAssertNil(CompactMediaPresentationIdentity.headphones.preferredIslandWidth)
        XCTAssertEqual(
            CompactMediaPresentationIdentity.volume.preferredIslandWidth,
            CompactIslandTier.secondTierMinimumWidth
        )
    }

    func testRealtimeMonitoringSettingOnlyControlsCompactIsland() async {
        let suiteName = "NowPlayingViewModelTests.realtime-monitoring"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = MediaMonitoringSettings(defaults: defaults)
        let spectrumProvider = StubSpectrumProvider()
        let viewModel = NowPlayingViewModel(
            service: DelayedMediaRemoteProvider(responses: [
                (snapshot: snapshot(title: "Track A"), delay: .zero)
            ]),
            spectrumProvider: spectrumProvider,
            volumeService: StubAudioOutputVolumeProvider(),
            monitoringSettings: settings
        )

        await viewModel.refresh()
        // 开关关闭：不上岛，但监听与频谱采样仍在运行（支撑展开态与锁屏显示）。
        XCTAssertFalse(viewModel.isRealtimeMusicMonitoringEnabled)
        XCTAssertFalse(viewModel.isCompactMediaDisplayActive)
        XCTAssertEqual(spectrumProvider.startCallCount, 1)

        settings.isRealtimeMusicMonitoringEnabled = true
        XCTAssertTrue(viewModel.isRealtimeMusicMonitoringEnabled)
        XCTAssertTrue(viewModel.isCompactMediaDisplayActive)
        XCTAssertEqual(spectrumProvider.startCallCount, 1)

        settings.isRealtimeMusicMonitoringEnabled = false
        XCTAssertFalse(viewModel.isRealtimeMusicMonitoringEnabled)
        XCTAssertFalse(viewModel.isCompactMediaDisplayActive)
        XCTAssertEqual(spectrumProvider.stopCallCount, 0)

        settings.isRealtimeMusicMonitoringEnabled = true
        XCTAssertTrue(viewModel.isRealtimeMusicMonitoringEnabled)
        XCTAssertTrue(viewModel.isCompactMediaDisplayActive)
        XCTAssertEqual(spectrumProvider.startCallCount, 1)
        XCTAssertTrue(defaults.bool(forKey: "media.realtimeMusicMonitoringEnabled"))
    }

    func testSpectrumStyleSwitchUpdatesTuningWithoutRestartingSampling() async {
        let suiteName = "NowPlayingViewModelTests.spectrum-style"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = MediaMonitoringSettings(defaults: defaults)
        settings.isRealtimeMusicMonitoringEnabled = true
        let spectrumProvider = StubSpectrumProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(snapshot: snapshot(title: "Track A")),
            spectrumProvider: spectrumProvider,
            volumeService: StubAudioOutputVolumeProvider(),
            monitoringSettings: settings
        )

        await viewModel.refresh()
        XCTAssertEqual(spectrumProvider.startCallCount, 1)

        settings.musicSpectrumBarStyle = .seven
        settings.sevenBarSpectrumSensitivity = 0.76
        settings.sevenBarSpectrumAttackTime = 0.84
        settings.sevenBarSpectrumReleaseTime = 0.84
        settings.musicSpectrumBarWidthScale = 2.6
        settings.musicSpectrumBarSpacingScale = 1.8
        settings.musicSpectrumCornerRadiusScale = 0.64
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.style, .five)
        await Task.yield()

        XCTAssertEqual(viewModel.musicSpectrumConfiguration.style, .seven)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.sensitivity, 0.76)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.attackTime, 0.84)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.releaseTime, 0.84)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.barWidthScale, 2.6)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.barSpacingScale, 1.8)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.barCornerRadiusScale, 0.64)
        XCTAssertEqual(spectrumProvider.startCallCount, 1)
        XCTAssertEqual(spectrumProvider.stopCallCount, 0)

        settings.musicSpectrumBarStyle = .five
        settings.fiveBarSpectrumSensitivity = 0.31
        settings.fiveBarSpectrumAttackTime = 0.42
        settings.fiveBarSpectrumReleaseTime = 0.42
        settings.musicSpectrumBarWidthScale = 2.2
        settings.musicSpectrumBarSpacingScale = 1.4
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.style, .seven)
        await Task.yield()

        XCTAssertEqual(viewModel.musicSpectrumConfiguration.style, .five)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.sensitivity, 0.31)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.attackTime, 0.42)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.releaseTime, 0.42)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.barWidthScale, 2.2)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.barSpacingScale, 1.4)
        XCTAssertEqual(viewModel.musicSpectrumConfiguration.barCornerRadiusScale, 0.64)
        XCTAssertEqual(spectrumProvider.startCallCount, 1)
        XCTAssertEqual(spectrumProvider.stopCallCount, 0)

        let restored = MediaMonitoringSettings(defaults: defaults)
        XCTAssertEqual(restored.musicSpectrumBarStyle, .five)
        XCTAssertEqual(restored.fiveBarSpectrumSensitivity, 0.31)
        XCTAssertEqual(restored.fiveBarSpectrumAttackTime, 0.42)
        XCTAssertEqual(restored.fiveBarSpectrumReleaseTime, 0.42)
        XCTAssertEqual(restored.sevenBarSpectrumSensitivity, 0.76)
        XCTAssertEqual(restored.sevenBarSpectrumAttackTime, 0.84)
        XCTAssertEqual(restored.sevenBarSpectrumReleaseTime, 0.84)
        XCTAssertEqual(restored.musicSpectrumBarWidthScale, 2.2)
        XCTAssertEqual(restored.musicSpectrumBarSpacingScale, 1.4)
        XCTAssertEqual(restored.musicSpectrumCornerRadiusScale, 0.64)
    }

    func testSpectrumGeometrySettingsMigrateFromSharedValues() {
        let suiteName = "NowPlayingViewModelTests.spectrum-geometry-migration"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.34, forKey: "media.musicSpectrumBarWidthScale")
        defaults.set(0.81, forKey: "media.musicSpectrumBarSpacingScale")

        let settings = MediaMonitoringSettings(defaults: defaults)

        XCTAssertEqual(settings.musicSpectrumBarWidthScale, 2.2555555555555555, accuracy: 0.0001)
        XCTAssertEqual(settings.musicSpectrumBarSpacingScale, 1.9466666666666668, accuracy: 0.0001)
    }

    func testSpectrumPublishingIsGatedToSwiftUIConsumers() async {
        let spectrumProvider = StubSpectrumProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(snapshot: snapshot(title: "Track A")),
            spectrumProvider: spectrumProvider,
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()
        XCTAssertEqual(spectrumProvider.startCallCount, 1)

        // 无 SwiftUI 消费者（锁屏不可见、岛未展开）时，只写共享缓冲，不发布 @Published spectrum。
        spectrumProvider.emit([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7])
        await Task.yield()
        XCTAssertTrue(viewModel.spectrum.isEmpty)

        // 锁屏小组件可见后，开始发布。
        viewModel.setLockScreenSpectrumConsumerActive(true)
        spectrumProvider.emit([0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1])
        await Task.yield()
        XCTAssertEqual(viewModel.spectrum, [0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1])

        // 锁屏小组件隐藏后，停止发布（保留最后一帧）。
        viewModel.setLockScreenSpectrumConsumerActive(false)
        spectrumProvider.emit([0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3])
        await Task.yield()
        XCTAssertEqual(viewModel.spectrum, [0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1])
    }

    func testOlderRefreshCannotOverwriteNewerSnapshot() async {
        let oldSnapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Old Track", artist: "Artist", isPlaying: false),
            status: "old"
        )
        let newSnapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(title: "Current Track", artist: "Artist", isPlaying: true),
            status: "current"
        )
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: oldSnapshot, delay: .milliseconds(200)),
            (snapshot: newSnapshot, delay: .milliseconds(20))
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )

        let olderRefresh = Task { await viewModel.refresh() }
        try? await Task.sleep(for: .milliseconds(10))
        let newerRefresh = Task { await viewModel.refresh() }
        await newerRefresh.value
        await olderRefresh.value

        XCTAssertEqual(viewModel.info?.title, "Current Track")
        XCTAssertEqual(viewModel.statusText, "current")
    }

    func testMediaNotificationBurstPerformsSingleSnapshotRefresh() async throws {
        let provider = StubMediaRemoteProvider(
            snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
        )
        let viewModel = NowPlayingViewModel(
            service: provider,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }
        try await Task.sleep(for: .milliseconds(20))
        let baseline = provider.currentSnapshotCallCount

        for _ in 0..<10 {
            provider.sendChange()
        }
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(provider.currentSnapshotCallCount, baseline + 1)
    }

    func testAudioDeviceListChangesAreDebounced() async throws {
        let volumeService = StubAudioOutputVolumeProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }
        let baseline = volumeService.availableOutputDevicesCallCount

        for _ in 0..<10 {
            volumeService.sendOutputDevicesChange()
        }
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(volumeService.availableOutputDevicesCallCount, baseline + 1)
    }

    func testEverySongChangeWithArtworkPublishesANewNotificationImmediately() async {
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .zero),
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track C"), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0

        await viewModel.refresh()
        XCTAssertNil(viewModel.songNotification)

        await viewModel.refresh()
        let trackBNotificationID = viewModel.songNotification?.id
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")

        await viewModel.refresh()
        let trackANotificationID = viewModel.songNotification?.id
        XCTAssertNotEqual(trackANotificationID, trackBNotificationID)
        XCTAssertEqual(viewModel.songNotification?.title, "Track A")

        await viewModel.refresh()
        XCTAssertNotEqual(viewModel.songNotification?.id, trackANotificationID)
        XCTAssertEqual(viewModel.songNotification?.title, "Track C")
    }

    func testSongNotificationWaitsForCoverSettleBeforePublishing() async throws {
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0.15

        await viewModel.refresh()
        XCTAssertNil(viewModel.songNotification)

        await viewModel.refresh()
        // 落定等待期间：封面还在过渡，横幅暂不弹。
        XCTAssertNil(viewModel.songNotification)

        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
    }

    func testSongBannerReschedulingSupersededBeforeSettle() async throws {
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .zero),
            (snapshot: snapshot(title: "Track C"), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0.15

        await viewModel.refresh()
        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertNil(viewModel.songNotification)

        // 0.15s 内又切到 C：B 的待发横幅被替代，最终只弹 C。
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(viewModel.songNotification?.title, "Track C")
    }

    func testArtistMetadataEnrichmentDoesNotRestartSongNotification() async {
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B", artist: ""), delay: .zero),
            (snapshot: snapshot(title: "Track B", artist: "Artist"), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0

        await viewModel.refresh()
        await viewModel.refresh()
        let notificationID = viewModel.songNotification?.id
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")

        await viewModel.refresh()
        XCTAssertEqual(viewModel.songNotification?.id, notificationID)
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
    }

    func testSongNotificationWaitsForMediaArtworkButSpectrumStartsForPlayingMedia() async {
        let artwork = Data([0x01, 0x02, 0x03])
        let spectrumProvider = StubSpectrumProvider()
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: artwork), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: artwork), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: spectrumProvider,
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0

        await viewModel.refresh()
        XCTAssertTrue(viewModel.isMediaArtworkReady)
        XCTAssertEqual(spectrumProvider.startCallCount, 1)

        await viewModel.refresh()
        XCTAssertFalse(viewModel.isMediaArtworkReady)
        XCTAssertNil(viewModel.songNotification)
        XCTAssertEqual(spectrumProvider.stopCallCount, 0)

        await viewModel.refresh()
        XCTAssertTrue(viewModel.isMediaArtworkReady)
        // 封面字节与上一首完全相同 → 判为「封面可能滞后」，需要下一批确认。
        XCTAssertNil(viewModel.songNotification, "疑似滞后的封面不进横幅")

        await viewModel.refresh()
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
        XCTAssertEqual(viewModel.songNotification?.artworkData, artwork)
        XCTAssertEqual(spectrumProvider.startCallCount, 1)
    }

    func testPlayingMediaWithoutArtworkStillStartsSpectrum() async {
        let spectrumProvider = StubSpectrumProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(
                    info: NowPlayingInfo(
                        title: "Short Video",
                        artist: "",
                        artworkData: nil,
                        isPlaying: true
                    ),
                    status: "playing"
                )
            ),
            spectrumProvider: spectrumProvider,
            volumeService: StubAudioOutputVolumeProvider()
        )

        await viewModel.refresh()

        XCTAssertTrue(viewModel.isCompactMediaDisplayActive)
        XCTAssertFalse(viewModel.isMediaArtworkReady)
        XCTAssertEqual(spectrumProvider.startCallCount, 1)
    }

    func testSongChangeWithoutArtworkHoldsPreviousCoverUntilWindowExpires() async throws {
        let artworkA = Data([0x0A])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: artworkA), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songArtworkWaitInterval = 0.25

        await viewModel.refresh()
        XCTAssertEqual(viewModel.displayArtwork, artworkA)
        XCTAssertFalse(viewModel.isUsingAppIconFallback)

        await viewModel.refresh()
        // 等封面窗口内：真等封面，保留上一张，一次翻面到位而不是先翻到图标。
        XCTAssertEqual(viewModel.displayArtwork, artworkA)
        XCTAssertTrue(viewModel.isSongArtworkPending)

        try await Task.sleep(for: .milliseconds(450))
        // 窗口到期仍未到：翻到 App 图标。测试环境无播放 App 图标，回退为空展示图。
        XCTAssertNil(viewModel.displayArtwork)
        XCTAssertFalse(viewModel.isSongArtworkPending)
    }

    func testRepeatedSnapshotsDoNotExtendArtworkWaitWindow() async throws {
        let artworkA = Data([0x0A])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: artworkA), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songArtworkWaitInterval = 0.2

        await viewModel.refresh()
        await viewModel.refresh()
        try await Task.sleep(for: .milliseconds(150))
        await viewModel.refresh()
        await viewModel.refresh()
        try await Task.sleep(for: .milliseconds(150))
        // 窗口按首次切歌起算，重复快照不重起：否则高频刷新会把等待拖成无限。
        XCTAssertNil(viewModel.displayArtwork)
        XCTAssertFalse(viewModel.isSongArtworkPending)
    }

    func testSongChangeArtworkArrivingWithinWaitFlipsDirectlyToRealCover() async throws {
        let artworkA = Data([0x0A])
        let artworkB = Data([0x0B])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: artworkA), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: artworkB), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songArtworkWaitInterval = 0.5

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertEqual(viewModel.displayArtwork, artworkA, "等封面窗口内保留上一张封面")

        await viewModel.refresh()
        XCTAssertEqual(viewModel.displayArtwork, artworkB)
        XCTAssertFalse(viewModel.isUsingAppIconFallback)
        XCTAssertFalse(viewModel.isSongArtworkPending)

        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(viewModel.displayArtwork, artworkB, "等待期过后不应再回退到图标")
    }

    /// 等不到封面：窗口到期后图标直接成为这首歌的封面。
    func testSongWithoutArtworkUsesIconAsCover() async throws {
        let icon = Data([0x1C, 0x0E])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: Data([0x0A])), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.applicationIconProvider = StubApplicationIconProvider(icon: icon)
        viewModel.songArtworkWaitInterval = 0.15

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertEqual(viewModel.displayArtwork, Data([0x0A]), "窗口内还是上一张封面")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(viewModel.displayArtwork, icon, "等不到封面时图标就是这首歌的封面")
        XCTAssertTrue(viewModel.isUsingAppIconFallback)
    }

    /// 横幅等封面：切歌后封面未到期间不弹；封面到了才弹（对齐封面落定帧）。
    func testSongBannerWaitsForArtworkThenPublishesWithIt() async throws {
        let artworkA = Data([0x0A])
        let artworkB = Data([0x0B])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: artworkA), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: artworkB), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0
        viewModel.songArtworkWaitInterval = 0.4

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertNil(viewModel.songNotification, "新歌封面未到时不弹横幅")

        await viewModel.refresh()
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
        XCTAssertEqual(viewModel.songNotification?.artworkData, artworkB)
    }

    /// 封面一直不到：等待窗口到期后横幅照弹，图图标即封面。
    func testSongBannerFallsBackToIconWhenArtworkNeverArrives() async throws {
        let icon = Data([0x1C, 0x0E])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: Data([0x0A])), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.applicationIconProvider = StubApplicationIconProvider(icon: icon)
        viewModel.songBannerSettleDelay = 0
        viewModel.songArtworkWaitInterval = 0.15

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertNil(viewModel.songNotification, "还在等封面时不弹横幅")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
        XCTAssertEqual(viewModel.songNotification?.artworkData, icon, "等不到封面时横幅用图标当封面")
    }

    func testArtworklessSongDoesNotNotifyAgainOnRepeatedSnapshots() async throws {
        let icon = Data([0x1C, 0x0E])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.applicationIconProvider = StubApplicationIconProvider(icon: icon)
        viewModel.songArtworkWaitInterval = 0.05
        viewModel.songBannerSettleDelay = 0
        viewModel.songBannerIdempotencyWindow = 0

        await viewModel.refresh()
        await viewModel.refresh()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
        viewModel.dismissSongNotification()

        for _ in 0..<3 {
            await viewModel.refresh()
            XCTAssertFalse(viewModel.isSongArtworkPending, "同一首无封面歌曲不应再次等封面")
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(viewModel.songNotification, "同一首歌的状态刷新不应再次弹出通知")
    }

    /// MediaRemote 先推新歌、封面还停在上一首：横幅不能整段生命周期都挂着旧封面。
    func testBannerArtworkIsCorrectedWhenRealCoverArrivesAfterStaleOne() async throws {
        let staleCover = Data([0xA1])
        let realCover = Data([0xB2])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: staleCover), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: staleCover), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: realCover), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertNil(viewModel.songNotification, "上一首的封面不能作为新歌的横幅封面")

        await viewModel.refresh()
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
        XCTAssertEqual(viewModel.songNotification?.artworkData, realCover, "真封面到达后横幅用真封面")
    }

    /// 相邻两首歌真的共用同一张封面（同一专辑连播）：确认一批后直接认下，
    /// 不进图标兜底、也不换图。
    func testSharedArtworkAcrossSongsIsAdoptedAfterConfirmation() async throws {
        let shared = Data([0xA1, 0xA2])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: shared), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: shared), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: shared), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.applicationIconProvider = StubApplicationIconProvider(icon: Data([0x1C]))
        viewModel.songBannerSettleDelay = 0

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertNil(viewModel.songNotification, "等确认期间不弹")

        await viewModel.refresh()
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
        XCTAssertEqual(
            viewModel.songNotification?.artworkData,
            shared,
            "确认是同一张封面后应直接用它，而不是退到 App 图标"
        )
        XCTAssertFalse(viewModel.isUsingAppIconFallback)
    }

    /// 封面疑似滞后且一直不更新：等到窗口结束退回 App 图标，横照也不带旧封面。
    func testSuspectedStaleCoverFallsBackToIconInsteadOfOldCover() async throws {
        let staleCover = Data([0xA1])
        let icon = Data([0x1C, 0x0E])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: staleCover), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: staleCover), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.applicationIconProvider = StubApplicationIconProvider(icon: icon)
        viewModel.songBannerSettleDelay = 0
        viewModel.songArtworkWaitInterval = 0.15

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertNil(viewModel.songNotification)

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
        XCTAssertEqual(viewModel.songNotification?.artworkData, icon, "宁可退回图标，也不发上一首的封面")
    }

    /// 同一首歌的横幅永不重复创建：封面晚到只更正图，id 不变。
    func testLateCoverNeverCreatesSecondBannerForSameSong() async throws {
        let icon = Data([0x1C, 0x0E])
        let realCover = Data([0xC3, 0xC4])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: Data([0x0A])), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: realCover), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.applicationIconProvider = StubApplicationIconProvider(icon: icon)
        viewModel.songBannerSettleDelay = 0
        viewModel.songArtworkWaitInterval = 0.15

        await viewModel.refresh()
        await viewModel.refresh()
        try await Task.sleep(for: .milliseconds(300))
        let iconBannerID = viewModel.songNotification?.id
        XCTAssertEqual(viewModel.songNotification?.artworkData, icon)

        // 真封面远晚于第一条横幅（超出幂等窗口也一样）→ 只更正，不新建。
        viewModel.songBannerIdempotencyWindow = 0
        await viewModel.refresh()
        XCTAssertEqual(viewModel.songNotification?.artworkData, realCover, "封面补到后横幅要就地改正图")
        XCTAssertEqual(viewModel.songNotification?.id, iconBannerID, "同key 横幅不新建、不重播动画")
    }

    /// 图标兜底弹出横幅后真封面才到：横幅同步换成真封面，不被去重窗口挡住。
    func testBannerArtworkIsCorrectedWhenCoverArrivesAfterIconFallback() async throws {
        let icon = Data([0x1C, 0x0E])
        let realCover = Data([0xC3])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: Data([0x0A])), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: realCover), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.applicationIconProvider = StubApplicationIconProvider(icon: icon)
        viewModel.songBannerSettleDelay = 0
        viewModel.songArtworkWaitInterval = 0.15

        await viewModel.refresh()
        await viewModel.refresh()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(viewModel.songNotification?.artworkData, icon)

        await viewModel.refresh()
        XCTAssertEqual(viewModel.songNotification?.artworkData, realCover, "真封面补到后横幅要从图标换成真封面")
    }

    /// 封面在横幅等待落定期间换到：横幅弹出时直接就是最终封面。
    func testPendingBannerPicksUpNewArtworkBeforePresenting() async throws {
        let staleCover = Data([0xA1])
        let realCover = Data([0xB2])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: staleCover), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: staleCover), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: realCover), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0.2

        await viewModel.refresh()
        await viewModel.refresh()
        await viewModel.refresh()
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
        XCTAssertEqual(viewModel.songNotification?.artworkData, realCover, "落定期间换了封面，横幅弹出时应是最终封面")
    }

    /// 同一首歌的封面瞬时缺失（暂停等空报）：画面不动，不该闪一下图标。
    func testSameSongTransientArtworkDropKeepsCurrentCover() async throws {
        let artworkA = Data([0x0A])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: artworkA), delay: .zero),
            (snapshot: snapshot(title: "Track A", hasArtwork: false), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songArtworkWaitInterval = 0.1

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertEqual(viewModel.displayArtwork, artworkA)
        XCTAssertFalse(viewModel.isSongArtworkPending)
    }

    func testNextClearsPreviousSongNotificationWhileMetadataIsPending() async {
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")

        viewModel.next()

        XCTAssertNil(viewModel.songNotification)
    }

    func testSwitchingAudioOutputToAirPodsShowsCompactEarNotificationWithoutPanel() async {
        let volumeService = StubAudioOutputVolumeProvider()
        let bluetoothService = StubBluetoothConnectionProvider(percentage: 82)
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService,
            bluetoothConnectionService: bluetoothService
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }

        volumeService.sendOutputDeviceChange(
            audioOutput(name: "Jobeth 的 AirPods Pro", symbol: "airpodspro")
        )
        await Task.yield()
        for _ in 0..<20 where viewModel.headphoneConnectionPresentation?.batteryPercentage == nil {
            await Task.yield()
        }

        XCTAssertNil(viewModel.audioOutputNotification)
        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.deviceName, "Jobeth 的 AirPods Pro")
        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.deviceSymbolName, "airpodspro")
        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.batteryPercentage, 82)
        XCTAssertEqual(bluetoothService.requestCount, 1)
        XCTAssertFalse(viewModel.isHeadphoneConnectionDismissing)
    }

    func testSwitchingAudioOutputToBuiltInSpeakersIsSilent() async {
        let volumeService = StubAudioOutputVolumeProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }

        volumeService.sendOutputDeviceChange(
            audioOutput(name: "MacBook Pro 扬声器", symbol: "macbook")
        )
        await Task.yield()

        XCTAssertNil(viewModel.audioOutputNotification)
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
    }

    func testSelectingAudioOutputUpdatesSystemRouteAndCurrentDevice() {
        let speakers = AudioOutputDevice(
            id: 10,
            deviceName: "MacBook Pro 扬声器",
            deviceSymbolName: "macbook",
            isCurrent: true
        )
        let headphones = AudioOutputDevice(
            id: 20,
            deviceName: "Studio Headphones",
            deviceSymbolName: "headphones",
            isCurrent: false
        )
        let volumeService = StubAudioOutputVolumeProvider(devices: [speakers, headphones])
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }

        XCTAssertEqual(viewModel.availableAudioOutputs, [speakers, headphones])

        viewModel.selectAudioOutputDevice(headphones)

        XCTAssertEqual(volumeService.selectedDeviceID, headphones.id)
        XCTAssertEqual(viewModel.currentAudioOutput, headphones.snapshot)
        XCTAssertEqual(viewModel.availableAudioOutputs.first(where: { $0.id == speakers.id })?.isCurrent, false)
        XCTAssertEqual(viewModel.availableAudioOutputs.first(where: { $0.id == headphones.id })?.isCurrent, true)
    }

    func testSwitchingAudioOutputToDisplayIsSilent() async {
        let volumeService = StubAudioOutputVolumeProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }

        volumeService.sendOutputDeviceChange(
            audioOutput(name: "Studio Display", symbol: "display")
        )
        await Task.yield()

        XCTAssertNil(viewModel.audioOutputNotification)
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
    }

    func testSwitchingAudioOutputToGenericBluetoothHeadphonesShowsCompactNotification() async {
        let volumeService = StubAudioOutputVolumeProvider()
        let bluetoothService = StubBluetoothConnectionProvider(percentage: 70)
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService,
            bluetoothConnectionService: bluetoothService
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }

        volumeService.sendOutputDeviceChange(
            audioOutput(name: "Studio Headphones", symbol: "headphones")
        )
        await Task.yield()
        for _ in 0..<20 where viewModel.headphoneConnectionPresentation?.batteryPercentage == nil {
            await Task.yield()
        }

        XCTAssertNil(viewModel.audioOutputNotification)
        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.deviceName, "Studio Headphones")
        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.deviceSymbolName, "headphones")
        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.batteryPercentage, 70)
        XCTAssertEqual(bluetoothService.requestCount, 1)
    }

    func testNonHeadphoneOutputSwitchClearsVisibleOutputSwitchCompactNotification() async {
        let volumeService = StubAudioOutputVolumeProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }

        volumeService.sendOutputDeviceChange(
            audioOutput(name: "Jobeth 的 AirPods Pro", symbol: "airpodspro")
        )
        await Task.yield()
        volumeService.sendOutputDeviceChange(
            audioOutput(name: "MacBook Pro 扬声器", symbol: "macbook")
        )
        await Task.yield()

        XCTAssertNil(viewModel.audioOutputNotification)
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
        XCTAssertEqual(viewModel.currentAudioOutput?.deviceName, "MacBook Pro 扬声器")
    }

    func testAirPodsBluetoothConnectionShowsConnectedPanelOnly() {
        let viewModel = makeViewModel(
            snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
        )

        viewModel.handleBluetoothDeviceConnection(airPodsSnapshot(battery: 82))

        XCTAssertEqual(viewModel.audioOutputNotification?.deviceName, "Jobeth 的 AirPods Pro")
        XCTAssertEqual(viewModel.audioOutputNotification?.deviceSymbolName, "airpodspro")
        XCTAssertEqual(viewModel.audioOutputNotification?.notificationStatusText, "已连接")
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
        XCTAssertFalse(viewModel.hasCompactTransientPresentation)
    }

    func testAirPodsOutputChangeAfterBluetoothConnectionKeepsConnectedPanelAndShowsCompactSwitch() async {
        let bluetoothService = StubBluetoothConnectionProvider(percentage: 82)
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(),
            bluetoothConnectionService: bluetoothService
        )

        viewModel.handleBluetoothDeviceConnection(airPodsSnapshot(battery: 82))
        viewModel.handleAudioOutputDeviceChange(
            audioOutput(name: "Jobeth 的 AirPods Pro", symbol: "airpodspro")
        )
        for _ in 0..<20 where viewModel.headphoneConnectionPresentation?.batteryPercentage == nil {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.audioOutputNotification?.deviceName, "Jobeth 的 AirPods Pro")
        XCTAssertEqual(viewModel.audioOutputNotification?.notificationStatusText, "已连接")
        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.deviceName, "Jobeth 的 AirPods Pro")
        XCTAssertEqual(viewModel.headphoneConnectionPresentation?.batteryPercentage, 82)
        XCTAssertTrue(viewModel.hasCompactTransientPresentation)
        XCTAssertEqual(bluetoothService.requestCount, 1)
        XCTAssertEqual(viewModel.currentAudioOutput?.deviceName, "Jobeth 的 AirPods Pro")
    }

    func testBluetoothConnectionPanelResumesAfterDragExpansionCollapses() async throws {
        let notchViewModel = NotchViewModel(
            interactionSettings: NotchInteractionSettings(
                defaults: nil,
                hideDelay: 0,
                startsHidden: true
            )
        )
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(),
            notchViewModel: notchViewModel
        )

        notchViewModel.beginDragging()
        notchViewModel.endDragging()
        viewModel.handleBluetoothDeviceConnection(airPodsSnapshot(battery: 82))
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
        XCTAssertNil(viewModel.audioOutputNotification)

        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertFalse(notchViewModel.isExpanded)

        viewModel.handleBluetoothDeviceConnection(airPodsSnapshot(battery: 82))
        XCTAssertEqual(viewModel.audioOutputNotification?.notificationStatusText, "已连接")
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
    }

    func testGenericBluetoothHeadphonesConnectionShowsConnectedPanelOnly() {
        let viewModel = makeViewModel(
            snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
        )
        viewModel.handleBluetoothDeviceConnection(
            ConnectedHeadphonesSnapshot(
                deviceName: "Studio Headphones",
                deviceSymbolName: "headphones",
                batteryPercentage: 70
            )
        )

        XCTAssertEqual(viewModel.audioOutputNotification?.deviceName, "Studio Headphones")
        XCTAssertEqual(viewModel.audioOutputNotification?.notificationStatusText, "已连接")
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
    }

    func testBluetoothBatteryUpdateDoesNotCreateEarAnimation() {
        let viewModel = makeViewModel(
            snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
        )
        viewModel.handleBluetoothDeviceConnection(airPodsSnapshot(battery: nil))

        viewModel.handleBluetoothDeviceConnection(airPodsSnapshot(battery: 76))

        XCTAssertEqual(viewModel.audioOutputNotification?.deviceName, "Jobeth 的 AirPods Pro")
        XCTAssertEqual(viewModel.audioOutputNotification?.notificationStatusText, "已连接")
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
    }

    func testSongChangeDuringDeviceNotificationTakesOverPanel() async {
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0

        await viewModel.refresh()
        viewModel.handleBluetoothDeviceConnection(airPodsSnapshot(battery: 82))
        XCTAssertNotNil(viewModel.audioOutputNotification)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.songNotification?.title, "Track B")
        XCTAssertNil(viewModel.audioOutputNotification)
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
    }

    func testExpandedIslandSuppressesAllMediaNotifications() async {
        let notchViewModel = makeNotchViewModel()
        let volumeService = StubAudioOutputVolumeProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService,
            notchViewModel: notchViewModel
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }
        notchViewModel.click()

        volumeService.sendVolumeChange(
            AudioOutputVolumeSnapshot(
                volume: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro 扬声器",
                deviceSymbolName: "macbook"
            )
        )
        volumeService.sendOutputDeviceChange(
            audioOutput(name: "Studio Display", symbol: "display")
        )
        viewModel.handleBluetoothDeviceConnection(airPodsSnapshot(battery: 80))
        await Task.yield()

        XCTAssertNil(viewModel.volumePresentation)
        XCTAssertNil(viewModel.audioOutputNotification)
        XCTAssertNil(viewModel.headphoneConnectionPresentation)

        let songService = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .zero),
            (snapshot: snapshot(title: "Track C"), delay: .zero),
        ])
        let songViewModel = NowPlayingViewModel(
            service: songService,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(),
            notchViewModel: notchViewModel
        )
        songViewModel.songBannerSettleDelay = 0

        await songViewModel.refresh()
        await songViewModel.refresh()
        notchViewModel.click()
        await songViewModel.refresh()
        XCTAssertNil(songViewModel.songNotification)

        await songViewModel.refresh()
        XCTAssertEqual(songViewModel.songNotification?.title, "Track C")
    }

    func testExpandingIslandImmediatelyClearsVisibleMediaNotifications() async {
        let notchViewModel = makeNotchViewModel()
        let volumeService = StubAudioOutputVolumeProvider()
        let viewModel = NowPlayingViewModel(
            service: StubMediaRemoteProvider(
                snapshot: MediaRemoteSnapshot(info: nil, status: "idle")
            ),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService,
            notchViewModel: notchViewModel
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }

        volumeService.sendVolumeChange(
            AudioOutputVolumeSnapshot(
                volume: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro 扬声器",
                deviceSymbolName: "macbook"
            )
        )
        volumeService.sendOutputDeviceChange(
            audioOutput(name: "Studio Display", symbol: "display")
        )
        viewModel.handleBluetoothDeviceConnection(airPodsSnapshot(battery: 80))
        await Task.yield()
        XCTAssertNotNil(viewModel.volumePresentation)
        XCTAssertNotNil(viewModel.audioOutputNotification)
        XCTAssertNil(viewModel.headphoneConnectionPresentation)

        notchViewModel.click()

        XCTAssertNil(viewModel.volumePresentation)
        XCTAssertNil(viewModel.audioOutputNotification)
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
        XCTAssertFalse(viewModel.isAudioOutputNotificationDismissing)
        XCTAssertFalse(viewModel.isHeadphoneConnectionDismissing)

        notchViewModel.click()
        let songService = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .zero),
        ])
        let songViewModel = NowPlayingViewModel(
            service: songService,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(),
            notchViewModel: notchViewModel
        )
        songViewModel.songBannerSettleDelay = 0
        await songViewModel.refresh()
        await songViewModel.refresh()
        XCTAssertEqual(songViewModel.songNotification?.title, "Track B")

        notchViewModel.click()

        XCTAssertNil(songViewModel.songNotification)
    }

    func testRefreshCrossingExpandedStateDoesNotPublishAfterCollapse() async {
        let notchViewModel = makeNotchViewModel()
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .milliseconds(100)),
            (snapshot: snapshot(title: "Track C"), delay: .zero),
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider(),
            notchViewModel: notchViewModel
        )
        viewModel.songBannerSettleDelay = 0
        await viewModel.refresh()

        let refresh = Task { await viewModel.refresh() }
        try? await Task.sleep(for: .milliseconds(20))
        notchViewModel.click()
        notchViewModel.click()
        await refresh.value

        XCTAssertNil(viewModel.songNotification)
        XCTAssertEqual(viewModel.info?.title, "Track B")

        await viewModel.refresh()
        XCTAssertEqual(viewModel.songNotification?.title, "Track C")
    }

    func testDisabledNotificationSwitchesSuppressAllMediaAlerts() async {
        let settings = IslandNotificationSettings(defaults: nil)
        settings.isSongChangeEnabled = false
        settings.isVolumeAdjustmentEnabled = false
        settings.isAudioOutputChangeEnabled = false
        settings.isBluetoothConnectionEnabled = false

        let volumeService = StubAudioOutputVolumeProvider()
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .zero),
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: volumeService,
            notificationSettings: settings
        )
        viewModel.startObserving()
        defer { viewModel.stopObserving() }

        await viewModel.refresh()
        await viewModel.refresh()
        volumeService.sendVolumeChange(
            AudioOutputVolumeSnapshot(
                volume: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro 扬声器",
                deviceSymbolName: "macbook"
            )
        )
        volumeService.sendOutputDeviceChange(
            audioOutput(name: "Studio Display", symbol: "display")
        )
        viewModel.handleBluetoothDeviceConnection(airPodsSnapshot(battery: 80))
        await Task.yield()

        XCTAssertNil(viewModel.songNotification)
        XCTAssertNil(viewModel.volumePresentation)
        XCTAssertNil(viewModel.audioOutputNotification)
        XCTAssertNil(viewModel.headphoneConnectionPresentation)
    }

    func testMissingMetadataDismissesPreviousSongNotification() async {
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A"), delay: .zero),
            (snapshot: snapshot(title: "Track B"), delay: .zero),
            (snapshot: MediaRemoteSnapshot(info: nil, status: "switching"), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songBannerSettleDelay = 0

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertEqual(viewModel.songNotification?.title, "Track B")

        await viewModel.refresh()

        XCTAssertNil(viewModel.songNotification)
    }

    func testSongArtworkPendingSpansWaitWindowUntilArtworkArrives() async throws {
        let artworkA = Data([0x0A])
        let artworkB = Data([0x0B])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: artworkA), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero),
            (snapshot: snapshot(title: "Track B", artworkData: artworkB), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songArtworkWaitInterval = 0.25

        await viewModel.refresh()
        XCTAssertFalse(viewModel.isSongArtworkPending, "封面就绪时不应等待")

        await viewModel.refresh()
        // 等待期内：封面还没到，横幅等真封面；画面保留上一张封面。
        XCTAssertTrue(viewModel.isSongArtworkPending)
        XCTAssertEqual(viewModel.displayArtwork, artworkA)

        await viewModel.refresh()
        XCTAssertFalse(viewModel.isSongArtworkPending, "封面到达后应解除等待")
        XCTAssertEqual(viewModel.displayArtwork, artworkB)
    }

    func testSongArtworkPendingClearsWhenWaitTimesOut() async throws {
        let artworkA = Data([0x0A])
        let service = DelayedMediaRemoteProvider(responses: [
            (snapshot: snapshot(title: "Track A", artworkData: artworkA), delay: .zero),
            (snapshot: snapshot(title: "Track B", hasArtwork: false), delay: .zero)
        ])
        let viewModel = NowPlayingViewModel(
            service: service,
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
        viewModel.songArtworkWaitInterval = 0.1

        await viewModel.refresh()
        await viewModel.refresh()
        XCTAssertTrue(viewModel.isSongArtworkPending)

        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(
            viewModel.isSongArtworkPending,
            "等待超时应认定该歌没有封面：图标定格，横照弹"
        )
    }

    /// 固定返回同一份图标数据，替身系统读取播放 App 图标。
    private final class StubApplicationIconProvider: ApplicationIconProvider {
        private let icon: Data?

        init(icon: Data?) {
            self.icon = icon
        }

        override func iconData(forPID pid: Int32?) -> Data? {
            icon
        }
    }

    /// 默认封面按「歌名 + 歌手」派生：切歌时封面字节与上一首完全相同会被判成
    /// 「封面滞后一批」，所有歌共用一份默认数据会让多曲用例全部失真。
    /// 要表达「没有封面」用 hasArtwork: false。
    private func snapshot(
        title: String,
        artist: String = "Artist",
        artworkData: Data? = nil,
        hasArtwork: Bool = true
    ) -> MediaRemoteSnapshot {
        let artwork: Data? = hasArtwork
            ? artworkData ?? Data("artwork|\(title)|\(artist)".utf8)
            : nil
        return MediaRemoteSnapshot(
            info: NowPlayingInfo(
                title: title,
                artist: artist,
                artworkData: artwork,
                isPlaying: true
            ),
            status: title
        )
    }

    private func audioOutput(name: String, symbol: String) -> AudioOutputDeviceSnapshot {
        AudioOutputDeviceSnapshot(
            deviceName: name,
            deviceSymbolName: symbol
        )
    }

    private func airPodsSnapshot(battery: Int?) -> ConnectedHeadphonesSnapshot {
        ConnectedHeadphonesSnapshot(
            deviceName: "Jobeth 的 AirPods Pro",
            deviceSymbolName: "airpodspro",
            batteryPercentage: battery
        )
    }

    private func makeNotchViewModel() -> NotchViewModel {
        NotchViewModel(
            interactionSettings: NotchInteractionSettings(defaults: nil, startsHidden: true)
        )
    }

    private func makeViewModel(snapshot: MediaRemoteSnapshot) -> NowPlayingViewModel {
        NowPlayingViewModel(
            service: StubMediaRemoteProvider(snapshot: snapshot),
            spectrumProvider: StubSpectrumProvider(),
            volumeService: StubAudioOutputVolumeProvider()
        )
    }

    private func spotifySnapshot(title: String) -> MediaRemoteSnapshot {
        MediaRemoteSnapshot(
            info: NowPlayingInfo(
                title: title,
                artist: "Artist",
                sourceBundleIdentifier: "com.spotify.client",
                isPlaying: true
            ),
            status: "playing"
        )
    }
}

private final class StubMediaRemoteProvider: MediaRemoteProviding, @unchecked Sendable {
    var snapshot: MediaRemoteSnapshot
    let shuffleResult: Bool?
    let favoriteResult: Bool?
    var shuffleStateResult: Bool?
    private(set) var currentSnapshotCallCount = 0
    private(set) var shuffleStateCallCount = 0
    private(set) var toggleShuffleCallCount = 0
    private(set) var toggleFavoriteCallCount = 0
    private var onChange: (@Sendable () -> Void)?

    init(
        snapshot: MediaRemoteSnapshot,
        shuffleStateResult: Bool? = nil,
        shuffleResult: Bool? = nil,
        favoriteResult: Bool? = nil
    ) {
        self.snapshot = snapshot
        self.shuffleStateResult = shuffleStateResult
        self.shuffleResult = shuffleResult
        self.favoriteResult = favoriteResult
    }

    func currentSnapshot() async -> MediaRemoteSnapshot {
        currentSnapshotCallCount += 1
        return snapshot
    }
    func startObserving(_ onChange: @Sendable @escaping () -> Void) {
        self.onChange = onChange
    }
    func stopObserving() {
        onChange = nil
    }
    func sendChange() {
        onChange?()
    }
    func togglePlay() {}
    func shuffleState() async -> Bool? {
        shuffleStateCallCount += 1
        return shuffleStateResult
    }
    func toggleShuffle() async -> Bool? {
        toggleShuffleCallCount += 1
        return shuffleResult
    }
    func toggleFavorite() async -> Bool? {
        toggleFavoriteCallCount += 1
        return favoriteResult
    }
    func seek(to position: TimeInterval) {}
    func next() {}
    func previous() {}
}

private final class DelayedMediaRemoteProvider: MediaRemoteProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(snapshot: MediaRemoteSnapshot, delay: Duration)]
    private var lastResponse: (snapshot: MediaRemoteSnapshot, delay: Duration)?

    init(responses: [(snapshot: MediaRemoteSnapshot, delay: Duration)]) {
        self.responses = responses
        lastResponse = responses.last
    }

    func currentSnapshot() async -> MediaRemoteSnapshot {
        let response = lock.withLock {
            guard !responses.isEmpty else {
                return lastResponse ?? (
                    snapshot: MediaRemoteSnapshot(info: nil, status: "empty"),
                    delay: .zero
                )
            }
            let response = responses.removeFirst()
            lastResponse = response
            return response
        }
        try? await Task.sleep(for: response.delay)
        return response.snapshot
    }

    func startObserving(_ onChange: @Sendable @escaping () -> Void) {}
    func stopObserving() {}
    func togglePlay() {}
    func shuffleState() async -> Bool? { nil }
    func toggleShuffle() async -> Bool? { nil }
    func toggleFavorite() async -> Bool? { nil }
    func seek(to position: TimeInterval) {}
    func next() {}
    func previous() {}
}

private final class StubSpectrumProvider: AudioSpectrumProviding {
    let bandCount = AudioSpectrumConfiguration.sampledBandCount
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var onUpdate: (([Float]) -> Void)?

    func start(onUpdate: @escaping ([Float]) -> Void) {
        startCallCount += 1
        self.onUpdate = onUpdate
    }

    func stop() {
        stopCallCount += 1
        onUpdate = nil
    }

    func emit(_ values: [Float]) {
        onUpdate?(values)
    }
}

private final class StubBluetoothConnectionProvider: BluetoothDeviceConnectionProviding,
    @unchecked Sendable
{
    let percentage: Int?
    private(set) var requestCount = 0
    private var onDeviceConnected: (@Sendable (ConnectedHeadphonesSnapshot) -> Void)?

    init(percentage: Int?) {
        self.percentage = percentage
    }

    func startObserving(
        onDeviceConnected: @Sendable @escaping (ConnectedHeadphonesSnapshot) -> Void
    ) {
        self.onDeviceConnected = onDeviceConnected
    }

    func stopObserving() {
        onDeviceConnected = nil
    }

    func batteryPercentage(for deviceName: String) async -> Int? {
        requestCount += 1
        return percentage
    }
}

private final class StubAudioOutputVolumeProvider: AudioOutputVolumeProviding, @unchecked Sendable {
    private var onVolumeChange: (@Sendable (AudioOutputVolumeSnapshot) -> Void)?
    private var onOutputDeviceChange: (@Sendable (AudioOutputDeviceSnapshot) -> Void)?
    private var onOutputDevicesChange: (@Sendable () -> Void)?
    private var devices: [AudioOutputDevice]
    private(set) var selectedDeviceID: UInt32?
    private(set) var availableOutputDevicesCallCount = 0

    init(devices: [AudioOutputDevice] = []) {
        self.devices = devices
    }

    func startObserving(
        onVolumeChange: @Sendable @escaping (AudioOutputVolumeSnapshot) -> Void,
        onOutputDeviceChange: @Sendable @escaping (AudioOutputDeviceSnapshot) -> Void
    ) {
        self.onVolumeChange = onVolumeChange
        self.onOutputDeviceChange = onOutputDeviceChange
    }

    func stopObserving() {
        onVolumeChange = nil
        onOutputDeviceChange = nil
        onOutputDevicesChange = nil
    }

    func perform(_ command: AudioOutputVolumeCommand) -> Bool { false }

    func currentOutputDevice() -> AudioOutputDeviceSnapshot? {
        devices.first(where: \.isCurrent)?.snapshot
    }

    func availableOutputDevices() -> [AudioOutputDevice] {
        availableOutputDevicesCallCount += 1
        return devices
    }

    func selectOutputDevice(id: UInt32) -> Bool {
        guard devices.contains(where: { $0.id == id }) else { return false }
        selectedDeviceID = id
        devices = devices.map { device in
            AudioOutputDevice(
                id: device.id,
                deviceName: device.deviceName,
                deviceSymbolName: device.deviceSymbolName,
                isCurrent: device.id == id
            )
        }
        return true
    }

    func setOutputDevicesChangeHandler(_ onChange: @Sendable @escaping () -> Void) {
        onOutputDevicesChange = onChange
    }

    func sendVolumeChange(_ snapshot: AudioOutputVolumeSnapshot) {
        onVolumeChange?(snapshot)
    }

    func sendOutputDeviceChange(_ snapshot: AudioOutputDeviceSnapshot) {
        onOutputDeviceChange?(snapshot)
    }

    func sendOutputDevicesChange() {
        onOutputDevicesChange?()
    }
}
