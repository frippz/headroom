import Charts
import SwiftUI

/// The weekly limit across its window: what has been spent so far, a dashed
/// projection to the reset, and a faint diagonal for an even pace. Above the
/// diagonal is spending faster than the limit allows for.
struct WeeklyTrendChart: View {
    let snapshot: Snapshot
    /// Whether there is room to say what the window's ends are.
    var showsDays = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let readings = snapshot.weeklyReadings,
           let pct = snapshot.pct(.weekly),
           let resetsAt = snapshot.weeklyResetsAt {
            let outlook = WeeklyTrend.outlook(pct: pct, resetsAt: resetsAt, now: snapshot.updatedAt)
            let lines = TrendLines(readings: readings, pct: pct, resetsAt: resetsAt,
                                   now: snapshot.updatedAt, outlook: outlook)
            VStack(alignment: .leading, spacing: 4) {
                chart(lines)
                if showsDays { days(resetsAt) }
                verdict(outlook)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly trend")
            .accessibilityValue(Self.text(outlook))
        }
    }

    private func chart(_ lines: TrendLines) -> some View {
        let tint = snapshot.tint(.weekly, scheme)
        return Chart {
            line("Even pace", lines.evenPace, Color.secondary.opacity(0.5), StrokeStyle(lineWidth: 1))
            line("Projection", lines.projection, tint,
                 StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 3]))
            line("Spent", lines.spent, tint,
                 StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartXScale(domain: lines.start...lines.resetsAt)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.background(Color.primary.opacity(0.05)) }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(minHeight: 28)
    }

    private func line(_ name: String, _ points: [WeeklyReading], _ color: Color,
                      _ style: StrokeStyle) -> some ChartContent {
        ForEach(points, id: \.at) { point in
            LineMark(x: .value("Time", point.at),
                     y: .value("Utilization", min(point.pct, 100)),
                     series: .value("Line", name))
                .foregroundStyle(color)
                .lineStyle(style)
        }
    }

    /// Both ends fall on the same weekday, so the words say which end is which.
    private func days(_ resetsAt: Date) -> some View {
        let day = resetsAt.formatted(.dateTime.weekday(.abbreviated))
        return HStack {
            Text("started \(day)")
            Spacer(minLength: 4)
            Text("resets \(day)")
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private func verdict(_ outlook: WeeklyOutlook) -> some View {
        HStack(spacing: 3) {
            // A symbol as well as the tint, so running out never rests on colour.
            if case .runsOut = outlook {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Level.critical.tint(scheme))
            }
            Text(Self.text(outlook))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private static func text(_ outlook: WeeklyOutlook) -> String {
        switch outlook {
        case .tooEarly:
            return "Projection after day one"
        case .limitReached:
            return "Limit reached"
        case let .onPace(pctAtReset):
            return "On pace for \(Format.percent(pctAtReset))"
        case let .runsOut(at):
            return "Runs out \(at.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        }
    }
}

/// The chart's lines, as readings along the window.
private struct TrendLines {
    let start: Date
    let resetsAt: Date
    let spent: [WeeklyReading]
    let projection: [WeeklyReading]

    var evenPace: [WeeklyReading] {
        [WeeklyReading(at: start, pct: 0), WeeklyReading(at: resetsAt, pct: 100)]
    }

    init(readings: [WeeklyReading], pct: Double, resetsAt: Date, now: Date, outlook: WeeklyOutlook) {
        let start = resetsAt.addingTimeInterval(-WeeklyTrend.window)
        self.start = start
        self.resetsAt = resetsAt

        let current = WeeklyReading(at: now, pct: pct)
        // Every window starts at zero, so the line starts there even when the
        // first reading came later: a straight run up to it, for lack of better.
        spent = [WeeklyReading(at: start, pct: 0)]
            + readings.filter { $0.at > start && $0.at < now }
            + [current]

        switch outlook {
        case .tooEarly, .limitReached:
            projection = []
        case let .onPace(pctAtReset):
            projection = [current, WeeklyReading(at: resetsAt, pct: pctAtReset)]
        case let .runsOut(at):
            projection = [current, WeeklyReading(at: at, pct: 100)]
        }
    }
}
