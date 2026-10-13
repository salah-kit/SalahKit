import Foundation

/// Where a schedule applies: coordinates for calculated sources, and the time zone that
/// defines civil days for every source.
///
/// The time zone is the location's, not the device's: a mosque in Singapore keeps its days in
/// `Asia/Singapore` even on a phone set to London time. A location encodes its time zone as
/// the identifier string, such as `"Asia/Singapore"`.
nonisolated public struct PrayerLocation: Codable, Hashable, Sendable {
  /// Latitude in degrees, positive north.
  public var latitude: Double
  /// Longitude in degrees, positive east.
  public var longitude: Double
  /// The location's time zone. Civil days and wall times are resolved in it.
  public var timeZone: TimeZone
  /// The ISO 3166-1 alpha-2 country code, if known.
  public var countryCode: String?
  /// A display name, if the app has one.
  public var name: String?

  /// Creates a location.
  public init(
    latitude: Double, longitude: Double, timeZone: TimeZone, countryCode: String? = nil,
    name: String? = nil
  ) {
    self.latitude = latitude
    self.longitude = longitude
    self.timeZone = timeZone
    self.countryCode = countryCode
    self.name = name
  }

  private enum CodingKeys: String, CodingKey {
    case latitude, longitude, timeZone, countryCode, name
  }

  /// Decodes a location whose `timeZone` is an identifier string.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let identifier = try container.decode(String.self, forKey: .timeZone)
    guard let timeZone = TimeZone(identifier: identifier) else {
      throw DecodingError.dataCorruptedError(
        forKey: .timeZone, in: container,
        debugDescription: "Unknown time zone identifier \"\(identifier)\".")
    }
    self.init(
      latitude: try container.decode(Double.self, forKey: .latitude),
      longitude: try container.decode(Double.self, forKey: .longitude),
      timeZone: timeZone,
      countryCode: try container.decodeIfPresent(String.self, forKey: .countryCode),
      name: try container.decodeIfPresent(String.self, forKey: .name))
  }

  /// Encodes the location with its time zone as an identifier string.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(latitude, forKey: .latitude)
    try container.encode(longitude, forKey: .longitude)
    try container.encode(timeZone.identifier, forKey: .timeZone)
    try container.encodeIfPresent(countryCode, forKey: .countryCode)
    try container.encodeIfPresent(name, forKey: .name)
  }
}
