import Foundation
import SalahCore
import SalahFixtures
import Testing

@testable import SalahUI

/// What the components decide to show, checked without rendering.
@Suite("Display content")
struct DisplayContentTests {
  /// 24-hour times with Latin digits, so expectations read like the fixture tables.
  static let british = Locale(identifier: "en_GB")
  static let names = PrayerNames(locale: Locale(identifier: "en"))

  /// How the platform writes a wall-clock time such as `"04:59"` in ``british``: the same
  /// formatter on that clock time in GMT. ICU data can differ between platforms, so
  /// expectations compare with this instead of fixed text.
  static func clock(_ text: String) -> String {
    let parts = text.split(separator: ":").compactMap { Int($0) }
    let date = Date(timeIntervalSince1970: TimeInterval(parts[0] * 3_600 + parts[1] * 60))
    return ScheduleTimeText.string(date, timeZone: .gmt, locale: british)
  }

  static func rows(_ moment: PrayerFixtures.Moment) throws -> [RowContent] {
    let day = try #require(moment.schedule.day(containing: moment.date).day)
    return RowContent.rows(
      day: day, state: moment.state().prayerState, names: names, locale: british)
  }

  @Test("approaching: passed rows, Maghrib next and approaching with its countdown, Isha upcoming")
  func approachingRows() throws {
    let rows = try Self.rows(PrayerFixtures.approaching)
    #expect(rows.map(\.name) == ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"])
    #expect(
      rows.map(\.time) == ["04:59", "06:16", "12:07", "15:28", "17:58", "19:28"].map(Self.clock))
    #expect(
      rows.map(\.status) == [
        .passed, .passed, .passed, .passed, .next(approaching: true), .upcoming,
      ])
    #expect(rows.map { $0.countdown?.seconds } == [nil, nil, nil, nil, 600, nil])
    #expect(rows.allSatisfy { $0.dayOffset == 0 && $0.dayOffsetText == nil })
  }

  @Test("just started: Dhuhr just started, Asr next with a countdown")
  func justStartedRows() throws {
    let rows = try Self.rows(PrayerFixtures.justStarted)
    #expect(
      rows.map(\.status) == [
        .passed, .passed, .justStarted, .next(approaching: false), .upcoming, .upcoming,
      ])
    #expect(rows.compactMap { $0.countdown?.seconds } == [15_240])
  }

  @Test("an unknown state shows no status and no countdown on any row")
  func unknownState() throws {
    let moment = PrayerFixtures.partialDay
    #expect(moment.state().prayerState == nil)
    let rows = try Self.rows(moment)
    #expect(rows.map(\.name) == ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib"])
    #expect(rows.allSatisfy { $0.status == nil && $0.countdown == nil })
  }

  @Test("after the last published day: rows passed, no next row, no countdown")
  func afterLastPublishedDay() throws {
    let rows = try Self.rows(PrayerFixtures.afterLastPublishedDay)
    #expect(rows.allSatisfy { $0.status == .passed })
    #expect(rows.allSatisfy { $0.countdown == nil })
  }

  @Test("times are in the schedule's zone, not the device's: New York across its clock change")
  func scheduleZone() throws {
    let rows = try Self.rows(PrayerFixtures.beforeFajr)
    #expect(
      rows.map(\.time) == ["06:04", "07:19", "13:08", "16:23", "18:55", "20:10"].map(Self.clock))
    // The same rows read in another zone would differ, so the zone really is the day's.
    let day = try #require(
      PrayerFixtures.beforeFajr.schedule.day(containing: PrayerFixtures.beforeFajr.date).day)
    let fajr = try #require(day[.fajr])
    #expect(
      ScheduleTimeText.string(fajr.time, timeZone: .gmt, locale: Self.british)
        == Self.clock("10:04"))
    #expect(rows.first?.countdown?.seconds == 12_840)
  }

  @Test("Reykjavik's Maghrib and Isha after midnight carry +1")
  func afterMidnight() throws {
    let place = PrayerFixtures.reykjavikJune
    let day = try #require(place.schedule.day(place.featuredDay).day)
    let rows = RowContent.rows(day: day, state: nil, names: Self.names, locale: Self.british)
    #expect(rows.map(\.dayOffset) == [0, 0, 0, 0, 1, 1])
    #expect(rows.map(\.dayOffsetText) == [nil, nil, nil, nil, "+1", "+1"])
    #expect(rows.suffix(2).map(\.time) == ["00:04", "00:29"].map(Self.clock))
  }

  @Test("a Fajr before its owning day starts carries -1")
  func beforeMidnight() throws {
    let zone = TimeZone(identifier: "Europe/Moscow") ?? .gmt
    let location = PrayerLocation(latitude: 55.8, longitude: 49.1, timeZone: zone)
    let schedule = PrayerSchedule(source: EveningFajrSource(), location: location)
    let day = try #require(schedule.day(CivilDay(year: 2026, month: 6, day: 21)).day)
    let rows = RowContent.rows(day: day, state: nil, names: Self.names, locale: Self.british)
    #expect(rows.map(\.dayOffset) == [-1, 0])
    #expect(rows.first?.dayOffsetText == "-1")
    #expect(rows.first?.time == Self.clock("23:45"))
  }

  /// Fajr at 04:11 and Asr at 15:35 in Riyadh, written the way each locale writes a short time.
  /// 24-hour locales keep the hour's leading zero (issue #11): `Date.FormatStyle`'s `.shortened`
  /// time wrote "4:11" in French, Turkish and Indonesian.
  @Test(
    "times keep the locale's own short format",
    arguments: [
      ("fr", "04:11", "15:35"), ("tr", "04:11", "15:35"), ("id", "04.11", "15.35"),
      ("en_GB", "04:11", "15:35"),
    ])
  func shortTimeFormat(identifier: String, morning: String, afternoon: String) throws {
    let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let fajr = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 4, minute: 11)))
    let locale = Locale(identifier: identifier)
    #expect(ScheduleTimeText.string(fajr, timeZone: zone, locale: locale) == morning)
    #expect(
      ScheduleTimeText.string(fajr.addingTimeInterval(41_040), timeZone: zone, locale: locale)
        == afternoon)
  }

  @Test("day offsets use the locale's digits")
  func offsetDigits() {
    let arabic = ScheduleTimeText.dayOffsetText(1, locale: PrayerLocale.resolved("ar"))
    #expect(arabic?.contains("١") == true)
    #expect(arabic?.contains("+") == true)
    #expect(ScheduleTimeText.dayOffsetText(0, locale: Self.british) == nil)
  }

  @Test("a declared Jumu'ah is named Jumu'ah in rows and as the next prayer")
  func jumuah() throws {
    let place = PrayerFixtures.friday
    let day = try #require(place.schedule.day(place.featuredDay).day)
    let rows = RowContent.rows(day: day, state: nil, names: Self.names, locale: Self.british)
    #expect(rows.map(\.name) == ["Fajr", "Sunrise", "Jumu’ah", "Asr", "Maghrib", "Isha"])

    // 11:00 on that Friday, before Jumu'ah at 11:40.
    let morning = place.featuredDay.start(in: place.location.timeZone).addingTimeInterval(
      11 * 3_600)
    let state = try #require(
      place.schedule.state(at: morning, through: morning + 86_400).prayerState)
    let next = NextPrayerContent(
      state: state, names: Self.names, timeZone: place.location.timeZone, locale: Self.british)
    #expect(next.name == "Jumu’ah")
    #expect(next.abbreviation == "J")
    #expect(next.time == Self.clock("11:40"))
    #expect(next.countdown?.seconds == 2_400)
  }

  @Test("next prayer: name, abbreviation, time and countdown at the approaching moment")
  func nextPrayer() throws {
    let moment = PrayerFixtures.approaching
    let state = try #require(moment.state().prayerState)
    let next = NextPrayerContent(
      state: state, names: Self.names, timeZone: moment.place.location.timeZone,
      locale: Self.british)
    #expect(next.name == "Maghrib")
    #expect(next.abbreviation == "M")
    #expect(next.time == Self.clock("17:58"))
    #expect(next.countdown == CountdownContent(from: moment.date, to: moment.date + 600))
    #expect(next.justStarted == nil)
  }

  @Test("next prayer: the prayer that just started is named")
  func nextAfterJustStarted() throws {
    let moment = PrayerFixtures.justStarted
    let state = try #require(moment.state().prayerState)
    let next = NextPrayerContent(
      state: state, names: Self.names, timeZone: moment.place.location.timeZone,
      locale: Self.british)
    #expect(next.justStarted == "Dhuhr")
    #expect(next.name == "Asr")
  }

  @Test("next prayer: nothing is invented when the next prayer is unknown")
  func unknownNextPrayer() throws {
    let moment = PrayerFixtures.afterLastPublishedDay
    let state = try #require(moment.state().prayerState)
    #expect(state.nextPrayer == nil)
    let next = NextPrayerContent(
      state: state, names: Self.names, timeZone: moment.place.location.timeZone,
      locale: Self.british)
    #expect(next.name == nil)
    #expect(next.abbreviation == nil)
    #expect(next.time == nil)
    #expect(next.countdown == nil)
    #expect(next.justStarted == nil)
  }

  @Test("a countdown to a time already passed counts as zero")
  func countdownNeverNegative() {
    let now = PrayerFixtures.approaching.date
    let countdown = CountdownContent(from: now, to: now - 90)
    #expect(countdown.seconds == 0)
    #expect(countdown.end == now)
    #expect(countdown.compactText(locale: Locale(identifier: "en")) == "0s")
  }

  @Test("countdown text: compact for the screen, spoken for VoiceOver, both rounded down")
  func countdownText() {
    let now = PrayerFixtures.approaching.date
    let countdown = CountdownContent(from: now, to: now + 8_130)
    let english = Locale(identifier: "en")
    #expect(countdown.compactText(locale: english) == "2:15")
    #expect(countdown.spokenText(locale: english) == "2 hours, 15 minutes")
  }
}

/// A calculated-style source whose Fajr falls at 23:45 the evening before its owning day, as
/// Kazan's does under the middle-of-the-night rule.
private struct EveningFajrSource: PrayerSource {
  var expectedKinds: Set<PrayerKind> { [.fajr, .sunrise] }
  var maximumLead: Duration { .seconds(12 * 3_600) }

  func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
    let start = day.start(in: location.timeZone)
    return .available(
      PrayerDay(
        day: day, timeZone: location.timeZone,
        events: [
          PrayerEvent(scheduleDay: day, kind: .fajr, time: start - 15 * 60),
          PrayerEvent(scheduleDay: day, kind: .sunrise, time: start + 3 * 3_600 + 40 * 60),
        ]),
      coverage: .complete)
  }
}
