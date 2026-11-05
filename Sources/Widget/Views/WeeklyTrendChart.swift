import SwiftUI

/// The weekly limit across its window: what has been spent so far, a dashed
/// projection to the reset, and a faint diagonal for an even pace. Above the
/// diagonal is spending faster than the limit allows for.
struct WeeklyTrendChart: View {
    let snapshot: Snapshot
    /// Large has room for what the window's ends are; medium does not.
    var showsDays = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let readings = snapshot.weeklyReadings,
           let pct = snapshot.pct(.weekly),
           let resetsAt = snapshot.weeklyResetsAt {
            let outlook = WeeklyTrend.outlook(pct: pct, resetsAt: resetsAt, now: snapshot.updatedAt)
            let plot = TrendPlot(readings: readings, pct: pct, resetsAt: resetsAt,
                                 now: snapshot.updatedAt, outlook: outlook)
            VStack(alignment: .leading, spacing: 4) {
                chart(plot)
                if showsDays { days(resetsAt) }
                verdict(outlook)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly trend")
            .accessibilityValue(Self.text(outlook))
        }
    }

    private func chart(_ plot: TrendPlot) -> some View {
        let tint = snapshot.tint(.weekly, scheme)
        return ZStack {
            Rectangle().fill(Color.primary.opacity(0.05))
            TrendLine(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            TrendLine(points: plot.projection)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 3]))
            TrendLine(points: plot.spent)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(minHeight: 28)
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

/// The chart's lines in unit coordinates: x runs across the window, y up from
/// 0 to 100 percent.
private struct TrendPlot {
    let spent: [CGPoint]
    let projection: [CGPoint]

    init(readings: [WeeklyReading], pct: Double, resetsAt: Date, now: Date, outlook: WeeklyOutlook) {
        func x(_ date: Date) -> CGFloat {
            let elapsed = WeeklyTrend.window - resetsAt.timeIntervalSince(date)
            return CGFloat(min(max(elapsed / WeeklyTrend.window, 0), 1))
        }
        func y(_ pct: Double) -> CGFloat { CGFloat(min(max(pct / 100, 0), 1)) }

        let current = CGPoint(x: x(now), y: y(pct))
        // Every window starts at zero, so the line starts there even when the
        // first reading came later: a straight run up to it, for lack of better.
        spent = [CGPoint(x: 0, y: 0)]
            + readings.filter { $0.at < now }.map { CGPoint(x: x($0.at), y: y($0.pct)) }
            + [current]

        switch outlook {
        case .tooEarly, .limitReached:
            projection = []
        case let .onPace(pctAtReset):
            projection = [current, CGPoint(x: 1, y: y(pctAtReset))]
        case let .runsOut(at):
            projection = [current, CGPoint(x: x(at), y: 1)]
        }
    }
}

private struct TrendLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addLines(points.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.maxY - $0.y * rect.height)
        })
        return path
    }
}
