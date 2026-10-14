#if canImport(SwiftUI) && os(macOS)
  import Foundation
  import SalahCore
  import SalahFixtures
  import SwiftUI
  import Testing

  @testable import SalahUI

  /// The plain styles in narrow spaces, such as a small widget, a watch complication or large
  /// text: a time or a countdown must never wrap in the middle, where "4:14:00" could read as
  /// "4:14:0". Rows keep their height, and the next-prayer view grows no taller.
  @Suite("Narrow layouts")
  @MainActor
  struct NarrowLayoutTests {
    let moment = PrayerFixtures.justStarted
    let names = PrayerNames(locale: Locale(identifier: "en"))

    func height(_ view: some View, width: CGFloat) throws -> Int {
      let renderer = ImageRenderer(
        content: view.frame(width: width).environment(\.prayerTimerFrozen, true))
      renderer.scale = 1
      renderer.proposedSize = ProposedViewSize(width: width, height: nil)
      return try #require(renderer.cgImage).height
    }

    @Test("list rows stay one line high at 140 points")
    func listRows() throws {
      let state = try #require(moment.state().prayerState)
      let day = try #require(moment.schedule.day(containing: moment.date).day)
      let list = PrayerTimesList(day: day, state: state, names: names)
        .environment(\.locale, Locale(identifier: "en_US"))
      #expect(try height(list, width: 140) == height(list, width: 390))
    }

    @Test("the next prayer's lines don't wrap at 56 points")
    func nextPrayer() throws {
      let state = try #require(moment.state().prayerState)
      let view = NextPrayerView(
        state: state, names: names, timeZone: moment.place.location.timeZone
      )
      .environment(\.locale, Locale(identifier: "en_US"))
      #expect(try height(view, width: 56) <= height(view, width: 390))
    }
  }
#endif
