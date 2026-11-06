import AppKit
import Foundation
import SwiftUI
import WidgetKit

/// Owns the refresh loop. The widget never polls anything itself — this writes
/// the snapshot files and tells WidgetKit to reload.
@MainActor
final class Poller: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var profiles: [Profile] = []

    /// Severity each metric was last seen at, for the selected profile only.
    ///
    /// ponytail: in memory, so a relaunch part-way through a window can repeat
    /// one alert. Persisting it is a single UserDefaults line if that ever grates
    /// — it isn't worth a file today.
    private var lastLevel: [Metric: Level] = [:]

    @AppStorage(SettingsKey.warn) private var warn = 50.0
    @AppStorage(SettingsKey.critical) private var critical = 80.0
    @AppStorage(SettingsKey.selectedProfile) private var selectedProfile = ""
    @AppStorage(SettingsKey.refreshInterval) private var refreshSeconds = RefreshInterval.standard.rawValue

    /// The stored interval held to the offered range, so a value from before
    /// faster intervals were removed, or from `defaults write`, never polls
    /// faster than the floor.
    private var pollSeconds: Int {
        min(max(refreshSeconds, RefreshInterval.fiveMinutes.rawValue),
            RefreshInterval.tenMinutes.rawValue)
    }
    @AppStorage(SettingsKey.notifyThreshold) private var notifyThreshold = true
    @AppStorage(SettingsKey.saveWeeklyReadings) private var saveWeeklyReadings = false

    private var loop: Task<Void, Never>?
    /// Only the wait, never the poll — see wakeNow().
    private var sleeper: Task<Void, Never>?

    /// One per profile, keyed by `Profile.id`. Every profile is polled, not just
    /// the selected one, because each widget can be scoped to a different
    /// account and the sandboxed widget cannot fetch anything itself.
    private var monitors: [String: ProfileMonitor] = [:]

    /// What the widget was last told about, so an unchanged poll doesn't spend a
    /// reload from WidgetKit's budget.
    private var lastPublished: SnapshotBundle?

    /// What the menu bar itself shows as text.
    ///
    /// Text is still the default form, and menu bar items are rendered as
    /// template images — so a coloured dot would come out grey and the bang is
    /// the one severity signal that survives. The ring below is the way round
    /// that, and it is opt-in.
    ///
    /// The metric and style are arguments rather than `@AppStorage` here, and
    /// that is load-bearing: `@AppStorage` on an ObservableObject does not
    /// publish a change, so reading them from this class would leave the menu
    /// bar showing the old choice until the next poll — up to ten minutes of a
    /// settings control appearing to do nothing. They live on the App scene,
    /// which SwiftUI does invalidate.
    func menuBarTitle(metric: Metric, style: MenuBarStyle) -> String {
        guard let snapshot else { return "··" }

        switch style {
        case .percentage:
            return marked(snapshot, metric)
        case .percentageAndReset:
            let resets = snapshot.hasReset(metric) ? "" : Format.until(snapshot.resetsAt(metric))
            return resets.isEmpty ? marked(snapshot, metric) : "\(marked(snapshot, metric)) · \(resets)"
        case .bothLimits:
            return "\(Metric.session.initial) \(Format.percent(snapshot.pct(.session)))"
                + "  \(Metric.weekly.initial) \(Format.percent(snapshot.pct(.weekly)))"
        }
    }

    /// The same reading as a drawn form, for the appearances that ask for one.
    ///
    /// Computed rather than published: the label body is re-evaluated when the
    /// snapshot changes or the setting does, and a 16-point render costs less
    /// than the plumbing to keep a cached copy in step with both.
    func menuBarImage(appearance: MenuBarAppearance, metric: Metric,
                      colorMode: MenuBarColorMode, customHex: String) -> NSImage? {
        MenuBarIcon.image(appearance: appearance,
                          pct: snapshot?.pct(metric),
                          level: snapshot?.level(metric) ?? .none,
                          colorMode: colorMode, customHex: customHex)
    }

    private func marked(_ snapshot: Snapshot, _ metric: Metric) -> String {
        let text = Format.percent(snapshot.pct(metric))
        return snapshot.level(metric) == .critical ? "! \(text)" : text
    }

    var activeProfile: Profile? {
        profiles.first { $0.id == selectedProfile } ?? profiles.first
    }

    /// Starts immediately: the menu bar title must be populated before the user
    /// ever opens the menu, so this can't wait for a view's onAppear.
    ///
    /// `autostart: false` builds an inert one for previews and snapshot tests —
    /// no discovery against the real home directory, no poll loop.
    init(autostart: Bool = true, profiles: [Profile] = [], snapshot: Snapshot? = nil) {
        guard autostart else {
            self.profiles = profiles
            self.snapshot = snapshot
            return
        }
        // So the picker, which lists only offered intervals, shows the one in use.
        refreshSeconds = pollSeconds
        rediscover()
        start()
    }

    /// Rebuilds the profile list and the per-profile monitors. Cheap enough to
    /// run on every settings visit — it stats a handful of directories and parses
    /// one small JSON per profile.
    func rediscover() {
        profiles = ProfileStore.discover(extraPaths: ProfileStore.savedExtraPaths())

        let live = Set(profiles.map(\.id))
        monitors = monitors.filter { live.contains($0.key) }

        let saved = SnapshotBundle.read()
        for profile in profiles where monitors[profile.id] == nil {
            monitors[profile.id] = ProfileMonitor(
                profile: profile,
                weeklyReadings: saved?.profiles[profile.id]?.weeklyReadings ?? [])
        }

        if let active = activeProfile, selectedProfile != active.id {
            selectedProfile = active.id
        }
        if activeProfile == nil { snapshot = nil }
    }

    func select(_ profile: Profile) {
        selectedProfile = profile.id
        // Nothing stale must sit under a newly selected profile's name.
        snapshot = nil
        // Another account's severities would otherwise decide this one's alerts.
        lastLevel.removeAll()
        refreshNow()
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                await self?.waitForNextPoll()
            }
        }
    }

    func stop() {
        sleeper?.cancel()
        sleeper = nil
        loop?.cancel()
        loop = nil
    }

    /// The wait between polls, in a task of its own so it can be cut short
    /// without touching the poll it follows. The interval is read here, on each
    /// pass, so a change is picked up without restarting anything.
    private func waitForNextPoll() async {
        // Discarded rather than returned: `try?` on a Void call yields `Void?`,
        // which as a closure's only expression would make this a Task<()?, Never>.
        let task = Task { _ = try? await Task.sleep(for: .seconds(pollSeconds)) }
        sleeper = task
        await task.value
        sleeper = nil
    }

    /// Called when the interval changes: end the current wait so the new one
    /// starts from now. Going from ten minutes back down to five would otherwise
    /// take ten minutes to take effect.
    ///
    /// Deliberately not stop() plus start(). Cancelling the loop cancels a poll
    /// that may be in flight, and cancellation reaches URLSession — which comes
    /// back as URLError(.cancelled), which UsageAPI cannot tell from a real
    /// network failure. Changing a setting would have put "No connection" on the
    /// popover and "no update" on every widget.
    func wakeNow() {
        sleeper?.cancel()
    }

    /// Deletes here rather than leaving it to the next poll, which may be ten
    /// minutes away, or never come while there are no profiles to poll.
    func weeklyReadingsSettingChanged() {
        if !saveWeeklyReadings {
            if var saved = SnapshotBundle.read() {
                saved.removeWeeklyReadings()
                saved.write()
            }
            let current = Array(monitors.values)
            Task { for monitor in current { await monitor.forgetWeeklyReadings() } }
        }
        wakeNow()
    }

    func refreshNow() {
        Task { await refresh(force: true) }
    }

    private func refresh(force: Bool = false) async {
        // A manual tap while a poll is in flight would just repeat it.
        guard !isRefreshing, !profiles.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let labelled = profiles.count > 1
        var bundle = SnapshotBundle(
            profileList: profiles,
            defaultProfileID: profiles.first { $0.isDefault }?.id ?? profiles.first?.id,
            refreshSeconds: pollSeconds)

        for profile in profiles {
            guard let monitor = monitors[profile.id] else { continue }
            bundle.profiles[profile.id] = await monitor.snapshot(
                force: force, warn: warn, critical: critical,
                label: labelled ? profile.displayName : nil,
                tracksWeekly: saveWeeklyReadings,
                // Three polls, whatever the interval — otherwise picking a
                // five-minute refresh would label one-poll-old numbers outdated.
                staleAfter: Double(pollSeconds) * 3)
        }
        bundle.updatedAt = Date()
        // The setting can have been turned off while this poll waited on the
        // network, and the readings it fetched must not be written back.
        if !saveWeeklyReadings { bundle.removeWeeklyReadings() }

        snapshot = activeProfile.flatMap { bundle.profiles[$0.id] }
        bundle.write()
        if bundle.draws(differentlyFrom: lastPublished) {
            lastPublished = bundle
            WidgetCenter.shared.reloadAllTimelines()
        }
        if let snapshot { thresholdAlerts(snapshot) }
    }

    // MARK: - Alerts

    /// Only ever about the selected profile. A machine with four config folders
    /// on one account would otherwise fire four identical notifications for the
    /// same limit.
    ///
    /// Fires on an upward crossing only. Falling back — which is what a window
    /// resetting looks like — clears the latch, and that is what re-arms it.
    private func thresholdAlerts(_ snapshot: Snapshot) {
        guard notifyThreshold else {
            lastLevel.removeAll()
            return
        }
        for metric in [Metric.session, .weekly] + snapshot.perModelLimits {
            guard let pct = snapshot.pct(metric) else { continue }
            let level = snapshot.level(metric)
            let previous = lastLevel[metric] ?? .ok
            lastLevel[metric] = level
            guard level == .warn || level == .critical,
                  Self.rank(level) > Self.rank(previous) else { continue }

            let resets = Format.until(snapshot.resetsAt(metric))
            Task {
                await Notifier.shared.post(
                    title: "\(metric.title) at \(Format.percent(pct))",
                    body: resets.isEmpty ? "Headroom" : "Resets in \(resets)")
            }
        }
    }

    private static func rank(_ level: Level) -> Int {
        switch level {
        case .none, .ok: return 0
        case .warn:      return 1
        case .critical:  return 2
        }
    }
}
