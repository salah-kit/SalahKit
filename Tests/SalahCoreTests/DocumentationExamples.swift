import Foundation
import SalahCore
import Testing

/// The code of README.md's quick start and of the article "Using a mosque timetable with iqama
/// and incomplete coverage", compiled and run against the public API only.
///
/// `DocumentationTests` checks that every Swift block in those documents appears here line for
/// line, so an edit to a document that isn't mirrored here fails the tests.
@Suite struct DocumentationExamples {
  /// A few rows of a Singapore timetable for the README's quick start.
  static let singaporeTimetable = """
    {
      "expectedKinds": ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"],
      "rows": [
        {
          "day": "2026-10-16",
          "times": { "fajr": "05:31", "sunrise": "06:49", "dhuhr": "12:52",
                     "asr": "16:01", "maghrib": "18:53", "isha": "20:03" },
          "observances": { "dhuhr": "jumuah" }
        }
      ]
    }
    """

  @Test func readmeQuickStart() throws {
    let timetableJSON = Data(Self.singaporeTimetable.utf8)

    // Published times, as JSON your app downloaded or bundled (see TimetableSource).
    let source = try JSONDecoder().decode(TimetableSource.self, from: timetableJSON)

    guard let zone = TimeZone(identifier: "Asia/Singapore") else { return }
    let location = PrayerLocation(latitude: 1.3521, longitude: 103.8198, timeZone: zone)

    // The mosque's own iqama times, where the timetable publishes none.
    let iqama = IqamaRules(
      rules: [.fajr: .after(minutes: 20), .dhuhr: .after(minutes: 10), .isha: .after(minutes: 10)],
      jumuah: .at(WallClockTime(hour: 13, minute: 15)))

    let schedule = PrayerSchedule(source: source, location: location, iqama: iqama)
    let names = PrayerNames(locale: PrayerLocale.resolved("ar"))
    let now = Date()

    switch schedule.state(at: now, through: now.addingTimeInterval(2 * 86_400)) {
    case .available(let state, _):
      if let next = state.nextPrayer {
        let remaining = PrayerDurationFormat.string(
          next.time.timeIntervalSince(now), locale: names.locale)
        print("\(names.name(of: next)) in \(remaining)")
      } else {
        print("The next prayer isn't published yet.")
      }
    case .unavailable(let coverage, _):
      print("No published times here:", coverage.gaps.map(\.reason))
    }

    let friday = schedule.day(CivilDay(year: 2026, month: 10, day: 16)).day
    #expect(friday?[.dhuhr]?.iqama == (try instant("2026-10-16T13:15:00+08:00")))
    #expect(friday?[.fajr]?.iqama == (try instant("2026-10-16T05:51:00+08:00")))
    #expect(friday?[.dhuhr].map(names.name(of:)) == "الجمعة")
  }

