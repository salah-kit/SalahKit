import Foundation
import SalahCore
import SalahTimes

/// The chosen language: wording from the String Catalog, and SalahCore's names and digits in the
/// same locale, whatever the process's language is.
///
/// The extension runs in the device's language, so it can't rely on the system choosing the
/// catalog's language: it looks wording up in the chosen language's `.lproj` folder of its own
/// bundle and names up with `PrayerNames(locale:)`, the explicit-locale catalog lookup.
nonisolated struct WidgetStrings: Sendable {
  /// The chosen language.
  let language: NamesLanguage
  /// The locale with the language's own digits (`PrayerLocale.resolved`).
  let locale: Locale
  /// Prayer names in this locale.
  let names: PrayerNames
  /// The `<language>.lproj` folder of the bundle that runs this code: the app's or the
  /// extension's.
  private let tablePath: String?

  init(language: NamesLanguage, bundle: Bundle = .main) {
    self.language = language
    locale = PrayerLocale.resolved(language.rawValue)
    names = PrayerNames(locale: locale)
    tablePath = bundle.path(forResource: language.rawValue, ofType: "lproj")
  }

  /// Whether the language is written right to left.
  var isRightToLeft: Bool {
    locale.language.characterDirection == .rightToLeft
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
    case Place.london.id: self("London")
    case Place.tromso.id: self("Tromsø")
    case Place.invalid.id: self("Invalid coordinates")
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
    case .karachi: self("University of Islamic Sciences, Karachi")
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
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = locale.calendar
    formatter.timeZone = timeZone
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  /// A day and time in `timeZone`, for the expired view and the log: "Oct 15, 15:27".
  func dayAndTime(_ date: Date, in timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = locale.calendar
    formatter.timeZone = timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  /// VoiceOver's words for a countdown: "Time remaining: 1 hour, 27 minutes".
  func timeRemaining(_ spoken: String) -> String {
    self("Time remaining: \(spoken)")
  }

  /// VoiceOver's words for the time left from `date` until `end`, for a countdown drawn at a
  /// fixed moment: "Time remaining: 1 hour, 27 minutes".
  func timeRemaining(from date: Date, until end: Date) -> String {
    timeRemaining(
      PrayerDurationFormat.string(end.timeIntervalSince(date), width: .spoken, locale: locale))
  }

  /// The words before and after a live countdown in VoiceOver's label, where the running timer
  /// goes: "Time remaining: " and nothing after it in English.
  var timeRemainingAroundTimer: (before: String, after: String) {
    let marker = "\u{FFFC}"
    let parts = timeRemaining(marker).components(separatedBy: marker)
    return (parts.first ?? "", parts.dropFirst().joined(separator: marker))
  }

  /// VoiceOver's words for a row without a time, which shows "–": "Can't calculate" when the
  /// source can't calculate it, otherwise "Unknown".
  func missingTime(_ reason: ScheduleGapReason?) -> String {
    reason == .calculationUnavailable ? self("Can't calculate") : self("Unknown")
  }

  /// What separates the parts of a label VoiceOver reads as one, such as a row's name and
  /// time: a comma, or the Arabic comma "،" in Arabic.
  var labelSeparator: String {
    switch language {
    case .english: ", "
    case .arabic: "، "
    }
  }

  /// Names joined as the locale joins a list: "Fajr, Sunrise, and Isha".
  func list(_ kinds: [PrayerKind]) -> String {
    kinds.map { names.name(of: $0) }.formatted(.list(type: .and).locale(locale))
  }
}
