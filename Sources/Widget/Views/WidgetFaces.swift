import SwiftUI

/// Deliberately not `WidgetFamily`: keeping WidgetKit out of these views lets the
/// snapshot tests render them without linking an app extension.
enum Face: String, CaseIterable {
    case small, medium, large

    /// Points, at 1x. WidgetKit's macOS system family sizes.
    var size: CGSize {
        switch self {
        case .small:  return CGSize(width: 170, height: 170)
        case .medium: return CGSize(width: 364, height: 170)
        case .large:  return CGSize(width: 364, height: 382)
        }
    }
}

/// Why a widget can't show what it was configured to show.
enum WidgetProblem {
    case noData
    case profileMissing

    var headline: String {
        switch self {
        case .noData:         return "Open Headroom"
        case .profileMissing: return "Profile not found"
        }
    }

    var detail: String {
        switch self {
        case .noData:
            return "The menu bar app supplies the data"
        case .profileMissing:
            return "Pick another in Edit Widget"
        }
    }
}

/// The widget body for every family. Split out from the `@main` entry point so
/// the snapshot tests can render these without linking an app extension.
struct UsageWidgetView: View {
    let snapshot: Snapshot?
    var scopeLabel: String?
    var problem: WidgetProblem?
    let face: Face
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let problem {
                unavailable(problem)
            } else if let snapshot {
                VStack(spacing: face == .small ? 6 : 10) {
                    scopeHeader
                    switch face {
                    case .small:  small(snapshot)
                    case .medium: medium(snapshot)
                    case .large:  large(snapshot)
                    }
                }
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Only drawn when the machine has more than one profile — the ordinary
    /// case gets no extra chrome.
    @ViewBuilder
    private var scopeHeader: some View {
        if let scopeLabel {
            Text(scopeLabel)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Families

    private func small(_ snapshot: Snapshot) -> some View {
        VStack(spacing: 8) {
            RingGauge(pct: snapshot.pct(.session),
                      level: snapshot.level(.session),
                      lineWidth: 11,
                      tint: snapshot.tint(.session, scheme))
            VStack(spacing: 2) {
                MetricLabel(snapshot: snapshot, metric: .session, size: 10)
                Text(snapshot.resetsText(.session))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            staleMark(snapshot)
        }
    }

    private func medium(_ snapshot: Snapshot) -> some View {
        HStack(spacing: 20) {
            MetricGauge(snapshot: snapshot, metric: .session, lineWidth: 10)
            MetricGauge(snapshot: snapshot, metric: .weekly, lineWidth: 10)
            VStack(alignment: .leading, spacing: 7) {
                WeeklyTrendChart(snapshot: snapshot)
                burn(snapshot)
                perModel(snapshot)
                Spacer(minLength: 0)
                staleMark(snapshot)
                age(snapshot)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func large(_ snapshot: Snapshot) -> some View {
        VStack(spacing: 12) {
            // Takes whatever height the rows below leave, so the rings grow to
            // fill the family rather than leaving dead space above and below.
            HStack(spacing: 26) {
                MetricGauge(snapshot: snapshot, metric: .session, lineWidth: 12)
                MetricGauge(snapshot: snapshot, metric: .weekly, lineWidth: 12)
            }
            .frame(maxHeight: .infinity)

            WeeklyTrendChart(snapshot: snapshot, showsDays: true)
                .frame(height: 92)
            burn(snapshot)
            perModel(snapshot)
            staleMark(snapshot)
            age(snapshot)
        }
    }

    // MARK: - Pieces

    /// Only ever drawn once a rate has actually been measured, which takes a
    /// couple of polls of active use — so most of the time this is nothing.
    @ViewBuilder
    private func burn(_ snapshot: Snapshot) -> some View {
        if let summary = snapshot.burnSummary() {
            HStack(spacing: 4) {
                Image(systemName: "flame")
                Text(summary)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    /// Per-model weekly windows, on the plans that have them. Absent everywhere
    /// else, which is why nothing reserves space for it.
    ///
    /// Medium gets the name and percentage only: beside two rings the column is
    /// too narrow for `LimitRow`'s bar, which squeezed the percentage out.
    @ViewBuilder
    private func perModel(_ snapshot: Snapshot) -> some View {
        let limits = snapshot.perModelLimits
        if !limits.isEmpty {
            VStack(spacing: 5) {
                ForEach(limits, id: \.self) { metric in
                    if face == .medium {
                        HStack(spacing: 6) {
                            MetricLabel(snapshot: snapshot, metric: metric)
                            Spacer(minLength: 4)
                            Text(Format.percent(snapshot.pct(metric)))
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(snapshot.tint(metric, scheme))
                        }
                        .lineLimit(1)
                        .limitAccessibility(snapshot, metric)
                    } else {
                        LimitRow(snapshot: snapshot, metric: metric)
                    }
                }
            }
        }
    }

    /// The widget can't fix a failed refresh itself — the host app owns that — so
    /// this says the numbers are old rather than offering an action.
    @ViewBuilder
    private func staleMark(_ snapshot: Snapshot) -> some View {
        if snapshot.error != nil {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(snapshot.stale ? "outdated" : "no update")
            }
            .font(.system(size: 9))
            .foregroundStyle(Level.warn.tint)
        }
    }

    /// How old these numbers are.
    ///
    /// `Text(_:style:)` keeps counting inside an already-rendered widget with no
    /// timeline reload, so this is the one thing on the face that stays true when
    /// everything around it has frozen. Without it, 0.3.9's dead widget spent two
    /// days showing confident percentages and a countdown stopped mid-air, with
    /// nothing on screen to say so.
    private func age(_ snapshot: Snapshot) -> some View {
        // Two views, not one concatenated Text: only a Text that *is* the date
        // is guaranteed to keep ticking on its own.
        HStack(spacing: 3) {
            Text("updated")
            Text(snapshot.updatedAt, style: .relative)
                .monospacedDigit()
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }

    private var empty: some View {
        unavailable(.noData)
    }

    /// Says what went wrong rather than rendering another account's numbers,
    /// which would look like the widget working and be wrong.
    private func unavailable(_ problem: WidgetProblem) -> some View {
        VStack(spacing: 6) {
            Image(systemName: problem == .profileMissing
                  ? "questionmark.folder" : "chart.pie")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(problem.headline)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
            if let scopeLabel {
                Text(scopeLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(problem.detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}
