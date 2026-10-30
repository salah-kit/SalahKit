import Foundation
import Testing

@testable import SalahCore

private let friday = CivilDay(year: 2026, month: 10, day: 16)

private func dhuhr(_ observance: PrayerObservance) -> PrayerEvent {
  PrayerEvent(
    scheduleDay: friday, kind: .dhuhr, time: Date(timeIntervalSince1970: 1_792_144_800),
    observance: observance)
}

private func names(_ identifier: String) -> PrayerNames {
  PrayerNames(locale: Locale(identifier: identifier))
}

@Suite struct PrayerNamesTests {
  @Test func englishNames() {
    let english = names("en")
    #expect(
      PrayerKind.allCases.map(english.name(of:))
        == ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"])
    #expect(PrayerKind.allCases.map(english.abbreviation(of:)) == ["F", "S", "D", "A", "M", "I"])
    #expect(english.string(for: .jumuah) == "Jumu’ah")
    #expect(english.string(for: .jumuahAbbreviation) == "J")
  }

  @Test func explicitLocaleWhateverTheProcessLanguage() {
    // The process runs in English (or whatever the host uses); the names follow the locale.
    #expect(names("ar").name(of: .fajr) == "الفجر")
    #expect(names("ar").name(of: .isha) == "العشاء")
    #expect(names("tr").name(of: .fajr) == "İmsak")
    #expect(names("tr").name(of: .asr) == "İkindi")
    #expect(names("ur").name(of: .dhuhr) == "ظہر")
    #expect(names("fa").name(of: .dhuhr) == "ظهر")
    #expect(names("bn").name(of: .maghrib) == "মাগরিব")
    #expect(names("id").name(of: .isha) == "Isya")
    #expect(names("ms").name(of: .isha) == "Isyak")
  }

  @Test func frenchHasItsOwnValues() {
    #expect(names("fr").name(of: .sunrise) == "Lever du soleil")
    #expect(names("fr").abbreviation(of: .sunrise) == "L")
    #expect(names("fr").string(for: .jumuah) == "Joumouah")
  }

  @Test func regionalAndScriptVariantsMatchTheirLanguage() {
    #expect(names("ar-EG").name(of: .maghrib) == "المغرب")
    #expect(names("ar_SA").name(of: .maghrib) == "المغرب")
    #expect(names("tr-TR").name(of: .maghrib) == "Akşam")
    #expect(names("ur-Arab-PK").name(of: .fajr) == "فجر")
    #expect(names("ar@numbers=latn").name(of: .asr) == "العصر")
    #expect(PrayerNames(locale: PrayerLocale.resolved("ar")).name(of: .asr) == "العصر")
  }

  @Test func unsupportedLanguagesFallBackToEnglish() {
    #expect(names("de").name(of: .fajr) == "Fajr")
    #expect(names("de-DE").abbreviation(of: .isha) == "I")
    #expect(names("zh-Hant-TW").name(of: .sunrise) == "Sunrise")
    #expect(names("").name(of: .dhuhr) == "Dhuhr")
  }

  @Test func jumuahOnlyWhenObservanceDeclaresIt() {
    let english = names("en")
    #expect(english.name(of: dhuhr(.jumuah)) == "Jumu’ah")
    #expect(english.abbreviation(of: dhuhr(.jumuah)) == "J")
    // A Friday Dhuhr without declared Jumu'ah stays Dhuhr.
    #expect(friday.weekday == 6)
    #expect(english.name(of: dhuhr(.ordinary)) == "Dhuhr")
    #expect(english.abbreviation(of: dhuhr(.ordinary)) == "D")
    #expect(names("ar").name(of: dhuhr(.jumuah)) == "الجمعة")
    #expect(names("tr").name(of: dhuhr(.jumuah)) == "Cuma")
    #expect(names("tr").abbreviation(of: dhuhr(.jumuah)) == "Cu")
  }

  @Test func eventNamesFollowTheirKind() {
    let asr = PrayerEvent(scheduleDay: friday, kind: .asr, time: Date(timeIntervalSince1970: 0))
    #expect(names("en").name(of: asr) == "Asr")
    #expect(names("ar").abbreviation(of: asr) == "عص")
  }

  @Test func overridesReplaceSingleEntries() {
    let custom = PrayerNames(
      locale: Locale(identifier: "en"),
      overrides: [.name(.dhuhr): "Zuhr", .jumuah: "Jumu'ah", .abbreviation(.fajr): "Fj"])
    #expect(custom.name(of: .dhuhr) == "Zuhr")
    #expect(custom.name(of: dhuhr(.ordinary)) == "Zuhr")
    #expect(custom.name(of: dhuhr(.jumuah)) == "Jumu'ah")
    #expect(custom.abbreviation(of: .fajr) == "Fj")
    #expect(custom.string(for: .name(.dhuhr)) == "Zuhr")
    // Entries without an override still come from the catalog.
    #expect(custom.name(of: .asr) == "Asr")
    #expect(custom.abbreviation(of: .dhuhr) == "D")
    #expect(custom.abbreviation(of: dhuhr(.jumuah)) == "J")
    #expect(custom.locale == Locale(identifier: "en"))
  }

  @Test func missingCatalogFallsBackToEnglishNotKeys() {
    let arabicWithoutCatalog = PrayerNames(
      locale: Locale(identifier: "ar"), overrides: [.name(.isha): "Ishaa"], catalog: nil)
    #expect(arabicWithoutCatalog.name(of: .fajr) == "Fajr")
    #expect(arabicWithoutCatalog.string(for: .jumuahAbbreviation) == "J")
    #expect(arabicWithoutCatalog.name(of: .isha) == "Ishaa")
  }

  @Test func entriesMapToSalahsKeys() {
    #expect(PrayerNames.Entry.name(.maghrib).key == "prayer.maghrib")
    #expect(PrayerNames.Entry.abbreviation(.sunrise).key == "prayer.sunrise.abbr")
    #expect(PrayerNames.Entry.jumuah.key == "prayer.dhuhr.jumuah")
    #expect(PrayerNames.Entry.jumuahAbbreviation.key == "prayer.dhuhr.jumuah.abbr")
  }
}
