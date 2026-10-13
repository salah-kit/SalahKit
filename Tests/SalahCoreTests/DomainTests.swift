import Foundation
import Testing

@testable import SalahCore

@Suite struct PrayerKindTests {
  @Test func canonicalOrderAndPrayers() {
    #expect(PrayerKind.allCases == [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha])
    #expect(PrayerKind.allCases.sorted(by: >).first == .isha)
    #expect(PrayerKind.fajr < .sunrise && PrayerKind.maghrib < .isha)
    #expect(PrayerKind.allCases.filter(\.isPrayer) == [.fajr, .dhuhr, .asr, .maghrib, .isha])
  }

  @Test func dictionaryEncodesAsObjectKeyedByRawValue() throws {
    let data = try JSONEncoder().encode([PrayerKind.isha: 1])
    #expect(String(decoding: data, as: UTF8.self) == #"{"isha":1}"#)
    let decoded = try JSONDecoder().decode([PrayerKind: Int].self, from: Data(#"{"fajr":2}"#.utf8))
    #expect(decoded == [.fajr: 2])
  }
}

@Suite struct CivilDayTests {
  @Test func parsesAndFormatsTheShape() {
    #expect(CivilDay("2026-10-16") == CivilDay(year: 2026, month: 10, day: 16))
    #expect(CivilDay(year: 987, month: 1, day: 5).description == "0987-01-05")
    for text in ["2026-1-16", "26-10-16", "2026/10/16", "2026-10-16T00:00", "", "2026-10-1a"] {
      #expect(CivilDay(text) == nil, "\(text)")
    }
    // Shape only: an impossible date parses, and reports itself invalid.
    #expect(CivilDay("2026-02-30")?.isValid == false)
  }

  @Test func validity() {
    #expect(CivilDay(year: 2024, month: 2, day: 29).isValid)
    #expect(!CivilDay(year: 2026, month: 2, day: 29).isValid)
    #expect(!CivilDay(year: 2026, month: 13, day: 1).isValid)
    #expect(!CivilDay(year: 2026, month: 4, day: 31).isValid)
    #expect(!CivilDay(year: 0, month: 1, day: 1).isValid)
    #expect(CivilDay(year: 2000, month: 2, day: 29).isValid)
    #expect(!CivilDay(year: 1900, month: 2, day: 29).isValid)
  }

  @Test func weekdayMatchesTheCalendar() {
    #expect(CivilDay(year: 2026, month: 10, day: 16).weekday == 6)  // Friday
    #expect(CivilDay(year: 1970, month: 1, day: 1).weekday == 5)  // Thursday
    #expect(CivilDay(year: 2026, month: 1, day: 4).weekday == 1)  // Sunday
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    var day = CivilDay(year: 1999, month: 12, day: 25)
    for _ in 0..<800 {
      let date = calendar.date(
        from: DateComponents(year: day.year, month: day.month, day: day.day))!
      #expect(day.weekday == calendar.component(.weekday, from: date), "\(day)")
      day = day.adding(days: 1)
    }
  }

  @Test func arithmeticCrossesMonthsYearsAndLeapDays() {
    let day = CivilDay(year: 2026, month: 12, day: 31)
    #expect(day.adding(days: 1) == CivilDay(year: 2027, month: 1, day: 1))
    #expect(CivilDay(year: 2024, month: 2, day: 28).adding(days: 1) == CivilDay("2024-02-29"))
    #expect(CivilDay(year: 2026, month: 3, day: 1).adding(days: -1) == CivilDay("2026-02-28"))
    #expect(day.adding(days: -365) == CivilDay("2025-12-31"))
    #expect(CivilDay("2026-01-01")!.days(to: CivilDay("2027-01-01")!) == 365)
    #expect(CivilDay("2024-01-01")!.days(to: CivilDay("2025-01-01")!) == 366)
    #expect(CivilDay("2026-10-16")!.days(to: CivilDay("2026-10-13")!) == -3)
    // Arithmetic normalizes an impossible date the way the day count does.
    #expect(CivilDay(year: 2026, month: 2, day: 30).adding(days: 0) == CivilDay("2026-03-02"))
  }

  @Test func ordersChronologically() {
    let days = ["2026-10-16", "2025-12-31", "2026-01-02", "2026-10-15"].compactMap(CivilDay.init)
    #expect(
      days.sorted().map(\.description) == ["2025-12-31", "2026-01-02", "2026-10-15", "2026-10-16"])
  }

  @Test func containingUsesTheGivenZone() throws {
    let instant = try #require(InstantText.parse("2026-06-21T22:30:00Z"))
    let riyadh = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    #expect(CivilDay(containing: instant, in: riyadh) == CivilDay("2026-06-22"))
    #expect(CivilDay(containing: instant, in: newYork) == CivilDay("2026-06-21"))
    let beforeEpoch = try #require(InstantText.parse("1969-12-31T23:59:59Z"))
    #expect(
      CivilDay(containing: beforeEpoch, in: TimeZone(identifier: "UTC")!) == CivilDay("1969-12-31"))
  }

