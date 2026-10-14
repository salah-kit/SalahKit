// The stop harness: the widget's stop code, run in a separate process against the running app.
//
// A tap on a desktop widget can't be automated, so the harness stands in for the widget
// extension. It's signed like the extension (sandboxed, with the same App Group), runs the same
// `StopPlaybackIntent.perform()`, and reads back what the app published. Each command prints one
// line of JSON and exits 0, or 2 for a usage error:
//
//   MenuBarStopHarness stop     runs StopPlaybackIntent().perform(): clears the stored value and
//                               posts the stop signal, as the widget's button does
//   MenuBarStopHarness signal   posts the stop signal only, leaving the stored value as it is, as
//                               if the cleared value hadn't reached the app yet
//   MenuBarStopHarness state    prints what's stored: what plays, the app's diagnostics log, and
//                               the widget's timeline built from them by the extension's code
//   MenuBarStopHarness sleep    asks an app launched with -testEvents to simulate three minutes
//                               of sleep and a wake (TestEventSignal)
//   MenuBarStopHarness clock    asks it to simulate the clock being set ten minutes ahead

import Foundation
import SalahWidgets

/// One line of the harness's output.
struct Output: Encodable {
  var command: String
  /// When the command ran, by this process's clock.
  var date: Date
  /// For `signal`, `sleep` and `clock`: whether the system accepted the signal. (`stop` runs the
  /// intent, whose result doesn't say.)
  var signalAccepted: Bool?
  /// For `state`: what plays, as stored.
  var nowPlaying: NowPlaying?
  /// For `state`: the app's diagnostics log, as stored.
  var log: DiagnosticsLog?
  /// For `state`: whether the settings are stored.
  var settingsStored: Bool?
  /// For `state`: the widget's timeline, built from the stored values by the extension's code.
  var widget: WidgetProbe?
}

/// What the widget extension would show now.
struct WidgetProbe: Encodable {
  var entryCount: Int
  /// Whether the first entry shows the Stop button.
  var showsStopButton: Bool
  /// What the first entry shows: `setupRequired`, `available`, `unavailable` or `expired`.
  var firstEntry: String

  init(_ entries: [MenuBarEntry]) {
    entryCount = entries.count
    showsStopButton = entries.first?.showsStopButton ?? false
    switch entries.first?.content {
    case .setupRequired, nil: firstEntry = "setupRequired"
    case .timeline(.schedule(.available), _): firstEntry = "available"
    case .timeline(.schedule(.unavailable), _): firstEntry = "unavailable"
    case .timeline(.expired, _): firstEntry = "expired"
    }
  }
}

func emit(_ output: Output) {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.sortedKeys]
  let data = (try? encoder.encode(output)) ?? Data("{}".utf8)
  FileHandle.standardOutput.write(data + Data("\n".utf8))
}

switch CommandLine.arguments.dropFirst().first {
case "stop":
  // The intent's own code, not a copy of it.
  _ = try await StopPlaybackIntent().perform()
  emit(Output(command: "stop", date: Date()))
case "signal":
  emit(Output(command: "signal", date: Date(), signalAccepted: MenuBarID.stopSignal.post()))
case "sleep":
  emit(Output(command: "sleep", date: Date(), signalAccepted: TestEventSignal.sleep.post()))
case "clock":
  emit(Output(command: "clock", date: Date(), signalAccepted: TestEventSignal.clockChange.post()))
case "state":
  let settings = SharedValue.menuBarSettings.load()
  let nowPlaying = SharedValue.nowPlaying.load()
  let timeline = MenuBarTimeline.timeline(settings: settings, nowPlaying: nowPlaying, now: Date())
  emit(
    Output(
      command: "state", date: Date(), nowPlaying: nowPlaying,
      log: SharedValue.diagnosticsLog.load(),
      settingsStored: settings != nil, widget: WidgetProbe(timeline.entries)))
default:
  FileHandle.standardError.write(
    Data("usage: MenuBarStopHarness stop | signal | state | sleep | clock\n".utf8))
  exit(2)
}
