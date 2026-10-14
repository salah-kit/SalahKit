import Foundation
import SalahTimes

/// Settings read from the launch arguments, for tests and demos. The README lists them.
///
/// The clock, the notification center, the mute and the test tone apply to this run only. The
/// place, method, language and alert arguments change the settings as if they were made in the
/// app, so they're saved. An argument whose value can't be read is ignored, and when an argument
/// is given twice, the later one wins.
nonisolated struct LaunchOptions: Equatable, Sendable {
  /// `-now <ISO 8601 instant>`: start the app's clock at this instant; it then runs in real
  /// time. The widget extension always uses the real clock.
  var now: Date?
  /// `-place makkah|istanbul|london|tromso`.
  var place: Place?
  /// `-method <name>`: a `CalculationMethod` raw value such as `ummAlQura`.
  var method: CalculationMethod?
  /// `-language en|ar`: the names' language.
  var language: NamesLanguage?
  /// `-alerts on|off`.
  var alertsEnabled: Bool?
  /// `-reminder <minutes>|off`: the reminder before each prayer.
  var reminderMinutes: Int??
  /// `-notifications memory`: an in-memory notification center instead of the system's, so a
  /// test run asks for no permission and leaves nothing in Notification Center.
  var inMemoryNotifications = false
  /// `-muted`: play the tone at zero volume.
  var muted = false
  /// `-playTestTone once|repeating`: start the test tone at launch, once or until stopped.
  var testTone: TestTone?
  /// `-showWindow`: open the schedule window at launch. The menu-bar extra shows the same view;
  /// a window is easier to reach for UI tests than a status item that macOS may hide.
  var showWindow = false
  /// `-testEvents`: let the stop harness simulate a sleep and a clock change (`TestEvents`).
  var acceptsTestEvents = false

  /// How long the launch's test tone plays.
  enum TestTone: String, Equatable, Sendable {
    case once
    case repeating
  }

  init() {}

  init(arguments: [String]) {
    func value(after flag: String) -> String? {
      guard let index = arguments.lastIndex(of: flag), index + 1 < arguments.count else {
        return nil
      }
      return arguments[index + 1]
    }
    now = value(after: "-now").flatMap { try? Date($0, strategy: .iso8601) }
    place = value(after: "-place").flatMap(Place.preset)
    method = value(after: "-method").flatMap(CalculationMethod.init(rawValue:))
    language = value(after: "-language").flatMap(NamesLanguage.init(rawValue:))
    switch value(after: "-alerts") {
    case "on": alertsEnabled = true
    case "off": alertsEnabled = false
    default: break
    }
    if let reminder = value(after: "-reminder") {
      if reminder == "off" {
        reminderMinutes = .some(nil)
      } else if let minutes = Int(reminder), (1...120).contains(minutes) {
        reminderMinutes = .some(minutes)
      }
    }
    inMemoryNotifications = value(after: "-notifications") == "memory"
    muted = arguments.contains("-muted")
    testTone = value(after: "-playTestTone").flatMap(TestTone.init(rawValue:))
    showWindow = arguments.contains("-showWindow")
    acceptsTestEvents = arguments.contains("-testEvents")
  }

  /// The stored settings with this launch's changes.
  func applied(to settings: MenuBarSettings) -> MenuBarSettings {
    var settings = settings
    if let place { settings.place = place }
    if let method { settings.choose(method) }
    if let language { settings.language = language }
    if let alertsEnabled { settings.alerts.enabled = alertsEnabled }
    if let reminderMinutes { settings.alerts.reminderMinutes = reminderMinutes }
    return settings
  }
}

/// The app's clock: the real clock, or one started at a chosen instant that then runs in real
/// time. Test runs with `-testEvents` can also move it forward, as a sleep or a clock change
/// would.
///
/// `@unchecked Sendable`: `offset`, the only mutable state, is read and written only while
/// `lock` is held.
nonisolated final class AppClock: @unchecked Sendable {
  private let lock = NSLock()
  /// How far the app's clock is ahead of the real one.
  private var offset: TimeInterval

  /// Creates a clock.
  ///
  /// - Parameters:
  ///   - start: The instant the app shows at `launch`; `nil` uses the real clock.
  ///   - launch: The real instant the app launched.
  init(start: Date? = nil, launch: Date = Date()) {
    offset = start.map { $0.timeIntervalSince(launch) } ?? 0
  }

  /// The app's instant at a real instant.
  func now(at real: Date = Date()) -> Date {
    real.addingTimeInterval(lock.withLock { offset })
  }

  /// The real instant at which the app's clock shows `date`.
  func real(at date: Date) -> Date {
    date.addingTimeInterval(-lock.withLock { offset })
  }

  /// Moves the app's clock forward, without running anything that came due meanwhile.
  func jump(by seconds: TimeInterval) {
    lock.withLock { offset += seconds }
  }
}
