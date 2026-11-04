import PocketNotchCore
import XCTest
@testable import ClipboardModule

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testAddCollectsInOrder() {
        let store = ClipboardStore()
        store.add("A")
        store.add("B")
        XCTAssertEqual(store.items.map(\.text), ["B", "A"])
    }

    func testAddDedupesAndMovesToFront() {
        let store = ClipboardStore()
        store.add("A")
        store.add("B")
        store.add("A")
        XCTAssertEqual(store.items.map(\.text), ["A", "B"])
    }

    func testAddCapsAtLimitKeepingNewest() {
        let store = ClipboardStore()
        store.clear()
        for index in 1...(ClipboardStore.maxItems + 2) {
            store.add("clip-\(index)")
        }
        XCTAssertEqual(store.items.count, ClipboardStore.maxItems)
        XCTAssertEqual(store.items.first?.text, "clip-\(ClipboardStore.maxItems + 2)")
        XCTAssertEqual(store.items.last?.text, "clip-3")
    }


    func testLockedItemSortsFirstAndIsNotReplaced() throws {
        let store = ClipboardStore()
        store.add("A")
        store.add("B")
        store.add("C")
        let target = try XCTUnwrap(store.items.first { $0.text == "A" })

        store.toggleLock(target)

        XCTAssertEqual(store.items.map(\.text), ["A", "C", "B"])
        XCTAssertTrue(store.items[0].isLocked)
        let lockedID = store.items[0].id

        store.add("A")
        store.add("D")

        XCTAssertEqual(store.items.map(\.text), ["A", "D", "C", "B"])
        XCTAssertEqual(store.items[0].id, lockedID)
        XCTAssertTrue(store.items[0].isLocked)
    }

    func testUnlockingRestoresNormalOrdering() throws {
        let store = ClipboardStore()
        store.add("A")
        store.add("B")
        store.add("C")
        let target = try XCTUnwrap(store.items.first { $0.text == "A" })

        store.toggleLock(target)
        store.toggleLock(store.items[0])

        XCTAssertEqual(store.items.map(\.text), ["C", "B", "A"])
        XCTAssertTrue(store.items.allSatisfy { !$0.isLocked })
    }

    func testLockedItemSurvivesEviction() throws {
        let store = ClipboardStore()
        store.clear()
        for index in 1...ClipboardStore.maxItems {
            store.add("clip-\(index)")
        }
        let oldest = try XCTUnwrap(store.items.last)
        store.toggleLock(oldest)

        store.add("new")

        XCTAssertEqual(store.items.count, ClipboardStore.maxItems)
        XCTAssertEqual(store.items.first?.text, oldest.text)
        XCTAssertTrue(store.items.first?.isLocked == true)
        XCTAssertFalse(store.items.contains { $0.text == "clip-2" })
    }

    func testClearEmptiesHistory() {
        let store = ClipboardStore()
        store.add("A")
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    func testRemoveRemovesOnlyTargetItem() {
        let store = ClipboardStore()
        store.add("A")
        store.add("B")
        store.add("C")
        let target = store.items[1]
        store.remove(target)
        XCTAssertEqual(store.items.map(\.text), ["C", "A"])
        XCTAssertFalse(store.items.contains { $0.id == target.id })
    }

    func testClassifiesHttpAndHttpsAsLink() throws {
        let store = ClipboardStore()
        store.add("https://example.com/page?q=1")
        store.add("http://example.com")
        store.add("buy some milk")
        XCTAssertEqual(store.items[0].kind, .text("buy some milk"))
        XCTAssertEqual(store.items[1].kind, .link("http://example.com"))
        XCTAssertEqual(store.items[2].kind, .link("https://example.com/page?q=1"))
    }

    func testLinkClassificationTrimsSurroundingWhitespace() {
        let store = ClipboardStore()
        store.add("  https://example.com\n")
        let item = try? XCTUnwrap(store.items.first)
        XCTAssertEqual(item?.kind, .link("https://example.com"))
    }

    func testAddImageCollectsAndDedupesByData() {
        let store = ClipboardStore()
        let data = Data([0x01, 0x02, 0x03])
        store.addImage(data: data, filename: "a.png")
        store.addImage(data: data, filename: "b.png")
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.text, "b.png")
    }

    func testImageAndTextStaySeparate() {
        let store = ClipboardStore()
        store.addImage(data: Data([0x01]), filename: "pic.png")
        store.add("https://example.com")
        store.add("plain")
        XCTAssertEqual(store.items.map(\.text), ["plain", "https://example.com", "pic.png"])
    }

    func testNewContentDoesNotAutoRequestTab() {
        let controller = ExpandedTabRequestController()
        let store = ClipboardStore(expansionRequest: controller)
        store.add("new content")
        store.addImage(data: Data([0x01, 0x02]), filename: "a.png")
        XCTAssertNil(controller.pendingTab)
    }

    func testManualRequestClipboardTabActivates() {
        let controller = ExpandedTabRequestController()
        let store = ClipboardStore(expansionRequest: controller)
        store.add("content")
        store.requestClipboardTab()
        XCTAssertEqual(controller.pendingTab, .clipboard)
    }

    func testManualRequestClipboardTabWorksWithEmptyHistory() {
        let controller = ExpandedTabRequestController()
        let store = ClipboardStore(expansionRequest: controller)
        store.requestClipboardTab()
        XCTAssertEqual(controller.pendingTab, .clipboard)
    }
}