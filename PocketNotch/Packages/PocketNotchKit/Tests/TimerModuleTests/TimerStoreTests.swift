import PocketNotchCore
import XCTest
@testable import TimerModule

@MainActor
final class TimerStoreTests: XCTestCase {
    func testInitialStateIsCountdownWithoutTime() {
        let store = TimerStore()
        XCTAssertEqual(store.mode, .countdown)
        XCTAssertEqual(store.runState, .idle)
        XCTAssertEqual(store.countdownDuration, 0)
        XCTAssertEqual(store.remaining, 0)
        XCTAssertEqual(store.elapsed, 0)
        XCTAssertTrue(store.isCountdownIdle)
        XCTAssertTrue(store.needsCountdownInput)
    }

    func testStartWithoutDurationStaysIdle() {
        let store = TimerStore()
        store.start()
        XCTAssertEqual(store.runState, .idle)
        XCTAssertTrue(store.needsCountdownInput)
    }

    func testSetCountdownDurationClampsAndClearsInputNeed() {
        let store = TimerStore()
        store.setCountdownDuration(90)
        XCTAssertEqual(store.countdownDuration, 90)
        XCTAssertEqual(store.remaining, 90)
        XCTAssertFalse(store.needsCountdownInput)

        store.setCountdownDuration(0)
        XCTAssertEqual(store.countdownDuration, 90)

        store.setCountdownDuration(TimerStore.countdownMaximum * 2)
        XCTAssertEqual(store.countdownDuration, TimerStore.countdownMaximum)
    }

    func testAdjustCountdownClampsToRange() {
        let store = TimerStore()
        store.setCountdownDuration(TimerStore.defaultCountdown)
        for _ in 0..<20 {
            store.adjustCountdown(by: -TimerStore.countdownStep)
        }
        XCTAssertEqual(store.countdownDuration, TimerStore.countdownMinimum)
        XCTAssertEqual(store.remaining, TimerStore.countdownMinimum)

        let steps = Int(TimerStore.countdownMaximum / TimerStore.countdownStep) + 2
        for _ in 0..<steps {
            store.adjustCountdown(by: TimerStore.countdownStep)
        }
        XCTAssertEqual(store.countdownDuration, TimerStore.countdownMaximum)
    }

    func testCountdownSupportsSecondsAndHours() {
        let store = TimerStore()
        store.setCountdownDuration(5)
        XCTAssertEqual(store.countdownDuration, 5)
        XCTAssertEqual(store.remaining, 5)

        store.setCountdownDuration(2 * 3600)
        XCTAssertEqual(store.countdownDuration, 2 * 3600)
        XCTAssertEqual(store.remaining, 2 * 3600)
    }

    func testCountdownSupportsHundredths() {
        let store = TimerStore()
        store.setCountdownDuration(5.239)
        XCTAssertEqual(store.countdownDuration, 5.24, accuracy: 0.001)
        XCTAssertEqual(store.remaining, 5.24, accuracy: 0.001)

        store.setCountdownDuration(TimerStore.countdownMinimum)
        XCTAssertEqual(store.countdownDuration, TimerStore.countdownMinimum, accuracy: 0.001)
    }

    func testAdjustCountdownIgnoredWhileRunning() {
        let store = TimerStore()
        store.setCountdownDuration(TimerStore.defaultCountdown)
        store.start()
        let before = store.countdownDuration
        store.adjustCountdown(by: TimerStore.countdownStep)
        XCTAssertEqual(store.countdownDuration, before)
        store.stop()
    }

    func testExtendCountdownWhileRunning() {
        let store = TimerStore()
        store.setCountdownDuration(60)
        store.start()

        store.extendCountdown(by: TimerStore.countdownStep)

        XCTAssertEqual(store.runState, .running)
        XCTAssertGreaterThan(store.remaining, 118)
        XCTAssertLessThanOrEqual(store.remaining, 120)
        XCTAssertEqual(store.countdownDuration, 60)
        store.stop()
    }

    func testExtendCountdownWhilePaused() {
        let store = TimerStore()
        store.setCountdownDuration(60)
        store.start()
        store.pause()
        let paused = store.remaining

        store.extendCountdown(by: TimerStore.countdownStep)

        XCTAssertEqual(store.runState, .paused)
        XCTAssertEqual(store.remaining, paused + 60, accuracy: 0.001)
        XCTAssertEqual(store.countdownDuration, 60)
        store.stop()
    }

