import XCTest
@testable import MediaModule

final class MediaSnapshotArbiterTests: XCTestCase {
    func testPausedSessionDoesNotInheritAnotherApplicationGlobalPlayingState() {
        XCTAssertFalse(
            MediaRemotePlaybackStateResolver.resolve(
                playbackRate: 0
            )
        )
        XCTAssertTrue(
            MediaRemotePlaybackStateResolver.resolve(
                playbackRate: 1
            )
        )
        XCTAssertFalse(
            MediaRemotePlaybackStateResolver.resolve(
                playbackRate: nil
            )
        )
    }

    func testEmptySnapshotDoesNotReplaceSourceThatIsStillProducingAudio() {
        let arbiter = MediaSnapshotArbiter()
        let qqMusic = snapshot(title: "QQ Track", pid: 101, isPlaying: true)
        let empty = MediaRemoteSnapshot(info: nil, status: "empty")

        _ = select(qqMusic, with: arbiter, audioPIDs: [101])
        let selected = select(empty, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected.info?.title, "QQ Track")
        XCTAssertTrue(selected.info?.isPlaying == true)
    }

    func testEmptySnapshotClearsSourceAfterAudioStops() {
        let arbiter = MediaSnapshotArbiter()
        let playing = snapshot(title: "Track", pid: 101, isPlaying: true)
        let empty = MediaRemoteSnapshot(info: nil, status: "empty")

        _ = select(playing, with: arbiter, audioPIDs: [101])
        let selected = select(empty, with: arbiter, audioPIDs: [])

        XCTAssertNil(selected.info)
    }

    func testPausedDifferentApplicationDoesNotReplaceAudioProducingSource() {
        let arbiter = MediaSnapshotArbiter()
        let qqMusic = snapshot(title: "QQ Track", pid: 101, isPlaying: true)
        let netease = snapshot(title: "Netease Track", pid: 202, isPlaying: false)

        _ = select(qqMusic, with: arbiter, audioPIDs: [101])
        let selected = select(netease, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected.info?.title, "QQ Track")
        XCTAssertEqual(selected.info?.appPID, 101)
        XCTAssertTrue(selected.info?.isPlaying == true)
    }

    func testPausedMetadataWithCurrentPIDStopsSourceWithoutTitleMixing() {
        let arbiter = MediaSnapshotArbiter()
        let qqMusic = snapshot(title: "QQ Track", pid: 101, isPlaying: true)
        // MediaRemote 切换应用时可能已返回网易云元数据，但 PID 仍短暂保留为 QQ。
        let mixedNetease = snapshot(title: "Netease Track", pid: 101, isPlaying: false)

        _ = select(qqMusic, with: arbiter, audioPIDs: [101])
        let selected = select(mixedNetease, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected.info?.title, "QQ Track")
        XCTAssertFalse(selected.info?.isPlaying == true)
    }

    func testPlayingTrackChangeFromSameAudioProducingSourceIsAccepted() {
        let arbiter = MediaSnapshotArbiter()
        let firstTrack = snapshot(title: "QQ Track 1", pid: 101, isPlaying: true)
        let secondTrack = snapshot(title: "QQ Track 2", pid: 101, isPlaying: true)

        _ = select(firstTrack, with: arbiter, audioPIDs: [101])
        let selected = select(secondTrack, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected, secondTrack)
    }

