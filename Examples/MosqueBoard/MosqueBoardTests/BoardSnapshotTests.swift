import Foundation
import SalahCore
import Testing

@testable import MosqueBoard

/// The board's logic at fixed instants, below the UI.
struct BoardSnapshotTests {
  private let english = BoardStrings(language: "en")

  private func snapshot(_ board: Board.ID, at text: String, strings: BoardStrings? = nil) throws
    -> BoardSnapshot
  {
    BoardSnapshot.make(
      board: try Board.load(board), at: try Date(text, strategy: .iso8601),
      strings: strings ?? english)
  }

  private func row(_ kind: PrayerKind, in snapshot: BoardSnapshot) throws -> BoardSnapshot.Row {
    try #require(snapshot.rows.first { $0.kind == kind })
  }

  @Test func muisAfternoon() throws {
    let board = try snapshot(.muis, at: "2026-10-14T14:00:00+08:00")
    #expect(board.rows.map(\.kind) == PrayerKind.allCases)
    #expect(try row(.fajr, in: board).time == "05:31")
    #expect(try row(.fajr, in: board).iqama == "05:51")
    #expect(try row(.fajr, in: board).status == .passed)
    #expect(try row(.asr, in: board).status == .next(approaching: false))
    #expect(try row(.sunrise, in: board).iqama == nil)
    #expect(
      board.next
        == .prayer(
          name: "Asr", time: "16:06", countdown: "2:06", spokenCountdown: "2 hours, 6 minutes",
          owningDay: nil))
    #expect(board.banner == nil)
    #expect(board.attribution == BoardSnapshot.muisAttribution)
    #expect(board.gregorianDate.contains("October 14, 2026"))
  }

  @Test func jumuahOnlyWhereDeclared() throws {
    let friday = try snapshot(.muis, at: "2026-10-16T12:00:00+08:00")
    let thursday = try snapshot(.muis, at: "2026-10-15T12:00:00+08:00")
    #expect(try row(.dhuhr, in: friday).name == "Jumu’ah")
    #expect(try row(.dhuhr, in: friday).iqama == "13:22")
    #expect(try row(.dhuhr, in: thursday).name == "Dhuhr")
    #expect(try row(.dhuhr, in: thursday).iqama == "13:02")
  }

  @Test func expiredCoverage() throws {
    let lastEvening = try snapshot(.muis, at: "2026-12-31T21:00:00+08:00")
    #expect(lastEvening.next == .unpublished("The next prayer isn't published yet"))
    #expect(lastEvening.banner == nil)

    let newYear = try snapshot(.muis, at: "2027-01-01T09:00:00+08:00")
    #expect(newYear.rows.isEmpty)
    #expect(newYear.dayUnavailable == "The timetable publishes no times for this day.")
    #expect(newYear.next == nil)
    let banner = try #require(newYear.banner)
    #expect(banner.title == "The timetable doesn't cover this time")
    #expect(banner.gaps.first?.hasPrefix("Friday, January 1, 2027: Fajr, Sunrise") == true)
    #expect(banner.gaps.first?.hasSuffix("(not published)") == true)
  }

  @Test func overnightIsha() throws {
    let evening = try snapshot(.edinburgh, at: "2026-06-21T23:30:00+01:00")
    #expect(
      evening.next
        == .prayer(
          name: "Isha", time: "01:15", countdown: "1:45", spokenCountdown: "1 hour, 45 minutes",
          owningDay: nil))
    #expect(try row(.isha, in: evening).isNextDay)

    let afterMidnight = try snapshot(.edinburgh, at: "2026-06-22T00:30:00+01:00")
    #expect(afterMidnight.gregorianDate.contains("June 22, 2026"))
    #expect(
      afterMidnight.next
        == .prayer(
          name: "Isha", time: "01:15", countdown: "45m", spokenCountdown: "45 minutes",
          owningDay: "From the timetable of Sunday, June 21, 2026"))
    // The rows are 22 June's: its own Isha is the next night's and still upcoming.
    #expect(try row(.fajr, in: afterMidnight).status == .upcoming)
    #expect(try row(.isha, in: afterMidnight).status == .upcoming)
  }

  @Test func countdownsAcrossClockChangesUseElapsedTime() throws {
    // 23:00 GMT on 28 March to Fajr at 05:17 BST: 5 h 17 min elapsed, not the 6:17 on the wall.
    let spring = try snapshot(.edinburgh, at: "2026-03-28T23:00:00Z")
    #expect(
      spring.next
        == .prayer(
          name: "Fajr", time: "05:17", countdown: "5:17", spokenCountdown: "5 hours, 17 minutes",
          owningDay: "From the timetable of Sunday, March 29, 2026"))
    // 23:00 BST on 24 October to Fajr at 05:02 GMT: 7 h 2 min elapsed, not 6:02.
    let autumn = try snapshot(.edinburgh, at: "2026-10-24T23:00:00+01:00")
    #expect(
      autumn.next
        == .prayer(
          name: "Fajr", time: "05:02", countdown: "7:02", spokenCountdown: "7 hours, 2 minutes",
          owningDay: "From the timetable of Sunday, October 25, 2026"))
  }

  @Test func partialRowAndMissingDay() throws {
    let partialNoon = try snapshot(.edinburgh, at: "2026-06-24T12:00:00+01:00")
    #expect(try row(.isha, in: partialNoon).time == nil)
    #expect(try row(.isha, in: partialNoon).missingReason == "not published")
    #expect(try row(.isha, in: partialNoon).missingText == "Not published")
    #expect(partialNoon.banner == nil)

    let partialNight = try snapshot(.edinburgh, at: "2026-06-24T23:00:00+01:00")
    #expect(partialNight.next == nil)
    #expect(try row(.fajr, in: partialNight).status == nil)
    #expect(try row(.fajr, in: partialNight).statusText == "Unknown")
    let gap = try #require(partialNight.banner?.gaps.first)
    #expect(gap == "Wednesday, June 24, 2026: Isha (not published)")

    let missingDay = try snapshot(.edinburgh, at: "2026-06-26T12:00:00+01:00")
    #expect(missingDay.rows.isEmpty)
    #expect(missingDay.banner?.gaps.first?.hasPrefix("Friday, June 26, 2026:") == true)
  }

  @Test func arabicNamesDigitsAndDirection() throws {
    let arabic = BoardStrings(language: "ar")
    #expect(arabic.isRightToLeft)
    let board = try snapshot(.muis, at: "2026-10-14T14:00:00+08:00", strings: arabic)
    #expect(try row(.fajr, in: board).name == "الفجر")
    #expect(try row(.fajr, in: board).time == "٠٥:٣١")
    #expect(try row(.fajr, in: board).statusText == "انقضت")
    #expect(board.title == "سنغافورة")
    #expect(board.hijriDate.contains("١٤٤٨"))
    guard case .prayer(let name, let time, _, _, _) = board.next else {
      Issue.record("no next prayer")
      return
    }
    #expect(name == "العصر")
    #expect(time == "١٦:٠٦")
  }

  @Test func aMissingTimeShowsItsOwnReason() throws {
    // 01:30 doesn't exist in Edinburgh on the spring-forward day, so Fajr can't be resolved.
    let day = CivilDay(year: 2026, month: 3, day: 29)
    func local(_ hour: Int, _ minute: Int) -> TimetableTime {
      .local(WallClockTime(hour: hour, minute: minute))
    }
    let source = TimetableSource(
      rows: [
        TimetableSource.Row(
          day: day,
          times: [
            .fajr: local(1, 30), .sunrise: local(6, 51), .dhuhr: local(13, 19),
            .asr: local(16, 45), .maghrib: local(19, 45), .isha: local(21, 50),
          ])
      ],
      expectedKinds: Set(PrayerKind.allCases))
    let edinburgh = try Board.load(.edinburgh)
    let board = Board(
      id: .edinburgh, schedule: PrayerSchedule(source: source, location: edinburgh.location))
    let noon = BoardSnapshot.make(
      board: board, at: try Date("2026-03-29T12:00:00+01:00", strategy: .iso8601),
      strings: english)
    let fajr = try row(.fajr, in: noon)
    #expect(fajr.time == nil)
    #expect(fajr.missingReason == "the local time is skipped or repeated")
    #expect(fajr.missingText == "The local time is skipped or repeated")
  }

  @Test func anIqamaAfterMidnightIsMarkedOnlyWhenItsPrayerBeginsBefore() throws {
    let lateIsha = try row(.isha, in: try snapshot(.edinburgh, at: "2026-04-30T22:00:00+01:00"))
    #expect(lateIsha.time == "23:48")
    #expect(!lateIsha.isNextDay)
    #expect(lateIsha.iqama == "00:00")
    #expect(lateIsha.iqamaIsNextDay)

    // Both after midnight: the begin time's mark covers the iqama.
    let overnight = try row(.isha, in: try snapshot(.edinburgh, at: "2026-06-21T23:30:00+01:00"))
    #expect(overnight.isNextDay)
    #expect(overnight.iqama == "01:25")
    #expect(!overnight.iqamaIsNextDay)

    let sameDay = try row(.isha, in: try snapshot(.edinburgh, at: "2026-03-29T12:00:00+01:00"))
    #expect(!sameDay.iqamaIsNextDay)
  }

  @Test func launchOptionsAndClock() throws {
    let options = LaunchOptions(arguments: [
      "MosqueBoard", "-board", "edinburgh", "-now", "2026-06-21T23:30:00+01:00", "-frozen",
      "-language", "ar",
    ])
    let start = try Date("2026-06-21T23:30:00+01:00", strategy: .iso8601)
    #expect(
      options == LaunchOptions(board: .edinburgh, now: start, frozen: true, language: "ar"))
    #expect(LaunchOptions(arguments: ["MosqueBoard"]) == LaunchOptions())

    let launch = Date(timeIntervalSince1970: 0)
    let running = BoardClock(start: start, launch: launch)
    #expect(running.now(at: launch.addingTimeInterval(90)) == start.addingTimeInterval(90))
    let frozen = BoardClock(start: start, launch: launch, frozen: true)
    #expect(frozen.now(at: launch.addingTimeInterval(90)) == start)
    #expect(BoardClock(launch: launch).now(at: launch.addingTimeInterval(5)) == launch + 5)

    // `-frozen` without a valid `-now` can't freeze the real clock, so the board keeps
    // redrawing instead of showing the launch instant forever.
    let unparsed = LaunchOptions(arguments: ["MosqueBoard", "-now", "2026-06-22T00:30", "-frozen"])
    #expect(unparsed.now == nil)
    let live = BoardClock(start: unparsed.now, launch: launch, frozen: unparsed.frozen)
    #expect(!live.frozen)
    #expect(live.now(at: launch.addingTimeInterval(60)) == launch + 60)
  }
}
