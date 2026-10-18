import Foundation
import SalahCore

/// The app's language: UI strings from the String Catalog, and SalahCore's names, digits and
/// dates in the same locale.
nonisolated struct PhoneStrings: Sendable {
  /// The languages the String Catalog translates.
  static let languages = ["en", "ar"]

  /// `en` or `ar`.
  let language: String
  /// The locale with the language's own digits (`PrayerLocale.resolved`).
  let locale: Locale
  /// Prayer names in this locale.
  let names: PrayerNames
  /// The `<language>.lproj` folder in the app bundle, so strings follow `language` even when
  /// it differs from the system language.
  private let tablePath: String?

  init(language requested: String?, bundle: Bundle = .main) {
    let preferred = requested ?? bundle.preferredLocalizations.first ?? "en"
    let code = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
    language = Self.languages.contains(code) ? code : "en"
    locale = PrayerLocale.resolved(language)
    names = PrayerNames(locale: locale)
    tablePath = bundle.path(forResource: language, ofType: "lproj")
  }

  /// Whether the language is written right to left.
  var isRightToLeft: Bool {
    locale.language.characterDirection == .rightToLeft
  }

  /// A UI string from the String Catalog.
  func callAsFunction(_ value: String.LocalizationValue) -> String {
    let bundle = tablePath.flatMap(Bundle.init(path:)) ?? .main
    return String(localized: value, bundle: bundle, locale: locale)
  }
}

/// Dates, times and numbers in the location's time zone and the app's language.
nonisolated struct PhoneFormat: Sendable {
  let locale: Locale
  let timeZone: TimeZone
  private let calendar: Calendar

  init(strings: PhoneStrings, timeZone: TimeZone) {
    locale = strings.locale
    self.timeZone = timeZone
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = strings.locale
    self.calendar = calendar
  }

  /// A 24-hour clock time with the locale's digits: "05:31", or "05:31:09" for a time with
  /// seconds (rounding `none`).
  func time(_ date: Date) -> String {
    let hasSeconds = Int(date.timeIntervalSinceReferenceDate.rounded(.down)) % 60 != 0
    let format: Date.FormatString =
      hasSeconds
      ? "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)"
      : "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
    return date.formatted(
      Date.VerbatimFormatStyle(
        format: format, locale: locale, timeZone: timeZone, calendar: calendar))
  }

  /// The clock in the header, always without seconds.
  func clock(_ date: Date) -> String {
    date.formatted(
      Date.VerbatimFormatStyle(
        format:
          "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        locale: locale, timeZone: timeZone, calendar: calendar))
  }

  /// "Wednesday, October 14, 2026".
  func longDate(_ date: Date) -> String {
    date.formatted(
      Date.FormatStyle(
        date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone))
  }

  /// A calendar day, formatted from its start in the location's zone.
  func longDate(_ day: CivilDay) -> String {
    longDate(day.start(in: timeZone))
  }

  /// The day's weekday: "Sunday".
  func weekday(_ day: CivilDay) -> String {
    day.start(in: timeZone).formatted(
      Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).weekday(.wide))
  }

  /// A number in the locale's digits: "18.5".
  func number(_ value: Double) -> String {
    value.formatted(.number.locale(locale))
  }

  /// A whole number with its sign: "+5", "−7".
  func signed(_ value: Int) -> String {
    value.formatted(.number.sign(strategy: .always(includingZero: false)).locale(locale))
  }

  /// Minutes in words with the locale's digits and plural forms, for VoiceOver: "90 minutes".
  ///
  /// Some plural forms have no number, such as Arabic's "دقيقة" and "دقيقتان", so a signed
  /// amount uses `CalculationText.spokenSignedMinutes(_:)`, which keeps its direction.
  func spokenMinutes(_ value: Int) -> String {
    Measurement(value: Double(value), unit: UnitDuration.minutes).formatted(
      .measurement(width: .wide, usage: .asProvided, numberFormatStyle: .number.locale(locale))
        .locale(locale))
  }

  /// Items joined as the locale joins a list: "Fajr, Sunrise, and Isha".
  func list(_ items: [String]) -> String {
    items.formatted(.list(type: .and).locale(locale))
  }

  /// Items joined without a conjunction: "Sunrise −7 min, Dhuhr +5 min".
  func units(_ items: [String]) -> String {
    items.formatted(.list(type: .and, width: .narrow).locale(locale))
  }
}
