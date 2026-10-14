import Foundation
import SalahCore
import SalahFixtures
import Testing

@testable import SalahUI

@Suite("Missing list rows")
struct ListRowContentTests {
  let locale = Locale(identifier: "en_GB")
  let names = PrayerNames(locale: Locale(identifier: "en"))

  @Test("a partial day keeps the missing published kind in canonical order")
  func partialDay() throws {
    let moment = PrayerFixtures.partialDay
    guard
      case .available(let day, .partial(let missing)) = moment.schedule.day(containing: moment.date)
    else {
      Issue.record("The fixture must be a partial day")
      return
    }
    let rows = ListRowContent.rows(
      day: day, state: moment.state().prayerState, names: names, locale: locale, missing: missing)
    #expect(rows.map(\.kind) == PrayerKind.allCases)
    #expect(
      rows.last == .missing(day: day.day, kind: .isha, reason: .noPublishedData, name: "Isha"))
    #expect(Set(rows.map(\.id)).count == rows.count)
  }

  @Test("known-only rows retain their events, order, identity and formatting")
  func knownOnly() throws {
    let moment = PrayerFixtures.approaching
    var day = try #require(moment.schedule.day(containing: moment.date).day)
    // PrayerDay is mutable. The default list keeps even an adopter's supplied order.
    day.events.reverse()
    let known = RowContent.rows(
      day: day, state: moment.state().prayerState, names: names, locale: locale)
    let rows = ListRowContent.rows(
      day: day, state: moment.state().prayerState, names: names, locale: locale, missing: [:])
    #expect(rows == known.map(ListRowContent.event))
    #expect(rows.map(\.id) == day.events.map(\.id))
  }

  @Test("explicit reasons survive canonical ordering; known events win conflicting gaps")
  func explicitReasons() throws {
    let moment = PrayerFixtures.approaching
    var day = try #require(moment.schedule.day(containing: moment.date).day)
    day.events = day.events.filter { $0.kind == .dhuhr || $0.kind == .asr }
    let missing: [PrayerKind: ScheduleGapReason] = [
      .isha: .unresolvedWallTime, .fajr: .calculationUnavailable,
      .maghrib: .invalidData, .sunrise: .noPublishedData, .dhuhr: .invalidData,
    ]
    let rows = ListRowContent.rows(
      day: day, state: moment.state().prayerState, names: names, locale: locale, missing: missing)
    #expect(rows.map(\.kind) == PrayerKind.allCases)
    #expect(
      rows[0] == .missing(day: day.day, kind: .fajr, reason: .calculationUnavailable, name: "Fajr"))
    #expect(
      rows[1] == .missing(day: day.day, kind: .sunrise, reason: .noPublishedData, name: "Sunrise"))
    #expect(
      rows[4] == .missing(day: day.day, kind: .maghrib, reason: .invalidData, name: "Maghrib"))
    #expect(
      rows[5] == .missing(day: day.day, kind: .isha, reason: .unresolvedWallTime, name: "Isha"))
    let known = RowContent.rows(
      day: day, state: moment.state().prayerState, names: names, locale: locale)
    #expect(Array(rows[2...3]) == known.map(ListRowContent.event))
  }

  @Test("only explicitly missing kinds are added, with names in their own locale")
  func noInferredKinds() {
    let day = PrayerDay(day: CivilDay(year: 2026, month: 10, day: 16), timeZone: .gmt, events: [])
    let arabic = PrayerNames(locale: PrayerLocale.resolved("ar"))
    let rows = ListRowContent.rows(
      day: day, state: nil, names: arabic, locale: locale, missing: [.dhuhr: .noPublishedData])
    #expect(
      rows == [
        .missing(
          day: day.day, kind: .dhuhr, reason: .noPublishedData, name: arabic.name(of: .dhuhr))
      ])
    #expect(rows.count == 1)
  }
}
