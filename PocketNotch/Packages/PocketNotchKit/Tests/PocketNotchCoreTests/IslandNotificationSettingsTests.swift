import XCTest
@testable import PocketNotchCore

@MainActor
final class IslandNotificationDismissalSettingsTests: XCTestCase {
    func testDismissalEffectsDefaultToStandard() {
        let settings = IslandNotificationSettings(defaults: nil)

        XCTAssertEqual(settings.songChangeDismissalEffect, .standard)
        XCTAssertEqual(settings.audioOutputChangeDismissalEffect, .standard)
    }

    func testDismissalEffectsPersistIndependently() {
        let suiteName = "IslandNotificationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandNotificationSettings(defaults: defaults)
        settings.songChangeDismissalEffect = .particleDissolve
        settings.audioOutputChangeDismissalEffect = .particleDissolve

        let restored = IslandNotificationSettings(defaults: defaults)
        XCTAssertEqual(restored.songChangeDismissalEffect, .particleDissolve)
        XCTAssertEqual(restored.audioOutputChangeDismissalEffect, .particleDissolve)
    }

    func testDismissalEffectPresentationOrderAndTitles() {
        XCTAssertEqual(
            IslandNotificationDismissalEffect.allCases,
            [.standard, .particleDissolve]
        )
        XCTAssertEqual(
            IslandNotificationDismissalEffect.allCases.map(\.title),
            ["标准", "粒子消散"]
        )
    }

    func testDismissalEffectCompletionDelaysCoverVisualDuration() {
        XCTAssertEqual(
            IslandNotificationDismissalEffect.particleDissolve.completionDelay(
                reduceMotion: false
            ),
            .milliseconds(1_760)
        )

        for effect in IslandNotificationDismissalEffect.allCases {
            XCTAssertEqual(effect.completionDelay(reduceMotion: true), .milliseconds(150))
        }
    }

    func testParticleDissolvePerformanceBudget() {
        XCTAssertEqual(ParticleDissolveMotion.duration, 1.68)
        XCTAssertEqual(IslandNotificationParticleDustStyle.content.count, 72)
        XCTAssertEqual(IslandNotificationParticleDustStyle.backdrop.count, 64)
        XCTAssertEqual(IslandNotificationParticleMaskStyle.backdrop.cellSize, 1.1)
        XCTAssertLessThan(
            IslandNotificationParticleDustStyle.content.onset(
                horizontalProgress: 1,
                noise: 0.5
            ),
            IslandNotificationParticleDustStyle.content.onset(
                horizontalProgress: 0,
                noise: 0.5
            )
        )
    }

    func testParticleDissolveMaskRunsFromRightToLeft() {
        for style in [
            IslandNotificationParticleMaskStyle.content,
            .backdrop,
        ] {
            let noise = 0.5
            let rightThreshold = style.dissolveThreshold(
                horizontalProgress: 1,
                noise: noise
            )
            let leftThreshold = style.dissolveThreshold(
                horizontalProgress: 0,
                noise: noise
            )
            let midpoint = (rightThreshold + leftThreshold) / 2

            XCTAssertLessThan(rightThreshold, leftThreshold)
            XCTAssertLessThan(
                style.remainingOpacity(
                    progress: midpoint,
                    horizontalProgress: 1,
                    noise: noise
                ),
                style.remainingOpacity(
                    progress: midpoint,
                    horizontalProgress: 0,
                    noise: noise
                )
            )
        }
    }

    func testParticleDissolveMaskStartsWithoutOpacityJump() {
        for style in [
            IslandNotificationParticleMaskStyle.content,
            .backdrop,
        ] {
            XCTAssertEqual(
                style.remainingOpacity(
                    progress: style.earliestOnset,
                    horizontalProgress: 1,
                    noise: 0
                ),
                1,
                accuracy: 0.000_001
            )
        }
    }

    func testUnknownDismissalEffectFallsBackToStandard() {
        let suiteName = "IslandNotificationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unknown", forKey: "notifications.songChangeDismissalEffect")

        let settings = IslandNotificationSettings(defaults: defaults)

