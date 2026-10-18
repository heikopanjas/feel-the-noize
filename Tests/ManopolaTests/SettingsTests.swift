import Foundation
import Testing

@testable import Manopola

struct SettingsTests {
    /// Runs the body against a private defaults domain, so nothing touches the app's real preferences.
    private func withSettings(_ body: (Settings, UserDefaults) -> Void) {
        let suiteName = "com.panjas.ManopolaTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create a defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(Settings(defaults: defaults), defaults)
    }

    @Test func defaultsMatchTheDesign() {
        withSettings { settings, _ in
            #expect(settings.detentsPerRevolution == 36)
            #expect(settings.volumeStepPercent == 2)
            #expect(settings.reverseDirection == false)
            #expect(settings.hapticDetents == true)
            #expect(settings.showOverlay == true)
        }
    }

    @Test func valuesRoundTrip() {
        withSettings { settings, _ in
            settings.detentsPerRevolution = 72
            settings.volumeStepPercent = 5
            settings.reverseDirection = true
            settings.hapticDetents = false
            settings.showOverlay = false
            #expect(settings.detentsPerRevolution == 72)
            #expect(settings.volumeStepPercent == 5)
            #expect(settings.reverseDirection == true)
            #expect(settings.hapticDetents == false)
            #expect(settings.showOverlay == false)
            #expect(settings.controlSettings == ControlSettings(stepPercent: 5, reverseDirection: true))
        }
    }

    @Test func outOfRangeStoredValuesFallBackToDefaults() {
        withSettings { settings, defaults in
            defaults.set(50, forKey: "detentsPerRevolution")
            defaults.set(4, forKey: "volumeStepPercent")
            #expect(settings.detentsPerRevolution == 36)
            #expect(settings.volumeStepPercent == 2)
        }
    }

    @Test func everyDeviceIsEnabledUntilExcluded() {
        withSettings { settings, _ in
            #expect(settings.excludedDeviceUIDs.isEmpty)
            #expect(settings.isDeviceEnabled("speakers"))
            settings.setDevice("speakers", enabled: false)
            #expect(!settings.isDeviceEnabled("speakers"))
            #expect(settings.isDeviceEnabled("airpods"))
            #expect(settings.controlSettings.excludedDeviceUIDs == ["speakers"])
            settings.setDevice("speakers", enabled: true)
            #expect(settings.excludedDeviceUIDs.isEmpty)
        }
    }

    @Test func settingADeviceToItsCurrentStateDoesNotWrite() {
        withSettings { settings, _ in
            var changes = 0
            settings.onChange = { changes += 1 }
            settings.setDevice("speakers", enabled: true)
            #expect(changes == 0)
        }
    }

    @Test func rememberDevicesMergesAndWritesOnlyWhatIsNew() {
        withSettings { settings, _ in
            var changes = 0
            settings.onChange = { changes += 1 }
            settings.rememberDevices(["speakers": "MacBook Pro Speakers"])
            settings.rememberDevices(["airpods": "AirPods Pro"])
            settings.rememberDevices(["speakers": "MacBook Pro Speakers"])
            #expect(settings.knownDevices == ["speakers": "MacBook Pro Speakers", "airpods": "AirPods Pro"])
            #expect(changes == 2)

            settings.rememberDevices(["airpods": "Heiko's AirPods"])
            #expect(settings.knownDevices["airpods"] == "Heiko's AirPods")
            #expect(changes == 3)
        }
    }

    @Test func softwareVolumeIsOptInAndRespectsExclusion() {
        withSettings { settings, _ in
            #expect(!settings.wantsSoftwareVolume("m2"))
            settings.setSoftwareVolume("m2", enabled: true)
            #expect(settings.softwareVolumeDeviceUIDs == ["m2"])
            #expect(settings.wantsSoftwareVolume("m2"))
            settings.setDevice("m2", enabled: false)
            #expect(!settings.wantsSoftwareVolume("m2"))
            settings.setSoftwareVolume("m2", enabled: false)
            #expect(settings.softwareVolumeDeviceUIDs.isEmpty)
        }
    }

    @Test func softwareVolumeLevelStartsFullAndIsStoredWithoutOnChange() {
        withSettings { settings, _ in
            var changes = 0
            settings.onChange = { changes += 1 }
            #expect(settings.softwareVolumeLevel("m2") == 1)
            settings.setSoftwareVolumeLevel("m2", 0.42)
            #expect(abs(settings.softwareVolumeLevel("m2") - 0.42) < 0.000_01)
            #expect(settings.softwareVolumeLevel("other") == 1)
            #expect(changes == 0)
        }
    }

    @Test func everyWriteCallsOnChange() {
        withSettings { settings, _ in
            var changes = 0
            settings.onChange = { changes += 1 }
            settings.detentsPerRevolution = 18
            settings.showOverlay = false
            #expect(changes == 2)
        }
    }
}
