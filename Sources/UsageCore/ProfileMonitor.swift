import Foundation

/// Everything needed to watch one profile: its API client and its burn-rate
/// samples.
///
/// One per profile is what keeps profiles from leaking into each other — the API
/// cache is single-profile state, and a shared instance would serve whichever
/// account touched it last.
public actor ProfileMonitor {
    public let profile: Profile

    private let api: UsageAPI

    /// Recent five-hour readings, oldest first, for the burn rate.
    ///
    /// ponytail: in memory only. A relaunch starts over and the rate reappears
    /// two polls later; persisting it would mean writing a file on every poll
    /// to preserve a number that is meaningless once its window has moved on.
    private var samples: [(at: Date, pct: Double)] = []
    private static let burnWindow: TimeInterval = 30 * 60
    /// The shortest gap worth measuring a slope across. Below this, a single
    /// large turn reads as an implausible rate.
    private static let minGap: TimeInterval = 120

    /// Saved only by being published: `bundle.json` holds them for the widget
    /// anyway, so a relaunch seeds them from there rather than from a second file.
    private var readings: [WeeklyReading]

    public init(profile: Profile, weeklyReadings: [WeeklyReading] = []) {
        self.profile = profile
        self.readings = weeklyReadings
        self.api = UsageAPI(profile: profile)
    }

    /// One poll.
    public func snapshot(
        force: Bool = false,
        warn: Double = 50,
        critical: Double = 80,
        label: String? = nil,
        tracksWeekly: Bool = false,
        staleAfter: TimeInterval = 180
    ) async -> Snapshot {
        let result = await api.fetch(force: force, staleAfter: staleAfter)

        // The snapshot's clock is when its numbers were fetched, not when this
        // poll ran — during an outage "updated 2s ago" next to hours-old
        // percentages was a lie the stale flag then had to contradict.
        var snapshot = Snapshot(updatedAt: result.fetchedAt ?? Date(),
                                usage: result.data,
                                error: result.error, stale: result.stale,
                                warn: warn, critical: critical)
        snapshot.profileLabel = label
        snapshot.burnRatePerHour = burnRate(for: result.data?.fiveHour?.utilization)
        snapshot.weeklyReadings = updateWeeklyReadings(tracking: tracksWeekly, result: result)
        return snapshot
    }

    public func forgetWeeklyReadings() {
        readings = []
    }

    /// Nil when the setting is off, and forgets what it had.
    ///
    /// A failed fetch serves the cached numbers, which are not a new reading.
    func updateWeeklyReadings(tracking: Bool, result: FetchResult, now: Date = Date()) -> [WeeklyReading]? {
        guard tracking else {
            readings = []
            return nil
        }
        if result.error == nil, let week = result.data?.sevenDay, let resetsAt = week.resetsAt {
            readings = WeeklyTrend.adding(pct: week.utilization, resetsAt: resetsAt,
                                          to: readings, now: now)
        }
        return readings
    }

    /// Percentage points per hour on the five-hour window, measured across this
    /// process's own readings.
    ///
    /// A falling percentage means the window turned over, not that usage is
    /// dropping — so a non-positive slope yields nil rather than a negative rate.
    /// Rounded to whole points, which `Snapshot.burnRatePerHour` explains.
    func burnRate(for pct: Double?, now: Date = Date()) -> Double? {
        guard let pct else { return nil }
        let previous = samples.last

        // A falling reading is the window turning over, and everything before it
        // describes a window that no longer exists. Ageing those out instead of
        // dropping them would mean measuring across the reset for a further half
        // hour — every one of those slopes negative — so a fresh window would
        // report nothing precisely when a projection is worth having.
        if let previous, pct < previous.pct { samples.removeAll() }

        samples.append((now, pct))
        samples.removeAll { now.timeIntervalSince($0.at) > Self.burnWindow }

        // Nothing since the last poll means nothing is burning right now.
        //
        // Load-bearing, not tidiness: without it the slope keeps decaying for
        // half an hour after a session ends — 180/h, then 120, then 90 — and
        // every one of those is a different published snapshot. That is exactly
        // the per-poll churn `SnapshotBundle.draws(differentlyFrom:)` exists to
        // keep out of WidgetKit's reload budget.
        guard let previous, pct > previous.pct else { return nil }

        guard let oldest = samples.first(where: { now.timeIntervalSince($0.at) >= Self.minGap })
        else { return nil }
        let elapsed = now.timeIntervalSince(oldest.at)
        let delta = pct - oldest.pct
        guard elapsed > 0, delta > 0 else { return nil }

        let rate = delta / (elapsed / 3600)
        // Under a point an hour there is nothing to project, and rounding would
        // make it zero regardless.
        return rate < 1 ? nil : rate.rounded()
    }
}
