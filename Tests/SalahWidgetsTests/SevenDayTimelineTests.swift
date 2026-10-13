import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

@testable import SalahWidgets

/// Successive 48-hour timelines over seven days, with a fixed clock (proposal §7.3, "Done
/// means"). Each test runs ``WidgetHost`` and checks, at every five minutes and around every
/// entry and event, that the entry on show says what the schedule says at that instant, that it
/// never shows a schedule state past its timeline's validity, and that it shows the expired
/// entry exactly while a late provider call leaves the timeline exhausted.
@Suite("Seven days of widget timelines")
struct SevenDayTimelineTests {
  static let riyadh = TimeZone(identifier: "Asia/Riyadh") ?? .gmt
  static let makkah = PrayerLocation(
    latitude: 21.4225, longitude: 39.8262, timeZone: riyadh, countryCode: "SA", name: "Makkah")
  /// 2026-10-13 12:00 in Makkah.
  static let start = Date(timeIntervalSince1970: 1_791_882_000)
  static let week: TimeInterval = 7 * 86_400

  static func calculated(
    at location: PrayerLocation = makkah,
    _ settings: CalculationSettings = CalculationSettings(method: .ummAlQura)
  ) -> PrayerSchedule {
    PrayerSchedule(source: CalculationSource(settings), location: location)
  }

  // MARK: Calculated schedules

  @Test("a calculated schedule shows every prayer in turn, with reloads on time")
  func calculatedOnTime() throws {
    let schedule = Self.calculated()
    let host = try WidgetHost(from: Self.start, until: Self.start + Self.week) { date in
      (try PrayerTimelineBuilder(schedule: schedule).timeline(from: date), schedule)
    }

    let shown = check(host, from: Self.start, through: Self.start + Self.week)
    #expect(shown.expired.isEmpty)
    // One call a day: the start, then every reload halfway through a 48-hour timeline.
    #expect(host.calls.count == 7)
    #expect(host.calls.allSatisfy { $0.timeline.isTruncated == false })

    // Every prayer of the week becomes the next prayer, in order, and nothing else does.
    let prayers = schedule.events(from: Self.start, through: Self.start + Self.week + 86_400)
      .events.filter { $0.kind.isPrayer && $0.time > Self.start }.map(\.id)
    let sequence = shown.nextPrayers
    #expect(sequence == Array(prayers.prefix(sequence.count)))
    #expect(sequence.count == 35 || sequence.count == 36)
    #expect(shown.justStarted.count >= 35)
  }

  @Test("a provider call later than the timeline's validity shows the expired entry until it comes")
  func delayedProviderCall() throws {
    let schedule = Self.calculated()
    // The timeline of call 2 is valid for 48 hours and asks for a reload after 24; the next call
    // comes 30 hours after that, 6 hours past the validity.
    let host = try WidgetHost(
      from: Self.start, until: Self.start + Self.week, delays: [2: 30 * 3_600]
    ) {
      date in (try PrayerTimelineBuilder(schedule: schedule).timeline(from: date), schedule)
    }

    try #require(host.calls.count >= 4)
    let late = host.calls[2].timeline.validUntil
    let shown = check(host, from: Self.start, through: Self.start + Self.week)
    #expect(host.calls[3].date == late.addingTimeInterval(6 * 3_600))
    #expect(shown.expired.isEmpty == false)
    #expect(shown.expired.allSatisfy { $0 >= late && $0 < host.calls[3].date })
    #expect(shown.expired.contains(late))
    #expect(shown.expired.contains(host.calls[3].date.addingTimeInterval(-1)))
  }

  @Test("a provider call late by less than the slack never shows the expired entry")
  func delayWithinSlack() throws {
    let schedule = Self.calculated()
    let host = try WidgetHost(
      from: Self.start, until: Self.start + Self.week, delays: [1: 20 * 3_600, 4: 23 * 3_600]
    ) { date in (try PrayerTimelineBuilder(schedule: schedule).timeline(from: date), schedule) }

    #expect(check(host, from: Self.start, through: Self.start + Self.week).expired.isEmpty)
  }

  @Test("static-text steps: truncated timelines that reload before they run out")
  func stepsStrategy() throws {
    let schedule = Self.calculated()
    let builder = PrayerTimelineBuilder(
      schedule: schedule,
      strategy: .steps(fine: .seconds(60), coarse: .seconds(900), window: .seconds(1_800)))
    let host = try WidgetHost(from: Self.start, until: Self.start + Self.week) { date in
      (try builder.timeline(from: date), schedule)
    }

    let shown = check(host, from: Self.start, through: Self.start + Self.week)
    #expect(shown.expired.isEmpty)
    #expect(host.calls.contains { $0.timeline.isTruncated })
    #expect(host.calls.allSatisfy { $0.timeline.entries.count <= 96 })
  }

