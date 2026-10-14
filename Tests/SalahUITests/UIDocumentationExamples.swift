import Foundation
import SalahCore
import SalahFixtures
import Testing

@testable import SalahUI

#if canImport(SwiftUI)
  import SwiftUI
#endif

// The Swift code of the article "Styling rows and cards" and of README.md's SalahUI blocks,
// compiled and run against the public API. `UIDocumentationTests` checks that every such block
// appears here line for line, so an edit to a document that isn't mirrored here fails the tests.

@Suite("UI documentation examples")
struct UIDocumentationExamples {
  @Test func accentPassesTheContrastCheck() {
    let accent = ThemeColor(red: 0.04, green: 0.52, blue: 1.00)
    let surface = ThemeColor(red: 0.075, green: 0.094, blue: 0.180)
    let alertRed = ThemeColor(red: 1.00, green: 0.27, blue: 0.23)
    let check = ContrastCheck()
    #expect(check.problems(foreground: accent, background: surface, reserved: [alertRed]).isEmpty)
  }
}

#if canImport(SwiftUI)
  struct TodayView: View {
    let schedule: PrayerSchedule
    let now: Date
    let names = PrayerNames(locale: Locale(identifier: "en"))

    var body: some View {
      let zone = schedule.location.timeZone
      let bound = CivilDay(containing: now, in: zone).adding(days: 2).start(in: zone)
      let state = schedule.state(at: now, through: bound).prayerState
      VStack {
        if let state {
          NextPrayerView(state: state, names: names, timeZone: zone)
        } else {
          Text("Prayer times aren't available right now")
        }
        if let day = schedule.day(containing: now).day {
          PrayerTimesList(day: day, state: state, names: names)
        }
      }
    }
  }

  struct LanternRow: PrayerRowStyle {
    func makeBody(configuration: Configuration) -> some View {
      HStack {
        configuration.name.font(.title3)
        Spacer()
        (configuration.time ?? Text(verbatim: "–")).monospacedDigit()
      }
      .padding(8)
      .background(
        configuration.status == .next(approaching: true) ? Color.orange.opacity(0.2) : .clear,
        in: Capsule())
    }
  }

  struct CardStyle: NextPrayerStyle {
    func makeBody(configuration: Configuration) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        if let justStarted = configuration.justStarted {
          justStarted.font(.caption).foregroundStyle(.secondary)
        }
        if let name = configuration.name, let time = configuration.time {
          HStack(alignment: .firstTextBaseline) {
            name.font(.title2.bold())
            Spacer()
            time.monospacedDigit()
          }
        } else {
          Text("The next prayer isn't known yet")
        }
        configuration.countdown?.font(.largeTitle).monospacedDigit()
      }
      .padding()
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
  }

  struct CircularStyle: NextPrayerStyle {
    func makeBody(configuration: Configuration) -> some View {
      VStack(spacing: 0) {
        configuration.abbreviation ?? Text(verbatim: "–")
        configuration.countdown?.font(.caption2).monospacedDigit()
      }
    }
  }

  /// The article's view fragments, put together so they compile and render.
  struct ArticleFragments: View {
    let day: PrayerDay
    let state: PrayerState
    let names: PrayerNames
    let zone: TimeZone

    var body: some View {
      VStack {
        // The day's times with your row style. Unknown times get no status and no countdown.
        PrayerTimesList(day: day, state: state, names: names)
          .prayerRowStyle(LanternRow())
        NextPrayerView(state: state, names: names, timeZone: zone, countdown: .staticText)
        arabic
        NextPrayerView(state: state, names: names, timeZone: zone)
          .nextPrayerStyle(CircularStyle())
      }
    }

    @ViewBuilder var arabic: some View {
      let locale = PrayerLocale.resolved("ar")
      NextPrayerView(state: state, names: PrayerNames(locale: locale), timeZone: zone)
        .environment(\.locale, locale)
    }
  }

  #Preview("After the last published day") {
    let moment = PrayerFixtures.afterLastPublishedDay
    if let state = moment.state().prayerState {
      NextPrayerView(
        state: state, names: PrayerNames(locale: .current), timeZone: moment.place.location.timeZone
      )
      .nextPrayerStyle(CardStyle())
    }
  }
#endif

#if canImport(SwiftUI) && os(macOS)
  extension UIDocumentationExamples {
    @MainActor
    @Test("the article's views render at every moment")
    func articleViewsRender() throws {
      for moment in PrayerFixtures.moments {
        let today = TodayView(schedule: moment.schedule, now: moment.date)
        #expect(ImageRenderer(content: today.frame(width: 390)).cgImage != nil)
      }
      let moment = PrayerFixtures.approaching
      let state = try #require(moment.state().prayerState)
      let day = try #require(moment.schedule.day(containing: moment.date).day)
      let fragments = ArticleFragments(
        day: day, state: state, names: PrayerNames(locale: Locale(identifier: "en")),
        zone: moment.place.location.timeZone)
      #expect(ImageRenderer(content: fragments.frame(width: 390)).cgImage != nil)
      let unknown = try #require(PrayerFixtures.afterLastPublishedDay.state().prayerState)
      let card = NextPrayerView(
        state: unknown, names: PrayerNames(locale: .current),
        timeZone: PrayerFixtures.incomplete.location.timeZone
      )
      .nextPrayerStyle(CardStyle())
      #expect(ImageRenderer(content: card.frame(width: 390)).cgImage != nil)
    }
  }
#endif
