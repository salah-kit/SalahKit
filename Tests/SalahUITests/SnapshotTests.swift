#if canImport(SwiftUI) && os(macOS)
  import Foundation
  import SalahCore
  import SalahFixtures
  import SalahUIPreviews
  import SwiftUI
  import Testing

  @testable import SalahUI

  /// The default styles at every SalahFixtures moment, left to right in English and right to
  /// left in Arabic: the galleries the previews show, rendered and compared with references.
  ///
  /// Live countdowns are frozen at their start, so an image shows the time left at the moment
  /// whatever the clock says when the test runs.
  @Suite("Snapshots of the default styles")
  @MainActor
  struct SnapshotTests {
    nonisolated enum Direction: String, CaseIterable, Sendable {
      case leftToRight = "en"
      case rightToLeft = "ar"

      var locale: Locale {
        self == .leftToRight ? GalleryLocale.english : GalleryLocale.arabic
      }

      var layout: LayoutDirection {
        self == .leftToRight ? .leftToRight : .rightToLeft
      }
    }

    nonisolated static let moments = PrayerFixtures.moments.map(\.id)

    func gallery(_ moment: PrayerFixtures.Moment, _ direction: Direction) -> some View {
      MomentGallery(moment: moment, locale: direction.locale)
        .environment(\.layoutDirection, direction.layout)
        .environment(\.prayerTimerFrozen, true)
    }

    @Test("every moment", arguments: moments, Direction.allCases)
    func moment(_ id: String, _ direction: Direction) throws {
      let moment = try #require(PrayerFixtures.moments.first { $0.id == id })
      Snapshot.check(gallery(moment, direction), named: "\(id)-\(direction.rawValue)")
    }

    @Test(
      "days with times after midnight and a declared Jumu'ah",
      arguments: ["reykjavikJune", "friday"], Direction.allCases)
    func place(_ id: String, _ direction: Direction) throws {
      let place = try #require(PrayerFixtures.places.first { $0.id == id })
      Snapshot.check(
        PlaceGallery(place: place, locale: direction.locale)
          .environment(\.layoutDirection, direction.layout),
        named: "\(id)-\(direction.rawValue)")
    }

    /// A device set to Los Angeles or Tokyo shows Makkah's schedule on Makkah's clock: the
    /// image is the reference of the device in Makkah's own zone.
    @Test(
      "a device time zone other than the schedule's changes nothing",
      arguments: ["America/Los_Angeles", "Asia/Tokyo"])
    func deviceTimeZone(_ identifier: String) throws {
      let zone = try #require(TimeZone(identifier: identifier))
      let moment = PrayerFixtures.approaching
      Snapshot.check(
        gallery(moment, .leftToRight).environment(\.timeZone, zone), named: "approaching-en",
        recordable: false)
    }
  }
#endif
