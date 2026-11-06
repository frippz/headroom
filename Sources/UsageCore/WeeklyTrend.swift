import Foundation

/// One saved reading of the weekly limit.
public struct WeeklyReading: Codable, Sendable, Equatable {
    public var at: Date
    public var pct: Double

    public init(at: Date, pct: Double) {
        self.at = at
        self.pct = pct
    }
}

/// Where the weekly limit is heading if the rest of the window goes like the
/// part already spent.
public enum WeeklyOutlook: Sendable, Equatable {
    case tooEarly
    case limitReached
    case onPace(pctAtReset: Double)
    case runsOut(at: Date)
}

public enum WeeklyTrend {
    /// The API reports only when the window ends. It starts this long before.
    public static let window: TimeInterval = 7 * 86400
    /// Hourly keeps a whole window to about 170 readings in a file the widget
    /// reads on every reload.
    private static let spacing: TimeInterval = 3600
    /// A first day's use says little about the week: five busy hours on the
    /// first morning would otherwise project several times the limit.
    private static let minElapsed: TimeInterval = 86400

    /// `readings` with this one added, less anything from an earlier window.
    public static func adding(pct: Double, resetsAt: Date, to readings: [WeeklyReading],
                              now: Date = Date()) -> [WeeklyReading] {
        let start = resetsAt.addingTimeInterval(-window)
        var kept = readings.filter { $0.at >= start }
        // A falling reading is the window turning over, even when the reported
        // reset has not moved yet; `ProfileMonitor.burnRate` reads it the same way.
        if let last = kept.last, pct < last.pct { kept.removeAll() }
        if let last = kept.last, now.timeIntervalSince(last.at) < spacing { return kept }
        kept.append(WeeklyReading(at: now, pct: pct))
        return kept
    }

    /// Projects at the window's average rate, not the latest: use comes in
    /// bursts with nights between them, and the average already counts both.
    public static func outlook(pct: Double, resetsAt: Date, now: Date = Date()) -> WeeklyOutlook {
        if pct >= 100 { return .limitReached }
        let elapsed = window - resetsAt.timeIntervalSince(now)
        guard elapsed >= minElapsed else { return .tooEarly }

        let pctAtReset = pct * window / elapsed
        guard pctAtReset >= 100 else { return .onPace(pctAtReset: pctAtReset) }
        return .runsOut(at: now.addingTimeInterval((100 - pct) / pct * elapsed))
    }
}
