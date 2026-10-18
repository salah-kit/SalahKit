import Foundation

/// Locale helpers for prayer text.
nonisolated public enum PrayerLocale {
  /// Applies SalahKit's numbering system for a locale's language and region (ar → arab, or latn
  /// in ar-AE, ar-DZ, ar-EH, ar-LY, ar-MA and ar-TN; ur/fa → arabext; bn → beng). An identifier
  /// that names a numbering system keeps it.
  ///
  /// Platforms disagree about the default digits of these languages (`ar` gives Latin digits
  /// on macOS and Arabic-Indic digits on some Linux toolchains), so an app that wants the same
  /// digits everywhere passes its locale through this function.
  ///
  /// Arabic follows CLDR's default for the country the identifier names: `ar-MA`, `ar-DZ`,
  /// `ar-TN`, `ar-LY`, `ar-EH` and `ar-AE` get Latin digits (`latn`), and every other Arabic
  /// locale gets Arabic-Indic digits (`arab`), including a bare `ar`, `ar-001` and a region CLDR
  /// has no Arabic locale for, such as `ar-FR`. Other languages come back unchanged, and region
  /// and script are kept: `ar-EG` becomes `ar-EG` with `arab` digits. An explicit numbering
  /// system, such as `ar-MA-u-nu-arab` or `ar@numbers=latn`, wins.
  ///
  /// - Parameter identifier: A locale identifier, such as `"ar"`, `"ar-MA"` or `"ur_PK"`.
  /// - Returns: The locale with SalahKit's numbering system applied where one applies.
  public static func resolved(_ identifier: String) -> Locale {
    let locale = Locale(identifier: identifier)
    guard namesNumberingSystem(identifier) else { return resolved(locale, explicit: false) }
    // An identifier that names its digits comes back rebuilt through `Locale.Components`, in
    // ICU form (`ar_MA@numbers=arab`), on every platform:
    // - Foundation on macOS 27 drops a `-u-nu-` value that matches the language's script when it
    //   parses an identifier: `ar-MA-u-nu-arab` becomes `ar-MA-u-nu`, which formats no digits.
    // - On Linux, `NumberFormatter` crashes on a locale made from a BCP 47 `-u-nu-` identifier
    //   (Swift 6.2 to 6.4), while the ICU form formats.
    // `Locale.Components` keeps the value, though not keys it doesn't model, such as `cf` or a
    // private-use tag; none of those changes prayer text.
    let components = Locale.Components(identifier: identifier)
    guard components.numberingSystem != nil else { return locale }
    return Locale(components: components)
  }

  /// Applies SalahKit's numbering system for a locale's language and region, as
  /// ``resolved(_:)-(String)`` does. A locale that names a numbering system keeps it.
  ///
  /// A locale made with `Locale(identifier:)` from an identifier such as `ar-MA-u-nu-arab` may
  /// already have lost its numbering system (Foundation on macOS 27 drops it). Build such a
  /// locale with `Locale.Components` or an `@numbers=` identifier, or pass the identifier to
  /// ``resolved(_:)-(String)``.
  ///
  /// - Parameter locale: The locale to resolve.
  /// - Returns: The locale with SalahKit's numbering system applied where one applies.
  public static func resolved(_ locale: Locale) -> Locale {
    resolved(locale, explicit: namesNumberingSystem(locale.identifier))
  }

  private static func resolved(_ locale: Locale, explicit: Bool) -> Locale {
    if explicit {
      // Rebuilt in ICU form, as ``resolved(_:)-(String)`` does, so `NumberFormatter` on Linux
      // gets a locale it can format with.
      let components = Locale.Components(locale: locale)
      return components.numberingSystem == nil ? locale : Locale(components: components)
    }
    guard
      let numbering = defaultNumbering(
        language: locale.language.languageCode?.identifier,
        region: locale.language.region?.identifier)
    else { return locale }
    var components = Locale.Components(locale: locale)
    components.numberingSystem = Locale.NumberingSystem(numbering)
    return Locale(components: components)
  }

  /// The numbering system SalahKit applies to a language in a region, or `nil` to leave the
  /// locale unchanged.
  ///
  /// The region is the one the identifier names, not a `-u-rg-` override: CLDR takes a
  /// locale's default digits from its language and region, and the override only changes
  /// region preferences such as currency and the first day of the week.
  static func defaultNumbering(language: String?, region: String?) -> String? {
    switch language {
    case "ar": latinDigitArabicRegions.contains(region ?? "") ? "latn" : "arab"
    case "ur", "fa": "arabext"
    case "bn": "beng"
    default: nil
    }
  }

  /// The regions whose CLDR locale for Arabic defaults to Latin digits: the United Arab
  /// Emirates, Algeria, Western Sahara, Libya, Morocco and Tunisia (CLDR 40 to 48). CLDR's 21
  /// other Arabic country locales default to Arabic-Indic digits. RFC 0001 §4.9 explains why
  /// SalahKit keeps its own table instead of asking Foundation.
  static let latinDigitArabicRegions: Set<String> = ["AE", "DZ", "EH", "LY", "MA", "TN"]

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
