import Foundation
import Observation
import SalahWidgets
import os

/// What the app plays, and the live-state pattern around it (SalahWidgets' article "Lessons
/// from Salah"):
///
/// 1. The app publishes what it plays in a `SharedValue` the widget reads.
/// 2. The widget's Stop button runs ``StopPlaybackIntent`` in the extension's process: it
///    clears the value and posts the stop signal.
/// 3. The app acts on the signal, not on the stored value, which can reach this process after
///    the signal does.
/// 4. The app publishes what it plays again, which confirms the stop to the widget.
@MainActor
@Observable
final class LiveState {
  /// What plays, or `nil`.
  private(set) var nowPlaying: NowPlaying?

  @ObservationIgnored private let player: any TonePlaying
  @ObservationIgnored private let storage: SharedValue<NowPlaying>
  @ObservationIgnored private let signal: DarwinSignal
  @ObservationIgnored private let widgetKinds: [String]
  @ObservationIgnored private let diagnostics: Diagnostics
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private var observation: DarwinSignal.Observation?
  @ObservationIgnored private let logger = Logger(
    subsystem: MenuBarID.logSubsystem, category: "LiveState")

  /// Creates the live state.
  ///
  /// - Parameters:
  ///   - player: Plays the tone.
  ///   - storage: Where the widget reads what plays.
  ///   - signal: The signal the widget's intent posts.
  ///   - widgetKinds: The widgets to reload when what plays changes.
  ///   - diagnostics: Where the app records what it did, for the stop harness.
  ///   - now: The real clock, for the start date the widget shows.
  init(
    player: any TonePlaying, storage: SharedValue<NowPlaying> = .nowPlaying,
    signal: DarwinSignal = MenuBarID.stopSignal, widgetKinds: [String] = [MenuBarID.widgetKind],
    diagnostics: Diagnostics = Diagnostics(),
    now: @escaping () -> Date = Date.init
  ) {
    self.player = player
    self.storage = storage
    self.signal = signal
    self.widgetKinds = widgetKinds
    self.diagnostics = diagnostics
    self.now = now
  }

  /// Whether the stop signal is observed.
  var isObservingStopSignal: Bool { observation?.isActive == true }

  /// Starts observing the stop signal and publishes that nothing plays yet, which also clears a
  /// value left by a run that ended while playing.
  func start() {
    observation = signal.observe { [weak self] in self?.stopSignalArrived() }
    diagnostics.record(.launched, detail: isObservingStopSignal ? "observing" : "not observing")
    publish()
  }

  /// Plays the tone for an alert, or the test tone for `nil`.
  ///
  /// - Parameter cycles: How many times the chime plays, or `nil` to repeat it until stopped.
  func play(_ alert: NowPlaying.Alert?, cycles: Int? = 3) {
    do {
      try player.play(cycles: cycles) { [weak self] in self?.finished() }
    } catch {
      logger.error("The tone couldn't start: \(String(describing: error), privacy: .public)")
      diagnostics.record(.playbackFailed, detail: String(describing: error))
      nowPlaying = nil
      publish()
      return
    }
    nowPlaying = NowPlaying(alert: alert, startedAt: now())
    diagnostics.record(.started, detail: alert.map { "\($0.prayer.rawValue) \($0.kind)" } ?? "test")
    publish()
  }

  /// Stops the tone, from the app's own controls.
  func stop() {
    stopPlayback(reason: "app")
  }

  /// The widget's intent posted the stop signal. The stored value isn't read: the intent's
  /// write may not have reached this process yet, and an app that waits for it would ignore
  /// the tap (`DarwinSignal`'s documentation).
  private func stopSignalArrived() {
    diagnostics.record(.stopSignal)
    stopPlayback(reason: "signal")
  }

  private func stopPlayback(reason: String) {
    let wasPlaying = player.isPlaying
    player.stop()
    nowPlaying = nil
    diagnostics.record(.stopped, detail: "\(reason) wasPlaying=\(wasPlaying)")
    publish()
  }

  private func finished() {
    nowPlaying = nil
    diagnostics.record(.finished)
    publish()
  }

  /// Saves what plays for the widget, reloading it only when the stored value changed.
  private func publish() {
    let value = nowPlaying
    do {
      let changed = try storage.save(value, reloading: widgetKinds)
      diagnostics.record(.published, detail: "playing=\(value != nil) changed=\(changed)")
    } catch {
      logger.error("Publishing failed: \(String(describing: error), privacy: .public)")
      diagnostics.record(.published, detail: "failed \(error)")
    }
  }
}

/// Records what the app did in the App Group's ``DiagnosticsLog``, and in the unified log.
@MainActor
final class Diagnostics {
  private let storage: SharedValue<DiagnosticsLog>?
  private let now: () -> Date
  private var log: DiagnosticsLog
  private let logger = Logger(subsystem: MenuBarID.logSubsystem, category: "Diagnostics")

  /// Creates the recorder, which starts a new log for this launch.
  ///
  /// - Parameters:
  ///   - storage: Where the log goes, or `nil` to keep it in memory.
  ///   - now: The real clock.
  init(
    storage: SharedValue<DiagnosticsLog>? = .diagnosticsLog, now: @escaping () -> Date = Date.init
  ) {
    self.storage = storage
    self.now = now
    log = DiagnosticsLog(launchID: UUID().uuidString, records: [])
  }

  /// The records so far.
  var records: [DiagnosticsRecord] { log.records }

  /// Adds a record.
  func record(_ event: DiagnosticsRecord.Event, detail: String? = nil) {
    log = log.appending(event, detail: detail, at: now())
    logger.log(
      "\(event.rawValue, privacy: .public) \(detail ?? "", privacy: .public)")
    _ = try? storage?.save(log)
  }
}
