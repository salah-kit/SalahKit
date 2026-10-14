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

    /// SwiftUI's time zone doesn't change the times: with the environment set to Los Angeles or
    /// Tokyo, Makkah's schedule still reads Makkah's clock, the reference image.
    ///
    /// The device's own zone is checked by running the whole suite in a process whose zone is
    /// another one: CI runs `TZ=Pacific/Kiritimati swift test --filter SnapshotTests` (UTC+14),
    /// and every image must still equal its reference.
    @Test(
      "SwiftUI's time zone doesn't change the times",
      arguments: ["America/Los_Angeles", "Asia/Tokyo"])
    func environmentTimeZone(_ identifier: String) throws {
      let zone = try #require(TimeZone(identifier: identifier))
      let moment = PrayerFixtures.approaching
      Snapshot.check(
        gallery(moment, .leftToRight).environment(\.timeZone, zone), named: "approaching-en",
        recordable: false)
    }
  }
#endif
