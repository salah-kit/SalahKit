import Foundation

/// Settings read from the launch arguments, for tests and demos.
///
/// - `-board muis|edinburgh`: the timetable to show (default `muis`).
/// - `-now <ISO 8601 instant>`: start the board's clock at this instant; it then advances in
///   real time, or stays put with `-frozen`.
/// - `-language en|ar`: the language of names, digits and dates (default: the app's language).
nonisolated struct LaunchOptions: Equatable, Sendable {
  var board: Board.ID = .muis
  var now: Date?
  var frozen = false
  var language: String?

  init(board: Board.ID = .muis, now: Date? = nil, frozen: Bool = false, language: String? = nil) {
    self.board = board
    self.now = now
    self.frozen = frozen
    self.language = language
  }

  init(arguments: [String]) {
    func value(after flag: String) -> String? {
      guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
      }
      return arguments[index + 1]
    }
    if let text = value(after: "-board"), let board = Board.ID(rawValue: text) {
      self.board = board
    }
    if let text = value(after: "-now") {
      now = try? Date(text, strategy: .iso8601)
    }
    frozen = arguments.contains("-frozen")
    language = value(after: "-language")
  }
}

/// The board's clock: the real clock, or one started at a chosen instant.
nonisolated struct BoardClock: Sendable {
  /// The instant the board shows when the app launches; `nil` uses the real clock.
  var start: Date?
  /// The real instant the app launched.
  var launch: Date
  /// Whether the clock stays at `start`.
  var frozen: Bool

  init(start: Date? = nil, launch: Date = Date(), frozen: Bool = false) {
    self.start = start
    self.launch = launch
    self.frozen = frozen
  }

  /// The board's instant at a real instant.
  func now(at real: Date) -> Date {
    guard let start else { return real }
    return frozen ? start : start.addingTimeInterval(real.timeIntervalSince(launch))
  }
}
