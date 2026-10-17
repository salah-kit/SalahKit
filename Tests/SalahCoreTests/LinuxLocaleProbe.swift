// Diagnostic only: prints how Foundation on this platform parses Arabic locale identifiers.
import Foundation
import Testing

@testable import SalahCore

private func say(_ text: String) {
  FileHandle.standardError.write(Data(("PROBE " + text + "\n").utf8))
}

private let parseCases = [
  "ar-MA-u-nu-arab", "ar-u-nu-arab", "bn-u-nu-beng", "en-u-nu-latn", "ar-u-ca-islamic-nu-arab",
  "ar-SA-u-nu-arab-rg-mazzzz", "ar-EG-u-nu-latn", "ar-MA-u-nu-latn", "fa-u-nu-latn",
  "ur-PK-u-nu-arabext", "ar_MA@numbers=arab", "ar@numbers=latn", "ar-MA", "ar_MA", "ar",
  "ar-001", "ar-FR", "ar-SA-u-rg-mazzzz", "ar-MA-u-rg-sazzzz", "ar-Arab-MA", "ar-ma",
  "ar-MA@calendar=islamic",
]

private let countries = [
  "AE", "DZ", "EH", "LY", "MA", "TN", "BH", "DJ", "EG", "ER", "IL", "IQ", "JO", "KM", "KW", "LB",
  "MR", "OM", "PS", "QA", "SA", "SD", "SO", "SS", "SY", "TD", "YE",
]

@Suite(.serialized) struct LinuxLocaleProbe {
  @Test func probe() {
    for id in parseCases {
      let parsed = Locale(identifier: id)
      let components = Locale.Components(identifier: id)
      let rebuilt = Locale(components: components)
      let resolved = PrayerLocale.resolved(id)
      say(
        "parse \(id) -> id=\(parsed.identifier) nu=\(parsed.numberingSystem.identifier)"
          + " langRegion=\(parsed.language.region?.identifier ?? "-")"
          + " region=\(parsed.region?.identifier ?? "-")"
          + " | components.nu=\(components.numberingSystem?.identifier ?? "nil")"
          + " rebuilt.id=\(rebuilt.identifier) rebuilt.nu=\(rebuilt.numberingSystem.identifier)"
          + " | resolved.id=\(resolved.identifier) resolved.nu=\(resolved.numberingSystem.identifier)")
    }
    let available = Locale.availableIdentifiers.filter { $0.hasPrefix("ar") }.sorted()
    say("available \(available.count): \(available.joined(separator: " "))")
    for region in countries {
      let id = "ar_\(region)"
      say(
        "default \(id) foundation=\(Locale(identifier: id).numberingSystem.identifier)"
          + " salahkit=\(PrayerLocale.resolved(id).numberingSystem.identifier)")
    }
    // Formatting last, one locale at a time, so a crash names the locale that caused it.
    for id in parseCases {
      for (label, locale) in [
        ("rebuilt", Locale(components: Locale.Components(identifier: id))),
        ("resolved", PrayerLocale.resolved(id)), ("parsed", Locale(identifier: id)),
      ] {
        say("style \(label) \(id) ...")
        say("style \(label) \(id) = \((1234).formatted(.number.grouping(.never).locale(locale)))")
      }
    }
    for id in parseCases {
      for (label, locale) in [
        ("rebuilt", Locale(components: Locale.Components(identifier: id))),
        ("resolved", PrayerLocale.resolved(id)), ("parsed", Locale(identifier: id)),
      ] {
        say("formatter \(label) \(id) id=\(locale.identifier) ...")
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        say("formatter \(label) \(id) = \(formatter.string(from: 1234) ?? "nil")")
      }
    }
  }
}