  @Test("high latitude: Tromsø's partial June days and Kazan's Fajr before midnight")
  func highLatitude() throws {
    let tromso = PrayerLocation(
      latitude: 69.6492, longitude: 18.9553, timeZone: TimeZone(identifier: "Europe/Oslo") ?? .gmt)
    let kazan = PrayerLocation(
      latitude: 55.7963, longitude: 49.1088, timeZone: TimeZone(identifier: "Europe/Moscow") ?? .gmt
    )
    var middle = CalculationSettings(method: .muslimWorldLeague)
    middle.parameters.highLatitudeRule = .middleOfTheNight
    var disabled = CalculationSettings(method: .muslimWorldLeague)
    disabled.parameters.highLatitudeRule = .disabled
    // 2026-06-15 12:00 UTC.
    let june = Date(timeIntervalSince1970: 1_781_524_800)

    for schedule in [Self.calculated(at: tromso, disabled), Self.calculated(at: kazan, middle)] {
      let host = try WidgetHost(from: june, until: june + Self.week) { date in
        (try PrayerTimelineBuilder(schedule: schedule).timeline(from: date), schedule)
      }
      #expect(check(host, from: june, through: june + Self.week).expired.isEmpty)
    }
  }

  // MARK: Published timetables

  /// Ten days of published rows from 2026-10-13, with a partial row on 10-15 (no Isha), no row on
  /// 10-17, and the last row on 10-19.
  static let timetable: TimetableSource = {
    var rows: [TimetableSource.Row] = []
    for offset in 0..<7 {
      let day = CivilDay(year: 2026, month: 10, day: 13 + offset)
      if offset == 4 { continue }
      var times: [PrayerKind: TimetableTime] = [
        .fajr: .local(WallClockTime(hour: 5, minute: offset)),
        .sunrise: .local(WallClockTime(hour: 6, minute: 16)),
        .dhuhr: .local(WallClockTime(hour: 12, minute: 7)),
        .asr: .local(WallClockTime(hour: 15, minute: 28)),
        .maghrib: .local(WallClockTime(hour: 17, minute: 58)),
        .isha: .local(WallClockTime(hour: 19, minute: 28)),
      ]
      if offset == 2 { times[.isha] = nil }
      rows.append(TimetableSource.Row(day: day, times: times))
    }
    return TimetableSource(rows: rows, expectedKinds: Set(PrayerKind.allCases))
  }()

