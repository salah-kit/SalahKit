import Foundation
import SalahCore
import Testing

@testable import MosqueBoard

/// The bundled timetables decode with `TimetableSource` and give the days Timetables.md
/// describes.
struct TimetableDataTests {
  private static func instant(_ text: String) throws -> Date {
    try Date(text, strategy: .iso8601)
  }

  private static func days(from first: CivilDay, through last: CivilDay) -> [CivilDay] {
    (0...first.days(to: last)).map { first.adding(days: $0) }
  }

  @Test func muisDecodesEveryDayOf2026AsComplete() throws {
    let source = try Board.timetable(.muis)
    let board = try Board.load(.muis)
    #expect(source.expectedKinds == Set(PrayerKind.allCases))
    #expect(source.rows.count == 365)
    #expect(source.firstDay == CivilDay(year: 2026, month: 1, day: 1))
    #expect(source.lastDay == CivilDay(year: 2026, month: 12, day: 31))
    for day in Self.days(from: source.firstDay!, through: source.lastDay!) {
      let availability = source.prayerDay(day, at: board.location)
      #expect(availability.coverage == .complete, "\(day)")
      #expect(availability.day?.events.count == 6, "\(day)")
      #expect(availability.day?.events.allSatisfy { $0.iqama == nil } == true, "\(day)")
    }
    #expect(
      source.prayerDay(CivilDay(year: 2027, month: 1, day: 1), at: board.location)
        == .unavailable(.noPublishedData))
  }

  @Test func muisTimesAreSingaporeWallTimes() throws {
    let board = try Board.load(.muis)
    let day = try #require(board.schedule.day(CivilDay(year: 2026, month: 10, day: 14)).day)
    #expect(day[.fajr]?.time == (try Self.instant("2026-10-14T05:31:00+08:00")))
    #expect(day[.isha]?.time == (try Self.instant("2026-10-14T20:03:00+08:00")))
  }

  @Test func edinburghDecodesWithItsDeliberateCases() throws {
    let source = try Board.timetable(.edinburgh)
    let board = try Board.load(.edinburgh)
    #expect(source.rows.count == 244)
    #expect(source.firstDay == CivilDay(year: 2026, month: 3, day: 1))
    #expect(source.lastDay == CivilDay(year: 2026, month: 10, day: 31))

    let partial = CivilDay(year: 2026, month: 6, day: 24)
    let missing = CivilDay(year: 2026, month: 6, day: 26)
    for day in Self.days(from: source.firstDay!, through: source.lastDay!) {
      let availability = source.prayerDay(day, at: board.location)
      switch day {
      case partial:
        #expect(availability.coverage == .partial(missing: [.isha: .noPublishedData]))
        #expect(availability.day?[.isha] == nil)
        #expect(availability.day?[.maghrib]?.iqama != nil)
      case missing:
        #expect(availability == .unavailable(.noPublishedData))
      default:
        #expect(availability.coverage == .complete, "\(day)")
        let events = availability.day?.events ?? []
        #expect(events.filter { $0.kind.isPrayer }.allSatisfy { $0.iqama != nil }, "\(day)")
        let jumuah = availability.day?[.dhuhr]?.observance == .jumuah
        #expect(jumuah == (day.weekday == 6), "\(day)")
      }
    }
    #expect(
      source.prayerDay(CivilDay(year: 2026, month: 11, day: 1), at: board.location)
        == .unavailable(.noPublishedData))
  }

  @Test func edinburghResolvesAfterMidnightAndAcrossClockChanges() throws {
    let board = try Board.load(.edinburgh)
    let june21 = try #require(board.schedule.day(CivilDay(year: 2026, month: 6, day: 21)).day)
    // "01:15+1" belongs to 21 June and happens on 22 June, in BST.
    #expect(june21[.isha]?.time == (try Self.instant("2026-06-22T01:15:00+01:00")))
    #expect(june21[.isha]?.iqama == (try Self.instant("2026-06-22T01:25:00+01:00")))

    let springForward = try #require(
      board.schedule.day(CivilDay(year: 2026, month: 3, day: 29)).day)
    #expect(springForward[.fajr]?.time == (try Self.instant("2026-03-29T05:17:00+01:00")))
    let fallBack = try #require(board.schedule.day(CivilDay(year: 2026, month: 10, day: 25)).day)
    #expect(fallBack[.fajr]?.time == (try Self.instant("2026-10-25T05:02:00Z")))
  }

  @Test func declaredJumuahIsAppPolicyOnFridaysOnly() throws {
    let board = try Board.load(.muis)
    let thursday = try #require(board.schedule.day(CivilDay(year: 2026, month: 10, day: 15)).day)
    let friday = try #require(board.schedule.day(CivilDay(year: 2026, month: 10, day: 16)).day)
    #expect(thursday[.dhuhr]?.observance == .ordinary)
    #expect(friday[.dhuhr]?.observance == .jumuah)
    #expect(friday.events.filter { $0.observance == .jumuah }.count == 1)
    // The app's rules: Jumu'ah 30 minutes after Zohor, the Dhuhr rule 10 minutes.
    #expect(friday[.dhuhr]?.iqama == (try Self.instant("2026-10-16T13:22:00+08:00")))
    #expect(thursday[.dhuhr]?.iqama == (try Self.instant("2026-10-15T13:02:00+08:00")))
    // Days the timetable doesn't publish stay unpublished.
    let source = DeclaredJumuahSource(timetable: try Board.timetable(.muis))
    #expect(
      source.prayerDay(CivilDay(year: 2027, month: 1, day: 1), at: board.location)
        == .unavailable(.noPublishedData))
  }
}
