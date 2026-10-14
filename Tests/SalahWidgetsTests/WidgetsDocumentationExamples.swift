import Foundation
import SalahCalculation
import SalahCore
import SalahFixtures
import SalahTimes
import SalahWidgets
import Testing

#if canImport(WidgetKit) && canImport(SwiftUI)
  import SalahUI
  import SwiftUI
  import WidgetKit
#endif

// The Swift code of the article "Building widget timelines without daily app launches" and of
// README.md's widget section, compiled and run against the public API only.
// `WidgetsDocumentationTests` checks that every such block appears here line for line, so an
// edit to a document that isn't mirrored here fails the tests.

// Compiled into the app and the widget extension, which both have the App Group capability.
struct PrayerSettings: Codable, Equatable, Sendable {
  var location: PrayerLocation
  var calculation: CalculationSettings
}

extension SharedValue where Value == PrayerSettings {
  static var prayers: Self {
    SharedValue(appGroup: "group.com.example.prayers", key: "settings.v1")
  }
}

// In the extension: two days of entries, ending with one that says the times ran out.
func prayerTimeline(from now: Date) throws -> PrayerTimeline? {
  guard let settings = SharedValue.prayers.load() else { return nil }
  let schedule = PrayerSchedule(
    source: CalculationSource(settings.calculation), location: settings.location)
  return try PrayerTimelineBuilder(schedule: schedule).timeline(from: now)
}

func saveForWidgets(_ settings: PrayerSettings) {
  do {
    try SharedValue.prayers.save(settings, reloading: ["prayers"])
  } catch {
    print("The widgets' settings weren't saved: \(error)")
  }
}

extension DarwinSignal {
  static let stopPlayback = DarwinSignal(name: "com.example.prayers.stop")
}

#if canImport(WidgetKit) && canImport(SwiftUI)
  struct PrayerEntry: TimelineEntry {
    enum Content {
      case setupRequired
      case timeline(PrayerTimelineState, timeZone: TimeZone)
    }

    var date: Date
    var content: Content
  }

  struct PrayerProvider: TimelineProvider {
    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
      guard let settings = SharedValue.prayers.load() else {
        let entry = PrayerEntry(date: .now, content: .setupRequired)
        return completion(Timeline(entries: [entry], policy: .never))
      }
      let zone = settings.location.timeZone
      let schedule = PrayerSchedule(
        source: CalculationSource(settings.calculation), location: settings.location)
      completion(
        PrayerTimelineBuilder(schedule: schedule).timeline(from: .now) { date, state in
          PrayerEntry(date: date, content: .timeline(state, timeZone: zone))
        })
    }

    func placeholder(in context: Context) -> PrayerEntry {
      PrayerEntry(date: .now, content: .setupRequired)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
      completion(placeholder(in: context))
    }
  }

  struct PrayerWidgetView: View {
    var entry: PrayerEntry

    var body: some View {
      switch entry.content {
      case .setupRequired:
        Text("Open the app to choose a place")
      case .timeline(.expired, _):
        Text("Open the app to refresh the prayer times")
      case .timeline(.schedule(.unavailable), _):
        Text("Prayer times aren't available for this place")
      case .timeline(.schedule(.available(let state, _)), let zone):
        NextPrayerView(state: state, names: PrayerNames(locale: .current), timeZone: zone)
      }
    }
  }
#endif

/// A player for the signal example.
@MainActor
final class ExamplePlayer {
  private(set) var stops = 0
  func stop() { stops += 1 }
}

@Suite("Widget documentation examples", .serialized)
struct WidgetsDocumentationExamples {
  static let makkah = PrayerFixtures.makkah.location
  let schedule = PrayerSchedule(
    source: CalculationSource(CalculationSettings(method: .ummAlQura)), location: makkah)
  let now = PrayerFixtures.approaching.date

  @Test func timelineEndsWithItsExpiry() throws {
    let timeline = try PrayerTimelineBuilder(schedule: schedule).timeline(from: now)
    #expect(timeline.entries.last?.state == .expired(knownThrough: timeline.validUntil))
    #expect(timeline.reloadDate < timeline.validUntil)
  }

  @Test("the shared settings round-trip and gate reloads")
  func sharedSettings() throws {
    defer {
      UserDefaults(suiteName: "group.com.example.prayers")?.removePersistentDomain(
        forName: "group.com.example.prayers")
    }
    let settings = PrayerSettings(
      location: Self.makkah, calculation: CalculationSettings(method: .ummAlQura))
    #expect(try prayerTimeline(from: now) == nil)
    saveForWidgets(settings)
    #expect(SharedValue.prayers.load() == settings)
    #expect(try SharedValue.prayers.save(settings, reloading: ["prayers"]) == false)
    let timeline = try #require(try prayerTimeline(from: now))
    #expect(timeline.entries.first?.state.prayerState?.nextPrayer?.kind == .maghrib)
    #expect(timeline.entries.last?.state == .expired(knownThrough: timeline.validUntil))
  }

  @Test("the provider's schedule gives a 48-hour timeline that ends with its expiry")
  func providerSchedule() throws {
    let settings = PrayerSettings(
      location: Self.makkah, calculation: CalculationSettings(method: .ummAlQura))
    let schedule = PrayerSchedule(
      source: CalculationSource(settings.calculation), location: settings.location)
    let timeline = try PrayerTimelineBuilder(schedule: schedule).timeline(from: now)
    #expect(timeline.entries.first?.state.prayerState?.nextPrayer?.kind == .maghrib)
    #expect(timeline.validUntil == now.addingTimeInterval(48 * 3_600))
  }

  #if canImport(notify)
    @MainActor
    @Test("the stop signal reaches the observer")
    func signal() async {
      let player = ExamplePlayer()
      // In the widget's App Intent:
      DarwinSignal.stopPlayback.post()

      // In the app, on the main actor. Keep the observation for as long as you observe:
      let observation = DarwinSignal.stopPlayback.observe { player.stop() }
      DarwinSignal.stopPlayback.post()
      for _ in 0..<500 where player.stops == 0 {
        try? await Task.sleep(for: .milliseconds(10))
      }
      #expect(player.stops == 1)
      observation.cancel()
    }
  #endif

  #if canImport(WidgetKit) && canImport(SwiftUI) && os(macOS)
    @MainActor
    @Test("the widget view renders every kind of entry")
    func widgetView() throws {
      let zone = Self.makkah.timeZone
      let timeline = try PrayerTimelineBuilder(schedule: schedule).timeline(from: now)
      let contents: [PrayerEntry.Content] = [
        .setupRequired,
        .timeline(timeline.entries[0].state, timeZone: zone),
        .timeline(.schedule(PrayerFixtures.missingDay.state()), timeZone: zone),
        .timeline(.expired(knownThrough: timeline.validUntil), timeZone: zone),
      ]
      for content in contents {
        let renderer = ImageRenderer(
          content: PrayerWidgetView(entry: PrayerEntry(date: now, content: content)).frame(
            width: 200))
        #expect(renderer.cgImage != nil)
      }
    }
  #endif
}
