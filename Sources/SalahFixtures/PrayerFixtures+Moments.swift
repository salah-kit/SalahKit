import Foundation

// Each date is an exact instant, written as seconds since 1970 with its ISO 8601 text beside it.
// They are the instants of FixtureData.md's moments table; the fixture tests compare the two.

nonisolated extension PrayerFixtures {
  /// 2026-10-13 at 17:48 in Makkah, ten minutes before Maghrib.
  ///
  /// The next prayer is Maghrib at 17:58, inside the default 15-minute approaching window. The
  /// previous prayer is Asr at 15:28, and its iqama at 15:48 has passed, so nothing counts as
  /// just started.
  public static let approaching = Moment(
    id: "approaching",
    place: makkah,
    // 2026-10-13T17:48:00+03:00
    date: Date(timeIntervalSince1970: 1_791_902_880))

  /// 2026-06-21 at 13:11 in London, four minutes after Dhuhr.
  ///
  /// Dhuhr, at 13:07, has just started. The timetable publishes no iqama, so under the default
  /// policy it counts as just started for 15 minutes. The next prayer, Asr at 17:25, is far away.
  public static let justStarted = Moment(
    id: "justStarted",
    place: londonSummer,
    // 2026-06-21T13:11:00+01:00
    date: Date(timeIntervalSince1970: 1_782_043_860))

  /// 2026-10-13 at 19:26 in Jakarta, 30 minutes after Isha.
  ///
  /// Every prayer of the day has passed, and Isha's iqama at 19:06 has too. The next prayer is the
  /// Fajr of the following day, at 04:14, because the timetable has that day's row.
  public static let afterIsha = Moment(
    id: "afterIsha",
    place: jakarta,
    // 2026-10-13T19:26:00+07:00
    date: Date(timeIntervalSince1970: 1_791_894_360))

  /// 2026-03-08 at 01:30 in New York, before the clocks go forward.
  ///
  /// It is 01:30 EST (UTC-5) and the clocks jump at 02:00. Fajr, at 06:04 EDT (UTC-4), is 3 hours
  /// and 34 minutes away, although the wall clock suggests 4 hours and 34 minutes. The previous
  /// prayer is the Isha of 2026-03-07.
  public static let beforeFajr = Moment(
    id: "beforeFajr",
    place: newYorkDSTChange,
    // 2026-03-08T01:30:00-05:00
    date: Date(timeIntervalSince1970: 1_772_951_400))

  /// 2026-11-10 at 19:21 in Singapore, 30 minutes after Maghrib on a row without Isha.
  ///
  /// The timetable doesn't publish this evening's Isha, so the schedule can't say which prayer
  /// started last or comes next. Its state is unavailable, and its coverage names the gap.
  public static let partialDay = Moment(
    id: "partialDay",
    place: incomplete,
    // 2026-11-10T19:21:00+08:00
    date: Date(timeIntervalSince1970: 1_794_309_660))

  /// 2026-11-11 at 12:00 in Singapore, in the middle of a day without a row.
  ///
  /// The timetable has nothing for the day, so the schedule can't say which prayer started last
  /// or comes next. Its state is unavailable, and its coverage names the missing day.
  public static let missingDay = Moment(
    id: "missingDay",
    place: incomplete,
    // 2026-11-11T12:00:00+08:00
    date: Date(timeIntervalSince1970: 1_794_369_600))

  /// 2026-11-13 at 20:34 in Singapore, 30 minutes after Isha on the last published day.
  ///
  /// The timetable ends here. The state is available, with Isha as the previous and latest
  /// prayer, and no next prayer is known.
  public static let afterLastPublishedDay = Moment(
    id: "afterLastPublishedDay",
    place: incomplete,
    // 2026-11-13T20:34:00+08:00
    date: Date(timeIntervalSince1970: 1_794_573_240))
}
