import Foundation
import SalahAlerts
import SalahCore
import SalahWidgets

/// What the app is playing, published for the widget's Stop button.
///
/// The app writes it whenever playback starts or ends. The widget's intent clears it before it
/// signals the app, so the widget redraws without the button at once; the app then publishes
/// what it really plays, which confirms the stop. That makes the intent a second writer of this
/// one key, on purpose: the app's republish after every signal settles any race between the two.
nonisolated struct NowPlaying: Codable, Hashable, Sendable {
  /// The alert whose tone plays, or `nil` for the test tone the user started.
  var alert: Alert?
  /// When the tone started.
  var startedAt: Date

  /// The alert a tone belongs to.
  struct Alert: Codable, Hashable, Sendable {
    var prayer: PrayerKind
    var observance: PrayerObservance
    var kind: AlertKind
  }
}

nonisolated extension SharedValue where Value == NowPlaying {
  /// What's playing, in the App Group. `nil` when nothing plays.
  static var nowPlaying: Self {
    SharedValue(appGroup: MenuBarID.appGroup, key: "nowPlaying.v1")
  }
}

// DIAGNOSTICS: the example's evidence channel, not part of the pattern.
//
// The app records what it did with playback, the stop signal and system events in a bounded log
// in the App Group, and the stop harness reads it from its own process. An app built on this
// example can delete this part.

/// One thing the app did with playback, the stop signal or a system event.
nonisolated struct DiagnosticsRecord: Codable, Hashable, Sendable {
  /// What happened.
  enum Event: String, Codable, Hashable, Sendable {
    /// The app started and published its state.
    case launched
    /// A tone started.
    case started
    /// A tone ended by itself.
    case finished
    /// A tone couldn't start.
    case playbackFailed
    /// The stop signal arrived.
    case stopSignal
    /// The app stopped playback; ``DiagnosticsRecord/detail`` says why.
    case stopped
    /// The app published what it plays; ``DiagnosticsRecord/detail`` says what and whether the
    /// stored value changed.
    case published
    /// The Mac woke, or the clock or time zone changed; ``DiagnosticsRecord/detail`` says which.
    case systemEvent
    /// The app planned its alerts; ``DiagnosticsRecord/detail`` has the engine's and the
    /// notification plan's counts.
    case replanned
    /// The display planned again after a system event; ``DiagnosticsRecord/detail`` is the menu
    /// bar's new title.
    case displayRefreshed
  }

  /// The record's number, counting from 1 at each launch.
  var sequence: Int
  /// When it happened, by the app's real clock.
  var date: Date
  var event: Event
  var detail: String?
}

/// The app's records since it launched, oldest first.
nonisolated struct DiagnosticsLog: Codable, Hashable, Sendable {
  /// How many records the log keeps.
  static let capacity = 100

  /// An identifier of the launch the records belong to.
  var launchID: String
  var records: [DiagnosticsRecord]

  /// The log with one more record, dropping the oldest beyond ``capacity``.
  func appending(_ event: DiagnosticsRecord.Event, detail: String? = nil, at date: Date) -> Self {
    var log = self
    let sequence = (records.last?.sequence ?? 0) + 1
    log.records.append(
      DiagnosticsRecord(sequence: sequence, date: date, event: event, detail: detail))
    log.records.removeFirst(max(0, log.records.count - Self.capacity))
    return log
  }
}

nonisolated extension SharedValue where Value == DiagnosticsLog {
  /// The app's diagnostics log, in the App Group. The app is its only writer.
  static var diagnosticsLog: Self {
    SharedValue(appGroup: MenuBarID.appGroup, key: "diagnostics.v1")
  }
}

/// Signals the stop harness posts to simulate system events in a test run. The app observes
/// them only when launched with `-testEvents`.
nonisolated enum TestEventSignal {
  /// The Mac slept through ``sleepSeconds`` and woke: the app moves its clock forward and posts
  /// `NSWorkspace.didWakeNotification` in its own process.
  static let sleep = DarwinSignal(name: "io.github.salah-kit.MenuBar.test.sleep")
  /// The clock was set ``clockChangeSeconds`` ahead: the app moves its clock forward and posts
  /// `NSSystemClockDidChange` in its own process.
  static let clockChange = DarwinSignal(name: "io.github.salah-kit.MenuBar.test.clockChange")

  static let sleepSeconds: TimeInterval = 3 * 60
  static let clockChangeSeconds: TimeInterval = 10 * 60
}
