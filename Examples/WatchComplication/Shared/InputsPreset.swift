import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

/// The inputs the companion offers, one for each situation the watch must handle.
nonisolated enum InputsPreset: String, CaseIterable, Sendable {
  /// Makkah, calculated with Umm al-Qura: a source that never runs out.
  case makkah
  /// A sample mosque's published timetable with three days of rows from today: it runs out
  /// soon.
  case mosque
  /// The same mosque's timetable, whose last row was yesterday: the watch shows that it ended.
  case mosqueEnded

  /// Makkah's coordinates and zone.
  static let makkahLocation = PrayerLocation(
    latitude: 21.4225, longitude: 39.8262, timeZone: zone("Asia/Riyadh"), countryCode: "SA",
    name: "Makkah")

  /// Where the sample mosque is: East London.
  static let mosqueLocation = PrayerLocation(
    latitude: 51.5175, longitude: -0.0653, timeZone: zone("Europe/London"), countryCode: "GB",
    name: "Sample Mosque")

  /// The inputs for this preset, with timetable rows placed around `today`'s civil day in the
  /// mosque's zone.
  func inputs(today now: Date) -> WatchInputs {
    switch self {
    case .makkah:
      return WatchInputs(
        location: Self.makkahLocation,
        source: .calculated(settings: CalculationSettings(method: .ummAlQura)))
    case .mosque, .mosqueEnded:
      let today = CivilDay(containing: now, in: Self.mosqueLocation.timeZone)
      let first = self == .mosque ? today : today.adding(days: -3)
      return WatchInputs(
        location: Self.mosqueLocation,
        source: .timetable(Self.sampleTimetable(from: first, days: 3)))
    }
  }

  /// A three-day timetable for the sample mosque.
  ///
  /// The mosque is made up, so its rows are published as a real one would publish them, in
  /// local wall-clock times, but the times come from a Muslim World League calculation for its
  /// coordinates, rounded to the minute. A day the calculation can't produce is left out, as a
  /// publisher would leave it out.
  static func sampleTimetable(from first: CivilDay, days: Int) -> TimetableSource {
    let location = mosqueLocation
    let calculation = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
    let rows = (0..<days).compactMap { offset -> TimetableSource.Row? in
      let day = first.adding(days: offset)
      guard let prayerDay = calculation.prayerDay(day, at: location).day else { return nil }
      var times: [PrayerKind: TimetableTime] = [:]
      for event in prayerDay.events {
        times[event.kind] = .local(wallTime(of: event.time, on: day, in: location.timeZone))
      }
      return TimetableSource.Row(day: day, times: times)
    }
    return TimetableSource(rows: rows, expectedKinds: Set(PrayerKind.allCases))
  }

  /// The local clock time of `date` in `zone`, relative to the owning day: `"00:15+1"` for a
  /// time after midnight.
  static func wallTime(of date: Date, on day: CivilDay, in zone: TimeZone) -> WallClockTime {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    let offset = day.days(to: CivilDay(containing: date, in: zone))
    return WallClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0, dayOffset: offset)
  }

  private static func zone(_ identifier: String) -> TimeZone {
    TimeZone(identifier: identifier) ?? .gmt
  }
}