  @Test func codesAsAString() throws {
    let day = CivilDay(year: 2026, month: 3, day: 8)
    #expect(String(decoding: try JSONEncoder().encode([day]), as: UTF8.self) == #"["2026-03-08"]"#)
    #expect(try JSONDecoder().decode([CivilDay].self, from: Data(#"["2026-03-08"]"#.utf8)) == [day])
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode([CivilDay].self, from: Data(#"["8 March 2026"]"#.utf8))
    }
  }
}

@Suite struct InstantTextTests {
  @Test func parsesOffsetsAndFractions() throws {
    let utc = try #require(InstantText.parse("2026-06-21T23:15:00Z"))
    #expect(utc.timeIntervalSince1970 == 1_782_083_700)
    #expect(InstantText.parse("2026-06-22T00:15:00+01:00") == utc)
    #expect(InstantText.parse("2026-06-22T00:15:00+0100") == utc)
    #expect(InstantText.parse("2026-06-22T00:15+01") == utc)
    #expect(InstantText.parse("2026-06-21T19:15:00-04:00") == utc)
    #expect(
      InstantText.parse("2026-06-21T23:15:00.250Z")?.timeIntervalSince1970 == 1_782_083_700.25)
  }

  @Test func rejectsMalformedText() {
    let bad = [
      "2026-06-21T23:15:00", "2026-06-21 23:15:00Z", "2026-06-21T24:00:00Z",
      "2026-02-30T10:00:00Z", "2026-06-21T23:15:00+25:00", "2026-06-21T23:15:00Zjunk",
      "2026-06-21T23:15:00.Z",
    ]
    for text in bad { #expect(InstantText.parse(text) == nil, "\(text)") }
  }

  @Test func formatsUTCWithMillisecondsOnlyWhenPresent() throws {
    #expect(
      InstantText.format(Date(timeIntervalSince1970: 1_782_083_700)) == "2026-06-21T23:15:00Z")
    #expect(
      InstantText.format(Date(timeIntervalSince1970: 1_782_083_700.5)) == "2026-06-21T23:15:00.500Z"
    )
    #expect(InstantText.format(Date(timeIntervalSince1970: -1)) == "1969-12-31T23:59:59Z")
    let text = "2026-03-29T00:59:59.001Z"
    #expect(InstantText.format(try #require(InstantText.parse(text))) == text)
  }
}

@Suite struct EventAndDayTests {
  let monday = CivilDay(year: 2026, month: 6, day: 22)

  @Test func eventIdentityIsOwningDayKindAndInstant() throws {
    let time = try #require(InstantText.parse("2026-06-23T00:15:00+01:00"))
    let event = PrayerEvent(scheduleDay: monday, kind: .isha, time: time)
    #expect(event.id == "2026-06-22/isha/2026-06-22T23:15:00Z")
    var moved = event
    moved.time = time.addingTimeInterval(60)
    #expect(moved.id != event.id)
    var withIqama = event
    withIqama.iqama = time.addingTimeInterval(600)
    #expect(withIqama.id == event.id)
  }

  @Test func dayOrdersEventsAndAnswersByKind() throws {
    let zone = try #require(TimeZone(identifier: "Europe/London"))
    let fajr = PrayerEvent(scheduleDay: monday, kind: .fajr, time: Date(timeIntervalSince1970: 100))
    let isha = PrayerEvent(scheduleDay: monday, kind: .isha, time: Date(timeIntervalSince1970: 900))
    let day = PrayerDay(day: monday, timeZone: zone, events: [isha, fajr])
    #expect(day.events.map(\.kind) == [.fajr, .isha])
    #expect(day[.isha] == isha)
    #expect(day[.asr] == nil)
    #expect(!day.isFriday)
    #expect(
      PrayerDay(day: CivilDay(year: 2026, month: 6, day: 26), timeZone: zone, events: []).isFriday)
  }

  @Test func eventRoundTripsThroughJSON() throws {
    let event = PrayerEvent(
      scheduleDay: monday, kind: .dhuhr, time: Date(timeIntervalSince1970: 1_782_126_000),
      iqama: Date(timeIntervalSince1970: 1_782_127_800), observance: .jumuah)
    let decoded = try JSONDecoder().decode(PrayerEvent.self, from: JSONEncoder().encode(event))
    #expect(decoded == event)
  }
}

@Suite struct PrayerLocationTests {
  @Test func codesTheTimeZoneAsAnIdentifier() throws {
    let location = PrayerLocation(
      latitude: 1.3521, longitude: 103.8198, timeZone: TimeZone(identifier: "Asia/Singapore")!,
      countryCode: "SG", name: "Singapore")
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let json = String(decoding: try encoder.encode(location), as: UTF8.self)
    #expect(
      json.contains(#""timeZone":"Asia\/Singapore""#)
        || json.contains(#""timeZone":"Asia/Singapore""#))
    #expect(try JSONDecoder().decode(PrayerLocation.self, from: Data(json.utf8)) == location)
    let minimal = #"{"latitude": 55.95, "longitude": -3.19, "timeZone": "Europe/London"}"#
    let decoded = try JSONDecoder().decode(PrayerLocation.self, from: Data(minimal.utf8))
    #expect(decoded.timeZone.identifier == "Europe/London" && decoded.name == nil)
  }

  @Test func rejectsUnknownZones() {
    let json = #"{"latitude": 0, "longitude": 0, "timeZone": "Mars/Olympus"}"#
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PrayerLocation.self, from: Data(json.utf8))
    }
  }
}

