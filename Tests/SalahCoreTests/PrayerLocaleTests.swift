import Foundation
import Testing

@testable import SalahCore

private func digits(_ value: Int, _ locale: Locale) -> String {
  let formatter = NumberFormatter()
  formatter.locale = locale
  formatter.usesGroupingSeparator = false
  return formatter.string(from: NSNumber(value: value)) ?? ""
}

/// CLDR's Arabic country locales whose default is Latin digits, CLDR 40 to 48.
private let latinDigitRegions = ["AE", "DZ", "EH", "LY", "MA", "TN"]

/// CLDR's other Arabic country locales, whose default is Arabic-Indic digits, CLDR 40 to 48.
private let arabicIndicDigitRegions = [
  "BH", "DJ", "EG", "ER", "IL", "IQ", "JO", "KM", "KW", "LB", "MR", "OM", "PS", "QA", "SA", "SD",
  "SO", "SS", "SY", "TD", "YE",
]

@Suite struct PrayerLocaleTests {
  @Test func appliesTheNumberingSystemABareIdentifierLoses() {
    #expect(PrayerLocale.resolved("ar").numberingSystem.identifier == "arab")
    #expect(PrayerLocale.resolved("ur").numberingSystem.identifier == "arabext")
    #expect(PrayerLocale.resolved("fa").numberingSystem.identifier == "arabext")
    #expect(PrayerLocale.resolved("bn").numberingSystem.identifier == "beng")
  }

  @Test func formatsWithTheLanguagesDigits() {
    #expect(digits(1_234, PrayerLocale.resolved("ar")) == "١٢٣٤")
    #expect(digits(1_234, PrayerLocale.resolved("ur")) == "۱۲۳۴")
    #expect(digits(1_234, PrayerLocale.resolved("fa")) == "۱۲۳۴")
    #expect(digits(1_234, PrayerLocale.resolved("bn")) == "১২৩৪")
    #expect(digits(1_234, PrayerLocale.resolved("en")) == "1234")
  }

  @Test func keepsRegionAndScript() {
    let egypt = PrayerLocale.resolved("ar-EG")
    #expect(egypt.numberingSystem.identifier == "arab")
    #expect(egypt.region?.identifier == "EG")
    #expect(egypt.language.languageCode?.identifier == "ar")
    let pakistan = PrayerLocale.resolved("ur_PK")
    #expect(pakistan.numberingSystem.identifier == "arabext")
    #expect(pakistan.region?.identifier == "PK")
    let morocco = PrayerLocale.resolved("ar-Arab-MA")
    #expect(morocco.numberingSystem.identifier == "latn")
    #expect(morocco.region?.identifier == "MA")
    #expect(morocco.language.languageCode?.identifier == "ar")
  }

  @Test func arabicFollowsCLDRsRegionalDefault() {
    // RFC 0001 §4.9: the six regions whose CLDR locale defaults to Latin digits get `latn`.
    for region in latinDigitRegions {
      let locale = PrayerLocale.resolved("ar-\(region)")
      #expect(locale.numberingSystem.identifier == "latn", "ar-\(region)")
      #expect(locale.region?.identifier == region, "ar-\(region)")
      #expect(digits(1_234, locale) == "1234", "ar-\(region)")
    }
    for region in arabicIndicDigitRegions {
      let locale = PrayerLocale.resolved("ar_\(region)")
      #expect(locale.numberingSystem.identifier == "arab", "ar_\(region)")
      #expect(digits(1_234, locale) == "١٢٣٤", "ar_\(region)")
    }
    #expect(PrayerLocale.latinDigitArabicRegions == Set(latinDigitRegions))
  }

