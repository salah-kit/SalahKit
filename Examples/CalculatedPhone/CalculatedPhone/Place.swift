import Foundation
import SalahCore

/// Where the app calculates: a preset, or coordinates given at launch.
///
/// The app reads no location services. A real app would get coordinates from Core Location and
/// a time zone from a geocoder; this one keeps the location an explicit input, as SalahCore does.
nonisolated struct Place: Codable, Hashable, Identifiable, Sendable {
  /// A preset's identifier, or ``customID`` for coordinates given at launch.
  var id: String
  var location: PrayerLocation

  /// The identifier of a place given by coordinates (`-latitude`, `-longitude`, `-timeZone`).
  static let customID = "custom"

  static let makkah = Place(
    id: "makkah", latitude: 21.4225, longitude: 39.8262, zone: "Asia/Riyadh", country: "SA",
    name: "Makkah")
  static let london = Place(
    id: "london", latitude: 51.5074, longitude: -0.1278, zone: "Europe/London", country: "GB",
    name: "London")
  /// Kashgar keeps Beijing time, about two hours ahead of the Sun: Isha falls after midnight in
  /// summer and belongs to the evening before.
  static let kashgar = Place(
    id: "kashgar", latitude: 39.4704, longitude: 75.9898, zone: "Asia/Shanghai", country: "CN",
    name: "Kashgar")
  /// Kazan's clock runs behind the Sun: under the middle-of-the-night rule, a summer Fajr falls
  /// before midnight and belongs to the next day.
  static let kazan = Place(
    id: "kazan", latitude: 55.7963, longitude: 49.1088, zone: "Europe/Moscow", country: "RU",
    name: "Kazan")
  /// North of the Arctic Circle: in midsummer the Sun doesn't set, so Fajr, sunrise, Maghrib
  /// and Isha can't be calculated.
  static let tromso = Place(
    id: "tromso", latitude: 69.6492, longitude: 18.9553, zone: "Europe/Oslo", country: "NO",
    name: "Tromsø")
  /// A latitude beyond the pole, to show how the app reports input SalahTimes rejects.
  static let invalid = Place(
    id: "invalid", latitude: 95, longitude: 0, zone: "UTC", country: nil,
    name: "Invalid coordinates")

  static let presets: [Place] = [makkah, london, kashgar, kazan, tromso, invalid]

  /// The preset with this identifier.
  static func preset(_ id: String) -> Place? {
    presets.first { $0.id == id }
  }

  init(id: String, location: PrayerLocation) {
    self.id = id
    self.location = location
  }

  private init(
    id: String, latitude: Double, longitude: Double, zone: String, country: String?,
    name: String
  ) {
    self.init(
      id: id,
      location: PrayerLocation(
        latitude: latitude, longitude: longitude,
        // Every identifier above is in every tz database; GMT only guards a broken system.
        timeZone: TimeZone(identifier: zone) ?? .gmt, countryCode: country, name: name))
  }
}
