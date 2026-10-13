import Foundation

/// A calendar date in the proleptic Gregorian calendar, such as 2026-10-16.
///
/// A civil day becomes a span of time only together with a time zone, which for a schedule is
/// always the location's zone, never the device's. Use ``start(in:)`` and ``interval(in:)`` to
/// get its instants, and ``adding(days:)`` to move between days: day arithmetic is calendar
/// arithmetic, never a multiple of 86,400 seconds.
///
/// A `CivilDay` encodes as `"YYYY-MM-DD"`. Parsing checks the shape only, so a day such as
/// 2026-02-30 can exist as a value; ``isValid`` says whether it's a real date, and sources treat
/// an invalid day as invalid data.
nonisolated public struct CivilDay: Codable, Hashable, Comparable, Sendable,
  LosslessStringConvertible
{
  /// The year, from 1 to 9999 for a valid day.
  public let year: Int
  /// The month, from 1 to 12 for a valid day.
  public let month: Int
  /// The day of the month, from 1 to the month's length for a valid day.
  public let day: Int

  /// Creates a day from its components, as given. Check ``isValid`` before relying on it.
  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// Parses `"YYYY-MM-DD"`: a four-digit year and two-digit month and day.
  ///
  /// Returns `nil` for any other shape. The parsed day isn't necessarily valid.
  public init?(_ description: String) {
    let parts = description.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    self.init(year: year, month: month, day: day)
  }

  /// The civil day that contains `date` in `timeZone`.
  public init(containing date: Date, in timeZone: TimeZone) {
    let seconds =
      Int((date.timeIntervalSince1970).rounded(.down))
      + timeZone.secondsFromGMT(for: date)
    let civil = Gregorian.date(daysSinceEpoch: Gregorian.floorDivision(seconds, 86_400))
    self.init(year: civil.year, month: civil.month, day: civil.day)
  }

  /// The day as `"YYYY-MM-DD"`.
  public var description: String {
    "\(InstantText.pad(year, 4))-\(InstantText.pad(month, 2))-\(InstantText.pad(day, 2))"
  }

  /// Whether this is a real Gregorian date between the years 1 and 9999.
  public var isValid: Bool {
    (1...9_999).contains(year) && (1...12).contains(month)
      && (1...Gregorian.daysInMonth(year: year, month: month)).contains(day)
  }

  /// The day of the week, numbered like `Calendar`'s weekday: 1 is Sunday, 6 is Friday and
  /// 7 is Saturday.
  public var weekday: Int {
    // 1970-01-01 was a Thursday (weekday 5).
    Gregorian.floorModulo(daysSinceEpoch + 4, 7) + 1
  }

  /// The day `days` days after this one (or before it, for a negative count).
  public func adding(days: Int) -> CivilDay {
    let civil = Gregorian.date(daysSinceEpoch: daysSinceEpoch + days)
    return CivilDay(year: civil.year, month: civil.month, day: civil.day)
  }

  /// The number of days from this day to `other`; negative when `other` is earlier.
  public func days(to other: CivilDay) -> Int {
    other.daysSinceEpoch - daysSinceEpoch
  }

  /// Orders days chronologically.
  public static func < (lhs: CivilDay, rhs: CivilDay) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  /// Decodes `"YYYY-MM-DD"`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let day = CivilDay(text) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected a day as YYYY-MM-DD, found \"\(text)\".")
    }
    self = day
  }

  /// Encodes `"YYYY-MM-DD"`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }

  var daysSinceEpoch: Int {
    Gregorian.daysSinceEpoch(year: year, month: month, day: day)
  }
}
