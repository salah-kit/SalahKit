import Foundation
import SalahAlerts
import SalahCore
import SalahWidgets
import Testing

@testable import MenuBar

/// Time the test moves by hand, shared by any number of clocks.
///
/// Advancing runs each clock's armed wake-up when its date is reached, earliest first; jumping, as
/// a sleep or a clock change does, runs nothing.
@MainActor
final class TestTime {
  /// The moment, for code off the main actor, such as the notification scheduler.
  let shared: SharedDate
  private(set) var now: Date {
    didSet { shared.value = now }
  }
  /// The clocks on this time, held weakly: each clock holds its time.
  private var clocks: [WeakClock] = []

  private struct WeakClock {
    weak var clock: ManualClock?
  }

  init(_ now: Date) {
    self.now = now
    shared = SharedDate(now)
  }

  /// A clock with its own wake-up, on this time.
  func makeClock() -> ManualClock {
    ManualClock(time: self)
  }

  fileprivate func register(_ clock: ManualClock) {
    clocks.append(WeakClock(clock: clock))
  }

  /// Moves time to `date`, running each wake-up reached on the way at its own date.
  ///
  /// Code that keeps arming wake-ups at or before `date` would never let time pass; after 10,000
  /// wake-ups the test records an issue instead of hanging.
  func advance(to date: Date) {
    var count = 0
    while let next = clocks.compactMap(\.clock)
      .compactMap({ clock in clock.wakeDate.map { ($0, clock) } })
      .filter({ $0.0 <= date }).min(by: { $0.0 < $1.0 })
    {
      count += 1
      guard count <= 10_000 else {
        Issue.record("The wake-ups before \(date) didn't settle.")
        return
      }
      now = max(now, next.0)
      next.1.runWake()
    }
    now = max(now, date)
  }

  /// Moves time without running anything, as a sleep or a clock change does.
  func jump(to date: Date) {
    now = date
  }
}

/// A clock on a ``TestTime``, with one wake-up of its own.
@MainActor
final class ManualClock: AlertClock {
  let time: TestTime
  /// The armed wake-up's date, or `nil`.
  private(set) var wakeDate: Date?
  private var action: (@MainActor @Sendable () -> Void)?
  /// Every date a wake-up was armed for, in order.
  private(set) var armed: [Date] = []

  /// A clock on time of its own, starting at `now`.
  convenience init(_ now: Date) {
    self.init(time: TestTime(now))
  }

  fileprivate init(time: TestTime) {
    self.time = time
    time.register(self)
  }

  var now: Date { time.now }

  /// The moment, for code off the main actor.
  var shared: SharedDate { time.shared }

  func wake(at date: Date?, perform action: @escaping @MainActor @Sendable () -> Void) {
    wakeDate = date
    self.action = date == nil ? nil : action
    if let date { armed.append(date) }
  }

  /// Runs the armed wake-up and disarms it.
  fileprivate func runWake() {
    let run = action
    wakeDate = nil
    action = nil
    run?()
  }

  /// Moves the time to `date`, running the wake-ups reached on the way.
  func advance(to date: Date) {
    time.advance(to: date)
  }

  /// Runs this clock's armed wake-up now, at its date.
  func fire() {
    guard let wake = wakeDate else { return }
    time.advance(to: wake)
  }

  /// Moves the time without running anything, as a sleep or a clock change does.
  func jump(to date: Date) {
    time.jump(to: date)
  }
}

/// A date that any thread reads and the main actor moves.
///
/// `@unchecked Sendable`: `stored` is read and written only while `lock` is held.
nonisolated final class SharedDate: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Date

  init(_ date: Date) {
    stored = date
  }

  var value: Date {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

/// A tone player that records what it was asked to do.
@MainActor
final class FakeTonePlayer: TonePlaying {
  private(set) var isPlaying = false
  /// The `cycles` of each `play`, in order.
  private(set) var plays: [Int?] = []
  private(set) var stops = 0
  /// Makes the next `play` throw.
  var failsNextPlay = false
  private var onFinish: (@MainActor () -> Void)?

  func play(cycles: Int?, onFinish: @escaping @MainActor () -> Void) throws {
    if failsNextPlay {
      failsNextPlay = false
      throw TonePlayerError.cannotPlay
    }
    plays.append(cycles)
    isPlaying = true
    self.onFinish = onFinish
  }

  func stop() {
    stops += 1
    isPlaying = false
    onFinish = nil
  }

  /// Ends the tone by itself.
  func finish() {
    isPlaying = false
    let finished = onFinish
    onFinish = nil
    finished?()
  }
}

/// Widget kinds a shared value asked to reload, collected across threads.
///
/// `@unchecked Sendable`: `recorded` is read and written only while `lock` is held.
nonisolated final class ReloadRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [[String]] = []

  var reloads: [[String]] { lock.withLock { recorded } }

  func record(_ kinds: [String]) {
    lock.withLock { recorded.append(kinds) }
  }
}

/// Storage of the test's own, in a suite no other test or process uses.
enum TestStorage {
  static func suite() -> String {
    "io.github.salah-kit.MenuBarTests.\(UUID().uuidString)"
  }

  static func nowPlaying(_ recorder: ReloadRecorder = ReloadRecorder()) -> SharedValue<NowPlaying> {
    SharedValue(appGroup: suite(), key: "nowPlaying.v1") { recorder.record($0) }
  }

  static func log() -> SharedValue<DiagnosticsLog> {
    SharedValue(appGroup: suite(), key: "diagnostics.v1")
  }

  /// A signal name no other test or process uses.
  static func signal() -> DarwinSignal {
    DarwinSignal(name: "io.github.salah-kit.MenuBarTests.\(UUID().uuidString)")
  }
}

/// Fixed places and instants.
enum Fixture {
  /// Makkah, Umm al-Qura, English, alerts off.
  static let makkah = MenuBarSettings(place: .makkah, method: .ummAlQura, language: .english)

  /// 14 October 2026, a Wednesday.
  static let day = CivilDay(year: 2026, month: 10, day: 14)

  /// An event of Makkah's schedule on ``day``.
  static func event(_ kind: PrayerKind, settings: MenuBarSettings = makkah) throws -> PrayerEvent {
    let day = try #require(settings.schedule.day(day).day)
    return try #require(day.events.first { $0.kind == kind })
  }
}

/// A count the main actor updates.
@MainActor
final class Counter {
  var count = 0
}

/// Waits, up to `seconds`, for `condition` to hold, letting the main actor run meanwhile.
@MainActor
func eventually(within seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
  let deadline = Date().addingTimeInterval(seconds)
  while Date() < deadline {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return condition()
}
