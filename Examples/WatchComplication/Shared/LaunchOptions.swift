import Foundation

/// Options read from the launch arguments, for tests and demos. The README lists them.
nonisolated struct LaunchOptions: Equatable, Sendable {
  /// `-now <ISO 8601 instant>`: show this instant, with the clock stopped there.
  var now: Date?
  /// `-language en|ar`.
  var language: String?
  /// `-preset makkah|mosque|mosqueEnded`: the companion selects it; the watch app stores it
  /// through the same path as received inputs, without an iPhone.
  var preset: InputsPreset?
  /// `-resetInputs` (watch): start with no stored inputs, as a fresh install does.
  var resetInputs = false
  /// `-send` (companion): send the selected preset once the session is active.
  var send = false
  /// `-screen states|diagnostics` (watch): open that screen at launch.
  var screen: String?

  init() {}

  init(arguments: [String]) {
    func value(after flag: String) -> String? {
      guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
      }
      return arguments[index + 1]
    }
    now = value(after: "-now").flatMap { try? Date($0, strategy: .iso8601) }
    language = value(after: "-language")
    preset = value(after: "-preset").flatMap(InputsPreset.init(rawValue:))
    resetInputs = arguments.contains("-resetInputs")
    send = arguments.contains("-send")
    screen = value(after: "-screen")
  }

  /// The instant to show: `-now` when given, otherwise the real clock.
  func date(real: Date = Date()) -> Date {
    now ?? real
  }
}
