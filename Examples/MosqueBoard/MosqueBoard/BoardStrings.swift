import Foundation
import SalahCore

/// The board's language: UI strings from the String Catalog, and SalahCore's names, digits and
/// dates in the same locale.
nonisolated struct BoardStrings: Sendable {
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