    func testExtendCountdownClampsToMaximum() {
        let store = TimerStore()
        store.setCountdownDuration(TimerStore.countdownMaximum - 30)
        store.start()

        store.extendCountdown(by: TimerStore.countdownStep)

        XCTAssertEqual(store.remaining, TimerStore.countdownMaximum, accuracy: 0.5)
        store.stop()
    }

    func testExtendCountdownIgnoredOutsideActiveCountdown() {
        let store = TimerStore()
        store.extendCountdown(by: TimerStore.countdownStep)
        XCTAssertEqual(store.remaining, 0)

        store.setCountdownDuration(60)
        store.extendCountdown(by: TimerStore.countdownStep)
        XCTAssertEqual(store.remaining, 60)

        store.setMode(.stopwatch)
        store.start()
        store.extendCountdown(by: TimerStore.countdownStep)
        XCTAssertEqual(store.remaining, 60)
        store.stop()
    }

    func testCountdownStartPauseResumeAndReset() {
        let store = TimerStore()
        store.setCountdownDuration(90)
        store.start()
        XCTAssertEqual(store.runState, .running)

        store.pause()
        XCTAssertEqual(store.runState, .paused)
        let paused = store.remaining
        store.start()
        XCTAssertEqual(store.runState, .running)
        XCTAssertLessThanOrEqual(store.remaining, paused)

        store.reset()
        XCTAssertEqual(store.runState, .idle)
        XCTAssertEqual(store.countdownDuration, 0)
        XCTAssertEqual(store.remaining, 0)
        XCTAssertTrue(store.needsCountdownInput)
    }

    func testSetModeResetsStateAndSurvivesRunning() {
        let store = TimerStore()
        store.setMode(.stopwatch)
        XCTAssertEqual(store.mode, .stopwatch)
        XCTAssertEqual(store.runState, .idle)
        XCTAssertEqual(store.elapsed, 0)

        store.start()
        store.setMode(.countdown)
        XCTAssertEqual(store.mode, .stopwatch)
        store.stop()
    }

    func testToggleTransitionsRunningPaused() {
        let store = TimerStore()
        store.setCountdownDuration(60)
        store.toggle()
        XCTAssertEqual(store.runState, .running)
        store.toggle()
        XCTAssertEqual(store.runState, .paused)
        store.stop()
    }

    func testStopwatchElapsedNeverNegative() {
        let store = TimerStore()
        store.setMode(.stopwatch)
        store.start()
        XCTAssertGreaterThanOrEqual(store.elapsed, 0)
        store.stop()
    }

    func testStopwatchRecordsLapsAndResetClearsThem() {
        let store = TimerStore()
        store.setMode(.stopwatch)
        store.start()
        store.recordLap()
        store.recordLap()
        XCTAssertEqual(store.laps.count, 2)
        XCTAssertTrue(store.laps.allSatisfy { $0 >= 0 })

        store.reset()
        XCTAssertTrue(store.laps.isEmpty)
        store.stop()
    }

    func testRecordLapOnlyWorksInRunningStopwatch() {
        let store = TimerStore()
        store.recordLap()
        XCTAssertTrue(store.laps.isEmpty)

        store.setMode(.stopwatch)
        store.recordLap()
        XCTAssertTrue(store.laps.isEmpty)

        store.start()
        store.recordLap()
        XCTAssertEqual(store.laps.count, 1)
        store.stop()
    }

    func testSwitchingModeClearsLaps() {
        let store = TimerStore()
        store.setMode(.stopwatch)
        store.start()
        store.recordLap()
        XCTAssertEqual(store.laps.count, 1)

        store.pause()
        store.setMode(.countdown)
        XCTAssertTrue(store.laps.isEmpty)
        store.stop()
    }

    func testClockFormatting() {
        XCTAssertEqual(NowTimerCardView.clock(seconds: 0), "00:00")
        XCTAssertEqual(NowTimerCardView.clock(seconds: 5), "00:05")
        XCTAssertEqual(NowTimerCardView.clock(seconds: 65), "01:05")
        XCTAssertEqual(NowTimerCardView.clock(seconds: 599), "09:59")
        XCTAssertEqual(NowTimerCardView.clock(seconds: 3599), "59:59")
        XCTAssertEqual(NowTimerCardView.clock(seconds: 3600), "60:00")
        XCTAssertEqual(NowTimerCardView.clock(seconds: 3661), "61:01")
        XCTAssertEqual(NowTimerCardView.clock(seconds: 7200), "120:00")
    }
}
