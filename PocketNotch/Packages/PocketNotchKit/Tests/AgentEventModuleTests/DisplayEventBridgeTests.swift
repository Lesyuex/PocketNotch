import XCTest
import Display
@testable import AgentEventModule

private final class BridgeProcessCommand: ProcessCommandProviding, @unchecked Sendable {
    var executableByPID: [Int32: String] = [:]
    var parentByPID: [Int32: Int32] = [:]

    func probe(pid: Int32) -> (cpuSeconds: TimeInterval?, alive: Bool) {
        (nil, executableByPID[pid] != nil)
    }


    func executableName(pid: Int32) -> String? { executableByPID[pid] }

    func parentPID(pid: Int32) -> Int32? { parentByPID[pid] }
}

@MainActor
final class DisplayEventBridgeTests: XCTestCase {
    func testConversionBindsHookToSessionAgentProcess() {
        let processCommand = BridgeProcessCommand()
        processCommand.executableByPID = [400: "curl", 300: "zsh", 200: "codex"]
        processCommand.parentByPID = [400: 300, 300: 200]
        let bridge = DisplayEventBridge(
            displaySystem: DisplaySystem(),
            processCommand: processCommand
        )

        let converted = bridge.convert(event(pid: 400, parentPID: 300))

        XCTAssertEqual(converted.pid, 200)
    }

    func testConversionDoesNotBindTemporaryHookPIDWhenAgentAncestorIsMissing() {
        let processCommand = BridgeProcessCommand()
        processCommand.executableByPID = [400: "curl", 300: "zsh"]
        processCommand.parentByPID = [400: 300]
        let bridge = DisplayEventBridge(
            displaySystem: DisplaySystem(),
            processCommand: processCommand
        )

        let converted = bridge.convert(event(pid: 400, parentPID: 300))

        XCTAssertNil(converted.pid)
    }

    func testRolloutEventConvertsToStateOnlyEvent() {
        let bridge = DisplayEventBridge(displaySystem: DisplaySystem())

        let converted = bridge.convert(event(pid: 0, parentPID: 0, source: .rollout))

        XCTAssertTrue(converted.isStateOnly)
    }

    func testRolloutCompletionCanDriveTerminalFeedback() {
        let bridge = DisplayEventBridge(displaySystem: DisplaySystem())

        let converted = bridge.convert(event(
            pid: 0,
            parentPID: 0,
            source: .rollout,
            type: .completed
        ))

        XCTAssertFalse(converted.isStateOnly)
        XCTAssertEqual(converted.type, .sessionCompleted)
    }

    private func event(
        pid: Int32,
        parentPID: Int32,
        source: AgentEventSource? = nil,
        type: EventType = .agentStart
    ) -> AgentEventModule.AgentEvent {
        AgentEventModule.AgentEvent(
            id: UUID().uuidString,
            agent: "codex",
            sessionId: "session",
            type: type,
            pid: pid,
            parentPID: parentPID,
            source: source,
            timestamp: Date()
        )
    }
}