@Suite struct WallTimeTests {
  @Test func parsesAndFormats() {
    #expect(WallClockTime("21:15") == WallClockTime(hour: 21, minute: 15))
    #expect(WallClockTime("00:15+1") == WallClockTime(hour: 0, minute: 15, dayOffset: 1))
    #expect(WallClockTime("5:05") == WallClockTime(hour: 5, minute: 5))
    #expect(WallClockTime(hour: 5, minute: 5).description == "05:05")
    #expect(WallClockTime(hour: 0, minute: 15, dayOffset: 1).description == "00:15+1")
    for text in ["21:5", "2115", "21:15:00", "21:15+", "21:15+x", "-1:00", "", "a1:15"] {
      #expect(WallClockTime(text) == nil, "\(text)")
    }
  }

  @Test func validityIsSeparateFromShape() {
    #expect(WallClockTime("24:00")?.isValid == false)
    #expect(WallClockTime("23:60")?.isValid == false)
    #expect(WallClockTime("23:59+2")?.isValid == false)
    #expect(WallClockTime("00:00+1")?.isValid == true)
  }

  @Test func timetableTimeCodesLocalAndInstantTimes() throws {
    let json = #"["21:15", "00:15+1", "2026-06-22T00:15:00+01:00"]"#
    let decoded = try JSONDecoder().decode([TimetableTime].self, from: Data(json.utf8))
    #expect(decoded[0] == .local(WallClockTime(hour: 21, minute: 15)))
    #expect(decoded[1] == .local(WallClockTime(hour: 0, minute: 15, dayOffset: 1)))
    #expect(decoded[2] == .instant(Date(timeIntervalSince1970: 1_782_083_700)))
    let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
    #expect(encoded == #"["21:15","00:15+1","2026-06-21T23:15:00Z"]"#)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode([TimetableTime].self, from: Data(#"["2026-06-22T00:15:00"]"#.utf8))
    }
  }

  @Test func resolutionDefaultsToRejectingBothCases() throws {
    let policy = try JSONDecoder().decode(WallTimeResolution.self, from: Data("{}".utf8))
    #expect(policy == WallTimeResolution(repeated: .reject, nonexistent: .reject))
    let custom = #"{"repeated": "later", "nonexistent": "nextValid"}"#
    #expect(
      try JSONDecoder().decode(WallTimeResolution.self, from: Data(custom.utf8))
        == WallTimeResolution(repeated: .later, nonexistent: .nextValid))
  }
}

@Suite struct RulesAndPolicyCodingTests {
  @Test func iqamaRulesCodeAfterAndAt() throws {
    let json =
      #"{"rules": {"fajr": {"after": 20}, "isha": {"at": "20:30"}}, "jumuah": {"at": "13:30"}}"#
    let rules = try JSONDecoder().decode(IqamaRules.self, from: Data(json.utf8))
    #expect(rules.rules[.fajr] == .after(minutes: 20))
    #expect(rules.rules[.isha] == .at(WallClockTime(hour: 20, minute: 30)))
    #expect(rules.jumuah == .at(WallClockTime(hour: 13, minute: 30)))
    #expect(rules.wallTimeResolution == WallTimeResolution())
    #expect(try JSONDecoder().decode(IqamaRules.self, from: JSONEncoder().encode(rules)) == rules)
    #expect(try JSONDecoder().decode(IqamaRules.self, from: Data("{}".utf8)) == IqamaRules())
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(IqamaRules.Rule.self, from: Data(#"{"before": 5}"#.utf8))
    }
  }

  @Test func statePolicyCodesSeconds() throws {
    let json = #"{"approaching": 600, "justStarted": {"fixed": 300}}"#
    let policy = try JSONDecoder().decode(StatePolicy.self, from: Data(json.utf8))
    #expect(policy == StatePolicy(approaching: .seconds(600), justStarted: .fixed(.seconds(300))))
    #expect(try JSONDecoder().decode(StatePolicy.self, from: Data("{}".utf8)) == StatePolicy())
    let untilIqama = StatePolicy(justStarted: .untilIqama(fallback: .seconds(900)))
    #expect(
      try JSONDecoder().decode(StatePolicy.self, from: JSONEncoder().encode(untilIqama))
        == untilIqama)
    let fractional = #"{"approaching": 0.5}"#
    #expect(
      try JSONDecoder().decode(StatePolicy.self, from: Data(fractional.utf8)).approaching
        == .milliseconds(500))
  }
}
