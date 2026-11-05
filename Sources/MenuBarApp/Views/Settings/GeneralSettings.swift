import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @ObservedObject var poller: Poller

    @AppStorage(SettingsKey.refreshInterval) private var refreshSeconds = RefreshInterval.standard.rawValue
    @AppStorage(SettingsKey.hotkey) private var hotkey = HotkeyChoice.off.rawValue
    @AppStorage(SettingsKey.saveWeeklyReadings) private var saveWeeklyReadings = false
    /// Read once when the view is first built rather than on every redraw — an
    /// install cannot change source while the app is running.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Picker("Check usage", selection: $refreshSeconds) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval.rawValue)
                    }
                }
                // End the current wait rather than let it run out: it is a sleep
                // of the old length, so without this a change from ten minutes
                // to five would take ten minutes to happen.
                .onChange(of: refreshSeconds) { _, _ in poller.wakeNow() }
                Text("Every profile is polled on this schedule, and each poll is what refreshes the widgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                Picker("Global shortcut", selection: $hotkey) {
                    ForEach(HotkeyChoice.allCases) { choice in
                        Text(choice.label).tag(choice.rawValue)
                    }
                }
                .onChange(of: hotkey) { _, new in
                    HotkeyManager.shared.apply(HotkeyChoice(rawValue: new) ?? .off)
                }
                Text("Opens the menu from anywhere. If another app already owns the combination, this one silently loses it — pick a different one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Save weekly readings", isOn: $saveWeeklyReadings)
                    // Now rather than at the next poll, so turning it off deletes
                    // the readings when it says it does.
                    .onChange(of: saveWeeklyReadings) { _, _ in poller.wakeNow() }
                Text("Saves each profile's weekly limit percentage about once an hour, to draw a trend graph on medium and large widgets. Readings stay on this Mac, are cleared at each reset, and are deleted when you turn this off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Weekly trend")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }

    // MARK: - Login item

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            // Unsigned builds can't register a login item; say so rather than
            // silently flipping the toggle back.
            launchError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