  @Test func arabicWithoutACLDRRegionalDefaultGetsArabicIndicDigits() {
    // A bare `ar`, `ar-001` and regions with no Arabic locale of their own changed defaults
    // in CLDR 46, so platforms disagree about them; SalahKit gives them `arab`.
    for identifier in ["ar", "ar-001", "ar-FR", "ar-US", "ar-GB", "ar-TR", "ar-Arab"] {
      #expect(
        PrayerLocale.resolved(identifier).numberingSystem.identifier == "arab", "\(identifier)")
    }
  }

  @Test func readsTheRegionWhateverTheIdentifiersSpelling() {
    for identifier in ["ar_MA", "ar-ma", "AR-MA", "ar-Arab-MA", "ar-MA@calendar=islamic"] {
      #expect(
        PrayerLocale.resolved(identifier).numberingSystem.identifier == "latn", "\(identifier)")
    }
  }

  @Test func followsTheLanguagesRegionNotARegionOverride() {
    // CLDR takes default digits from the language and region; `-u-rg-` only changes region
    // preferences such as currency and the first day of the week.
    #expect(PrayerLocale.resolved("ar-SA-u-rg-mazzzz").numberingSystem.identifier == "arab")
    #expect(PrayerLocale.resolved("ar-MA-u-rg-sazzzz").numberingSystem.identifier == "latn")
    #expect(PrayerLocale.resolved("ar-u-rg-mazzzz").numberingSystem.identifier == "arab")
  }

  @Test func keepsAnExplicitNumberingSystem() {
    #expect(PrayerLocale.resolved("ar-MA-u-nu-arab").numberingSystem.identifier == "arab")
    #expect(PrayerLocale.resolved("ar_MA@numbers=arab").numberingSystem.identifier == "arab")
    #expect(PrayerLocale.resolved("ar-EG-u-nu-latn").numberingSystem.identifier == "latn")
    #expect(PrayerLocale.resolved("ar-MA-u-nu-latn").numberingSystem.identifier == "latn")
    #expect(PrayerLocale.resolved("ar@numbers=latn").numberingSystem.identifier == "latn")
    #expect(PrayerLocale.resolved("fa-u-nu-latn").numberingSystem.identifier == "latn")
    #expect(PrayerLocale.resolved("bn@numbers=latn").numberingSystem.identifier == "latn")
    #expect(digits(12, PrayerLocale.resolved("ar-EG-u-nu-latn")) == "12")
    #expect(digits(12, PrayerLocale.resolved("ar-MA-u-nu-arab")) == "١٢")
  }

  @Test func keepsANumberingSystemThatMatchesTheLanguagesScript() {
    // Foundation on macOS 27 parses `ar-MA-u-nu-arab` as `ar-MA-u-nu`, with numbering "yes".
    let cases = [
      ("ar-MA-u-nu-arab", "arab", "١٢"), ("ar-u-ca-islamic-nu-arab", "arab", "١٢"),
      ("bn-u-nu-beng", "beng", "১২"), ("en-u-nu-latn", "latn", "12"),
      ("ar-SA-u-nu-arab-rg-mazzzz", "arab", "١٢"),
    ]
    for (identifier, numbering, twelve) in cases {
      let locale = PrayerLocale.resolved(identifier)
      #expect(locale.numberingSystem.identifier == numbering, "\(identifier)")
      #expect(digits(12, locale) == twelve, "\(identifier)")
    }
    let islamic = PrayerLocale.resolved("ar-u-ca-islamic-nu-arab")
    #expect(islamic.calendar.identifier == .islamic)
    let override = PrayerLocale.resolved("ar-SA-u-nu-arab-rg-mazzzz")
    #expect(override.language.region?.identifier == "SA")
    #expect(override.region?.identifier == "MA")
  }

  @Test func matchesFoundationForEveryArabicCountryLocale() {
    // The table is CLDR's, as of CLDR 40 to 48; this test fails when a platform's CLDR data
    // moves a country's default, which needs an RFC 0001 amendment. Foundation's bare `ar`,
    // `ar-001` and regions without a locale of their own vary by platform and aren't compared.
    let available = Locale.availableIdentifiers.compactMap { identifier -> String? in
      let language = Locale(identifier: identifier).language
      guard language.languageCode?.identifier == "ar",
        let region = language.region?.identifier, region.count == 2
      else { return nil }
      return region
    }
    let regions = Set(latinDigitRegions + arabicIndicDigitRegions + available)
    for region in regions.sorted() {
      let identifier = "ar_\(region)"
      #expect(
        PrayerLocale.resolved(identifier).numberingSystem
          == Locale(identifier: identifier).numberingSystem, "\(identifier)")
    }
  }

  @Test func onlyTheUnicodeExtensionNamesTheDigits() {
    #expect(PrayerLocale.namesNumberingSystem("ar-u-ca-islamic-nu-latn"))
    #expect(PrayerLocale.namesNumberingSystem("ar-t-en-u-nu-latn"))
    #expect(PrayerLocale.namesNumberingSystem("ar-u-nu-latn-x-priv"))
    // Niue's region code isn't the key either.
    #expect(!PrayerLocale.namesNumberingSystem("ar-NU-u-ca-islamic"))
    // A `nu` in a private-use or transformed part isn't the numbering-system key (#54).
    for identifier in ["ar-u-ca-islamic-x-nu-latn", "ar-x-u-nu-latn", "ar-u-ca-islamic-t-nu"] {
      #expect(!PrayerLocale.namesNumberingSystem(identifier), "\(identifier)")
      #expect(digits(1_234, PrayerLocale.resolved(identifier)) == "١٢٣٤", "\(identifier)")
      #expect(
        PrayerLocale.resolved(Locale(identifier: identifier)).numberingSystem.identifier
          == "arab", "\(identifier)")
    }
  }

  @Test func leavesOtherLanguagesUnchanged() {
    for identifier in ["en", "en_US", "fr", "tr", "id", "ms", "de"] {
      #expect(PrayerLocale.resolved(identifier) == Locale(identifier: identifier), "\(identifier)")
    }
  }

  @Test func localeOverloadMatchesTheIdentifierOverload() {
    #expect(PrayerLocale.resolved(Locale(identifier: "ar")).numberingSystem.identifier == "arab")
    #expect(PrayerLocale.resolved(Locale(identifier: "bn-BD")).numberingSystem.identifier == "beng")
    #expect(PrayerLocale.resolved(Locale(identifier: "en")) == Locale(identifier: "en"))
    #expect(PrayerLocale.resolved(Locale(identifier: "ar_TN")) == PrayerLocale.resolved("ar_TN"))
    #expect(PrayerLocale.resolved(Locale(identifier: "ar_EG")) == PrayerLocale.resolved("ar_EG"))
    let morocco = Locale(components: .init(languageCode: .arabic, languageRegion: .morocco))
    #expect(PrayerLocale.resolved(morocco).numberingSystem.identifier == "latn")
    for identifier in ["ur", "ar", "ar-MA", "ar-EG"] {
      let resolved = PrayerLocale.resolved(Locale(identifier: identifier))
      #expect(PrayerLocale.resolved(resolved) == resolved, "\(identifier)")
    }
  }

  @Test func localeOverloadKeepsAnExplicitNumberingSystem() {
    var components = Locale.Components(languageCode: .arabic, languageRegion: .morocco)
    components.numberingSystem = Locale.NumberingSystem("arab")
    let arabicIndicMorocco = Locale(components: components)
    #expect(PrayerLocale.resolved(arabicIndicMorocco).numberingSystem.identifier == "arab")
    components = Locale.Components(languageCode: .arabic, languageRegion: .egypt)
    components.numberingSystem = Locale.NumberingSystem("latn")
    #expect(
      PrayerLocale.resolved(Locale(components: components)).numberingSystem.identifier == "latn")
    #expect(
      PrayerLocale.resolved(Locale(identifier: "ar@numbers=latn")).numberingSystem.identifier
        == "latn")
  }

  /// `NumberFormatter` on Linux crashes on a locale made from a BCP 47 `-u-nu-` identifier, so
  /// the locale overload rebuilds such a locale in ICU form, as the identifier overload does.
  @Test func localeOverloadFormatsALocaleThatNamesItsDigitsInBCP47() {
    #expect(digits(12, PrayerLocale.resolved(Locale(identifier: "ar-EG-u-nu-latn"))) == "12")
    #expect(digits(12, PrayerLocale.resolved(Locale(identifier: "fa-u-nu-latn"))) == "12")
  }

  /// A locale or an identifier that names its digits in ICU form comes back unchanged, with the
  /// keys `Locale.Components` doesn't model, such as `cf`.
  @Test func leavesALocaleInICUFormUnchanged() {
    let identifier = "ar_EG@cf=account;numbers=latn"
    #expect(PrayerLocale.resolved(Locale(identifier: identifier)).identifier == identifier)
    #expect(PrayerLocale.resolved(identifier).identifier == identifier)
    #expect(digits(12, PrayerLocale.resolved(identifier)) == "12")
  }
}
