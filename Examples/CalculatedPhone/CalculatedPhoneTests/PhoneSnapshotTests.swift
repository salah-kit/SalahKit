import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

@testable import CalculatedPhone

/// The screen's logic at fixed instants, below the UI.
///
/// Expected times are SalahTimes 0.1.0's, computed once through SalahCalculation's public API
/// (`PrayerSchedule(source: CalculationSource(settings), location:)`) in a separate package; the
/// README records how. The journeys assert the same values on screen.
struct PhoneSnapshotTests {
  private let english = PhoneStrings(language: "en")

  private func settings(
    _ place: Place, _ method: CalculationMethod, change: (inout AppSettings) -> Void = { _ in }
  ) -> AppSettings {
    var settings = AppSettings.defaults
    settings.place = place
    settings.choose(.preset(method))
    change(&settings)
    return settings
  }

  private func snapshot(
    _ settings: AppSettings, at text: String, strings: PhoneStrings? = nil
  ) throws -> PhoneSnapshot {
    PhoneSnapshot.make(
      settings: settings, at: try Date(text, strategy: .iso8601), strings: strings ?? english)
  }

  private func row(_ kind: PrayerKind, in snapshot: PhoneSnapshot) throws -> PhoneSnapshot.Row {
    try #require(snapshot.rows.first { $0.kind == kind })
  }

  private func times(_ snapshot: PhoneSnapshot) -> [String?] {
    snapshot.rows.map(\.time)
  }

  // MARK: An ordinary day

