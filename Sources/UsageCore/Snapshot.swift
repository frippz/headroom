import Foundation

/// One profile's limits, as the widget needs them.
///
/// The widget extension is sandboxed: it cannot read ~/.claude, cannot reach the
/// Keychain, and has no timer of its own. So it never fetches or parses anything
/// — it reads what the host publishes in a `SnapshotBundle` and renders it.
public struct Snapshot: Codable, Sendable, Equatable {
    public var updatedAt: Date
    public var sessionPct: Double?
    public var sessionResetsAt: Date?
    public var weeklyPct: Double?
    public var weeklyResetsAt: Date?
    /// Per-model weekly windows, on the plans that have them.
    public var opusPct: Double?
    public var opusResetsAt: Date?
    public var sonnetPct: Double?
    public var sonnetResetsAt: Date?
    /// Purchased extra usage, when the account has any.
    public var extraUsagePct: Double?
    /// Percentage points per hour on the five-hour window, whole points.
    ///
    /// Rounded at the source, not in the view: `SnapshotBundle.draws(
    /// differentlyFrom:)` compares published bundles to decide whether to spend a
    /// WidgetKit reload, and an unrounded rate would differ on every single poll
    /// — which is exactly the budget problem that comparison exists to solve.
    public var burnRatePerHour: Double?
    /// This window's saved weekly readings, oldest first. Nil unless the
    /// user's opt-in setting is on, and no graph is drawn then.
    public var weeklyReadings: [WeeklyReading]?
    /// Non-nil when the last refresh failed: "no-token", "token-expired",
    /// "http-401", "network", "bad-json".
    public var error: String?
    public var stale: Bool
    /// Carried here rather than read from UserDefaults, so the widget colours
    /// by the same thresholds without reading the app's defaults.
    public var warn: Double
    public var critical: Double
    /// Which profile these numbers belong to. Set only when the machine has more
    /// than one, so the ordinary single-profile case shows no extra chrome.
    public var profileLabel: String?

    public init(
        updatedAt: Date = Date(),
        usage: UsageData? = nil,
        error: String? = nil,
        stale: Bool = false,
        warn: Double = 50,
        critical: Double = 80
    ) {
        self.updatedAt = updatedAt
        self.warn = warn
        self.critical = critical
        self.sessionPct = usage?.fiveHour?.utilization
        self.sessionResetsAt = usage?.fiveHour?.resetsAt
        self.weeklyPct = usage?.sevenDay?.utilization
        self.weeklyResetsAt = usage?.sevenDay?.resetsAt
        self.opusPct = usage?.sevenDayOpus?.utilization
        self.opusResetsAt = usage?.sevenDayOpus?.resetsAt
        self.sonnetPct = usage?.sevenDaySonnet?.utilization
        self.sonnetResetsAt = usage?.sevenDaySonnet?.resetsAt
        self.extraUsagePct = usage?.extraUsage?.utilization
        self.error = error
        self.stale = stale
    }

    public var sessionLevel: Level { Level.of(sessionPct, warn: warn, critical: critical) }
    public var weeklyLevel: Level { Level.of(weeklyPct, warn: warn, critical: critical) }

    /// How long until the five-hour window fills at the current burn rate.
    ///
    /// Nil is the ordinary answer, and deliberately so: no measured rate yet, no
    /// room left, or — most often — the window resets before it could fill.
    /// Announcing "full in 6h" about a window that empties in two would be worse
    /// than saying nothing, so that case returns nil rather than a number.
    public func timeToFull(now: Date = Date()) -> TimeInterval? {
        guard let rate = burnRatePerHour, rate > 0,
              let pct = sessionPct, pct < 100 else { return nil }
        let seconds = (100 - pct) / rate * 3600
        if let reset = sessionResetsAt, now.addingTimeInterval(seconds) >= reset {
            return nil
        }
        return seconds
    }
}
