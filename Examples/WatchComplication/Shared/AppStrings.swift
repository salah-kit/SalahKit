import Foundation
import SalahCore

/// The example's language: UI strings from the String Catalog, and SalahCore's names, digits
/// and dates in the same locale.
///
/// The companion, the watch app and the complication each compile the same catalog, so each
/// process looks its strings up in its own bundle.
nonisolated struct AppStrings: Sendable {
  /// The languages the String Catalog translates.
  static let languages = ["en", "ar"]

  /// `en` or `ar`.
  let language: String
  /// The locale with the language's own digits (`PrayerLocale.resolved`).
  let locale: Locale
  /// Prayer names in this locale.
  let names: PrayerNames
  /// The `<language>.lproj` folder in the bundle, so strings follow `language` even when it
  /// differs from the system language.
  private let tablePath: String?

  /// Strings in the requested language, or the bundle's preferred one when there's no request
  /// (the complication, which has no launch arguments).
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

  /// A short clock time in `timeZone`, such as "15:27" or "3:27 PM", in the locale's digits.
  func time(_ date: Date, in timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = locale.calendar
    formatter.timeZone = timeZone
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  /// A short date and time in `timeZone`, such as "Oct 14, 15:27".
  func dateTime(_ date: Date, in timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = locale.calendar
    formatter.timeZone = timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  /// A civil day, such as "Fri, Oct 16".
  func day(_ day: CivilDay, in timeZone: TimeZone) -> String {
    day.start(in: timeZone).formatted(
      Date.FormatStyle(locale: locale, calendar: locale.calendar, timeZone: timeZone)
        .weekday(.abbreviated).month(.abbreviated).day())
  }

  /// Why a schedule has no times, in a few words.
  func reason(_ reason: ScheduleGapReason?) -> String {
    switch reason {
    case .noPublishedData: self("No published times")
    case .calculationUnavailable: self("Can't be calculated")
    case .invalidData: self("Invalid location or settings")
    case .unresolvedWallTime: self("Unclear time at a clock change")
    case nil: self("Unknown")
    }
  }
}
