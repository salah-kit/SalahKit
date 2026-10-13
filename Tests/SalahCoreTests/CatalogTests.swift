import Foundation
import Testing

@testable import SalahCore

private let languages: Set<String> = ["en", "ar", "fr", "ur", "id", "tr", "fa", "bn", "ms"]
private let unreviewed: Set<String> = ["ur", "fa", "bn", "tr", "id", "ms"]

/// Every entry, with its English value in Salah's catalog at 4bc00e9.
private let salahEnglish: [PrayerNames.Entry: String] = [
  .name(.fajr): "Fajr", .abbreviation(.fajr): "F",
  .name(.sunrise): "Sunrise", .abbreviation(.sunrise): "S",
  .name(.dhuhr): "Dhuhr", .abbreviation(.dhuhr): "D",
  .name(.asr): "Asr", .abbreviation(.asr): "A",
  .name(.maghrib): "Maghrib", .abbreviation(.maghrib): "M",
  .name(.isha): "Isha", .abbreviation(.isha): "I",
  .jumuah: "Jumuah", .jumuahAbbreviation: "J",
]

@Suite struct CatalogTests {
  @Test func bundledResourceLoadsAndParses() throws {
    let url = try #require(StringCatalog.resourceURL)
    let data = try Data(contentsOf: url)
    let catalog = try JSONDecoder().decode(StringCatalog.self, from: data)
    #expect(catalog.sourceLanguage == "en")
    #expect(StringCatalog.bundled == catalog)
  }

  @Test func fileStaysValidForXcodesEditor() throws {
    let url = try #require(StringCatalog.resourceURL)
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let root = try #require(object as? [String: Any])
    #expect(root["sourceLanguage"] as? String == "en")
    #expect(root["version"] as? String == "1.0")
    let strings = try #require(root["strings"] as? [String: [String: Any]])
    for (key, entry) in strings {
      #expect(entry["extractionState"] as? String == "manual", "\(key)")
      #expect((entry["comment"] as? String)?.isEmpty == false, "\(key)")
    }
  }

  @Test func containsExactlyTheFourteenKeysInNineLanguages() throws {
    let catalog = try #require(StringCatalog.bundled)
    let keys = Set(PrayerNames.Entry.allEntries.map(\.key))
    #expect(keys.count == 14)
    #expect(Set(catalog.strings.keys) == keys)
    for (key, entry) in catalog.strings {
      #expect(Set(entry.localizations.keys) == languages, "\(key)")
      for (language, localization) in entry.localizations {
        let value = try #require(localization.stringUnit?.value, "\(key) \(language)")
        #expect(!value.isEmpty && value != key, "\(key) \(language)")
      }
    }
  }

  @Test func draftedTranslationsNeedReview() throws {
    let catalog = try #require(StringCatalog.bundled)
    for (key, entry) in catalog.strings {
      for (language, localization) in entry.localizations {
        let expected = unreviewed.contains(language) ? "needs_review" : "translated"
        #expect(localization.stringUnit?.state == expected, "\(key) \(language)")
      }
    }
  }

  @Test func englishValuesMatchSalahsAndTheBuiltInFallback() throws {
    let catalog = try #require(StringCatalog.bundled)
    #expect(Set(salahEnglish.keys) == Set(PrayerNames.Entry.allEntries))
    for (entry, value) in salahEnglish {
      #expect(catalog.strings[entry.key]?.localizations["en"]?.stringUnit?.value == value)
      #expect(entry.englishFallback == value)
    }
  }

  @Test func localeCandidatesFromMostToLeastSpecific() {
    #expect(
      StringCatalog.candidates(for: Locale(identifier: "zh-Hant-TW"))
        == ["zh-Hant-TW", "zh-Hant", "zh-TW", "zh"])
    #expect(
      StringCatalog.candidates(for: Locale(identifier: "ar_EG")).suffix(2) == ["ar-EG", "ar"])
    #expect(StringCatalog.candidates(for: Locale(identifier: "fr")).last == "fr")
    #expect(StringCatalog.candidates(for: Locale(identifier: "")).isEmpty)
  }

  @Test func matchingOrderPrefersTheMostSpecificLanguage() {
    func entry(_ values: [String: String]) -> StringCatalog.Entry {
      StringCatalog.Entry(
        localizations: values.mapValues {
          StringCatalog.Localization(
            stringUnit: StringCatalog.StringUnit(state: "translated", value: $0))
        })
    }
    let catalog = StringCatalog(
      sourceLanguage: "en",
      strings: [
        "k": entry([
          "en": "source", "zh": "zh", "zh-Hant": "zh-Hant", "zh-TW": "zh-TW",
          "zh-Hant-HK": "zh-Hant-HK", "pt-BR": "pt-BR",
        ])
      ])
    func value(_ identifier: String) -> String? {
      catalog.value(for: "k", locale: Locale(identifier: identifier))
    }
    #expect(value("zh-Hant-HK") == "zh-Hant-HK")
    #expect(value("zh-Hant-TW") == "zh-Hant")
    #expect(value("zh-Hans-TW") == "zh-TW")
    #expect(value("zh-Hans-CN") == "zh")
    #expect(value("pt-BR") == "pt-BR")
    #expect(value("pt_br") == "pt-BR")
    #expect(value("pt-PT") == "source")
    #expect(value("de") == "source")
    #expect(catalog.value(for: "missing", locale: Locale(identifier: "zh")) == nil)
  }

  @Test func decodesWhatXcodeWritesForNewAndVariedKeys() throws {
    // A key Xcode just added has no `localizations`; a plural uses `variations`, not a
    // `stringUnit`. Neither may fail the catalog, and neither has a value to return.
    let json = #"""
      {
        "sourceLanguage" : "en",
        "strings" : {
          "new.key" : { "extractionState" : "manual" },
          "plural.key" : {
            "localizations" : {
              "en" : { "variations" : { "plural" : { "one" : { "stringUnit" : {
                "state" : "translated", "value" : "%lld day" } } } } }
            }
          },
          "plain.key" : {
            "localizations" : {
              "en" : { "stringUnit" : { "state" : "translated", "value" : "Plain" } }
            }
          }
        },
        "version" : "1.0"
      }
      """#
    let catalog = try JSONDecoder().decode(StringCatalog.self, from: Data(json.utf8))
    #expect(catalog.strings.count == 3)
    #expect(catalog.value(for: "new.key", locale: Locale(identifier: "en")) == nil)
    #expect(catalog.value(for: "plural.key", locale: Locale(identifier: "en")) == nil)
    #expect(catalog.value(for: "plain.key", locale: Locale(identifier: "ar")) == "Plain")
  }
}
