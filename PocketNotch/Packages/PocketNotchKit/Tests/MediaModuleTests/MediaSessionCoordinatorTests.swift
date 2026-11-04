import XCTest
@testable import MediaModule

final class MediaSessionCoordinatorTests: XCTestCase {
    func testClientEnumerationPlayingStateIsNotForcedPausedWhenElapsedStalls() {
        let coordinator = MediaSessionCoordinator()
        let snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(
                title: "Track",
                artist: "Artist",
                appPID: 1937,
                elapsedTime: 12,
                isPlaying: true
            ),
            status: "client enumeration"
        )

        _ = coordinator.resolve(snapshot, origin: .clientEnumeration)
        let resolved = coordinator.resolve(snapshot, origin: .clientEnumeration)
        XCTAssertTrue(resolved.info?.isPlaying == true)
    }

    func testMediaRemotePlayingStateWithStalledElapsedEventuallyPauses() {
        let coordinator = MediaSessionCoordinator()
        let snapshot = MediaRemoteSnapshot(
            info: NowPlayingInfo(
                title: "Track",
                artist: "Artist",
                appPID: 1940,
                elapsedTime: 12,
                isPlaying: true
            ),
            status: "media remote"
        )

        _ = coordinator.resolve(snapshot, origin: .mediaRemote)
        _ = coordinator.resolve(snapshot, origin: .mediaRemote)
        let resolved = coordinator.resolve(snapshot, origin: .mediaRemote)
        XCTAssertFalse(resolved.info?.isPlaying == true)
    }
}
