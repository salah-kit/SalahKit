import AppIntents
import Foundation
import SalahWidgets

/// The widget's Stop button.
///
/// WidgetKit runs `perform()` in the widget extension's process, which can't reach the app's
/// audio. It clears the stored ``NowPlaying``, so the widget redraws without the button at once,
/// and posts the stop signal, which the running app acts on: it stops the tone and publishes
/// what it plays again, which confirms the stop or corrects the widget (`LiveState` in the app).
///
/// The stop harness runs this same `perform()` in a separate process, to prove the round trip
/// against the running app without a tap on a desktop widget.
nonisolated struct StopPlaybackIntent: AppIntent {
  static var title: LocalizedStringResource { "Stop the tone" }
  static var description: IntentDescription {
    IntentDescription("Stops the tone MenuBar is playing.")
  }
  /// Only the widget's button runs it; Shortcuts and Spotlight don't offer it.
  static var isDiscoverable: Bool { false }

  func perform() async throws -> some IntentResult {
    StopRequest.send()
    return .result()
  }
}

/// The intent's work, with its storage and signal as parameters for the tests.
nonisolated enum StopRequest {
  /// Clears the stored value and posts the stop signal.
  ///
  /// The value is cleared first, so the widget's reload after the intent already draws no Stop
  /// button. The app doesn't read the cleared value: it acts on the signal, because a value
  /// written in this process can reach the app's process after the signal does.
  ///
  /// - Returns: Whether the system accepted the signal. Acceptance doesn't mean the app was
  ///   running.
  @discardableResult
  static func send(
    nowPlaying: SharedValue<NowPlaying> = .nowPlaying, signal: DarwinSignal = MenuBarID.stopSignal
  ) -> Bool {
    _ = try? nowPlaying.save(nil, reloading: [MenuBarID.widgetKind])
    return signal.post()
  }
}
