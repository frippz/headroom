import Foundation

/// Every profile's snapshot in one file.
///
/// Widgets are configured individually, so any of them may be scoped to any
/// profile — which means the host has to poll them all and publish them all.
/// `Snapshot` itself is unchanged: it stays the per-profile payload the views
/// already render, and this only wraps it.
public struct SnapshotBundle: Codable, Sendable, Equatable {
    public var updatedAt: Date
    /// Keyed by `Profile.id`, which is the config directory path.
    public var profiles: [String: Snapshot]
    /// Ordered, default first — the widget's configuration picker reads this
    /// rather than enumerating directories, which its sandbox forbids.
    public var profileList: [Profile]
    public var defaultProfileID: String?
    /// The host's poll interval, so a widget's fallback timeline can match it
    /// rather than guess.
    public var refreshSeconds: Int?

    public init(updatedAt: Date = Date(),
                profiles: [String: Snapshot] = [:],
                profileList: [Profile] = [],
                defaultProfileID: String? = nil,
                refreshSeconds: Int? = nil) {
        self.updatedAt = updatedAt
        self.profiles = profiles
        self.profileList = profileList
        self.defaultProfileID = defaultProfileID
        self.refreshSeconds = refreshSeconds
    }

    /// Whether anything the widget actually draws has moved.
    ///
    /// `updatedAt` is stamped `Date()` on every poll whether or not a fetch
    /// succeeded, so a plain `!=` is always true — and reloading on that is the
    /// 1440 requests a day that put us over WidgetKit's reload budget. Reloads
    /// from a containing app are only budget-exempt while it is foreground, and
    /// an `LSUIElement` menu bar app never is.
    ///
    /// ponytail: an active session still moves the numbers most minutes, so this
    /// buys back the idle hours rather than capping the busy ones. If the budget
    /// still bites, floor it to one reload every five minutes — measured, not
    /// guessed.
    public func draws(differentlyFrom other: SnapshotBundle?) -> Bool {
        guard let other else { return true }
        return undated() != other.undated()
    }

    private func undated() -> SnapshotBundle {
        var copy = self
        copy.updatedAt = .distantPast
        copy.profiles = copy.profiles.mapValues {
            var snapshot = $0
            snapshot.updatedAt = .distantPast
            // The line ends at `weeklyPct`, so a reading can only change what is
            // drawn along with that number. An idle hour's reading would
            // otherwise spend a reload on the same flat line; whether there are
            // readings at all is the setting, and that does draw differently.
            snapshot.weeklyReadings = snapshot.weeklyReadings.map { _ in [] }
            return snapshot
        }
        return copy
    }

    /// What turning the opt-in setting off leaves behind.
    public mutating func removeWeeklyReadings() {
        profiles = profiles.mapValues {
            var snapshot = $0
            snapshot.weeklyReadings = nil
            return snapshot
        }
    }

    /// Exactly the named profile, or nil.
    ///
    /// Deliberately does not fall back: a widget configured for one account and
    /// quietly showing another's numbers is worse than one that says it can't
    /// find the account. Callers decide, because "unconfigured" and "configured
    /// but gone" deserve different answers.
    public func snapshot(forExactly profileID: String) -> Snapshot? {
        profiles[profileID]
    }

    public func profile(forExactly profileID: String) -> Profile? {
        profileList.first { $0.id == profileID }
    }

    public var defaultProfile: Profile? {
        profileList.first { $0.id == defaultProfileID } ?? profileList.first
    }

    public var defaultSnapshot: Snapshot? {
        defaultProfile.flatMap { profiles[$0.id] }
    }
}

extension SnapshotBundle {
    /// Team-prefixed, which macOS accepts for a Developer-signed app without a
    /// provisioning profile. Must match both targets' entitlements in
    /// project.yml.
    public static let appGroup = "XU3G5KB593.se.frodlund.claude-usage"

    /// The one place the host writes and the widget reads. Nil when the process
    /// lacks the App Group entitlement — an unsigned `swift run`, for one.
    public static var location: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("bundle.json")
    }

    @discardableResult
    public func write(to url: URL? = location) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let url, let data = try? encoder.encode(self) else { return false }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomic so the widget can never read a half-written file; owner-only
        // because it carries account emails and config paths.
        guard (try? data.write(to: url, options: .atomic)) != nil
        else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }

    public static func read(from url: URL? = location) -> SnapshotBundle? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SnapshotBundle.self, from: data)
    }
}