  @Test func makkahAfternoon() throws {
    let screen = try snapshot(.defaults, at: "2026-10-14T14:00:00+03:00")
    #expect(screen.place == "Makkah")
    #expect(screen.clock == "14:00")
    #expect(screen.gregorianDate == "Wednesday, October 14, 2026")
    #expect(screen.hijriDate.contains("1448"))
    #expect(screen.rows.map(\.kind) == PrayerKind.allCases)
    #expect(times(screen) == ["05:00", "06:16", "12:07", "15:27", "17:57", "19:27"])
    #expect(screen.rows.allSatisfy { $0.dayMarker == nil && $0.missing == nil })
    #expect(
      screen.rows.map(\.statusText)
        == ["Passed", "Passed", "Passed", "Next", "Upcoming", "Upcoming"])
    #expect(
      screen.next
        == .prayer(
          PhoneSnapshot.Moment(name: "Asr", time: "15:27"), countdown: "1:27",
          spokenCountdown: "1 hour, 27 minutes"))
    #expect(screen.latest == PhoneSnapshot.Moment(name: "Dhuhr", time: "12:07"))
    #expect(screen.previous == nil)
    #expect(screen.banner == nil)
    #expect(screen.dayUnavailable == nil)
  }

  @Test func sunriseIsTheLatestEventNotPrayer() throws {
    let screen = try snapshot(.defaults, at: "2026-10-14T07:00:00+03:00")
    #expect(screen.latest == PhoneSnapshot.Moment(name: "Fajr", time: "05:00"))
    #expect(screen.previous == PhoneSnapshot.Moment(name: "Sunrise", time: "06:16"))
  }

  @Test func afterIshaTheNextPrayerIsTomorrows() throws {
    let screen = try snapshot(.defaults, at: "2026-10-14T22:00:00+03:00")
    #expect(
      screen.next
        == .prayer(
          PhoneSnapshot.Moment(
            name: "Fajr", time: "05:00", owningDay: "Thursday's",
            owningDayLabel: "From Thursday's schedule"),
          countdown: "7:00", spokenCountdown: "7 hours"))
  }

  // MARK: Custom parameters

  @Test func customParametersMoveTheirTimes() throws {
    let hanafi = settings(.makkah, .ummAlQura) { $0.calculation.parameters.madhab = .hanafi }
    #expect(
      times(try snapshot(hanafi, at: "2026-10-14T14:00:00+03:00"))
        == ["05:00", "06:16", "12:07", "16:19", "17:57", "19:27"])

    var custom = hanafi
    custom.customize { $0.fajr = .angle(16) }
    #expect(custom.method == .custom)
    #expect(
      times(try snapshot(custom, at: "2026-10-14T14:00:00+03:00"))
        == ["05:10", "06:16", "12:07", "16:19", "17:57", "19:27"])

    custom.customize { $0.rounding = .up }
    #expect(
      times(try snapshot(custom, at: "2026-10-14T14:00:00+03:00"))
        == ["05:11", "06:16", "12:07", "16:20", "17:58", "19:28"])

    // Without rounding, times keep their seconds, and the screen shows them.
    custom.customize { $0.rounding = .none }
    #expect(
      times(try snapshot(custom, at: "2026-10-14T14:00:00+03:00"))
        == ["05:10:29", "06:15:59", "12:06:43", "16:19:29", "17:57:09", "19:27:09"])
  }

  @Test func customAngles() throws {
    let custom = settings(.makkah, .muslimWorldLeague) {
      $0.customize {
        $0.fajr = .angle(15)
        $0.isha = .angle(15)
      }
    }
    let screen = try snapshot(custom, at: "2026-10-14T14:00:00+03:00")
    #expect(times(screen) == ["05:15", "06:16", "12:07", "15:27", "17:57", "18:58"])
    let rows = Dictionary(uniqueKeysWithValues: screen.calculation.map { ($0.id, $0.value) })
    #expect(rows["method"] == "Custom")
    #expect(rows["fajr"] == "15°")
    #expect(rows["isha"] == "15°")
  }

  @Test func ramadanIshaOnlyWhenChosen() throws {
    let off = settings(.makkah, .ummAlQura)
    let on = settings(.makkah, .ummAlQura) {
      $0.calculation.parameters.ramadanIsha = AppSettings.ramadanRule
    }
    // 2027-02-20 is in Ramadan 1448 in the Umm al-Qura calendar.
    #expect(try row(.isha, in: try snapshot(off, at: "2027-02-20T12:00:00+03:00")).time == "19:51")
    #expect(try row(.isha, in: try snapshot(on, at: "2027-02-20T12:00:00+03:00")).time == "20:21")
    // Outside Ramadan the rule changes nothing.
    #expect(try row(.isha, in: try snapshot(on, at: "2026-10-14T12:00:00+03:00")).time == "19:27")
  }

  @Test func userAdjustmentsAddMinutes() throws {
    let adjusted = settings(.makkah, .ummAlQura) {
      $0.calculation.parameters.adjustments.fajr = 2
      $0.calculation.parameters.adjustments.isha = -5
    }
    let screen = try snapshot(adjusted, at: "2026-10-14T14:00:00+03:00")
    #expect(try row(.fajr, in: screen).time == "05:02")
    #expect(try row(.isha, in: screen).time == "19:22")
    #expect(adjusted.method == .preset(.ummAlQura))
  }

  // MARK: VoiceOver

  /// VoiceOver reads the Calculation section's minutes in words, with each parameter's title
  /// once: "Isha: 90 minutes after Maghrib", where the screen shows "90 min after Maghrib".
  @Test func calculationLabelsSayMinutesInWords() throws {
    let adjusted = settings(.makkah, .ummAlQura) {
      $0.calculation.parameters.adjustments.fajr = 2
      $0.calculation.parameters.adjustments.isha = -5
      $0.calculation.parameters.ramadanIsha = AppSettings.ramadanRule
    }
    let screen = try snapshot(adjusted, at: "2026-10-14T14:00:00+03:00")
    let rows = Dictionary(uniqueKeysWithValues: screen.calculation.map { ($0.id, $0) })
    #expect(rows["isha"]?.value == "90 min after Maghrib")
    #expect(rows["isha"]?.accessibilityLabel == "Isha: 90 minutes after Maghrib")
    #expect(rows["method"]?.accessibilityLabel == "Method: Umm al-Qura")
    #expect(rows["fajr"]?.accessibilityLabel == "Fajr: 18.5°")
    #expect(
      rows["adjustments"]?.accessibilityLabel == "Your minutes: Fajr +2 minutes, Isha -5 minutes")
    #expect(
      rows["ramadanIsha"]?.accessibilityLabel
        == "Ramadan Isha: 120 minutes after Maghrib in Ramadan")

    // Arabic writes minutes as a word in its plural form, never the abbreviation "د", which
    // VoiceOver would read as a letter.
    let arabic = try snapshot(
      adjusted, at: "2026-10-14T14:00:00+03:00", strings: PhoneStrings(language: "ar"))
    let labels = arabic.calculation.map(\.accessibilityLabel)
    for label in labels {
      #expect(!label.split(whereSeparator: \.isWhitespace).contains("د"), "\(label)")
    }
    let isha = try #require(arabic.calculation.first { $0.id == "isha" })
    #expect(isha.value.split(whereSeparator: \.isWhitespace).contains("د"))
    #expect(isha.accessibilityLabel.contains("دقيقة"), "\(isha.accessibilityLabel)")
    // Fajr +2 and Isha -5 keep their direction in Arabic too.
    let adjustments = try #require(arabic.calculation.first { $0.id == "adjustments" })
    #expect(adjustments.accessibilityLabel.contains("تأخير بدقيقتين"), "\(adjustments)")
    #expect(adjustments.accessibilityLabel.contains("تقديم بـ"), "\(adjustments)")
  }

  /// Minutes added or taken away keep their direction in every plural form. Arabic's forms for
  /// one and two minutes have no number, so "+1" and "-1" mustn't both read "دقيقة".
  @Test func signedMinutesKeepTheirDirection() {
    let english = CalculationText(strings: english)
    #expect(english.spokenSignedMinutes(1) == "+1 minute")
    #expect(english.spokenSignedMinutes(-1) == "-1 minute")
    #expect(english.spokenSignedMinutes(2) == "+2 minutes")
    #expect(english.spokenSignedMinutes(0) == "0 minutes")

    let arabic = CalculationText(strings: PhoneStrings(language: "ar"))
    #expect(arabic.spokenSignedMinutes(1) == "تأخير بدقيقة")
    #expect(arabic.spokenSignedMinutes(-1) == "تقديم بدقيقة")
    #expect(arabic.spokenSignedMinutes(2) == "تأخير بدقيقتين")
    #expect(arabic.spokenSignedMinutes(-2) == "تقديم بدقيقتين")
    let values = [-11, -3, -2, -1, 1, 2, 3, 11]
    let spoken = values.map(arabic.spokenSignedMinutes)
    #expect(Set(spoken).count == values.count, "\(spoken)")
    for (value, text) in zip(values, spoken) {
      #expect(text.hasPrefix(value > 0 ? "تأخير" : "تقديم"), "\(value): \(text)")
    }
    #expect(arabic.spokenSignedMinutes(3).contains("٣"), "\(spoken)")
  }

  // MARK: Across midnight

  @Test func kashgarIshaAfterMidnightIsNext() throws {
    let kashgar = settings(.kashgar, .muslimWorldLeague)
    let screen = try snapshot(kashgar, at: "2026-06-22T00:05:00+08:00")
    #expect(screen.gregorianDate == "Monday, June 22, 2026")
    #expect(
      screen.next
        == .prayer(
          PhoneSnapshot.Moment(
            name: "Isha", time: "00:19", owningDay: "Sunday's",
            owningDayLabel: "From Sunday's schedule"),
          countdown: "14m", spokenCountdown: "14 minutes"))
    #expect(
      screen.latest
        == PhoneSnapshot.Moment(
          name: "Maghrib", time: "22:27", owningDay: "Sunday's",
          owningDayLabel: "From Sunday's schedule"))
    // Today's rows are 22 June's: its own Isha is after the next midnight.
    #expect(times(screen) == ["05:28", "07:29", "14:58", "18:56", "22:27", "00:19"])
    #expect(try row(.isha, in: screen).dayMarker == "Next day")
    #expect(screen.rows.allSatisfy { $0.status == .upcoming })
  }

  @Test func kashgarIshaAfterMidnightIsLatest() throws {
    let kashgar = settings(.kashgar, .muslimWorldLeague)
    let screen = try snapshot(kashgar, at: "2026-06-22T00:30:00+08:00")
    #expect(
      screen.latest
        == PhoneSnapshot.Moment(
          name: "Isha", time: "00:19", owningDay: "Sunday's",
          owningDayLabel: "From Sunday's schedule"))
    #expect(screen.justStarted == "Isha has started")
    #expect(
      screen.next
        == .prayer(
          PhoneSnapshot.Moment(name: "Fajr", time: "05:28"), countdown: "4:58",
          spokenCountdown: "4 hours, 58 minutes"))
    #expect(try row(.fajr, in: screen).status == .next(approaching: false))
  }

  @Test func kazanFajrBeforeMidnightBelongsToTheNextDay() throws {
    let kazan = settings(.kazan, .muslimWorldLeague) {
      $0.calculation.parameters.highLatitudeRule = .middleOfTheNight
    }
    let screen = try snapshot(kazan, at: "2026-06-20T23:50:00+03:00")
    #expect(screen.gregorianDate == "Saturday, June 20, 2026")
    #expect(
      screen.latest
        == PhoneSnapshot.Moment(
          name: "Fajr", time: "23:45", owningDay: "Sunday's",
          owningDayLabel: "From Sunday's schedule"))
    #expect(screen.justStarted == "Fajr has started")
    #expect(
      screen.next
        == .prayer(
          PhoneSnapshot.Moment(
            name: "Dhuhr", time: "11:45", owningDay: "Sunday's",
            owningDayLabel: "From Sunday's schedule"),
          countdown: "11:55", spokenCountdown: "11 hours, 55 minutes"))
    // 20 June's own Fajr fell at 23:45 the evening before.
    #expect(times(screen) == ["23:45", "02:58", "11:45", "16:17", "20:32", "23:45"])
    #expect(try row(.fajr, in: screen).dayMarker == "Previous evening")
    #expect(try row(.isha, in: screen).dayMarker == nil)
    #expect(screen.rows.allSatisfy { $0.status == .passed })
  }

  // MARK: Source failure

  @Test func listReceivesTheCalculatedDaysFactsAndReasons() throws {
    let tromso = settings(.tromso, .muslimWorldLeague)
    let screen = try snapshot(tromso, at: "2026-06-21T15:00:00+02:00")
    let date = try Date("2026-06-21T15:00:00+02:00", strategy: .iso8601)
    let availability = tromso.schedule.day(containing: date)
    guard case .available(let day, .partial(let missing)) = availability else {
      Issue.record("Tromsø must have a partial calculated day")
      return
    }
    #expect(screen.list.day == day)
    #expect(screen.list.missing == missing)
    #expect(screen.list.missing.keys.sorted() == [.fajr, .sunrise, .maghrib, .isha])
    #expect(screen.list.state?.next?.kind == .asr)
    #expect(screen.list.day.events.map(\.kind) == [.dhuhr, .asr])
  }

  @Test func unavailableListHasNoEventsAndKeepsTheExplicitReasonForEveryKind() throws {
    let invalid = settings(.invalid, .muslimWorldLeague)
    let screen = try snapshot(invalid, at: "2026-06-21T12:00:00Z")
    #expect(screen.list.day.events.isEmpty)
    #expect(screen.list.state == nil)
    #expect(
      screen.list.missing
        == Dictionary(uniqueKeysWithValues: PrayerKind.allCases.map { ($0, .invalidData) }))
  }

  @Test func tromsoMidsummerAfterAsr() throws {
    let tromso = settings(.tromso, .muslimWorldLeague)
    let screen = try snapshot(tromso, at: "2026-06-21T20:00:00+02:00")
    #expect(times(screen) == [nil, nil, "12:46", "17:58", nil, nil])
    for kind in [PrayerKind.fajr, .sunrise, .maghrib, .isha] {
      #expect(try row(kind, in: screen).missing == "Can't be calculated")
    }
    // The state is unavailable, so no row claims a status.
    #expect(try row(.asr, in: screen).status == nil)
    #expect(try row(.asr, in: screen).statusText == "Unknown")
    #expect(
      screen.next
        == .unknown(
          message: "The next prayer can't be named.",
          reason: "Sunday, June 21, 2026: Maghrib and Isha (can't be calculated)"))
    #expect(screen.latest == nil)
    let banner = try #require(screen.banner)
    #expect(banner.title == "No current or next prayer can be named")
    #expect(
      Array(banner.gaps.prefix(2)) == [
        "Sunday, June 21, 2026: Maghrib and Isha (can't be calculated)",
        "Monday, June 22, 2026: Fajr and Sunrise (can't be calculated)",
      ])
  }

  @Test func tromsoMidsummerBetweenDhuhrAndAsr() throws {
    let tromso = settings(.tromso, .muslimWorldLeague)
    let screen = try snapshot(tromso, at: "2026-06-21T15:00:00+02:00")
    #expect(screen.latest == PhoneSnapshot.Moment(name: "Dhuhr", time: "12:46"))
    #expect(
      screen.next
        == .prayer(
          PhoneSnapshot.Moment(name: "Asr", time: "17:58"), countdown: "2:58",
          spokenCountdown: "2 hours, 58 minutes"))
    #expect(
      screen.banner
        == PhoneSnapshot.Banner(
          title: "Some of today's times are missing",
          gaps: ["Sunday, June 21, 2026: Fajr, Sunrise, Maghrib, and Isha (can't be calculated)"]))
  }

  @Test func invalidCoordinatesShowNoTimes() throws {
    let invalid = settings(.invalid, .muslimWorldLeague)
    let screen = try snapshot(invalid, at: "2026-06-21T12:00:00Z")
    #expect(screen.place == "Invalid coordinates")
    #expect(screen.rows.map(\.kind) == PrayerKind.allCases)
    #expect(screen.rows.allSatisfy { $0.time == nil })
    #expect(screen.rows.allSatisfy { $0.missing == "Invalid location or settings" })
    #expect(screen.dayUnavailable == "Today's times can't be shown: invalid location or settings")
    #expect(screen.latest == nil)
    guard case .unknown = screen.next else {
      Issue.record("An invalid location named a next prayer: \(screen.next)")
      return
    }
    let banner = try #require(screen.banner)
    #expect(banner.title == "No current or next prayer can be named")
    #expect(
      banner.gaps.contains(
        "Sunday, June 21, 2026: Fajr, Sunrise, Dhuhr, Asr, Maghrib, and Isha "
          + "(invalid location or settings)"))
  }

  // MARK: The calculation section

  @Test func everyParameterIsShown() {
    let rows = CalculationText(strings: english).rows(.defaults)
    #expect(
      rows.map(\.id) == [
        "method", "fajr", "maghrib", "isha", "madhab", "highLatitudeRule", "nightSpan",
        "methodAdjustments", "adjustments", "rounding", "ramadanIsha",
      ])
    #expect(
      rows.map(\.value) == [
        "Umm al-Qura", "18.5°", "Sunset", "90 min after Maghrib", "Shafi'i", "Recommended",
        "Sunset to Fajr", "None", "None", "Nearest minute", "Off",
      ])
  }

  @Test func methodSpecificParametersAreShown() {
    let text = CalculationText(strings: english)
    var settings = AppSettings.defaults
    settings.choose(.preset(.diyanet))
    #expect(
      text.rows(settings).first { $0.id == "methodAdjustments" }?.value
        == "Sunrise -7 min, Dhuhr +5 min, Asr +4 min, Maghrib +7 min")
    settings.choose(.preset(.tehran))
    #expect(text.rows(settings).first { $0.id == "maghrib" }?.value == "4.5°")
    settings.choose(.preset(.moonsightingCommittee))
    #expect(text.rows(settings).first { $0.id == "fajr" }?.value == "Moonsighting Committee")
    #expect(
      text.rows(settings).first { $0.id == "isha" }?.value
        == "Moonsighting Committee, general twilight")
    settings.choose(.preset(.muis))
    #expect(text.rows(settings).first { $0.id == "rounding" }?.value == "Up to the minute")
    settings.calculation.parameters.ramadanIsha = .interval(minutes: 120, hijriDayOffset: 1)
    #expect(
      text.rows(settings).first { $0.id == "ramadanIsha" }?.value
        == "120 min after Maghrib in Ramadan, Hijri day offset +1")
  }

  // MARK: Arabic

  @Test func arabic() throws {
    let arabic = PhoneStrings(language: "ar")
    #expect(arabic.isRightToLeft)
    let screen = try snapshot(.defaults, at: "2026-10-14T14:00:00+03:00", strings: arabic)
    #expect(try row(.fajr, in: screen).name == "الفجر")
    #expect(try row(.fajr, in: screen).time == "٠٥:٠٠")
    #expect(screen.hijriDate.contains("١٤٤٨"))
    guard case .prayer(let next, _, _) = screen.next else {
      Issue.record("No next prayer in Arabic")
      return
    }
    #expect(next.name == "العصر")
  }
}
