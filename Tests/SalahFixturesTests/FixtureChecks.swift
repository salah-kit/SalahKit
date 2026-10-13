import Foundation
import SalahCore
import SalahFixtures
import Testing

// Helpers and expectations shared by the fixture tests. Everything here is `nonisolated`, so the
// tests also compile when the package builds with `-default-isolation MainActor`.

/// An instant from ISO 8601 text with an offset or `Z`.
nonisolated func instant(_ text: String) throws -> Date {
  try Date(text, strategy: .iso8601)
}

/// A civil day from `"YYYY-MM-DD"`.
nonisolated func civilDay(_ text: String) throws -> CivilDay {
  try #require(CivilDay(text))
}

/// The place with this id from `PrayerFixtures.places`.
nonisolated func fixturePlace(_ id: String) throws -> PrayerFixtures.Place {
  try #require(PrayerFixtures.places.first { $0.id == id })
}

/// The moment with this id from `PrayerFixtures.moments`.
nonisolated func fixtureMoment(_ id: String) throws -> PrayerFixtures.Moment {
  try #require(PrayerFixtures.moments.first { $0.id == id })
}

/// A time zone by identifier.
nonisolated func timeZone(_ identifier: String) throws -> TimeZone {
  try #require(TimeZone(identifier: identifier))
}

/// The owning day's events as a published row prints them: `HH:MM`, with `+1` when the event
/// falls on the day after its owner.
nonisolated func wallText(_ time: Date, owner: CivilDay, in zone: TimeZone) -> String {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = zone
  let clock = calendar.dateComponents([.hour, .minute], from: time)
  let day = CivilDay(containing: time, in: zone)
  let suffix = day == owner ? "" : (day == owner.adding(days: 1) ? "+1" : "?")
  return twoDigits(clock.hour ?? -1) + ":" + twoDigits(clock.minute ?? -1) + suffix
}

nonisolated private func twoDigits(_ number: Int) -> String {
  number < 10 ? "0\(number)" : "\(number)"
}

/// An event as the schedule should report it: a prayer's owner, kind, begin time and iqama.
nonisolated func expectedEvent(
  _ owner: String, _ kind: PrayerKind, _ time: String, iqama: String? = nil
) throws -> PrayerEvent {
  PrayerEvent(
    scheduleDay: try civilDay(owner), kind: kind, time: try instant(time),
    iqama: try iqama.map(instant))
}

/// The expected shape of one place: its location and its featured day.
nonisolated struct PlaceShape: Sendable, CustomTestStringConvertible {
  let id: String
  let name: String
  let country: String
  let latitude: Double
  let longitude: Double
  let zone: String
  let featuredDay: String

  var testDescription: String { id }

  static let all: [PlaceShape] = [
    PlaceShape(
      id: "makkah", name: "Makkah", country: "SA", latitude: 21.4225, longitude: 39.8262,
      zone: "Asia/Riyadh", featuredDay: "2026-10-13"),
    PlaceShape(
      id: "londonSummer", name: "London", country: "GB", latitude: 51.5072, longitude: -0.1276,
      zone: "Europe/London", featuredDay: "2026-06-21"),
    PlaceShape(
      id: "reykjavikJune", name: "Reykjavik", country: "IS", latitude: 64.1466,
      longitude: -21.9426, zone: "Atlantic/Reykjavik", featuredDay: "2026-06-21"),
    PlaceShape(
      id: "newYorkDSTChange", name: "New York", country: "US", latitude: 40.7128,
      longitude: -74.0060, zone: "America/New_York", featuredDay: "2026-03-08"),
    PlaceShape(
      id: "jakarta", name: "Jakarta", country: "ID", latitude: -6.2088, longitude: 106.8456,
      zone: "Asia/Jakarta", featuredDay: "2026-10-13"),
    PlaceShape(
      id: "friday", name: "Jakarta", country: "ID", latitude: -6.2088, longitude: 106.8456,
      zone: "Asia/Jakarta", featuredDay: "2026-10-16"),
    PlaceShape(
      id: "ramadan", name: "Makkah", country: "SA", latitude: 21.4225, longitude: 39.8262,
      zone: "Asia/Riyadh", featuredDay: "2026-03-01"),
    PlaceShape(
      id: "incomplete", name: "Singapore", country: "SG", latitude: 1.3521, longitude: 103.8198,
      zone: "Asia/Singapore", featuredDay: "2026-11-11"),
  ]
}

