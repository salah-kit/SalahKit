import Foundation
import SalahCore
import SalahFixtures
import Testing

/// What is in the catalog of places and how each place is shaped.
@Suite struct PlaceCatalogTests {
  @Test func everyPlaceIsListedOnceInOrder() {
    let ids = [
      "makkah", "londonSummer", "reykjavikJune", "newYorkDSTChange", "jakarta", "friday",
      "ramadan", "incomplete",
    ]
    #expect(PrayerFixtures.places.map(\.id) == ids)
    #expect(Set(PrayerFixtures.places.map(\.id)).count == ids.count)
    #expect(Set(PrayerFixtures.places).count == ids.count)
    #expect(
      PrayerFixtures.places == [
        PrayerFixtures.makkah, PrayerFixtures.londonSummer, PrayerFixtures.reykjavikJune,
        PrayerFixtures.newYorkDSTChange, PrayerFixtures.jakarta, PrayerFixtures.friday,
        PrayerFixtures.ramadan, PrayerFixtures.incomplete,
      ])
    #expect(PlaceShape.all.map(\.id) == ids)
  }

  @Test(arguments: PlaceShape.all)
  func locationAndFeaturedDay(_ shape: PlaceShape) throws {
    let place = try fixturePlace(shape.id)
    let expected = PrayerLocation(
      latitude: shape.latitude, longitude: shape.longitude, timeZone: try timeZone(shape.zone),
      countryCode: shape.country, name: shape.name)
    #expect(place.location == expected)
    #expect(place.location.timeZone.identifier == shape.zone)
    #expect(place.featuredDay == (try civilDay(shape.featuredDay)))
    #expect(place.featuredDay.isValid)
  }

  @Test(arguments: PlaceShape.all)
  func timetableExpectsAllSixKindsAndPublishesItsOwnIqama(_ shape: PlaceShape) throws {
    let place = try fixturePlace(shape.id)
    #expect(place.source.expectedKinds == Set(PrayerKind.allCases))
    #expect(place.source.wallTimeResolution == WallTimeResolution())
    // Published iqama sits in the rows, so no place needs rules.
    #expect(place.iqama == nil)
    #expect(place.schedule.iqama == nil)
    #expect(place.schedule.location == place.location)
  }

  @Test(arguments: PlaceShape.all)
  func rowsCoverTheFeaturedDayAndTwoDaysEitherSide(_ shape: PlaceShape) throws {
    let place = try fixturePlace(shape.id)
    let days = (-2...2).map { place.featuredDay.adding(days: $0) }
    // `incomplete` leaves out its featured day on purpose.
    let published = shape.id == "incomplete" ? days.filter { $0 != place.featuredDay } : days
    #expect(place.source.rows.map(\.day) == published)
    #expect(place.source.firstDay == days.first)
    #expect(place.source.lastDay == days.last)
  }

  @Test(arguments: PlaceShape.all)
  func everyPublishedDayIsAValidCompleteDayExceptTheDeliberateGaps(_ shape: PlaceShape) throws {
    let place = try fixturePlace(shape.id)
    let zone = place.location.timeZone
    for offset in -2...2 {
      let owner = place.featuredDay.adding(days: offset)
      let availability = place.schedule.day(owner)
      if shape.id == "incomplete", owner == place.featuredDay {
        #expect(availability == .unavailable(.noPublishedData), "\(owner)")
        continue
      }
      let day = try #require(availability.day, "\(shape.id) \(owner)")
      #expect(day.day == owner)
      #expect(day.timeZone == zone)
      #expect(day.events.allSatisfy { $0.scheduleDay == owner })
      let expected: DayCoverage =
        shape.id == "incomplete" && offset == -1
        ? .partial(missing: [.isha: .noPublishedData])
        : .complete
      #expect(availability.coverage == expected, "\(shape.id) \(owner)")
      // Times strictly increase in canonical order, and each falls on its owning day or the next.
      let kinds = day.events.map(\.kind)
      #expect(kinds == Array(PrayerKind.allCases.prefix(kinds.count)))
      #expect(zip(day.events, day.events.dropFirst()).allSatisfy { $0.time < $1.time })
      let span = owner.start(in: zone)..<owner.adding(days: 2).start(in: zone)
      #expect(day.events.allSatisfy { span.contains($0.time) })
    }
  }

  @Test(arguments: SpotCheck.all)
  func theTimesOfTheKeyDaysAreExact(_ check: SpotCheck) throws {
    let place = try fixturePlace(check.place)
    let day = try #require(place.schedule.day(try civilDay(check.day)).day)
    #expect(day.events.map(\.time) == (try check.times.map(instant)))
    #expect(day.events.map(\.kind) == Array(PrayerKind.allCases.prefix(check.times.count)))
  }

  @Test func theFixturesAreUsableFromNonisolatedCode() async throws {
    let summary = await Task.detached {
      let places = PrayerFixtures.places
      let moments = PrayerFixtures.moments
      let state = PrayerFixtures.beforeFajr.state()
      let day = PrayerFixtures.friday.schedule.day(PrayerFixtures.friday.featuredDay)
      return [
        "\(places.count)", "\(moments.count)",
        "\(state.prayerState?.nextPrayer?.kind.rawValue ?? "")",
        "\(day.day?[.dhuhr]?.observance.rawValue ?? "")",
      ]
    }.value
    #expect(summary == ["8", "7", "fajr", "jumuah"])
  }
}
