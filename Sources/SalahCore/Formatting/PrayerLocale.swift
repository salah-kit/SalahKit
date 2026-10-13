import Foundation

/// Locale helpers for prayer text.
nonisolated public enum PrayerLocale {
  /// Re-applies the numbering system a bare identifier loses (ar → arab, ur/fa → arabext,
  /// bn → beng). An identifier that names a numbering system keeps it.
  ///
  /// Platforms disagree about the default digits of these languages (`ar` gives Latin digits
  /// on macOS and Arabic-Indic digits on some Linux toolchains), so an app that wants native
  /// digits everywhere passes its locale through this function. Other languages come back
  /// unchanged, and region and script are kept: `ar-EG` becomes `ar-EG` with `arab` digits.
  /// An explicit numbering system, such as `ar-MA-u-nu-latn` or `ar@numbers=latn`, wins.
  ///
  /// - Parameter identifier: A locale identifier, such as `"ar"` or `"ur_PK"`.
  /// - Returns: The locale with the language's native numbering system where one applies.
  public static func resolved(_ identifier: String) -> Locale {
    resolved(Locale(identifier: identifier), explicit: namesNumberingSystem(identifier))
  }

  /// Re-applies the numbering system a locale built from a bare identifier loses
  /// (ar → arab, ur/fa → arabext, bn → beng). A locale that names a numbering system keeps it.
  ///
  /// - Parameter locale: The locale to resolve.
  /// - Returns: The locale with the language's native numbering system where one applies.
  public static func resolved(_ locale: Locale) -> Locale {
    resolved(locale, explicit: namesNumberingSystem(locale.identifier))
  }

  private static func resolved(_ locale: Locale, explicit: Bool) -> Locale {
    guard !explicit, let numbering = nativeNumbering(locale.language.languageCode?.identifier)
    else { return locale }
    var components = Locale.Components(locale: locale)
    components.numberingSystem = Locale.NumberingSystem(numbering)
    return Locale(components: components)
  }

  /// The numbering system SalahKit applies to a language, or `nil` to leave it unchanged.
  static func nativeNumbering(_ languageCode: String?) -> String? {
    switch languageCode {
    case "ar": "arab"
    case "ur", "fa": "arabext"
    case "bn": "beng"
    default: nil
    }
  }

  /// Whether an identifier names a numbering system, as a BCP 47 `-u-…-nu-…` extension or an
  /// ICU `@numbers=` keyword.
  static func namesNumberingSystem(_ identifier: String) -> Bool {
    let lowered = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
    if lowered.contains("numbers=") {
      return true
    }
    guard let unicodeExtension = lowered.range(of: "-u-") else { return false }
    // Keys in the Unicode extension are two characters; "nu" is the numbering system.
    let subtags = lowered[unicodeExtension.upperBound...].split(separator: "-")
    return subtags.contains("nu")
  }
}
