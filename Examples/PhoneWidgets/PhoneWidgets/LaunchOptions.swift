import Foundation
import SalahTimes

/// Settings read from the launch arguments, for tests and demos. The README lists them.
///
/// The clock applies to this run only. The place, method and language arguments change the
/// settings as if they were made in the app, so they're saved. An argument whose value can't be
/// read is ignored.
nonisolated struct LaunchOptions: Equatable, Sendable {
  /// `-now <ISO 8601 instant>`: start the app's clock at this instant. The extension always uses
  /// the real clock.
  var now: Date?
  /// `-frozen`: keep the app's clock at `-now`.
  var frozen = false
  /// `-cleanStart`: remove the stored settings, as on a fresh install, before anything else.
  var cleanStart = false
  /// `-place makkah|london|tromso|invalid`.
  var place: Place?
  /// `-method <name>`: a `CalculationMethod` raw value such as `ummAlQura`.
  var method: CalculationMethod?
  /// `-language en|ar`: the names' language.
  var language: NamesLanguage?

  init() {}

  init(arguments: [String]) {
    func value(after flag: String) -> String? {
      guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
      }
      return arguments[index + 1]
    }
    now = value(after: "-now").flatMap { try? Date($0, strategy: .iso8601) }
    frozen = arguments.contains("-frozen")
    cleanStart = arguments.contains("-cleanStart")
    place = value(after: "-place").flatMap(Place.preset)
    method = value(after: "-method").flatMap(CalculationMethod.init(rawValue:))
    language = value(after: "-language").flatMap(NamesLanguage.init(rawValue:))
  }

  /// Whether the arguments change the settings.
  var changesSettings: Bool {
    place != nil || method != nil || language != nil
  }

  /// Applies the place, method and language arguments.
  func apply(to settings: inout WidgetSettings) {
    if let place {
      settings.place = place
    }
    if let method {
      settings.choose(method)
    }
    if let language {
      settings.language = language
    }
  }
}

/// The app's clock: the real clock, or one started at a chosen instant.
nonisolated struct AppClock: Sendable {
  /// The instant the app shows when it launches; `nil` uses the real clock.
  var start: Date?
  /// The real instant the app launched.
  var launch: Date
  /// Whether the clock stays at `start`. Only a clock with a start can be frozen.
  var frozen: Bool

  init(start: Date? = nil, launch: Date = Date(), frozen: Bool = false) {
    self.start = start
    self.launch = launch
    self.frozen = frozen && start != nil
  }

  /// The app's instant at a real instant.
  func now(at real: Date = Date()) -> Date {
    guard let start else { return real }
    return frozen ? start : start.addingTimeInterval(real.timeIntervalSince(launch))
  }
}
