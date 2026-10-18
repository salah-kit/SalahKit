import Foundation
import SalahCore
import SalahUI
import SalahWidgets
import Testing

@testable import PhoneWidgets

/// What every state of the widget shows, in its own words, in English and Arabic.
@Suite("Widget states and their wording")
struct WidgetDisplayTests {
  /// 2026-10-14 14:00 in Makkah.
  static let afternoon = Date(timeIntervalSince1970: 1_791_975_600)
  static let english = WidgetStrings(language: .english)
  static let arabic = WidgetStrings(language: .arabic)

  static func samples(_ language: NamesLanguage = .english) -> [String: PrayerEntry] {
    Dictionary(
      uniqueKeysWithValues: WidgetStateSample.all(language: language, now: afternoon).map {
        ($0.id, $0.entry)
      })
  }

  static func wording(_ entry: PrayerEntry?, _ strings: WidgetStrings = english) -> WidgetWording? {
    entry.map {
      WidgetWording(
        WidgetDisplay($0.content), strings: strings,
        timeZone: $0.content.context?.place.location.timeZone)
    }
  }

  @Test func theStatesScreenHasEveryState() {
    #expect(
      WidgetStateSample.all(language: .english, now: Self.afternoon).map(\.id) == [
        "setup", "normal", "partial", "unknownNext", "unavailable", "expired",
      ])
  }

  @Test func setupRequired() throws {
    let entry = try #require(Self.samples()["setup"])
    #expect(WidgetDisplay(entry.content) == .setupRequired)
    let wording = try #require(Self.wording(entry))
    #expect(wording.title == "Choose a place")
    #expect(wording.message == "Open PhoneWidgets to choose a place.")
    #expect(Self.wording(entry, Self.arabic)?.title == "اختر مكانًا")
  }

  @Test func normal() throws {
    let entry = try #require(Self.samples()["normal"])
    guard case .times(let times) = WidgetDisplay(entry.content) else {
      Issue.record("normal: \(entry.content)")
      return
    }
    #expect(times.isPartial == false)
    #expect(times.state.nextPrayer?.kind == .asr)
    #expect(times.day?.events.count == 6)
    let wording = try #require(Self.wording(entry))
    #expect(wording.title == nil)
    #expect(wording.message == nil)
    #expect(wording.short == nil)
  }

  @Test func partial() throws {
    let entry = try #require(Self.samples()["partial"])
    guard case .times(let times) = WidgetDisplay(entry.content) else {
      Issue.record("partial: \(entry.content)")
      return
    }
    #expect(times.isPartial)
    #expect(times.nextIsUnknown == false)
    #expect(times.state.nextPrayer?.kind == .asr)
    #expect(times.day?.events.map(\.kind) == [.dhuhr, .asr])
    let wording = try #require(Self.wording(entry))
    #expect(wording.message == "Fajr, Sunrise, Maghrib, and Isha: can't be calculated today.")
    #expect(wording.short == nil)
    let arabic = try #require(Self.wording(Self.samples(.arabic)["partial"], Self.arabic))
    #expect(arabic.message?.hasSuffix(": لا يمكن حسابها اليوم.") == true)
  }

  @Test func unknownNextPrayer() throws {
    let entry = try #require(Self.samples()["unknownNext"])
    guard case .times(let times) = WidgetDisplay(entry.content) else {
      Issue.record("unknownNext: \(entry.content)")
      return
    }
    #expect(times.nextIsUnknown)
    #expect(times.isPartial)
    #expect(times.state.latestPrayer?.kind == .isha)
    #expect(times.missingKinds.isEmpty)
    #expect(times.day?.events.count == 6)
    let wording = try #require(Self.wording(entry))
    #expect(wording.message == "The next prayer isn't known.")
    #expect(wording.short == "Unknown")
    let arabic = try #require(Self.wording(Self.samples(.arabic)["unknownNext"], Self.arabic))
    #expect(arabic.message == "الصلاة التالية غير معروفة.")
  }

  @Test func unavailable() throws {
    let entry = try #require(Self.samples()["unavailable"])
    #expect(WidgetDisplay(entry.content) == .unavailable(.invalidInput))
    let wording = try #require(Self.wording(entry))
    #expect(wording.title == "No prayer times")
    #expect(wording.message == "The place or the settings aren't valid.")
    #expect(wording.short == "Invalid place")
  }

  @Test func cannotCalculateAndNoData() {
    #expect(UnavailableReason([.calculationUnavailable]) == .cannotCalculate)
    #expect(UnavailableReason([.calculationUnavailable, .invalidData]) == .invalidInput)
    #expect(UnavailableReason([.noPublishedData]) == .noData)
    #expect(UnavailableReason([.unresolvedWallTime]) == .noData)
    let strings = Self.english
    #expect(
      WidgetWording(.unavailable(.cannotCalculate), strings: strings, timeZone: nil).message
        == "Prayer times can't be calculated here today.")
    #expect(
      WidgetWording(.unavailable(.noData), strings: strings, timeZone: nil).message
        == "No prayer times are available.")
  }

  @Test func expired() throws {
    let entry = try #require(Self.samples()["expired"])
    // The normal timeline's last entry, 48 hours after the call.
    let end = Self.afternoon.addingTimeInterval(48 * 3_600)
    #expect(entry.date == end)
    #expect(WidgetDisplay(entry.content) == .expired(knownThrough: end))
    let wording = try #require(Self.wording(entry))
    #expect(wording.title == "Times need refreshing")
    let riyadh = Place.makkah.location.timeZone
    #expect(Self.english.dayAndTime(end, in: riyadh).hasPrefix("Oct 16, 2026"))
    #expect(
      wording.message
        == "Known until \(Self.english.dayAndTime(end, in: riyadh)). Open PhoneWidgets to refresh.")
  }

  @Test func theNamesFollowTheChosenLanguage() {
    #expect(Self.english.names.name(of: .fajr) == "Fajr")
    #expect(Self.arabic.names.name(of: .fajr) == "الفجر")
    #expect(Self.arabic.isRightToLeft)
    #expect(Self.arabic("Makkah") == "مكة المكرمة")
    #expect(Self.english("Makkah") == "Makkah")
  }

  @Test("the widget's colors pass SalahUI's ContrastCheck", arguments: ["light", "dark"])
  func palette(_ name: String) {
    let palette = name == "dark" ? WidgetPalette.dark : WidgetPalette.light
    // Body text needs 4.5:1; the symbols of problems are large, 3:1.
    let text = ContrastCheck(minimumContrast: 4.5)
    for color in [palette.ink, palette.secondaryInk, palette.accent] {
      #expect(text.problems(foreground: color, background: palette.surface).isEmpty)
    }
    #expect(
      ContrastCheck().problems(foreground: palette.notice, background: palette.surface).isEmpty)
    // The accent never looks like the system's alert red.
    #expect(
      ContrastCheck().problems(
        foreground: palette.accent, background: palette.surface, reserved: WidgetPalette.reserved
      ).isEmpty)
  }

  // MARK: VoiceOver

  /// A countdown says what it counts: "Time remaining", then the time left.
  @Test func countdownLabelsSayTimeRemaining() {
    let asr = Self.afternoon.addingTimeInterval(87 * 60)
    #expect(
      Self.english.timeRemaining(from: Self.afternoon, until: asr)
        == "Time remaining: 1 hour, 27 minutes")
    let arabic = Self.arabic.timeRemaining(from: Self.afternoon, until: asr)
    #expect(arabic.hasPrefix("الوقت المتبقي: "), "\(arabic)")
    // A live countdown's label puts its timer after the same words.
    #expect(Self.english.timeRemainingAroundTimer.before == "Time remaining: ")
    #expect(Self.english.timeRemainingAroundTimer.after == "")
    #expect(Self.arabic.timeRemainingAroundTimer.before.hasPrefix("الوقت المتبقي: "))
  }

  /// Labels read as one join their parts with the language's comma: "الفجر، ٥:٠٠ ص".
  @Test func labelsUseTheLanguagesComma() {
    #expect(Self.english.labelSeparator == ", ")
    #expect(Self.arabic.labelSeparator == "، ")
  }

  /// A row without a time says why, rather than reading only the prayer's name.
  @Test func rowsWithoutATimeSayWhy() {
    #expect(Self.english.missingTime(.calculationUnavailable) == "Can't calculate")
    #expect(Self.english.missingTime(.noPublishedData) == "Unknown")
    #expect(Self.english.missingTime(nil) == "Unknown")
    #expect(Self.arabic.missingTime(nil) == Self.arabic("Unknown"))
    #expect(Self.arabic.missingTime(nil) != "Unknown")
  }
}
