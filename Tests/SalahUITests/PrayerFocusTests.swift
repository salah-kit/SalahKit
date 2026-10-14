import Foundation
import SalahCore
import SalahFixtures
import Testing

@testable import SalahUI

@Suite("Prayer focus")
struct PrayerFocusTests {
  let names = PrayerNames(locale: Locale(identifier: "en"))
  let locale = Locale(identifier: "en_GB")

  @Test("selection preserves the default and can give the just-started prayer precedence")
  func justStarted() throws {
    let moment = PrayerFixtures.justStarted
    let state = try #require(moment.state().prayerState)
    let started = try #require(state.justStarted)
    #expect(PrayerFocus(state: state) == state.nextPrayer.map(PrayerFocus.countdown))
    for selection in [PrayerFocus.Selection.justStartedOrNextPrayer, .justStartedOrNextEvent] {
      let content = NextPrayerContent(
        state: state, names: names, timeZone: moment.place.location.timeZone, locale: locale,
        selection: selection)
      #expect(content.focus == .countUp(started))
      #expect(content.name == "Dhuhr")
      #expect(content.abbreviation == "D")
      #expect(content.time == DisplayContentTests.clock("13:07"))
      #expect(content.countdown == nil)
      #expect(content.countUp?.seconds == moment.date.timeIntervalSince(started.time))
      #expect(content.countUp?.compactText(locale: locale) == "4m")
    }
  }

  @Test("next-event selection includes sunrise but never counts it up")
  func sunrise() throws {
    let place = PrayerFixtures.beforeFajr.place
    let schedule = place.schedule
    let day = try #require(schedule.day(place.featuredDay).day)
    let sunrise = try #require(day[.sunrise])
    let date = sunrise.time - 60
    let state = try #require(schedule.state(at: date, through: date + 86_400).prayerState)
    #expect(PrayerFocus(state: state)?.event.kind == .dhuhr)
    for selection in [PrayerFocus.Selection.nextEvent, .justStartedOrNextEvent] {
      let content = NextPrayerContent(
        state: state, names: names, timeZone: place.location.timeZone, locale: locale,
        selection: selection)
      #expect(content.focus == .countdown(sunrise))
      #expect(content.name == "Sunrise")
      #expect(content.countdown?.seconds == 60)
      #expect(content.countUp == nil)
    }
    let atSunrise = try #require(
      schedule.state(at: sunrise.time, through: sunrise.time + 86_400).prayerState)
    #expect(PrayerFocus(state: atSunrise, selection: .justStartedOrNextEvent)?.isCountUp == false)
    #expect(PrayerFocus(state: atSunrise, selection: .justStartedOrNextEvent)?.event.kind == .dhuhr)
  }

  @Test("the count-up ends exactly at Core's window boundary")
  func windowEnd() throws {
    let moment = PrayerFixtures.justStarted
    let initial = try #require(moment.state().prayerState)
    let started = try #require(initial.justStarted)
    let policy = StatePolicy(justStarted: .fixed(.seconds(900)))
    let boundary = started.time + 900
    let before = try #require(
      moment.schedule.state(at: boundary - 1, through: boundary + 86_400, policy: policy)
        .prayerState)
    let after = try #require(
      moment.schedule.state(at: boundary, through: boundary + 86_400, policy: policy).prayerState)
    #expect(PrayerFocus(state: before, selection: .justStartedOrNextEvent) == .countUp(started))
    #expect(PrayerFocus(state: after, selection: .justStartedOrNextEvent)?.isCountUp == false)
  }

  @Test("a finished timetable never invents a focus or timer")
  func unknown() throws {
    let moment = PrayerFixtures.afterLastPublishedDay
    let state = try #require(moment.state().prayerState)
    for selection in [
      PrayerFocus.Selection.nextPrayer, .nextEvent, .justStartedOrNextPrayer,
      .justStartedOrNextEvent,
    ] {
      let content = NextPrayerContent(
        state: state, names: names, timeZone: moment.place.location.timeZone, locale: locale,
        selection: selection)
      #expect(content.focus == nil)
      #expect(content.name == nil && content.time == nil)
      #expect(content.countdown == nil && content.countUp == nil)
    }
  }
}

#if canImport(SwiftUI) && os(macOS)
  import SwiftUI

  /// Compare the public view's rendered configuration with independently specified text.
  @MainActor
  struct FocusProbeStyle: NextPrayerStyle {
    func makeBody(configuration: Configuration) -> some View {
      VStack {
        configuration.name
        configuration.time
        configuration.countUp ?? configuration.countdown
      }
    }
  }

  extension PrayerFocusTests {
    @Test("a frozen live count-up shows the elapsed interval")
    @MainActor
    func frozenLiveCountUp() throws {
      let moment = PrayerFixtures.justStarted
      let state = try #require(moment.state().prayerState)
      let actual = NextPrayerView(
        state: state, names: names, timeZone: moment.place.location.timeZone,
        selection: .justStartedOrNextEvent
      )
      .nextPrayerStyle(FocusProbeStyle())
      .environment(\.locale, locale)
      .environment(\.prayerTimerFrozen, true)
      let expected = VStack {
        Text(verbatim: "Dhuhr")
        Text(verbatim: DisplayContentTests.clock("13:07"))
        Text(verbatim: "4:00").monospacedDigit()
      }
      let image = try #require(Snapshot.render(actual, width: 200))
      let reference = try #require(Snapshot.render(expected, width: 200))
      if Snapshot.compare(image, reference) != nil {
        Snapshot.write(image, to: Snapshot.failures.appendingPathComponent("focus-live.png"))
      }
      #expect(Snapshot.compare(image, reference) == nil)
    }

    @Test("the public next-prayer view passes the selected count-up to its style")
    @MainActor
    func renderedCountUp() throws {
      let moment = PrayerFixtures.justStarted
      let state = try #require(moment.state().prayerState)
      let actual = NextPrayerView(
        state: state, names: names, timeZone: moment.place.location.timeZone,
        countdown: .staticText, selection: .justStartedOrNextEvent
      )
      .nextPrayerStyle(FocusProbeStyle())
      .environment(\.locale, locale)
      let expected = VStack {
        Text(verbatim: "Dhuhr")
        Text(verbatim: DisplayContentTests.clock("13:07"))
        Text(verbatim: "4m")
      }
      let image = try #require(Snapshot.render(actual, width: 200))
      let reference = try #require(Snapshot.render(expected, width: 200))
      #expect(Snapshot.compare(image, reference) == nil)
    }
  }
#endif