    func testStaleTrackFromSameSourceDoesNotReplaceNewerTrack() {
        let arbiter = MediaSnapshotArbiter()
        let oldTrack = snapshot(
            title: "Track A",
            pid: 101,
            isPlaying: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newTrack = snapshot(
            title: "Track B",
            pid: 101,
            isPlaying: true,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let staleOldTrack = snapshot(
            title: "Track A",
            pid: 101,
            isPlaying: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        _ = select(oldTrack, with: arbiter, audioPIDs: [101])
        _ = select(newTrack, with: arbiter, audioPIDs: [101])
        let selected = select(staleOldTrack, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected.info, newTrack.info)
    }

    func testNewerReturnToPreviousTrackIsAccepted() {
        let clock = TestClock()
        let arbiter = MediaSnapshotArbiter(uptime: { clock.value })
        let firstTrack = snapshot(
            title: "Track A",
            pid: 101,
            isPlaying: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let secondTrack = snapshot(
            title: "Track B",
            pid: 101,
            isPlaying: true,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let previousTrack = snapshot(
            title: "Track A",
            pid: 101,
            isPlaying: true,
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        _ = select(firstTrack, with: arbiter, audioPIDs: [101])
        _ = select(secondTrack, with: arbiter, audioPIDs: [101])
        // 跨过回退保护窗口后的真实「上一首」操作必须被接受。
        clock.value += 2
        let selected = select(previousTrack, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected, previousTrack)
    }

    func testImmediateReturnToReplacedTrackIsRejectedAsStaleFlap() {
        let clock = TestClock()
        let arbiter = MediaSnapshotArbiter(uptime: { clock.value })
        let firstTrack = snapshot(title: "Track A", pid: 101, isPlaying: true)
        let newTrack = snapshot(title: "Track B", pid: 101, isPlaying: true)
        // 字典缺 timestamp 时 updatedAt 会退化为读取时刻（看起来最新），
        // 切歌后短时间内的回退快照必须按瞬时旧读拒绝。
        let staleRevert = snapshot(
            title: "Track A",
            pid: 101,
            isPlaying: true,
            updatedAt: Date().addingTimeInterval(10)
        )

        _ = select(firstTrack, with: arbiter, audioPIDs: [101])
        _ = select(newTrack, with: arbiter, audioPIDs: [101])
        clock.value += 0.3
        let selected = select(staleRevert, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected.info, newTrack.info)
    }

    func testSameTrackDoesNotLoseArtworkDuringPartialMetadataUpdate() {
        let arbiter = MediaSnapshotArbiter()
        let artwork = Data([0xCA, 0xFE])
        let ready = snapshot(title: "Track", pid: 101, isPlaying: true, artworkData: artwork)
        let partial = snapshot(title: "Track", pid: 101, isPlaying: true, artworkData: nil)

        _ = select(ready, with: arbiter, audioPIDs: [101])
        let selected = select(partial, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected.info?.artworkData, artwork)
    }

    func testNewTrackNeverInheritsPreviousArtwork() {
        let arbiter = MediaSnapshotArbiter()
        let artwork = Data([0xCA, 0xFE])
        let firstTrack = snapshot(title: "Track A", pid: 101, isPlaying: true, artworkData: artwork)
        let secondTrack = snapshot(title: "Track B", pid: 101, isPlaying: true, artworkData: nil)

        _ = select(firstTrack, with: arbiter, audioPIDs: [101])
        let selected = select(secondTrack, with: arbiter, audioPIDs: [101])

        XCTAssertNil(selected.info?.artworkData)
        XCTAssertEqual(selected.info?.title, "Track B")
    }

    func testExplicitPlayingSnapshotReplacesPreviousSourceDuringCoreAudioLag() {
        let arbiter = MediaSnapshotArbiter()
        let qqMusic = snapshot(title: "QQ Track", pid: 101, isPlaying: true)
        let mixedNetease = snapshot(title: "Netease Track", pid: 202, isPlaying: true)

        _ = select(qqMusic, with: arbiter, audioPIDs: [101])
        let selected = select(mixedNetease, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected.info?.title, "Netease Track")
        XCTAssertEqual(selected.info?.appPID, 202)
    }

    func testStaleAudioOutputCannotUndoFreshMediaRemoteSourceSwitch() {
        let clock = TestClock()
        let policy = MediaSourceSelectionPolicy(
            sourceSwitchProtectionInterval: 1,
            requiredFallbackConfirmations: 2
        )
        let arbiter = MediaSnapshotArbiter(policy: policy, uptime: { clock.value })
        let oldSource = snapshot(title: "Old Track", pid: 101, isPlaying: true)
        let newSource = snapshot(title: "New Track", pid: 202, isPlaying: true)

        _ = select(oldSource, with: arbiter, audioPIDs: [101])
        clock.value = 10
        _ = select(newSource, with: arbiter, audioPIDs: [101])

        let selected = select(
            oldSource,
            origin: .audioOutputFallback,
            with: arbiter,
            audioPIDs: [101]
        )

        XCTAssertEqual(selected.info?.appPID, 202)
    }

    func testConfirmedAudioOutputFallbackReplacesSourceAfterProtectionPeriod() {
        let clock = TestClock()
        let policy = MediaSourceSelectionPolicy(
            sourceSwitchProtectionInterval: 1,
            requiredFallbackConfirmations: 2
        )
        let arbiter = MediaSnapshotArbiter(policy: policy, uptime: { clock.value })
        let oldSource = snapshot(title: "Old Track", pid: 101, isPlaying: true)
        let newSource = snapshot(title: "New Track", pid: 202, isPlaying: true)

        _ = select(oldSource, with: arbiter, audioPIDs: [101])
        clock.value = 10
        _ = select(newSource, with: arbiter, audioPIDs: [101])
        clock.value = 12

        let firstConfirmation = select(
            oldSource,
            origin: .audioOutputFallback,
            with: arbiter,
            audioPIDs: [101]
        )
        let secondConfirmation = select(
            oldSource,
            origin: .audioOutputFallback,
            with: arbiter,
            audioPIDs: [101]
        )

        XCTAssertEqual(firstConfirmation.info?.appPID, 202)
        XCTAssertEqual(secondConfirmation.info?.appPID, 101)
    }

    func testUnavailableCoreAudioNeverOverridesMediaRemoteSelection() {
        let clock = TestClock()
        let arbiter = MediaSnapshotArbiter(uptime: { clock.value })
        let selectedSource = snapshot(title: "Selected", pid: 202, isPlaying: true)
        let fallback = snapshot(title: "Fallback", pid: 101, isPlaying: true)

        _ = arbiter.select(
            selectedSource,
            isSourceRunning: { _ in true },
            isSourceProducingAudio: { _ in nil }
        )
        clock.value = 10
        let selected = arbiter.select(
            fallback,
            origin: .audioOutputFallback,
            isSourceRunning: { _ in true },
            isSourceProducingAudio: { pid in pid == 101 ? true : nil }
        )

        XCTAssertEqual(selected.info?.appPID, 202)
    }

    func testAudioOutputFallbackDoesNotReplaceKnownMetadataForSameProcess() {
        let arbiter = MediaSnapshotArbiter()
        let paused = snapshot(title: "Known Track", pid: 101, isPlaying: false)
        let generic = snapshot(title: "媒体应用", pid: 101, isPlaying: true)

        _ = select(paused, with: arbiter, audioPIDs: [101])
        let selected = select(
            generic,
            origin: .audioOutputFallback,
            with: arbiter,
            audioPIDs: [101]
        )

        XCTAssertEqual(selected.info?.title, "Known Track")
        XCTAssertFalse(selected.info?.isPlaying == true)
    }

    func testPausedSourceWithStaleCoreAudioCanBeReplacedByConfirmedFallback() {
        let clock = TestClock()
        let policy = MediaSourceSelectionPolicy(
            sourceSwitchProtectionInterval: 0,
            requiredFallbackConfirmations: 2
        )
        let arbiter = MediaSnapshotArbiter(policy: policy, uptime: { clock.value })
        let paused = snapshot(title: "Paused", pid: 101, isPlaying: false)
        let fallback = snapshot(title: "Playing", pid: 202, isPlaying: true)

        _ = select(paused, with: arbiter, audioPIDs: [101])
        let first = select(
            fallback,
            origin: .audioOutputFallback,
            with: arbiter,
            audioPIDs: [101, 202]
        )
        let second = select(
            fallback,
            origin: .audioOutputFallback,
            with: arbiter,
            audioPIDs: [101, 202]
        )

        XCTAssertEqual(first.info?.appPID, 101)
        XCTAssertEqual(second.info?.appPID, 202)
    }

    func testPauseFromSameApplicationIsAccepted() {
        let arbiter = MediaSnapshotArbiter()
        let playing = snapshot(title: "Track", pid: 101, isPlaying: true)
        let paused = snapshot(title: "Track", pid: 101, isPlaying: false)

        _ = select(playing, with: arbiter, audioPIDs: [101])
        let selected = select(paused, with: arbiter, audioPIDs: [])

        XCTAssertEqual(selected, paused)
    }

    func testPauseFromSameTrackIsAcceptedWhileAudioActivityIsStale() {
        let arbiter = MediaSnapshotArbiter()
        let playing = snapshot(title: "Track", pid: 101, isPlaying: true)
        let paused = snapshot(title: "Track", pid: 101, isPlaying: false)

        _ = select(playing, with: arbiter, audioPIDs: [101])
        let selected = select(paused, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected, paused)
        XCTAssertFalse(selected.info?.isPlaying == true)
        XCTAssertTrue(arbiter.recentlySelectedSourcePIDs().isEmpty)
    }

    func testAudioProducingDifferentApplicationReplacesPreviousSource() {
        let arbiter = MediaSnapshotArbiter()
        let qqMusic = snapshot(title: "QQ Track", pid: 101, isPlaying: true)
        let netease = snapshot(title: "Netease Track", pid: 202, isPlaying: true)

        _ = select(qqMusic, with: arbiter, audioPIDs: [101])
        let selected = select(netease, with: arbiter, audioPIDs: [202])

        XCTAssertEqual(selected, netease)
    }

    func testPausedDifferentApplicationIsAcceptedAfterPreviousSourceStopsOutput() {
        let arbiter = MediaSnapshotArbiter()
        let qqMusic = snapshot(title: "QQ Track", pid: 101, isPlaying: true)
        let netease = snapshot(title: "Netease Track", pid: 202, isPlaying: false)

        _ = select(qqMusic, with: arbiter, audioPIDs: [101])
        let selected = select(netease, with: arbiter, audioPIDs: [])

        XCTAssertEqual(selected, netease)
    }

    func testPausingBackgroundSourceKeepsCurrentSourceAndRecency() {
        let arbiter = MediaSnapshotArbiter()
        let browser = snapshot(title: "Browser Track", pid: 101, isPlaying: true)
        let netease = snapshot(title: "Netease Track", pid: 202, isPlaying: true)
        let pausedBrowser = snapshot(title: "Browser Track", pid: 101, isPlaying: false)

        _ = select(browser, with: arbiter, audioPIDs: [101])
        _ = select(netease, with: arbiter, audioPIDs: [101, 202])
        let selected = select(pausedBrowser, with: arbiter, audioPIDs: [202])

        XCTAssertEqual(selected.info?.appPID, 202)
        XCTAssertEqual(arbiter.recentlySelectedSourcePIDs(), [202, 101])
    }

    func testPausingCurrentSourceRestoresPreviousSourceOrder() {
        let arbiter = MediaSnapshotArbiter()
        let browser = snapshot(title: "Browser Track", pid: 101, isPlaying: true)
        let netease = snapshot(title: "Netease Track", pid: 202, isPlaying: true)
        let pausedNetease = snapshot(title: "Netease Track", pid: 202, isPlaying: false)

        _ = select(browser, with: arbiter, audioPIDs: [101])
        _ = select(netease, with: arbiter, audioPIDs: [101, 202])
        _ = select(pausedNetease, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(arbiter.recentlySelectedSourcePIDs(), [101])
    }

    func testUnknownAudioStateFallsBackToPlaybackFlagsAndProcessLiveness() {
        let arbiter = MediaSnapshotArbiter()
        let qqMusic = snapshot(title: "QQ Track", pid: 101, isPlaying: true)
        let netease = snapshot(title: "Netease Track", pid: 202, isPlaying: false)

        _ = arbiter.select(
            qqMusic,
            isSourceRunning: { _ in true },
            isSourceProducingAudio: { _ in nil }
        )
        let selected = arbiter.select(
            netease,
            isSourceRunning: { $0 == 101 },
            isSourceProducingAudio: { _ in nil }
        )

        XCTAssertEqual(selected.info?.title, "QQ Track")
    }

    func testDiscardingUnrelatedApplicationKeepsSelectedSource() {
        let arbiter = MediaSnapshotArbiter()
        let playing = snapshot(title: "Track", pid: 101, isPlaying: true)

        _ = select(playing, with: arbiter, audioPIDs: [101])

        XCTAssertFalse(arbiter.discardSource(pid: 202))

        let pausedCandidate = snapshot(title: "Other", pid: 202, isPlaying: false)
        let selected = select(pausedCandidate, with: arbiter, audioPIDs: [101])
        XCTAssertEqual(selected.info?.appPID, 101)
        XCTAssertEqual(selected.info?.title, "Track")
    }

    func testDiscardingSelectedApplicationReportsRemoval() {
        let arbiter = MediaSnapshotArbiter()
        let playing = snapshot(title: "Track", pid: 101, isPlaying: true)

        _ = select(playing, with: arbiter, audioPIDs: [101])

        XCTAssertTrue(arbiter.discardSource(pid: 101))
        XCTAssertFalse(arbiter.discardSource(pid: 101))
    }

    func testDiscardedPlaybackSourceNoLongerBlocksPausedApplication() {
        let arbiter = MediaSnapshotArbiter()
        let qqMusic = snapshot(title: "QQ Track", pid: 101, isPlaying: true)
        let netease = snapshot(title: "Netease Track", pid: 202, isPlaying: false)

        _ = select(qqMusic, with: arbiter, audioPIDs: [101])
        arbiter.discardSource(pid: 101)
        let selected = select(netease, with: arbiter, audioPIDs: [101])

        XCTAssertEqual(selected, netease)
    }

    private func select(
        _ snapshot: MediaRemoteSnapshot,
        origin: MediaSnapshotOrigin = .mediaRemote,
        with arbiter: MediaSnapshotArbiter,
        audioPIDs: Set<Int32>
    ) -> MediaRemoteSnapshot {
        arbiter.select(
            snapshot,
            origin: origin,
            isSourceRunning: { _ in true },
            isSourceProducingAudio: { audioPIDs.contains($0) }
        )
    }

    private func snapshot(
        title: String,
        pid: Int32,
        isPlaying: Bool,
        artworkData: Data? = nil,
        updatedAt: Date = Date()
    ) -> MediaRemoteSnapshot {
        MediaRemoteSnapshot(
            info: NowPlayingInfo(
                title: title,
                artist: "Artist",
                artworkData: artworkData,
                appPID: pid,
                isPlaying: isPlaying,
                updatedAt: updatedAt
            ),
            status: "test"
        )
    }
}

private final class TestClock: @unchecked Sendable {
    var value: TimeInterval = 0
}