  @Test func mosqueTimetableArticle() throws {
    let timetableJSON = try DocumentationTests.article.jsonBlocks()[0]

    let source = try JSONDecoder().decode(TimetableSource.self, from: timetableJSON)
    guard let zone = TimeZone(identifier: "Europe/London") else { return }
    let location = PrayerLocation(latitude: 55.9533, longitude: -3.1883, timeZone: zone)

    let rules = IqamaRules(
      rules: [
        .dhuhr: .at(WallClockTime(hour: 13, minute: 30)),
        .asr: .after(minutes: 10),
        .maghrib: .after(minutes: 5),
      ],
      jumuah: .at(WallClockTime(hour: 13, minute: 45)))
    let schedule = PrayerSchedule(source: source, location: location, iqama: rules)

    #expect(source.firstDay == CivilDay(year: 2026, month: 10, day: 16))
    #expect(source.lastDay == CivilDay(year: 2026, month: 10, day: 18))

    // Show a day
    let names = PrayerNames(locale: Locale(identifier: "en_GB"))
    let clock = DateFormatter()
    clock.locale = names.locale
    clock.calendar = names.locale.calendar
    clock.timeZone = location.timeZone
    clock.dateStyle = .none
    clock.timeStyle = .short

    let friday = CivilDay(year: 2026, month: 10, day: 16)
    if case .available(let day, let coverage) = schedule.day(friday) {
      for event in day.events {
        let iqama = event.iqama.map { " (iqama \(clock.string(from: $0)))" } ?? ""
        print("\(names.name(of: event)) \(clock.string(from: event.time))\(iqama)")
      }
      print(coverage == .complete)  // true
    }

    let fridayDay = try #require(schedule.day(friday).day)
    #expect(schedule.day(friday).coverage == .complete)
    #expect(fridayDay[.dhuhr]?.observance == .jumuah)
    #expect(fridayDay[.dhuhr].map(names.name(of:)) == "Jumu’ah")
    #expect(fridayDay[.fajr]?.iqama == (try instant("2026-10-16T06:30:00+01:00")))
    #expect(fridayDay[.dhuhr]?.iqama == (try instant("2026-10-16T13:45:00+01:00")))
    #expect(fridayDay[.asr]?.iqama == (try instant("2026-10-16T15:51:00+01:00")))
    #expect(fridayDay[.maghrib]?.iqama == (try instant("2026-10-16T18:21:00+01:00")))
    #expect(fridayDay[.isha]?.iqama == (try instant("2026-10-16T20:15:00+01:00")))
    #expect(fridayDay[.sunrise]?.iqama == nil)
    let saturday = schedule.day(CivilDay(year: 2026, month: 10, day: 17))
    #expect(saturday.coverage == .partial(missing: [.isha: .noPublishedData]))
    #expect(saturday.day?.events.count == 5)
    #expect(saturday.day?[.dhuhr]?.iqama == (try instant("2026-10-17T13:30:00+01:00")))

    // Show what's happening now
    func headline(at now: Date) -> String {
      switch schedule.state(at: now, through: now.addingTimeInterval(2 * 86_400)) {
      case .available(let state, _):
        if let current = state.justStarted {
          return "\(names.name(of: current)) has started"
        }
        if let next = state.nextPrayer {
          let remaining = PrayerDurationFormat.string(
            next.time.timeIntervalSince(now), locale: names.locale)
          return "\(names.name(of: next)) in \(remaining)"
        }
        return "The next prayer isn't published yet"
      case .unavailable:
        return "The timetable doesn't cover this time"
      }
    }

    #expect(headline(at: try instant("2026-10-16T13:20:00+01:00")) == "Jumu’ah has started")
    #expect(headline(at: try instant("2026-10-16T13:50:00+01:00")) == "Asr in 1:51")
    #expect(
      headline(at: try instant("2026-10-17T19:00:00+01:00"))
        == "The timetable doesn't cover this time")
    #expect(
      headline(at: try instant("2026-10-18T21:00:00+01:00"))
        == "The next prayer isn't published yet")
    #expect(
      headline(at: try instant("2026-10-19T00:00:00+01:00"))
        == "The timetable doesn't cover this time")

    let evening = try Date("2026-10-17T19:00:00+01:00", strategy: .iso8601)
    let state = schedule.state(at: evening, through: evening.addingTimeInterval(86_400))
    for gap in state.coverage.gaps {
      print(gap.day, gap.kinds.map(\.rawValue), gap.reason)  // 2026-10-17 ["isha"] noPublishedData
    }
    print(state.changesAt == (try Date("2026-10-18T06:02:00+01:00", strategy: .iso8601)))  // true

    let gap = try #require(state.coverage.gaps.first)
    #expect(state.coverage.gaps.count == 1)
    #expect(gap.day == CivilDay(year: 2026, month: 10, day: 17))
    #expect(gap.kinds == [.isha])
    #expect(gap.reason == .noPublishedData)
    #expect(gap.interval.start == evening)
    #expect(gap.interval.end == (try instant("2026-10-18T06:02:00+01:00")))
    #expect(state.changesAt == (try instant("2026-10-18T06:02:00+01:00")))

    // Plan widget refreshes
    let noon = try Date("2026-10-16T12:00:00+01:00", strategy: .iso8601)
    let plan = try schedule.refreshPlan(from: noon, through: noon.addingTimeInterval(6 * 3_600))
    for entry in plan.entries {
      print(clock.string(from: entry.date), entry.state.prayerState?.justStarted != nil)
    }

    let expectedDates = try [
      "12:00", "12:53", "13:08", "13:45", "15:26", "15:41", "15:51",
    ].map { try instant("2026-10-16T\($0):00+01:00") }
    #expect(plan.dates == expectedDates)
    #expect(plan.validUntil == (try instant("2026-10-16T18:00:00+01:00")))
    #expect(!plan.isTruncated)

    // Times after midnight
    let summer = try JSONDecoder().decode(
      TimetableSource.Row.self, from: try DocumentationTests.article.jsonBlocks()[1])
    #expect(summer.times[.isha] == .local(WallClockTime(hour: 0, minute: 20, dayOffset: 1)))
    let resolution = try JSONDecoder().decode(
      [String: WallTimeResolution].self, from: try DocumentationTests.article.jsonBlocks()[2])
    #expect(
      resolution["wallTimeResolution"]
        == WallTimeResolution(repeated: .earlier, nonexistent: .nextValid))
  }
}

func instant(_ text: String) throws -> Date {
  try Date(text, strategy: .iso8601)
}
