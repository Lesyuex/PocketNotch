import AppKit
@testable import PocketNotchCore
import XCTest

final class ExpandedSearchKeyResolverTests: XCTestCase {
    func testPrintableCharacterInserts() {
        let action = ExpandedSearchKeyResolver.resolve(
            characters: "a",
            charactersIgnoringModifiers: "a",
            keyCode: 0,
            modifiers: []
        )
        XCTAssertEqual(action, .insert("a"))
    }

    func testShiftedCharacterInserts() {
        let action = ExpandedSearchKeyResolver.resolve(
            characters: "A",
            charactersIgnoringModifiers: "a",
            keyCode: 0,
            modifiers: [.shift]
        )
        XCTAssertEqual(action, .insert("A"))
    }

    func testNumpadDigitInserts() {
        let action = ExpandedSearchKeyResolver.resolve(
            characters: "5",
            charactersIgnoringModifiers: "5",
            keyCode: 87,
            modifiers: [.numericPad]
        )
        XCTAssertEqual(action, .insert("5"))
    }

    func testDeleteBackspaceResolves() {
        let action = ExpandedSearchKeyResolver.resolve(
            characters: "\u{7F}",
            charactersIgnoringModifiers: "\u{7F}",
            keyCode: 51,
            modifiers: []
        )
        XCTAssertEqual(action, .deleteBackward)
    }

    func testEscapeResolvesClear() {
        let action = ExpandedSearchKeyResolver.resolve(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53,
            modifiers: []
        )
        XCTAssertEqual(action, .clear)
    }

    func testReturnResolvesSubmit() {
        let action = ExpandedSearchKeyResolver.resolve(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36,
            modifiers: []
        )
        XCTAssertEqual(action, .submit)
    }

    func testCommandVIgnored() {
        let action = ExpandedSearchKeyResolver.resolve(
            characters: "v",
            charactersIgnoringModifiers: "v",
            keyCode: 9,
            modifiers: [.command]
        )
        XCTAssertEqual(action, .ignored)
    }

    func testOtherCommandShortcutIgnored() {
        let action = ExpandedSearchKeyResolver.resolve(
            characters: "c",
            charactersIgnoringModifiers: "c",
            keyCode: 8,
            modifiers: [.command]
        )
        XCTAssertEqual(action, .ignored)
    }

    func testControlShortcutIgnored() {
        let action = ExpandedSearchKeyResolver.resolve(
            characters: "\u{03}",
            charactersIgnoringModifiers: "c",
            keyCode: 8,
            modifiers: [.control]
        )
        XCTAssertEqual(action, .ignored)
    }

    func testFunctionKeyIgnored() {
        let scalar = Character(UnicodeScalar(NSUpArrowFunctionKey)!)
        let action = ExpandedSearchKeyResolver.resolve(
            characters: scalar,
            charactersIgnoringModifiers: scalar,
            keyCode: 126,
            modifiers: [.function]
        )
        XCTAssertEqual(action, .ignored)
    }
}