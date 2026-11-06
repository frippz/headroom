import SwiftUI

struct MenuView: View {
    let snapshot: Snapshot?
    let isRefreshing: Bool
    /// False when discovery found no Claude Code profile, so no poll will ever
    /// produce a snapshot.
    var hasProfiles = true
    var refresh: () -> Void = {}
    /// False renders the informational content only. ImageRenderer draws
    /// interactive controls as unavailable and reads the version from whatever
    /// bundle it's hosted in, so the snapshots would otherwise show prohibition
    /// badges and the test runner's version number.
    var showsActions = true

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot {
                // Only present when the machine has more than one profile — the
                // ordinary case gets no extra chrome.
                if let label = snapshot.profileLabel {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle")
                        Text(label).lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
                }
                // Above the numbers, so the eye and VoiceOver reach the
                // problem before the percentages it qualifies.
                if let message = snapshot.errorMessage {
                    banner(message, stale: snapshot.stale)
                    Divider().padding(.vertical, 10)
                }
                gauges(snapshot)
                WeeklyTrendChart(snapshot: snapshot, showsDays: true)
                    .frame(height: 92)
                    .padding(.top, 10)
                burn(snapshot)
                perModel(snapshot)
                Divider().padding(.vertical, 10)
                footer(snapshot)
            } else if hasProfiles {
                loading
            } else {
                banner("No Claude Code profile found — run Claude Code once to sign in",
                       stale: false)
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private func gauges(_ snapshot: Snapshot) -> some View {
        HStack(spacing: 18) {
            MetricGauge(snapshot: snapshot, metric: .session, lineWidth: 9)
            MetricGauge(snapshot: snapshot, metric: .weekly, lineWidth: 9)
        }
        .frame(height: 118)
        .frame(maxWidth: .infinity)
    }

    /// The projection, when there is one. Two polls of active use before it says
    /// anything, and silent again the moment the window resets first.
    @ViewBuilder
    private func burn(_ snapshot: Snapshot) -> some View {
        if let summary = snapshot.burnSummary() {
            HStack(spacing: 4) {
                Image(systemName: "flame")
                    .accessibilityHidden(true)
                Text("5-hour burn rate \(summary)")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
        }
    }

    /// Per-model weekly windows, on the plans that report them.
    @ViewBuilder
    private func perModel(_ snapshot: Snapshot) -> some View {
        let limits = snapshot.perModelLimits
        if !limits.isEmpty {
            VStack(spacing: 5) {
                ForEach(limits, id: \.self) { metric in
                    LimitRow(snapshot: snapshot, metric: metric)
                }
            }
            .padding(.top, 10)
        }
    }

    private func banner(_ message: String, stale: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Level.warn.tint)
                .accessibilityLabel("Warning")
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                if stale { Text("Numbers are outdated") }
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 10))
        .accessibilityElement(children: .combine)
    }

    // ponytail: text buttons, not an icon row — it's what menu bar apps
    // conventionally do, and it reads without a tooltip.
    private func footer(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let status = isRefreshing ? "Refreshing…" : Self.status(snapshot)
            Text(showsActions ? "\(status) · v\(AppVersion.current)" : status)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if showsActions {
                HStack(spacing: 14) {
                    Button("Refresh", action: refresh)
                        .disabled(isRefreshing)
                        .keyboardShortcut("r")
                    // Not SettingsLink: an LSUIElement app is never active on its
                    // own, so the window opened behind whatever app was in front.
                    Button("Settings…") {
                        openSettings()
                        NSApp.activate()
                    }
                    .keyboardShortcut(",")
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading usage…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func status(_ snapshot: Snapshot, now: Date = Date()) -> String {
        snapshot.hasNumbers ? updated(snapshot.updatedAt, now: now) : "Not updated yet"
    }

    /// RelativeDateTimeFormatter renders a zero interval as "in 0 sec.", which
    /// reads as a bug on a snapshot that was just taken. Anything inside the
    /// poll interval is "just now" anyway.
    static func updated(_ date: Date, now: Date = Date()) -> String {
        let age = now.timeIntervalSince(date)
        guard age >= 60 else { return "Updated just now" }
        return "Updated \(relative.localizedString(for: date, relativeTo: now))"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
