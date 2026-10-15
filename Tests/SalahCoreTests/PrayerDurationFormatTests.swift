// The first suite is migrated from Salah's
// `GuidanceTests/RelativeDurationFormatterTests.swift` at commit 4bc00e9, ported from XCTest to
// Swift Testing against `PrayerDurationFormat` (`.down` became `.remaining`, `.up` became
// `.elapsed`). Every expected string is kept unchanged. The other suites add Foundation
// formatting cases that are stable across platforms.

import Foundation
import Testing

@testable import SalahCore

/// Builds a locale with an explicit numbering system, as Salah's app and widget do.
private func locale(_ identifier: String, numbering: String? = nil) -> Locale {
  let base = Locale(identifier: identifier)
  guard let numbering else { return base }
  var components = Locale.Components(locale: base)
  components.numberingSystem = Locale.NumberingSystem(numbering)
  return Locale(components: components)
}

private func remaining(_ seconds: TimeInterval, _ locale: Locale) -> String {
  PrayerDurationFormat.string(seconds, direction: .remaining, locale: locale)
}

private func elapsed(_ seconds: TimeInterval, _ locale: Locale) -> String {
  PrayerDurationFormat.string(seconds, direction: .elapsed, locale: locale)
}

private func spoken(_ seconds: TimeInterval, _ locale: Locale) -> String {
  PrayerDurationFormat.string(seconds, width: .spoken, locale: locale)
}

private let english = Locale(identifier: "en")
/// Arabic with Arabic-Indic digits applied explicitly, as Salah builds it.
private let arabic = locale("ar", numbering: "arab")

/// Migrated from Salah's `RelativeDurationFormatterTests` (4bc00e9).
@Suite struct RelativeDurationFormatterMigratedTests {
  @Test func englishTiersAndBoundaries() {
    #expect(remaining(0, english) == "0s")
    #expect(remaining(1, english) == "1s")
    #expect(remaining(59, english) == "59s")
    #expect(remaining(60, english) == "1m")  // 60 s crosses into the minutes tier
    #expect(remaining(61, english) == "1m")  // floors, never rounds up
    #expect(remaining(3_599, english) == "59m")
    #expect(remaining(3_600, english) == "1:00")  // clock tier, minutes zero-padded
    #expect(remaining(3_661, english) == "1:01")
    #expect(remaining(10_140, english) == "2:49")  // 2 h 49 m
  }

  @Test func countUpPrefix() {
    #expect(elapsed(45, english) == "+45s")
    #expect(elapsed(16 * 60, english) == "+16m")
    #expect(elapsed(10_140, english) == "+2:49")
  }

  @Test func arabicDigitsUnitsAndPrefix() {
    #expect(remaining(49 * 60, arabic) == "٤٩د")
    #expect(remaining(10_140, arabic) == "٢:٤٩")
    #expect(remaining(3_600, arabic) == "١:٠٠")
    #expect(elapsed(45, arabic) == "+٤٥ث")
  }

  @Test func negativeIntervalClampsToZero() {
    #expect(remaining(-5, english) == "0s")
  }

  @Test func bidiIsolationWrap() {
    #expect(
      PrayerDurationFormat.string(3_600, direction: .remaining, locale: english, bidiIsolated: true)
        == "\u{2068}1:00\u{2069}")
  }
}

/// 45 s, 720 s and 8,130 s in Salah's nine languages.
@Suite struct DurationCompactLanguageTests {
  private func compact(_ locale: Locale) -> [String] {
    [45, 720, 8_130].map { remaining($0, locale) }
  }

  @Test func latinScriptLanguages() {
    #expect(compact(english) == ["45s", "12m", "2:15"])
    #expect(compact(locale("fr")) == ["45s", "12min", "2:15"])
    // CLDR's short forms, which differ from Salah's hand-written "12dk", "45dtk" and "12mnt".
    #expect(compact(locale("tr")) == ["45sn", "12d", "2:15"])
    #expect(compact(locale("id")) == ["45 dtk", "12m", "2.15"])  // Indonesian time separator
    #expect(compact(locale("ms")) == ["45s", "12m", "2:15"])
  }

  @Test func arabicWithArabicIndicDigits() {
    #expect(compact(arabic) == ["٤٥ث", "١٢د", "٢:١٥"])
  }

