import Foundation
import Testing

@testable import SalahCore

private let riyadh = TimeZone(identifier: "Asia/Riyadh") ?? .gmt

/// Noon in Riyadh on a Gregorian date.
private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
  var gregorian = Calendar(identifier: .gregorian)
  gregorian.timeZone = riyadh
  let parts = DateComponents(year: year, month: month, day: day, hour: 12)
  return gregorian.date(from: parts) ?? .distantPast
}

private func format(
  _ identifier: String, numbering: String? = nil, dayOffset: Int = 0,
  calendar: Calendar.Identifier = .islamicUmmAlQura
) -> HijriDateFormat {
  var locale = Locale(identifier: identifier)
  if let numbering {
    var components = Locale.Components(locale: locale)
    components.numberingSystem = Locale.NumberingSystem(numbering)
    locale = Locale(components: components)
  }
  return HijriDateFormat(
    locale: locale, timeZone: riyadh, dayOffset: dayOffset, calendar: calendar)
}

private func components(_ year: Int, _ month: Int, _ day: Int) -> HijriDateFormat.Components {
  HijriDateFormat.Components(year: year, month: month, day: day)
}

/// Umm al-Qura dates with the template `dMMMMy`.
@Suite struct HijriDateFormatTests {
  @Test func english() {
    #expect(format("en").string(from: noon(2026, 10, 7)) == "Rabiʻ II 26, 1448")
    #expect(format("en").string(from: noon(2026, 3, 1)) == "Ramadan 12, 1447")
  }

  @Test func arabic() {
    let arabic = format("ar", numbering: "arab")
    #expect(arabic.string(from: noon(2026, 10, 7)) == "٢٦ ربيع الآخر، ١٤٤٨")
    #expect(arabic.string(from: noon(2026, 3, 1)) == "١٢ رمضان، ١٤٤٧")
  }

  @Test func turkish() {
    #expect(format("tr").string(from: noon(2026, 10, 7)) == "26 Rebiülahir 1448")
    #expect(format("tr").string(from: noon(2026, 3, 1)) == "12 Ramazan 1447")
  }

  @Test func otherTemplates() {
    #expect(format("en").string(from: noon(2026, 10, 7), template: "MMMM") == "Rabiʻ II")
    #expect(format("en").string(from: noon(2026, 10, 7), template: "yMMMMd") == "Rabiʻ II 26, 1448")
  }

  @Test func componentsInUmmAlQura() {
    #expect(format("en").components(of: noon(2026, 10, 7)) == components(1_448, 4, 26))
    #expect(format("en").components(of: noon(2026, 3, 1)) == components(1_447, 9, 12))
  }

  @Test func dayOffsetMovesByWholeDays() {
    let date = noon(2026, 10, 7)
    #expect(format("en", dayOffset: 1).string(from: date) == "Rabiʻ II 27, 1448")
    #expect(format("en", dayOffset: -1).string(from: date) == "Rabiʻ II 25, 1448")
    #expect(format("en", dayOffset: 1).components(of: date) == components(1_448, 4, 27))
    #expect(format("en", dayOffset: -1).components(of: date) == components(1_448, 4, 25))
  }

  @Test func dayOffsetCrossesAMonthBoundary() {
    // In Umm al-Qura, 2026-10-11 is Rabi' II 30 and 2026-10-12 is Jumada I 1, 1448.
    #expect(format("en").components(of: noon(2026, 10, 11)) == components(1_448, 4, 30))
    #expect(
      format("en", dayOffset: 1).components(of: noon(2026, 10, 11)) == components(1_448, 5, 1))
    #expect(
      format("en", dayOffset: -1).components(of: noon(2026, 10, 12)) == components(1_448, 4, 30))
    #expect(
      format("en", dayOffset: 2).components(of: noon(2026, 10, 10)) == components(1_448, 5, 1))
  }

  @Test func usesTheGivenTimeZone() {
    // 22:30 UTC on 2026-10-07 is already 01:30 on 2026-10-08 in Riyadh.
    let late = noon(2026, 10, 7).addingTimeInterval(13.5 * 3_600)
    #expect(format("en").components(of: late) == components(1_448, 4, 27))
    let newYork = TimeZone(identifier: "America/New_York") ?? .gmt
    let inNewYork = HijriDateFormat(locale: Locale(identifier: "en"), timeZone: newYork)
    #expect(inNewYork.components(of: late) == components(1_448, 4, 26))
    #expect(inNewYork.string(from: late) == "Rabiʻ II 26, 1448")
  }

  @Test func otherIslamicCalendars() {
    let civil = format("en", calendar: .islamicCivil)
    #expect(civil.components(of: noon(2026, 10, 7)) == components(1_448, 4, 24))
    #expect(civil.string(from: noon(2026, 10, 7)) == "Rabiʻ II 24, 1448")
    // The arithmetic calendar puts the month boundary on a different day than Umm al-Qura.
    #expect(civil.components(of: noon(2026, 10, 12)) == components(1_448, 4, 29))
    #expect(civil.components(of: noon(2026, 10, 13)) == components(1_448, 5, 1))
  }

  @Test func defaultsToUmmAlQuraWithoutOffset() {
    let defaults = HijriDateFormat(locale: Locale(identifier: "en"), timeZone: riyadh)
    #expect(defaults.components(of: noon(2026, 10, 7)) == components(1_448, 4, 26))
    #expect(defaults.string(from: noon(2026, 10, 7)) == "Rabiʻ II 26, 1448")
  }
}
