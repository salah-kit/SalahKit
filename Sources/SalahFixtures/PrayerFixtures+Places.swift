import SalahCore

// The tables below are the tables of FixtureData.md, one row per line: the day, the six begin
// times (Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha) and, where the timetable publishes them, the
// five iqama times (Fajr, Dhuhr, Asr, Maghrib, Isha). Edit them together with that file;
// the fixture tests compare the two.

nonisolated extension PrayerFixtures {
  /// Makkah on 2026-10-13: an ordinary, complete timetable with published iqama.
  ///
  /// The times follow the Umm al-Qura method: Fajr at 18.5° below the horizon and Isha 90
  /// minutes after Maghrib. Every row publishes an iqama for each prayer: 25 minutes after Fajr,
  /// 20 after Dhuhr and Asr, 10 after Maghrib and 20 after Isha. The zone is `Asia/Riyadh`
  /// (UTC+3), which has no clock changes.
  public static let makkah = Place(
    id: "makkah",
    location: PrayerLocation(
      latitude: 21.4225, longitude: 39.8262, timeZone: zone("Asia/Riyadh"),
      countryCode: "SA", name: "Makkah"),
    source: timetable([
      row("2026-10-11", "04:59 06:15 12:07 15:29 18:00 19:30", "05:24 12:27 15:49 18:10 19:50"),
      row("2026-10-12", "04:59 06:15 12:07 15:28 17:59 19:29", "05:24 12:27 15:48 18:09 19:49"),
      row("2026-10-13", "04:59 06:16 12:07 15:28 17:58 19:28", "05:24 12:27 15:48 18:08 19:48"),
      row("2026-10-14", "05:00 06:16 12:07 15:27 17:57 19:27", "05:25 12:27 15:47 18:07 19:47"),
      row("2026-10-15", "05:00 06:16 12:06 15:27 17:56 19:26", "05:25 12:26 15:47 18:06 19:46"),
    ]),
    iqama: nil,
    featuredDay: CivilDay(year: 2026, month: 10, day: 13))

  /// London on the summer solstice, 2026-06-21: a late Isha.
  ///
  /// The times follow the Moonsighting Committee method. Maghrib is at 21:25 and Isha at 22:42,
  /// late in the evening but before midnight. The zone is `Europe/London` in British Summer Time
  /// (UTC+1), so the wall-clock times are an hour ahead of UTC. The timetable publishes no iqama.
  public static let londonSummer = Place(
    id: "londonSummer",
    location: PrayerLocation(
      latitude: 51.5072, longitude: -0.1276, timeZone: zone("Europe/London"),
      countryCode: "GB", name: "London"),
    source: timetable([
      row("2026-06-19", "02:44 04:43 13:07 17:25 21:24 22:41"),
      row("2026-06-20", "02:43 04:43 13:07 17:25 21:24 22:42"),
      row("2026-06-21", "02:43 04:43 13:07 17:25 21:25 22:42"),
      row("2026-06-22", "02:43 04:43 13:08 17:25 21:25 22:43"),
      row("2026-06-23", "02:44 04:44 13:08 17:26 21:25 22:42"),
    ]),
    iqama: nil,
    featuredDay: CivilDay(year: 2026, month: 6, day: 21))

  /// Reykjavik on 2026-06-21: events after midnight.
  ///
  /// At 64° N the June sun sets after midnight and never sinks far enough for the 18° and 17°
  /// twilight angles, so the Muslim World League times use the seventh-of-the-night rule.
  /// Maghrib and Isha fall at 00:04 and 00:29 on the next civil day, yet they belong to the row
  /// of the day they follow: the timetable writes them `00:04+1` and `00:29+1`. The Fajr of the
  /// next day, at 02:31, comes two hours after that Isha. The zone is `Atlantic/Reykjavik`
  /// (UTC+0). The timetable publishes no iqama.
  public static let reykjavikJune = Place(
    id: "reykjavikJune",
    location: PrayerLocation(
      latitude: 64.1466, longitude: -21.9426, timeZone: zone("Atlantic/Reykjavik"),
      countryCode: "IS", name: "Reykjavik"),
    source: timetable([
      row("2026-06-19", "02:31 02:55 13:30 18:22 00:03+1 00:28+1"),
      row("2026-06-20", "02:31 02:55 13:30 18:22 00:04+1 00:28+1"),
      row("2026-06-21", "02:31 02:55 13:31 18:23 00:04+1 00:29+1"),
      row("2026-06-22", "02:31 02:55 13:31 18:23 00:04+1 00:29+1"),
      row("2026-06-23", "02:31 02:56 13:31 18:23 00:04+1 00:29+1"),
    ]),
    iqama: nil,
    featuredDay: CivilDay(year: 2026, month: 6, day: 21))

  /// New York on 2026-03-08: the spring-forward day.
  ///
  /// The times follow the ISNA method. At 02:00 the clocks of `America/New_York` jump to 03:00,
  /// from UTC-5 to UTC-4, so the day lasts 23 hours and all its times are in daylight time. The
  /// Isha of the night before (2026-03-07, 19:09) is in standard time. A duration from that
  /// evening to Fajr is an hour shorter than the difference of the two wall-clock times. The
  /// timetable publishes no iqama.
  public static let newYorkDSTChange = Place(
    id: "newYorkDSTChange",
    location: PrayerLocation(
      latitude: 40.7128, longitude: -74.0060, timeZone: zone("America/New_York"),
      countryCode: "US", name: "New York"),
    source: timetable([
      row("2026-03-06", "05:07 06:22 12:08 15:22 17:53 19:08"),
      row("2026-03-07", "05:06 06:20 12:08 15:22 17:54 19:09"),
      row("2026-03-08", "06:04 07:19 13:08 16:23 18:55 20:10"),
      row("2026-03-09", "06:02 07:17 13:07 16:24 18:56 20:11"),
      row("2026-03-10", "06:01 07:16 13:07 16:24 18:57 20:12"),
    ]),
    iqama: nil,
    featuredDay: CivilDay(year: 2026, month: 3, day: 8))

  /// Jakarta on 2026-10-13: published iqama in an equatorial city.
  ///
  /// The times follow the Singapore preset of the calculator that produced them: Fajr at 20°
  /// and Isha at 18° below the horizon. Every row publishes an iqama 10 minutes after each
  /// prayer. The zone is `Asia/Jakarta` (UTC+7). None of its rows is a Friday;
  /// ``PrayerFixtures/friday`` has the same times around one.
  public static let jakarta = Place(
    id: "jakarta",
    location: PrayerLocation(
      latitude: -6.2088, longitude: 106.8456, timeZone: zone("Asia/Jakarta"),
      countryCode: "ID", name: "Jakarta"),
    source: timetable([
      row("2026-10-11", "04:16 05:34 11:41 14:43 17:46 18:56", "04:26 11:51 14:53 17:56 19:06"),
      row("2026-10-12", "04:15 05:33 11:41 14:43 17:46 18:56", "04:25 11:51 14:53 17:56 19:06"),
      row("2026-10-13", "04:15 05:33 11:40 14:44 17:46 18:56", "04:25 11:50 14:54 17:56 19:06"),
      row("2026-10-14", "04:14 05:32 11:40 14:44 17:46 18:56", "04:24 11:50 14:54 17:56 19:06"),
      row("2026-10-15", "04:14 05:32 11:40 14:45 17:46 18:56", "04:24 11:50 14:55 17:56 19:06"),
    ]),
    iqama: nil,
    featuredDay: CivilDay(year: 2026, month: 10, day: 13))

  /// Jakarta around Friday 2026-10-16: a declared Jumu'ah.
  ///
  /// The row of the featured day declares its Dhuhr as Jumu'ah, with a congregation at 12:15
  /// local time instead of the 10 minutes after Dhuhr that the other rows publish. Its other
  /// prayers and the other rows are ordinary. Friday alone never makes Dhuhr a Jumu'ah: the
  /// Fridays of the other fixtures declare nothing.
  public static let friday = Place(
    id: "friday",
    location: PrayerLocation(
      latitude: -6.2088, longitude: 106.8456, timeZone: zone("Asia/Jakarta"),
      countryCode: "ID", name: "Jakarta"),
    source: timetable([
      row("2026-10-14", "04:14 05:32 11:40 14:44 17:46 18:56", "04:24 11:50 14:54 17:56 19:06"),
      row("2026-10-15", "04:14 05:32 11:40 14:45 17:46 18:56", "04:24 11:50 14:55 17:56 19:06"),
      row(
        "2026-10-16", "04:13 05:32 11:40 14:45 17:46 18:56", "04:23 12:15 14:55 17:56 19:06",
        jumuah: true),
      row("2026-10-17", "04:13 05:31 11:40 14:46 17:46 18:56", "04:23 11:50 14:56 17:56 19:06"),
      row("2026-10-18", "04:12 05:31 11:39 14:46 17:46 18:56", "04:22 11:49 14:56 17:56 19:06"),
    ]),
    iqama: nil,
    featuredDay: CivilDay(year: 2026, month: 10, day: 16))

  /// Makkah on 2026-03-01, 12 Ramadan 1447: a Ramadan day.
  ///
  /// Isha is 120 minutes after Maghrib, the Umm al-Qura interval for Ramadan, instead of the 90
  /// minutes of ``PrayerFixtures/makkah``. The rows cover 10 to 14 Ramadan. The first, 2026-02-27,
  /// is a Friday that declares no Jumu'ah. The timetable publishes no iqama.
  public static let ramadan = Place(
    id: "ramadan",
    location: PrayerLocation(
      latitude: 21.4225, longitude: 39.8262, timeZone: zone("Asia/Riyadh"),
      countryCode: "SA", name: "Makkah"),
    source: timetable([
      row("2026-02-27", "05:27 06:43 12:33 15:55 18:24 20:24"),
      row("2026-02-28", "05:26 06:42 12:33 15:55 18:24 20:24"),
      row("2026-03-01", "05:25 06:41 12:33 15:55 18:25 20:25"),
      row("2026-03-02", "05:25 06:41 12:33 15:55 18:25 20:25"),
      row("2026-03-03", "05:24 06:40 12:33 15:55 18:26 20:26"),
    ]),
    iqama: nil,
    featuredDay: CivilDay(year: 2026, month: 3, day: 1))

  /// Singapore around 2026-11-11: incomplete coverage.
  ///
  /// The times follow the Singapore preset of the calculator that produced them, and the
  /// timetable has gaps on purpose:
  /// - 2026-11-10 is a partial row: it publishes everything but Isha.
  /// - 2026-11-11, the featured day, has no row at all.
  /// - 2026-11-13 is the last published day. Nothing follows it.
  ///
  /// A schedule reports each gap with its reason and never fills it from another day. The
  /// timetable publishes no iqama.
  public static let incomplete = Place(
    id: "incomplete",
    location: PrayerLocation(
      latitude: 1.3521, longitude: 103.8198, timeZone: zone("Asia/Singapore"),
      countryCode: "SG", name: "Singapore"),
    source: timetable([
      row("2026-11-09", "05:27 06:47 12:50 16:11 18:51 20:03"),
      row("2026-11-10", "05:27 06:47 12:50 16:11 18:51 -"),
      row("2026-11-12", "05:27 06:47 12:50 16:12 18:51 20:03"),
      row("2026-11-13", "05:27 06:48 12:50 16:12 18:51 20:04"),
    ]),
    iqama: nil,
    featuredDay: CivilDay(year: 2026, month: 11, day: 11))
}
