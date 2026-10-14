import Foundation
import SalahCore
import SalahTimes

/// The chosen language: wording from the String Catalog, and SalahCore's names and digits in the
/// same locale, whatever the process's language is.
///
/// The widget extension runs in the system's language, so it can't rely on the system choosing
/// the catalog's language: it looks wording up in the chosen language's `.lproj` folder of its
/// own bundle, and names up with `PrayerNames(locale:)`, the explicit-locale catalog lookup.
nonisolated struct MenuBarStrings: Sendable {
  /// The chosen language.
  let language: NamesLanguage
  /// The locale with the language's own digits (`PrayerLocale.resolved`).
  let locale: Locale
  /// Prayer names in this locale.
  let names: PrayerNames
  /// The `<language>.lproj` folder of the bundle that runs this code.
  private let tablePath: String?

  init(language: NamesLanguage, bundle: Bundle = .main) {
    self.language = language
    locale = language.locale
    names = PrayerNames(locale: locale)
    tablePath = bundle.path(forResource: language.rawValue, ofType: "lproj")
  }

  /// A string from the String Catalog, in the chosen language.
  func callAsFunction(_ value: String.LocalizationValue) -> String {
    let bundle = tablePath.flatMap(Bundle.init(path:)) ?? .main
    return String(localized: value, bundle: bundle, locale: locale)
  }

  /// The place's name.
  func placeName(_ place: Place) -> String {
    switch place.id {
    case Place.makkah.id: self("Makkah")
    case Place.istanbul.id: self("Istanbul")
    case Place.london.id: self("London")
    case Place.tromso.id: self("Tromsø")
    default: place.location.name ?? place.id
    }
  }

  /// The method's name.
  func methodName(_ method: CalculationMethod) -> String {
    switch method {
    case .muslimWorldLeague: self("Muslim World League")
    case .isna: self("ISNA (North America)")
    case .egyptian: self("Egyptian General Authority of Survey")
    case .ummAlQura: self("Umm al-Qura")
    case .diyanet: self("Diyanet (Turkey)")
    default: method.rawValue
    }
  }

  /// The language's name in itself, as a language picker shows it.
  static func endonym(_ language: NamesLanguage) -> String {
    switch language {
    case .english: "English"
    case .arabic: "العربية"
    }
  }

  /// A short clock time in `timeZone`, the schedule's, with the locale's digits.
  func time(_ date: Date, in timeZone: TimeZone) -> String {
    date.formatted(
      Date.FormatStyle(
        date: .omitted, time: .shortened, locale: locale, calendar: locale.calendar,
        timeZone: timeZone))
  }

  /// A day and time in `timeZone`: "Oct 15, 15:27".
  func dayAndTime(_ date: Date, in timeZone: TimeZone) -> String {
    date.formatted(
      Date.FormatStyle(
        date: .abbreviated, time: .shortened, locale: locale, calendar: locale.calendar,
        timeZone: timeZone))
  }

  /// Compact time left, rounded down: `45s`, `12m`, `2:15`.
  func remaining(_ seconds: TimeInterval) -> String {
    PrayerDurationFormat.string(seconds, locale: locale, bidiIsolated: language.isRightToLeft)
  }

  /// Compact time since, rounded down: `+5m`.
  func elapsed(_ seconds: TimeInterval) -> String {
    PrayerDurationFormat.string(
      seconds, direction: .elapsed, locale: locale, bidiIsolated: language.isRightToLeft)
  }

  /// Spoken time, rounded down: "12 minutes".
  func spoken(_ seconds: TimeInterval) -> String {
    PrayerDurationFormat.string(seconds, width: .spoken, locale: locale)
  }

  /// Why the schedule lacks a time, in a few words.
  func reason(_ reason: ScheduleGapReason) -> String {
    switch reason {
    case .noPublishedData: self("Not published")
    case .calculationUnavailable: self("Can't be calculated here")
    case .invalidData: self("Invalid data")
    case .unresolvedWallTime: self("Clock change")
    }
  }
}