        XCTAssertEqual(settings.songChangeDismissalEffect, .standard)
    }

    func testRemovedDismissalEffectsFallBackToStandard() {
        for rawValue in ["retract", "light-sweep", "smoke-dissolve"] {
            let suiteName = "IslandNotificationSettingsTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(rawValue, forKey: "notifications.songChangeDismissalEffect")

            let settings = IslandNotificationSettings(defaults: defaults)

            XCTAssertEqual(settings.songChangeDismissalEffect, .standard)
        }
    }

    func testVolumeIconStyleDefaultsToSystem() {
        let settings = IslandNotificationSettings(defaults: nil)

        XCTAssertEqual(settings.volumeIconStyle, .system)
    }

    func testVolumeIconStylePersistsIndependently() {
        let suiteName = "IslandNotificationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandNotificationSettings(defaults: defaults)
        settings.volumeIconStyle = .device

        let restored = IslandNotificationSettings(defaults: defaults)
        XCTAssertEqual(restored.volumeIconStyle, .device)
    }

    func testVolumeIconStylePresentationOrder() {
        XCTAssertEqual(VolumeIconStyle.allCases, [.system, .device])
    }
}

/// 系统原生 OSD 隐藏开关：与 PocketNotch 自身的提醒开关相互独立。
@MainActor
final class SystemVolumeHUDHiddenSettingsTests: XCTestCase {
    func testSystemHUDHidingDefaultsToHidden() {
        let settings = IslandNotificationSettings(defaults: nil)

        XCTAssertTrue(settings.isSystemVolumeHUDHidden)
        XCTAssertTrue(settings.isSystemBrightnessHUDHidden)
    }

    func testSystemHUDHidingPersistsIndependently() {
        let suiteName = "SystemVolumeHUDHiddenSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandNotificationSettings(defaults: defaults)
        settings.isSystemVolumeHUDHidden = false

        let restored = IslandNotificationSettings(defaults: defaults)
        XCTAssertFalse(restored.isSystemVolumeHUDHidden)
        XCTAssertTrue(restored.isSystemBrightnessHUDHidden)
    }

    func testTurningOffPocketNotchVolumeReminderForcesSystemHUDBack() {
        let suiteName = "SystemVolumeHUDHiddenSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandNotificationSettings(defaults: defaults)
        XCTAssertTrue(settings.isSystemVolumeHUDHidden)

        settings.isVolumeAdjustmentEnabled = false
        XCTAssertFalse(settings.isSystemVolumeHUDHidden)

        let restored = IslandNotificationSettings(defaults: defaults)
        XCTAssertFalse(restored.isSystemVolumeHUDHidden)
    }

    func testTurningOffPocketNotchBrightnessReminderForcesSystemHUDBack() {
        let suiteName = "SystemVolumeHUDHiddenSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandNotificationSettings(defaults: defaults)
        settings.isBrightnessAdjustmentEnabled = false

        XCTAssertFalse(settings.isSystemBrightnessHUDHidden)
        XCTAssertTrue(settings.isSystemVolumeHUDHidden)
    }

    func testReenablingPocketNotchReminderLeavesSystemHUDChoiceAlone() {
        let suiteName = "SystemVolumeHUDHiddenSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandNotificationSettings(defaults: defaults)
        settings.isVolumeAdjustmentEnabled = false
        settings.isVolumeAdjustmentEnabled = true

        XCTAssertFalse(settings.isSystemVolumeHUDHidden)
    }

    func testResetToDefaultRestoresHUDHiding() {
        let suiteName = "SystemVolumeHUDHiddenSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandNotificationSettings(defaults: defaults)
        settings.isSystemVolumeHUDHidden = false
        settings.isSystemBrightnessHUDHidden = false
        settings.isBrightnessPercentageEnabled = false
        XCTAssertFalse(settings.usesDefaultValues)

        settings.resetToDefault()
        XCTAssertTrue(settings.isSystemVolumeHUDHidden)
        XCTAssertTrue(settings.isSystemBrightnessHUDHidden)
        XCTAssertTrue(settings.isBrightnessPercentageEnabled)
        XCTAssertTrue(settings.usesDefaultValues)
    }
}
