import XCTest
@testable import ShelfModule

@MainActor
final class ShelfStoreTests: XCTestCase {
    func testAddAndRemove() {
        let store = ShelfStore()
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        store.add(url)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.name, "a.txt")

        let item = store.items[0]
        store.remove(item)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testClear() {
        let store = ShelfStore()
        store.add(URL(fileURLWithPath: "/tmp/a.txt"))
        store.add(URL(fileURLWithPath: "/tmp/b.txt"))
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    func testShelfDropReceiverAddsAll() {
        let store = ShelfStore()
        let receiver = ShelfDropReceiver(store: store)
        receiver.receive(urls: [
            URL(fileURLWithPath: "/tmp/a.txt"),
            URL(fileURLWithPath: "/tmp/b.txt"),
        ])
        XCTAssertEqual(store.items.count, 2)
    }
}
