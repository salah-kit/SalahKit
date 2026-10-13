import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

/// Places and helpers the calculation tests share.
nonisolated enum Places {
  static func zone(_ identifier: String) -> TimeZone {
    TimeZone(identifier: identifier) ?? .gmt
  }

  static let makkah = PrayerLocation(
    latitude: 21.4225, longitude: 39.8262, timeZone: zone("Asia/Riyadh"), countryCode: "SA",
    name: "Makkah")
  static let cairo = PrayerLocation(
    latitude: 30.0444, longitude: 31.2357, timeZone: zone("Africa/Cairo"), countryCode: "EG",
    name: "Cairo")
  static let istanbul = PrayerLocation(
    latitude: 41.0082, longitude: 28.9784, timeZone: zone("Europe/Istanbul"), countryCode: "TR",
    name: "Istanbul")
  static let london = PrayerLocation(
    latitude: 51.5074, longitude: -0.1278, timeZone: zone("Europe/London"), countryCode: "GB",
    name: "London")
  /// Moscow time runs behind the Sun here: Fajr at the middle of the night is before midnight.
  static let kazan = PrayerLocation(
    latitude: 55.7963, longitude: 49.1088, timeZone: zone("Europe/Moscow"), countryCode: "RU",
    name: "Kazan")
  /// China Standard Time runs far ahead of the Sun here: Isha after midnight in summer.
  static let kashgar = PrayerLocation(
    latitude: 39.4704, longitude: 75.9898, timeZone: zone("Asia/Shanghai"), countryCode: "CN",
    name: "Kashgar")
  static let oslo = PrayerLocation(
    latitude: 59.9139, longitude: 10.7522, timeZone: zone("Europe/Oslo"), countryCode: "NO",
    name: "Oslo")
  /// On the Arctic Circle: an interval Isha can fall after the next day's Fajr.
  static let rovaniemi = PrayerLocation(
    latitude: 66.5, longitude: 25.7, timeZone: zone("Europe/Helsinki"), countryCode: "FI",
    name: "Rovaniemi")
  /// Polar day in June, polar night in December.
  static let tromso = PrayerLocation(
    latitude: 69.6492, longitude: 18.9553, timeZone: zone("Europe/Oslo"), countryCode: "NO",
    name: "Tromsø")
  static let equator = PrayerLocation(latitude: 0, longitude: 0, timeZone: .gmt)

  static func day(_ text: String) -> CivilDay {
    CivilDay(text) ?? CivilDay(year: 1970, month: 1, day: 1)
  }

  /// The times SalahTimes computes directly, without the adapter.
  static func direct(
    _ day: CivilDay, at location: PrayerLocation, _ parameters: CalculationParameters
  ) throws -> PrayerTimes {
    guard let gregorian = GregorianDay(year: day.year, month: day.month, day: day.day) else {
      throw CalculationError.unsupportedDate
    }
    return try PrayerTimes(
      coordinates: Coordinates(latitude: location.latitude, longitude: location.longitude),
      day: gregorian, timeZone: location.timeZone, parameters: parameters)
  }

  static func event(of kind: PrayerKind) -> PrayerTimes.Event {
    switch kind {
    case .fajr: .fajr
    case .sunrise: .sunrise
    case .dhuhr: .dhuhr
    case .asr: .asr
    case .maghrib: .maghrib
    case .isha: .isha
    }
  }

  /// An instant written with its offset, such as `2026-06-20T23:45:00+03:00`.
  static func instant(_ text: String) -> Date? {
    try? Date(text, strategy: .iso8601)
  }
}
