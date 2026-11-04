import XCTest
@testable import RecentFoldersModule

final class FinderRecentFoldersServiceTests: XCTestCase {
    func testResolveEntryDecodesBookmarkToURL() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let bookmark = try (url as NSURL).bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let folder = FinderRecentFoldersService.resolveEntry([
            "file-bookmark": bookmark,
            "name": "Temp",
        ])

        XCTAssertEqual(folder?.url.standardizedFileURL, url.standardizedFileURL)
        XCTAssertEqual(folder?.name, "Temp")
    }

    func testResolveEntryFallsBackToLastPathComponent() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let bookmark = try (url as NSURL).bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let folder = FinderRecentFoldersService.resolveEntry(["file-bookmark": bookmark])

        XCTAssertEqual(folder?.name, url.lastPathComponent)
    }

    func testResolveEntryIgnoresBrokenEntries() {
        XCTAssertNil(FinderRecentFoldersService.resolveEntry([
            "file-bookmark": Data(),
            "name": "损坏",
        ]))
        XCTAssertNil(FinderRecentFoldersService.resolveEntry(["name": "无书签"]))
        XCTAssertNil(FinderRecentFoldersService.resolveEntry([:]))
    }
}