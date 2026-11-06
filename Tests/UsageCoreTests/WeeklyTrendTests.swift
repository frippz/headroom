import XCTest
@testable import UsageCore

final class WeeklyTrendTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func reading(hoursAgo: Double, pct: Double) -> WeeklyReading {
        WeeklyReading(at: now.addingTimeInterval(-hoursAgo * 3600), pct: pct)
    }

    /// `elapsed` days into the window as of `now`.
    private func reset(afterDays elapsed: Double) -> Date {
        now.addingTimeInterval(WeeklyTrend.window - elapsed * 86400)
    }

    // MARK: - Recording

    func testAddsAtMostOneReadingAnHour() {
        let resetsAt = reset(afterDays: 3)
        let recent = [reading(hoursAgo: 0.5, pct: 10)]
        XCTAssertEqual(WeeklyTrend.adding(pct: 11, resetsAt: resetsAt, to: recent, now: now), recent)

        let older = [reading(hoursAgo: 1, pct: 10)]
        XCTAssertEqual(WeeklyTrend.adding(pct: 11, resetsAt: resetsAt, to: older, now: now),
                       older + [WeeklyReading(at: now, pct: 11)])
    }

    func testAnIdleHourStillAddsAReading() {
        // Without it the line would slope across the whole idle stretch instead
        // of staying flat and rising when use resumed.
        let older = [reading(hoursAgo: 2, pct: 10)]
        XCTAssertEqual(WeeklyTrend.adding(pct: 10, resetsAt: reset(afterDays: 3), to: older, now: now).count, 2)
    }

    func testDropsReadingsFromBeforeTheWindow() {
        // Six days into this window, so the window started 144 hours ago.
        let readings = [reading(hoursAgo: 150, pct: 5), reading(hoursAgo: 100, pct: 8)]
        XCTAssertEqual(WeeklyTrend.adding(pct: 9, resetsAt: reset(afterDays: 6), to: readings, now: now),
                       [reading(hoursAgo: 100, pct: 8), WeeklyReading(at: now, pct: 9)])
    }

    func testAFallingReadingStartsOver() {
        let readings = [reading(hoursAgo: 5, pct: 60), reading(hoursAgo: 0.1, pct: 61)]
        XCTAssertEqual(WeeklyTrend.adding(pct: 2, resetsAt: reset(afterDays: 3), to: readings, now: now),
                       [WeeklyReading(at: now, pct: 2)])
    }

    // MARK: - Outlook

    func testOnPaceProjectsTheAverageRateToTheReset() {
        XCTAssertEqual(WeeklyTrend.outlook(pct: 20, resetsAt: reset(afterDays: 3.5), now: now),
                       .onPace(pctAtReset: 40))
    }

    func testRunsOutSaysWhen() {
        // 60% in three days is 20% a day, so the last 40% lasts two days.
        XCTAssertEqual(WeeklyTrend.outlook(pct: 60, resetsAt: reset(afterDays: 3), now: now),
                       .runsOut(at: now.addingTimeInterval(2 * 86400)))
    }

    func testTheFirstDayIsTooEarlyToProject() {
        XCTAssertEqual(WeeklyTrend.outlook(pct: 30, resetsAt: reset(afterDays: 0.5), now: now), .tooEarly)
    }

    func testAFullLimitIsReachedHoweverEarly() {
        XCTAssertEqual(WeeklyTrend.outlook(pct: 100, resetsAt: reset(afterDays: 0.5), now: now), .limitReached)
    }

    func testNoUseProjectsZero() {
        XCTAssertEqual(WeeklyTrend.outlook(pct: 0, resetsAt: reset(afterDays: 3), now: now),
                       .onPace(pctAtReset: 0))
    }

    // MARK: - Opt-in

    private let monitorProfile = Profile(configDir: URL(fileURLWithPath: "/Users/tester/.claude"),
                                         isDefault: true, email: nil, organization: nil)

    private func fresh(pct: Double) -> FetchResult {
        FetchResult(data: UsageData(fiveHour: nil,
                                    sevenDay: UsageNode(utilization: pct, resetsAt: reset(afterDays: 3))))
    }

    func testTurnedOffPublishesNothingAndForgetsWhatItHad() async {
        let monitor = ProfileMonitor(profile: monitorProfile, weeklyReadings: [reading(hoursAgo: 2, pct: 10)])

        let off = await monitor.updateWeeklyReadings(tracking: false, result: fresh(pct: 12), now: now)
        XCTAssertNil(off)

        let onAgain = await monitor.updateWeeklyReadings(tracking: true, result: fresh(pct: 12), now: now)
        XCTAssertEqual(onAgain, [WeeklyReading(at: now, pct: 12)])
    }

    func testResumesFromSavedReadings() async {
        let saved = [reading(hoursAgo: 2, pct: 10)]
        let monitor = ProfileMonitor(profile: monitorProfile, weeklyReadings: saved)

        let readings = await monitor.updateWeeklyReadings(tracking: true, result: fresh(pct: 12), now: now)
        XCTAssertEqual(readings, saved + [WeeklyReading(at: now, pct: 12)])
    }

    func testAFailedFetchKeepsReadingsButAddsNone() async {
        let saved = [reading(hoursAgo: 2, pct: 10)]
        let monitor = ProfileMonitor(profile: monitorProfile, weeklyReadings: saved)

        var failed = fresh(pct: 12)
        failed.error = "network"
        let readings = await monitor.updateWeeklyReadings(tracking: true, result: failed, now: now)
        XCTAssertEqual(readings, saved)
    }

    func testTurningOffRemovesReadingsFromTheFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundle-\(UUID().uuidString)/bundle.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var snapshot = Snapshot(updatedAt: now, usage: UsageData(
            fiveHour: nil, sevenDay: UsageNode(utilization: 10, resetsAt: reset(afterDays: 3))))
        snapshot.weeklyReadings = [reading(hoursAgo: 2, pct: 10)]
        XCTAssertTrue(SnapshotBundle(profiles: ["p": snapshot]).write(to: url))

        var saved = try XCTUnwrap(SnapshotBundle.read(from: url))
        saved.removeWeeklyReadings()
        XCTAssertTrue(saved.write(to: url))

        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("weeklyReadings"))
    }

    func testForgetLeavesNothingToComeBack() async {
        let monitor = ProfileMonitor(profile: monitorProfile, weeklyReadings: [reading(hoursAgo: 2, pct: 10)])
        await monitor.forgetWeeklyReadings()

        let readings = await monitor.updateWeeklyReadings(tracking: true, result: fresh(pct: 12), now: now)
        XCTAssertEqual(readings, [WeeklyReading(at: now, pct: 12)])
    }

    // MARK: - Reloads

    func testANewReadingAloneAsksForNoReloadButTheSettingDoes() {
        var snapshot = Snapshot(updatedAt: now, usage: UsageData(
            fiveHour: nil, sevenDay: UsageNode(utilization: 10, resetsAt: reset(afterDays: 3))))
        snapshot.weeklyReadings = [reading(hoursAgo: 2, pct: 10)]
        let before = SnapshotBundle(profiles: ["p": snapshot])

        // The hourly reading of an idle hour draws the same flat line.
        var added = before
        added.profiles["p"]?.weeklyReadings?.append(WeeklyReading(at: now, pct: 10))
        XCTAssertFalse(added.draws(differentlyFrom: before))

        var turnedOff = before
        turnedOff.profiles["p"]?.weeklyReadings = nil
        XCTAssertTrue(turnedOff.draws(differentlyFrom: before))
    }
}
