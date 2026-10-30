import Foundation

/// Hijri dates from Foundation's Islamic calendars, with an optional day offset.
///
/// ```swift
/// let hijri = HijriDateFormat(locale: PrayerLocale.resolved("ar"), timeZone: location.timeZone)
/// hijri.string(from: date)        // "٢٦ ربيع الآخر، ١٤٤٨"
/// hijri.components(of: date)      // year 1448, month 4, day 26
/// ```
///
/// Dates are read in the given time zone, normally the location's, not the device's. A
/// ``init(locale:timeZone:dayOffset:calendar:)`` `dayOffset` moves the date by whole days in
/// the calendar first, which is how apps apply a local moon-sighting correction.
nonisolated public struct HijriDateFormat: Sendable {
  /// A date in the Hijri calendar.
  public struct Components: Hashable, Sendable {
    /// The Hijri year, such as 1448.
    public var year: Int
    /// The month, from 1 (Muharram) to 12 (Dhu al-Hijjah).
    public var month: Int
    /// The day of the month, from 1 to 30.
    public var day: Int

    /// Creates a Hijri date, for example to compare with ``HijriDateFormat/components(of:)``.
    public init(year: Int, month: Int, day: Int) {
      self.year = year
      self.month = month
      self.day = day
    }
  }

  let locale: Locale
  let timeZone: TimeZone
  let dayOffset: Int
  let calendarIdentifier: Calendar.Identifier

  /// Creates a Hijri date format.
  ///
  /// - Parameters:
  ///   - locale: The locale for month names and digits. Pass a locale from
  ///     ``PrayerLocale/resolved(_:)-(String)`` for the same digits on every platform.
  ///   - timeZone: The zone in which a date's day is read; normally the location's.
  ///   - dayOffset: Whole days to add in the calendar before reading the date, such as `-1` or
  ///     `1` for a moon-sighting correction.
  ///   - calendar: The Islamic calendar: Umm al-Qura by default, or another such as
  ///     `.islamicCivil`.
  public init(
    locale: Locale, timeZone: TimeZone, dayOffset: Int = 0,
    calendar: Calendar.Identifier = .islamicUmmAlQura
  ) {
    self.locale = locale
    self.timeZone = timeZone
    self.dayOffset = dayOffset
    self.calendarIdentifier = calendar
  }

  /// Formats the Hijri date of an instant.
  ///
  /// - Parameters:
  ///   - date: The instant.
  ///   - template: A localized date-format template; the default `"dMMMMy"` gives day, month
  ///     name and year in the locale's order, such as "Rabiʻ II 26, 1448".
  /// - Returns: The formatted date.
  public func string(from date: Date, template: String = "dMMMMy") -> String {
    let calendar = makeCalendar()
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = timeZone
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: shifted(date, in: calendar))
  }

  /// The Hijri year, month and day of an instant, after the day offset.
  public func components(of date: Date) -> Components {
    let calendar = makeCalendar()
    let parts = calendar.dateComponents([.year, .month, .day], from: shifted(date, in: calendar))
    return Components(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
  }

  private func makeCalendar() -> Calendar {
    var calendar = Calendar(identifier: calendarIdentifier)
    calendar.timeZone = timeZone
    return calendar
  }

  private func shifted(_ date: Date, in calendar: Calendar) -> Date {
    guard dayOffset != 0 else { return date }
    return calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
  }
}
