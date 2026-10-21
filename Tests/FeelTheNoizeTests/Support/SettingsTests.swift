import Foundation
import Testing

@testable import FeelTheNoize

struct SettingsTests {
    /// Runs the body against a private defaults domain, so nothing touches the app's real preferences. The registration
    /// domain is shared by every `UserDefaults` in the process, so `Settings.init` registers its defaults for `.standard`
    /// as well; that is harmless here, because the test host never installs `AppDelegate`.
    private func withSettings(_ body: (Settings, UserDefaults) -> Void) {
        let suiteName = "com.panjas.FeelTheNoizeTests.\(UUID().uuidString)"
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
            #expect(settings.keepDialAwake == true)
        }
    }

    @Test func valuesRoundTrip() {
        withSettings { settings, _ in
            settings.detentsPerRevolution = 72
            settings.volumeStepPercent = 5
            settings.reverseDirection = true
            settings.hapticDetents = false
            settings.showOverlay = false
            settings.keepDialAwake = false
            #expect(settings.detentsPerRevolution == 72)
            #expect(settings.volumeStepPercent == 5)
            #expect(settings.reverseDirection == true)
            #expect(settings.hapticDetents == false)
            #expect(settings.showOverlay == false)
            #expect(settings.keepDialAwake == false)
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
            #expect(settings.isDeviceEnabled("speakers") == false)
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

    @Test func rememberDevicesMergesWithoutOnChange() {
        withSettings { settings, _ in
            var changes = 0
            settings.onChange = { changes += 1 }
            settings.rememberDevices(["speakers": "MacBook Pro Speakers"])
            settings.rememberDevices(["airpods": "AirPods Pro"])
            settings.rememberDevices(["speakers": "MacBook Pro Speakers"])
            #expect(settings.knownDevices == ["speakers": "MacBook Pro Speakers", "airpods": "AirPods Pro"])

            settings.rememberDevices(["airpods": "Heiko's AirPods"])
            #expect(settings.knownDevices["airpods"] == "Heiko's AirPods")
            #expect(changes == 0, "Remembering names is bookkeeping and must not refresh the settings")
        }
    }

    @Test func softwareVolumeIsOptInAndRespectsExclusion() {
        withSettings { settings, _ in
            #expect(settings.wantsSoftwareVolume("m2") == false)
            settings.setSoftwareVolume("m2", enabled: true)
            #expect(settings.softwareVolumeDeviceUIDs == ["m2"])
            #expect(settings.wantsSoftwareVolume("m2"))
            settings.setDevice("m2", enabled: false)
            #expect(settings.wantsSoftwareVolume("m2") == false)
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
            expectClose(settings.softwareVolumeLevel("m2"), 0.42, tolerance: 0.000_01)
            #expect(settings.softwareVolumeLevel("other") == 1)
            #expect(changes == 0)
        }
    }

    @Test func iconStyleDefaultsToArcAndFallsBack() {
        withSettings { settings, defaults in
            #expect(settings.iconStyle == .arc)
            settings.iconStyle = .dots
            #expect(settings.iconStyle == .dots)
            defaults.set("speaker", forKey: "iconStyle")
            #expect(settings.iconStyle == .arc)
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

    @Test func keptInputIsOffByDefaultAndRoundTrips() {
        withSettings { settings, defaults in
            var changes = 0
            settings.onChange = { changes += 1 }
            #expect(settings.keptInputDeviceUID == nil)
            settings.keptInputDeviceUID = "m2"
            #expect(settings.keptInputDeviceUID == "m2")
            settings.keptInputDeviceUID = "m2"
            #expect(changes == 1)
            settings.keptInputDeviceUID = nil
            #expect(settings.keptInputDeviceUID == nil)
            #expect(defaults.string(forKey: "keptInputDevice") == "")
            #expect(changes == 2)
        }
    }

    @Test func rememberInputDevicesIsSeparateFromOutputs() {
        withSettings { settings, _ in
            var changes = 0
            settings.onChange = { changes += 1 }
            settings.rememberInputDevices(["m2": "M2"])
            settings.rememberInputDevices(["m2": "M2"])
            #expect(settings.knownInputDevices == ["m2": "M2"])
            #expect(settings.knownDevices.isEmpty)
            #expect(changes == 0)
        }
    }
}
