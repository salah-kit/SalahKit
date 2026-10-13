import Foundation
import Testing

@testable import SalahCore

private func digits(_ value: Int, _ locale: Locale) -> String {
  let formatter = NumberFormatter()
  formatter.locale = locale
  formatter.usesGroupingSeparator = false
  return formatter.string(from: NSNumber(value: value)) ?? ""
}

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
  }

  @Test func everyArabicRegionGetsArabicIndicDigits() {
    // RFC 0001 §9 Q2: Maghreb regions, whose CLDR default is Latin, get `arab` until a
    // native-speaker review decides otherwise.
    #expect(PrayerLocale.resolved("ar-MA").numberingSystem.identifier == "arab")
  }

  @Test func keepsAnExplicitNumberingSystem() {
    #expect(PrayerLocale.resolved("ar-MA-u-nu-latn").numberingSystem.identifier == "latn")
    #expect(PrayerLocale.resolved("ar@numbers=latn").numberingSystem.identifier == "latn")
    #expect(PrayerLocale.resolved("fa-u-nu-latn").numberingSystem.identifier == "latn")
    #expect(PrayerLocale.resolved("bn@numbers=latn").numberingSystem.identifier == "latn")
    #expect(digits(12, PrayerLocale.resolved("ar-MA-u-nu-latn")) == "12")
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
    let resolved = PrayerLocale.resolved(Locale(identifier: "ur"))
    #expect(PrayerLocale.resolved(resolved) == resolved)
  }

  @Test func localeOverloadKeepsAnExplicitNumberingSystem() {
    var components = Locale.Components(languageCode: .arabic, languageRegion: .morocco)
    components.numberingSystem = Locale.NumberingSystem("latn")
    let latinMorocco = Locale(components: components)
    #expect(PrayerLocale.resolved(latinMorocco).numberingSystem.identifier == "latn")
    #expect(
      PrayerLocale.resolved(Locale(identifier: "ar@numbers=latn")).numberingSystem.identifier
        == "latn")
  }
}
