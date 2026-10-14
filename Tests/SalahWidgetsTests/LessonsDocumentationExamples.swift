import Foundation
import SalahCalculation
import SalahCore
import SalahWidgets
import Testing

#if canImport(AppIntents)
  import AppIntents
#endif

// The Swift code of the article "Lessons from Salah", compiled and run against the public API
// only. `WidgetsDocumentationTests` checks that every block of the article appears here or in
// WidgetsDocumentationExamples.swift, line for line.

nonisolated struct NowPlaying: Codable, Equatable, Sendable {
  var prayer: PrayerKind
  var startedAt: Date
}

nonisolated extension SharedValue where Value == NowPlaying {
  static var nowPlaying: Self {
    SharedValue(appGroup: "group.com.example.prayers", key: "nowPlaying.v1")
  }
}

#if canImport(AppIntents) && canImport(notify)
  nonisolated struct StopPlaybackIntent: AppIntent {
    static var title: LocalizedStringResource { "Stop" }

    func perform() async throws -> some IntentResult {
      _ = try? SharedValue.nowPlaying.save(nil, reloading: ["prayers"])
      DarwinSignal.stopPlayback.post()
      return .result()
    }
  }

  /// The app's player in the article's example: it plays until stopped.
  @MainActor
  final class LessonsPlayer {
    private(set) var nowPlaying: NowPlaying? = NowPlaying(prayer: .asr, startedAt: Date())
    func stop() { nowPlaying = nil }
  }

  /// The app's side of the article's example.
  @MainActor
  final class LessonsApp {
    var stopObservation: DarwinSignal.Observation?

    func start(player: LessonsPlayer) {
      // In the app, on the main actor, for as long as it runs:
      stopObservation = DarwinSignal.stopPlayback.observe {
        player.stop()
        _ = try? SharedValue.nowPlaying.save(player.nowPlaying, reloading: ["prayers"])
      }
    }
  }
#endif

// The same serialized suite as the other documentation examples: they share the example's App
// Group.
extension WidgetsDocumentationExamples {
  #if canImport(AppIntents) && canImport(notify)
    @MainActor
    @Test("the stop intent's code stops the app, which republishes what it plays")
    func lessonsStop() async throws {
      let player = LessonsPlayer()
      try SharedValue.nowPlaying.save(player.nowPlaying)
      let app = LessonsApp()
      app.start(player: player)
      defer { app.stopObservation?.cancel() }

      _ = try await StopPlaybackIntent().perform()
      #expect(SharedValue.nowPlaying.load() == nil)
      for _ in 0..<500 where player.nowPlaying != nil {
        try? await Task.sleep(for: .milliseconds(10))
      }
      #expect(player.nowPlaying == nil)
      #expect(SharedValue.nowPlaying.load() == nil)
    }

    @MainActor
    @Test("the app stops on the signal alone, and its republish clears a value left behind")
    func lessonsSignalAlone() async throws {
      let player = LessonsPlayer()
      try SharedValue.nowPlaying.save(player.nowPlaying)
      let app = LessonsApp()
      app.start(player: player)
      defer { app.stopObservation?.cancel() }

      DarwinSignal.stopPlayback.post()
      for _ in 0..<500 where player.nowPlaying != nil {
        try? await Task.sleep(for: .milliseconds(10))
      }
      #expect(player.nowPlaying == nil)
      #expect(SharedValue.nowPlaying.load() == nil)
    }
  #endif

  @Test("saving unchanged settings again reloads nothing")
  func lessonsReloadGating() throws {
    let settings = PrayerSettings(
      location: Self.makkah, calculation: CalculationSettings(method: .ummAlQura))
    try SharedValue.prayers.save(nil)
    defer { _ = try? SharedValue.prayers.save(nil) }
    let changed = try SharedValue.prayers.save(settings, reloading: ["prayers"])
    #expect(changed)
    #expect(try SharedValue.prayers.save(settings, reloading: ["prayers"]) == false)
  }

  @Test("the resolved locale keeps Arabic digits for durations and names")
  func lessonsDigits() {
    let locale = PrayerLocale.resolved("ar")
    let countdown = PrayerDurationFormat.string(720, locale: locale)  // "١٢د"
    let isha = PrayerNames(locale: locale).name(of: .isha)  // "العشاء"
    #expect(countdown == "١٢د")
    #expect(isha == "العشاء")
  }
}