  @Test func persianUsesSalahsAbbreviations() {
    // Foundation's narrow units are Latin letters in Persian ("۴۵s"), so the seconds and minutes
    // tiers use Salah's abbreviations after the locale's digits.
    let persian = locale("fa", numbering: "arabext")
    #expect(compact(persian) == ["۴۵ث", "۱۲د", "۲:۱۵"])
    #expect(elapsed(45, persian) == "+۴۵ث")
    #expect(remaining(0, persian) == "۰ث")
    #expect(remaining(3_599, persian) == "۵۹د")
  }

  @Test func urduWithExtendedArabicIndicDigits() {
    #expect(compact(locale("ur", numbering: "arabext")) == ["۴۵ سیکنڈ", "۱۲ منٹ", "۲:۱۵"])
  }

  @Test func bengaliUsesBengaliDigits() {
    // ICU data for Bengali differs between platforms, so only the digits are pinned.
    let bengali = locale("bn", numbering: "beng")
    for text in compact(bengali) {
      #expect(!text.contains { $0.isASCII && $0.isNumber }, "\(text)")
      #expect(text.contains { "০১২৩৪৫৬৭৮৯".contains($0) }, "\(text)")
    }
    #expect(remaining(8_130, bengali) == "২:১৫")
  }

  @Test func bareArabicKeepsArabicUnitsWhateverTheDigits() {
    // A bare "ar" gives Latin digits on macOS and Swift 6.4 Linux but Arabic-Indic digits on
    // Swift 6.2 Linux, so only the unit letters are pinned.
    let bare = Locale(identifier: "ar")
    #expect(remaining(45, bare).hasSuffix("ث"))
    #expect(remaining(720, bare).hasSuffix("د"))
  }
}

/// The tiers at their edges, rounded down.
@Suite struct DurationTierEdgeTests {
  private let inputs: [TimeInterval] = [59, 60, 119, 3_599, 3_600, 3_659, 8_130]

  @Test func englishEdges() {
    #expect(
      inputs.map { remaining($0, english) }
        == ["59s", "1m", "1m", "59m", "1:00", "1:00", "2:15"])
  }

  @Test func arabicEdges() {
    #expect(
      inputs.map { remaining($0, arabic) }
        == ["٥٩ث", "١د", "١د", "٥٩د", "١:٠٠", "١:٠٠", "٢:١٥"])
  }

  @Test func indonesianEdges() {
    #expect(
      inputs.map { remaining($0, locale("id")) }
        == ["59 dtk", "1m", "1m", "59m", "1.00", "1.00", "2.15"])
  }

  @Test func fractionsRoundDown() {
    #expect(remaining(59.999, english) == "59s")
    #expect(remaining(3_599.9, english) == "59m")
    #expect(remaining(0.5, english) == "0s")
    #expect(remaining(-0.5, english) == "0s")
  }

  @Test func nonFiniteInputCountsAsZero() {
    for value in [TimeInterval.nan, .infinity, -.infinity] {
      #expect(remaining(value, english) == "0s")
      #expect(elapsed(value, english) == "+0s")
      #expect(spoken(value, english) == "0 seconds")
    }
  }

  @Test func longDurationsStayInTheClockTier() {
    #expect(remaining(25 * 3_600 + 5 * 60, english) == "25:05")
  }
}

/// Spoken durations for VoiceOver, rounded down to the minute.
@Suite struct DurationSpokenTests {
  @Test func englishRoundsDown() {
    // Foundation's default rounding reads 8,130 s (2 h 15 m 30 s) as "16 minutes".
    #expect(spoken(8_130, english) == "2 hours, 15 minutes")
    #expect(spoken(720, english) == "12 minutes")
    #expect(spoken(45, english) == "45 seconds")
    #expect(spoken(3_600, english) == "1 hour")
    #expect(spoken(3_659, english) == "1 hour")
    #expect(spoken(119, english) == "1 minute")
  }

  @Test func arabicSpoken() {
    #expect(spoken(8_130, arabic) == "ساعتان و١٥ دقيقة")
    #expect(spoken(720, arabic) == "١٢ دقيقة")
  }

  @Test func spokenTextNeverCarriesASign() {
    #expect(
      PrayerDurationFormat.string(720, direction: .elapsed, width: .spoken, locale: english)
        == "12 minutes")
  }

  @Test func spokenCanBeIsolated() {
    #expect(
      PrayerDurationFormat.string(720, width: .spoken, locale: english, bidiIsolated: true)
        == "\u{2068}12 minutes\u{2069}")
  }

  @Test func elapsedIsolationWrapsTheSign() {
    #expect(
      PrayerDurationFormat.string(45, direction: .elapsed, locale: english, bidiIsolated: true)
        == "\u{2068}+45s\u{2069}")
  }
}