/// The begin times of one published day, as ISO 8601 instants with the zone's offset, in
/// canonical order. A partial day lists the times it publishes.
nonisolated struct SpotCheck: Sendable, CustomTestStringConvertible {
  let place: String
  let day: String
  let times: [String]

  var testDescription: String { "\(place) \(day)" }

  /// The featured day of every place from FixtureData.md, and the days around the holes of
  /// `incomplete`, whose featured day has no row.
  static let all: [SpotCheck] = [
    SpotCheck(
      place: "makkah", day: "2026-10-13",
      times: [
        "2026-10-13T04:59:00+03:00", "2026-10-13T06:16:00+03:00", "2026-10-13T12:07:00+03:00",
        "2026-10-13T15:28:00+03:00", "2026-10-13T17:58:00+03:00", "2026-10-13T19:28:00+03:00",
      ]),
    SpotCheck(
      place: "londonSummer", day: "2026-06-21",
      times: [
        "2026-06-21T02:43:00+01:00", "2026-06-21T04:43:00+01:00", "2026-06-21T13:07:00+01:00",
        "2026-06-21T17:25:00+01:00", "2026-06-21T21:25:00+01:00", "2026-06-21T22:42:00+01:00",
      ]),
    SpotCheck(
      place: "reykjavikJune", day: "2026-06-21",
      times: [
        "2026-06-21T02:31:00+00:00", "2026-06-21T02:55:00+00:00", "2026-06-21T13:31:00+00:00",
        "2026-06-21T18:23:00+00:00", "2026-06-22T00:04:00+00:00", "2026-06-22T00:29:00+00:00",
      ]),
    SpotCheck(
      place: "newYorkDSTChange", day: "2026-03-08",
      times: [
        "2026-03-08T06:04:00-04:00", "2026-03-08T07:19:00-04:00", "2026-03-08T13:08:00-04:00",
        "2026-03-08T16:23:00-04:00", "2026-03-08T18:55:00-04:00", "2026-03-08T20:10:00-04:00",
      ]),
    SpotCheck(
      place: "jakarta", day: "2026-10-13",
      times: [
        "2026-10-13T04:15:00+07:00", "2026-10-13T05:33:00+07:00", "2026-10-13T11:40:00+07:00",
        "2026-10-13T14:44:00+07:00", "2026-10-13T17:46:00+07:00", "2026-10-13T18:56:00+07:00",
      ]),
    SpotCheck(
      place: "friday", day: "2026-10-16",
      times: [
        "2026-10-16T04:13:00+07:00", "2026-10-16T05:32:00+07:00", "2026-10-16T11:40:00+07:00",
        "2026-10-16T14:45:00+07:00", "2026-10-16T17:46:00+07:00", "2026-10-16T18:56:00+07:00",
      ]),
    SpotCheck(
      place: "ramadan", day: "2026-03-01",
      times: [
        "2026-03-01T05:25:00+03:00", "2026-03-01T06:41:00+03:00", "2026-03-01T12:33:00+03:00",
        "2026-03-01T15:55:00+03:00", "2026-03-01T18:25:00+03:00", "2026-03-01T20:25:00+03:00",
      ]),
    SpotCheck(
      place: "incomplete", day: "2026-11-09",
      times: [
        "2026-11-09T05:27:00+08:00", "2026-11-09T06:47:00+08:00", "2026-11-09T12:50:00+08:00",
        "2026-11-09T16:11:00+08:00", "2026-11-09T18:51:00+08:00", "2026-11-09T20:03:00+08:00",
      ]),
    SpotCheck(
      place: "incomplete", day: "2026-11-10",
      times: [
        "2026-11-10T05:27:00+08:00", "2026-11-10T06:47:00+08:00", "2026-11-10T12:50:00+08:00",
        "2026-11-10T16:11:00+08:00", "2026-11-10T18:51:00+08:00",
      ]),
    SpotCheck(
      place: "incomplete", day: "2026-11-12",
      times: [
        "2026-11-12T05:27:00+08:00", "2026-11-12T06:47:00+08:00", "2026-11-12T12:50:00+08:00",
        "2026-11-12T16:12:00+08:00", "2026-11-12T18:51:00+08:00", "2026-11-12T20:03:00+08:00",
      ]),
    SpotCheck(
      place: "incomplete", day: "2026-11-13",
      times: [
        "2026-11-13T05:27:00+08:00", "2026-11-13T06:48:00+08:00", "2026-11-13T12:50:00+08:00",
        "2026-11-13T16:12:00+08:00", "2026-11-13T18:51:00+08:00", "2026-11-13T20:04:00+08:00",
      ]),
  ]
}

/// One moment of FixtureData.md: its place and its instant, written with the place's offset and
/// in UTC.
nonisolated struct MomentCheck: Sendable, CustomTestStringConvertible {
  let id: String
  let place: String
  let local: String
  let utc: String

  var testDescription: String { id }

  static let all: [MomentCheck] = [
    MomentCheck(
      id: "approaching", place: "makkah", local: "2026-10-13T17:48:00+03:00",
      utc: "2026-10-13T14:48:00Z"),
    MomentCheck(
      id: "justStarted", place: "londonSummer", local: "2026-06-21T13:11:00+01:00",
      utc: "2026-06-21T12:11:00Z"),
    MomentCheck(
      id: "afterIsha", place: "jakarta", local: "2026-10-13T19:26:00+07:00",
      utc: "2026-10-13T12:26:00Z"),
    MomentCheck(
      id: "beforeFajr", place: "newYorkDSTChange", local: "2026-03-08T01:30:00-05:00",
      utc: "2026-03-08T06:30:00Z"),
    MomentCheck(
      id: "partialDay", place: "incomplete", local: "2026-11-10T19:21:00+08:00",
      utc: "2026-11-10T11:21:00Z"),
    MomentCheck(
      id: "missingDay", place: "incomplete", local: "2026-11-11T12:00:00+08:00",
      utc: "2026-11-11T04:00:00Z"),
    MomentCheck(
      id: "afterLastPublishedDay", place: "incomplete", local: "2026-11-13T20:34:00+08:00",
      utc: "2026-11-13T12:34:00Z"),
  ]
}
