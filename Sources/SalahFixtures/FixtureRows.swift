import Foundation
import SalahCore

// Helpers that build the fixture timetables from the text of FixtureData.md's tables, so each
// row of Swift reads like the row of the table it comes from.
//
// The text is fixed in this module, so a malformed entry is a programming error. Library code
// can't trap on it, so a malformed time becomes an invalid one (hour -1) and a malformed day an
// invalid day (year 0): the schedule then reports that day as invalid data, and the fixture tests
// fail on it, instead of a time or a row quietly disappearing.

/// A published row.
///
/// - Parameters:
///   - day: The owning day, such as `"2026-10-13"`.
///   - times: The six begin times in canonical order (Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha),
///     separated by spaces. `00:04+1` is after midnight, on the day after the owning day, and `-`
///     is a time the timetable doesn't publish.
///   - iqama: The five published iqama times (Fajr, Dhuhr, Asr, Maghrib, Isha), separated by
///     spaces, with `-` for none. The default publishes no iqama.
///   - jumuah: Whether the row declares its Dhuhr as Jumu'ah.
nonisolated func row(
  _ day: String, _ times: String, _ iqama: String = "", jumuah: Bool = false
) -> TimetableSource.Row {
  let begin: [PrayerKind] = PrayerKind.allCases
  let congregation: [PrayerKind] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
  return TimetableSource.Row(
    day: CivilDay(day) ?? CivilDay(year: 0, month: 0, day: 0),
    times: wallTimes(times, for: begin),
    iqama: wallTimes(iqama, for: congregation),
    observances: jumuah ? [.dhuhr: .jumuah] : [:])
}

/// A timetable that publishes all six kinds on each of its rows.
nonisolated func timetable(_ rows: [TimetableSource.Row]) -> TimetableSource {
  TimetableSource(rows: rows, expectedKinds: Set(PrayerKind.allCases))
}

/// A time zone by identifier. An unknown identifier gives GMT, which the fixture tests catch.
nonisolated func zone(_ identifier: String) -> TimeZone {
  TimeZone(identifier: identifier) ?? .gmt
}

/// The wall times of a space-separated list, matched to `kinds` in order, without the `-` ones.
private nonisolated func wallTimes(
  _ text: String, for kinds: [PrayerKind]
) -> [PrayerKind: TimetableTime] {
  var times: [PrayerKind: TimetableTime] = [:]
  for (kind, entry) in zip(kinds, text.split(separator: " ")) where entry != "-" {
    times[kind] = .local(WallClockTime(String(entry)) ?? WallClockTime(hour: -1, minute: -1))
  }
  return times
}