  @Test("a timetable's partial row, missing day and end show as schedule states, not expiry")
  func timetableGapsAndEnd() throws {
    let schedule = PrayerSchedule(source: Self.timetable, location: Self.makkah)
    let host = try WidgetHost(from: Self.start, until: Self.start + Self.week) { date in
      (try PrayerTimelineBuilder(schedule: schedule).timeline(from: date), schedule)
    }

    let shown = check(host, from: Self.start, through: Self.start + Self.week)
    #expect(shown.expired.isEmpty)
    func state(_ day: Int, _ hour: Int, _ minute: Int = 0) -> PrayerTimelineState? {
      let date = CivilDay(year: 2026, month: 10, day: day).start(in: Self.riyadh)
        .addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60))
      return host.displayed(at: date)?.entry.state
    }

    // 10-15 at 18:30, after Maghrib on the row without Isha: nothing can be asserted.
    guard case .schedule(.unavailable(let partial, _)) = state(15, 18, 30) else {
      Issue.record(
        "10-15 18:30 should be unavailable, got \(String(describing: state(15, 18, 30)))")
      return
    }
    #expect(
      partial.gaps.contains {
        $0.day == CivilDay(year: 2026, month: 10, day: 15) && $0.kinds == [.isha]
      })

    // 10-17 at noon, the day without a row.
    guard case .schedule(.unavailable(let missing, _)) = state(17, 12) else {
      Issue.record("10-17 12:00 should be unavailable, got \(String(describing: state(17, 12)))")
      return
    }
    #expect(missing.gaps.allSatisfy { $0.reason == .noPublishedData })

    // 10-16 at 20:00, after Isha on the day before the missing one: Isha is known, the next
    // prayer isn't.
    let beforeMissing = try #require(state(16, 20)?.prayerState)
    #expect(beforeMissing.latestPrayer?.kind == .isha)
    #expect(beforeMissing.nextPrayer == nil)

    // 10-19 at 20:00, after the last published Isha, and 10-20 at 12:00, past the end: a source
    // gap the app must fill, never the timeline-expired entry.
    let afterLast = try #require(state(19, 20)?.prayerState)
    #expect(afterLast.latestPrayer?.kind == .isha)
    #expect(afterLast.nextPrayer == nil)
    guard case .schedule(.unavailable(let ended, _)) = state(20, 12) else {
      Issue.record("10-20 12:00 should be unavailable, got \(String(describing: state(20, 12)))")
      return
    }
    #expect(ended.gaps.allSatisfy { $0.reason == .noPublishedData })
  }

  @Test("no data at first, then the app saves a timetable and asks for a reload")
  func initialMissingData() throws {
    let empty = PrayerSchedule(
      source: TimetableSource(rows: [], expectedKinds: Set(PrayerKind.allCases)),
      location: Self.makkah)
    let published = PrayerSchedule(source: Self.timetable, location: Self.makkah)
    let saved = Self.start.addingTimeInterval(5 * 3_600)
    let host = try WidgetHost(from: Self.start, until: Self.start + 3 * 86_400, appReloads: [saved])
    { date in
      let schedule = date < saved ? empty : published
      return (try PrayerTimelineBuilder(schedule: schedule).timeline(from: date), schedule)
    }

    try #require(host.calls.count >= 2)
    #expect(host.calls.map(\.date).prefix(2) == [Self.start, saved])
    let shown = check(host, from: Self.start, through: Self.start + 3 * 86_400)
    #expect(shown.expired.isEmpty)
    for minutes in stride(from: 0, to: 300, by: 15) {
      let entry = host.displayed(at: Self.start.addingTimeInterval(TimeInterval(minutes * 60)))?
        .entry
      guard case .schedule(.unavailable)? = entry?.state else {
        Issue.record("before the save, \(minutes) min: \(String(describing: entry?.state))")
        continue
      }
    }
    // 17:00 on 10-13: Asr (15:28) has passed, Maghrib (17:58) is next.
    #expect(host.displayed(at: saved)?.entry.state.prayerState?.latestPrayer?.kind == .asr)
    #expect(host.displayed(at: saved)?.entry.state.prayerState?.nextPrayer?.kind == .maghrib)
  }

  // MARK: Checking what a host shows

  /// What a run showed, for the tests' own assertions.
  struct Shown {
    /// The instants sampled while the expired entry was on show.
    var expired: [Date] = []
    /// The next prayers on show, in order, without repeats.
    var nextPrayers: [String] = []
    /// The prayers shown as just started, in order, without repeats.
    var justStarted: [String] = []
  }

  /// Checks the host at every five minutes from `start` through `end`, and one second either side
  /// of every entry and event, and returns what it showed.
  func check(_ host: WidgetHost, from start: Date, through end: Date) -> Shown {
    var samples = Set(stride(from: start, through: end, by: 300))
    for call in host.calls {
      for entry in call.timeline.entries {
        samples.formUnion([
          entry.date, entry.date.addingTimeInterval(-1), entry.date.addingTimeInterval(1),
        ])
      }
      for event in call.schedule.events(from: start, through: end).events {
        samples.formUnion([
          event.time.addingTimeInterval(-1), event.time, event.time.addingTimeInterval(1),
        ])
      }
    }

    var shown = Shown()
    for date in samples.sorted() where date >= start && date <= end {
      guard let (call, entry) = host.displayed(at: date) else {
        Issue.record("nothing shown at \(date)")
        continue
      }
      let zone = call.schedule.location.timeZone
      switch entry.state {
      case .schedule(let state):
        if date >= call.timeline.validUntil {
          Issue.record(
            "a schedule state shown at \(date), after the validity \(call.timeline.validUntil)")
        }
        let expected = call.schedule.state(
          at: date, through: call.timeline.lookahead(in: zone), policy: StatePolicy())
        if ShownState(state) != ShownState(expected) {
          Issue.record("at \(date): shown \(ShownState(state)), expected \(ShownState(expected))")
        }
        if let next = state.prayerState?.nextPrayer?.id, shown.nextPrayers.last != next {
          shown.nextPrayers.append(next)
        }
        if let started = state.prayerState?.justStarted?.id, shown.justStarted.last != started {
          shown.justStarted.append(started)
        }
      case .expired(let knownThrough):
        if knownThrough != call.timeline.validUntil || date < knownThrough {
          Issue.record("expired through \(knownThrough) shown at \(date)")
        }
        shown.expired.append(date)
      }
    }
    return shown
  }
}
