import Foundation
import SalahCore
import SalahFixtures
import Testing

/// The case that each place demonstrates, asserted on the schedule it gives.
@Suite struct PlaceCaseTests {
  // MARK: Late Isha, events after midnight and a clock change

  @Test func londonHasALateIshaBeforeMidnightInSummerTime() throws {
    let place = try fixturePlace("londonSummer")
    let zone = place.location.timeZone
    let day = try #require(place.schedule.day(place.featuredDay).day)
    let isha = try #require(day[.isha])
    #expect(isha.time == (try instant("2026-06-21T22:42:00+01:00")))
    #expect(isha.time == (try instant("2026-06-21T21:42:00Z")))
    #expect(zone.secondsFromGMT(for: isha.time) == 3_600)
    #expect(CivilDay(containing: isha.time, in: zone) == place.featuredDay)
    #expect(
      isha.time.timeIntervalSince(place.featuredDay.start(in: zone)) > TimeInterval(22 * 3_600))
    #expect(place.featuredDay.interval(in: zone).duration == TimeInterval(24 * 3_600))
  }

  @Test func reykjavikMaghribAndIshaAfterMidnightBelongToThePreviousDay() throws {
    let place = try fixturePlace("reykjavikJune")
    let zone = place.location.timeZone
    let next = place.featuredDay.adding(days: 1)
    let day = try #require(place.schedule.day(place.featuredDay).day)
    let maghrib = try #require(day[.maghrib])
    let isha = try #require(day[.isha])

    #expect(maghrib.time == (try instant("2026-06-22T00:04:00+00:00")))
    #expect(isha.time == (try instant("2026-06-22T00:29:00+00:00")))
    for event in [maghrib, isha] {
      #expect(event.scheduleDay == place.featuredDay)
      #expect(CivilDay(containing: event.time, in: zone) == next)
    }
    #expect(
      place.source.rows.first { $0.day == place.featuredDay }?.times[.isha]
        == .local(WallClockTime(hour: 0, minute: 29, dayOffset: 1)))

    // After midnight the civil date is the next day, whose row starts with its own Fajr.
    let overnight = place.schedule.day(containing: isha.time)
    #expect(overnight.day?.day == next)
    let fajr = try #require(overnight.day?[.fajr])
    #expect(fajr.time == (try instant("2026-06-22T02:31:00+00:00")))
    #expect(fajr.time.timeIntervalSince(isha.time) == TimeInterval(2 * 3_600 + 2 * 60))

    // An event after midnight appears once, with its owning day, between the two days' events.
    let events = place.schedule.events(
      from: try instant("2026-06-21T23:00:00+00:00"),
      through: try instant("2026-06-22T03:00:00+00:00"))
    #expect(
      events.events.map { "\($0.scheduleDay)/\($0.kind.rawValue)" } == [
        "2026-06-21/maghrib", "2026-06-21/isha", "2026-06-22/fajr", "2026-06-22/sunrise",
      ])
    #expect(events.coverage.isComplete)
  }

  @Test func newYorkSpringForwardDayHasTwentyThreeHours() throws {
    let place = try fixturePlace("newYorkDSTChange")
    let zone = place.location.timeZone
    let previous = try #require(place.schedule.day(place.featuredDay.adding(days: -1)).day)
    let day = try #require(place.schedule.day(place.featuredDay).day)
    #expect(place.featuredDay.interval(in: zone).duration == TimeInterval(23 * 3_600))

    // Every time of the featured day is in daylight time, the night before in standard time.
    #expect(day.events.allSatisfy { zone.secondsFromGMT(for: $0.time) == -4 * 3_600 })
    #expect(previous.events.allSatisfy { zone.secondsFromGMT(for: $0.time) == -5 * 3_600 })

    let isha = try #require(previous[.isha])
    let fajr = try #require(day[.fajr])
    #expect(isha.time == (try instant("2026-03-07T19:09:00-05:00")))
    #expect(fajr.time == (try instant("2026-03-08T06:04:00-04:00")))
    // The wall clocks differ by 10 h 55 min, but 9 h 55 min elapse between them.
    #expect(fajr.time.timeIntervalSince(isha.time) == TimeInterval(9 * 3_600 + 55 * 60))
  }

  // MARK: Jumu'ah, Ramadan and incomplete coverage

  @Test func fridayDeclaresJumuahWithItsOwnIqama() throws {
    let place = try fixturePlace("friday")
    let zone = place.location.timeZone
    #expect(place.featuredDay.weekday == 6)
    let day = try #require(place.schedule.day(place.featuredDay).day)
    #expect(day.isFriday)

    let dhuhr = try #require(day[.dhuhr])
    #expect(dhuhr.observance == .jumuah)
    #expect(dhuhr.time == (try instant("2026-10-16T11:40:00+07:00")))
    #expect(dhuhr.iqama == (try instant("2026-10-16T12:15:00+07:00")))
    #expect(
      dhuhr.iqama == place.featuredDay.start(in: zone).addingTimeInterval(12 * 3_600 + 15 * 60))
    #expect(day.events.filter { $0.kind != .dhuhr }.allSatisfy { $0.observance == .ordinary })

    // The other days of the same timetable are ordinary, with the usual ten-minute iqama.
    for offset in [-2, -1, 1, 2] {
      let other = try #require(place.schedule.day(place.featuredDay.adding(days: offset)).day)
      let ordinary = try #require(other[.dhuhr])
      #expect(ordinary.observance == .ordinary)
      #expect(ordinary.iqama == ordinary.time.addingTimeInterval(600))
    }
  }

  @Test func onlyTheFridayPlaceDeclaresJumuah() throws {
    var declared: [String] = []
    for place in PrayerFixtures.places {
      for row in place.source.rows {
        let day = try #require(place.schedule.day(row.day).day)
        for event in day.events where event.observance == .jumuah {
          declared.append("\(place.id)/\(event.scheduleDay)/\(event.kind.rawValue)")
        }
      }
    }
    #expect(declared == ["friday/2026-10-16/dhuhr"])
  }

  @Test(arguments: [
    ("ramadan", "2026-02-27"), ("londonSummer", "2026-06-19"), ("reykjavikJune", "2026-06-19"),
    ("newYorkDSTChange", "2026-03-06"), ("incomplete", "2026-11-13"),
  ])
  func otherFridaysAreOrdinary(_ placeID: String, _ dayText: String) throws {
    let place = try fixturePlace(placeID)
    let owner = try civilDay(dayText)
    #expect(owner.weekday == 6)
    let day = try #require(place.schedule.day(owner).day)
    #expect(day.isFriday)
    #expect(day.events.allSatisfy { $0.observance == .ordinary })
    #expect(day[.dhuhr]?.observance == .ordinary)
  }

  @Test func ramadanFeaturedDayIsTheTwelfthOfRamadan() throws {
    let place = try fixturePlace("ramadan")
    let zone = place.location.timeZone
    let hijri = HijriDateFormat(locale: Locale(identifier: "en"), timeZone: zone)
    let noon = place.featuredDay.start(in: zone).addingTimeInterval(12 * 3_600)
    #expect(
      hijri.components(of: noon) == HijriDateFormat.Components(year: 1_447, month: 9, day: 12))

    // The rows are 10 to 14 Ramadan, and Isha is two hours after Maghrib on each.
    for (offset, hijriDay) in zip(-2...2, 10...14) {
      let owner = place.featuredDay.adding(days: offset)
      let date = owner.start(in: zone).addingTimeInterval(12 * 3_600)
      #expect(
        hijri.components(of: date)
          == HijriDateFormat.Components(year: 1_447, month: 9, day: hijriDay))
      let day = try #require(place.schedule.day(owner).day)
      let maghrib = try #require(day[.maghrib])
      let isha = try #require(day[.isha])
      #expect(isha.time.timeIntervalSince(maghrib.time) == TimeInterval(120 * 60))
      #expect(day.events.allSatisfy { $0.iqama == nil })
    }
  }

  @Test func incompleteHasAPartialRowAMissingDayAndALastPublishedDay() throws {
    let place = try fixturePlace("incomplete")
    let schedule = place.schedule

    #expect(schedule.day(try civilDay("2026-11-09")).coverage == .complete)

    let partial = schedule.day(try civilDay("2026-11-10"))
    #expect(partial.coverage == .partial(missing: [.isha: .noPublishedData]))
    #expect(partial.day?.events.map(\.kind) == [.fajr, .sunrise, .dhuhr, .asr, .maghrib])

    #expect(schedule.day(try civilDay("2026-11-11")) == .unavailable(.noPublishedData))
    #expect(schedule.day(try civilDay("2026-11-12")).coverage == .complete)
    #expect(schedule.day(try civilDay("2026-11-13")).coverage == .complete)

    #expect(place.source.lastDay == (try civilDay("2026-11-13")))
    #expect(schedule.day(try civilDay("2026-11-14")) == .unavailable(.noPublishedData))
    #expect(schedule.day(try civilDay("2026-11-15")) == .unavailable(.noPublishedData))
  }

  // MARK: Iqama

  @Test(arguments: [
    ("makkah", [PrayerKind.fajr: 25, .dhuhr: 20, .asr: 20, .maghrib: 10, .isha: 20]),
    ("jakarta", [PrayerKind.fajr: 10, .dhuhr: 10, .asr: 10, .maghrib: 10, .isha: 10]),
  ])
  func publishedIqamaFollowsEachPrayerByAFixedNumberOfMinutes(
    _ placeID: String, _ minutes: [PrayerKind: Int]
  ) throws {
    let place = try fixturePlace(placeID)
    for row in place.source.rows {
      let day = try #require(place.schedule.day(row.day).day)
      for event in day.events {
        let expected = minutes[event.kind].map { event.time.addingTimeInterval(Double($0) * 60) }
        #expect(event.iqama == expected, "\(placeID) \(row.day) \(event.kind)")
      }
    }
  }

  @Test(arguments: ["londonSummer", "reykjavikJune", "newYorkDSTChange", "ramadan", "incomplete"])
  func otherPlacesPublishNoIqama(_ placeID: String) throws {
    let place = try fixturePlace(placeID)
    for row in place.source.rows {
      #expect(row.iqama.isEmpty)
      let day = try #require(place.schedule.day(row.day).day)
      #expect(day.events.allSatisfy { $0.iqama == nil })
    }
  }
}
