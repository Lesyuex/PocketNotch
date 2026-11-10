import XCTest
@testable import PocketNotchCore

final class AppUpdateCheckerTests: XCTestCase {
    func testNewerPatchVersion() {
        XCTAssertTrue(AppVersionComparator.isNewer("0.1.1", than: "0.1.0"))
    }

    func testNewerMinorAndMajorVersion() {
        XCTAssertTrue(AppVersionComparator.isNewer("0.2.0", than: "0.1.9"))
        XCTAssertTrue(AppVersionComparator.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertTrue(AppVersionComparator.isNewer("1.10.0", than: "1.9.9"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(AppVersionComparator.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(AppVersionComparator.isNewer("0.1", than: "0.1.0"))
        XCTAssertFalse(AppVersionComparator.isNewer("0.1.0", than: "0.1"))
    }

    func testOlderVersionIsNotNewer() {
        XCTAssertFalse(AppVersionComparator.isNewer("0.1.0", than: "0.1.1"))
        XCTAssertFalse(AppVersionComparator.isNewer("0.9.9", than: "1.0.0"))
    }

    func testVPrefixAndPrereleaseSuffixAreIgnored() {
        XCTAssertTrue(AppVersionComparator.isNewer("v0.2.0", than: "0.1.0"))
        XCTAssertTrue(AppVersionComparator.isNewer("v1.0.0-beta.2", than: "0.9.0"))
        XCTAssertFalse(AppVersionComparator.isNewer("1.0.0-beta", than: "1.0.0"))
    }

    func testNormalizedVersionStripsVPrefix() {
        XCTAssertEqual(AppVersionComparator.normalizedVersion(" v1.2.3 "), "1.2.3")
        XCTAssertEqual(AppVersionComparator.normalizedVersion("1.2.3"), "1.2.3")
    }

    func testGitHubReleasePayloadDecoding() throws {
        let json = """
        {
          "tag_name": "v1.2.3",
          "name": "PocketNotch 1.2.3",
          "html_url": "https://github.com/Lesyuex/PocketNotch/releases/tag/v1.2.3"
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubLatestRelease.self, from: json)
        let update = AppUpdateRelease(
            tagName: release.tagName,
            name: release.name,
            releaseURL: release.htmlURL
        )

        XCTAssertEqual(update.tagName, "v1.2.3")
        XCTAssertEqual(update.version, "1.2.3")
        XCTAssertEqual(update.name, "PocketNotch 1.2.3")
        XCTAssertEqual(
            update.releaseURL.absoluteString,
            "https://github.com/Lesyuex/PocketNotch/releases/tag/v1.2.3"
        )
    }
}
