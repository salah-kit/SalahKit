import AppKit
import Foundation
import SalahCalculation
import SalahCore
import Testing

/// The widget's stop code and the simulated sleep and clock change, against the running app.
///
/// These tests have no host app: they run in `xctest`, outside any sandbox, so they can start
/// the real app and the stop harness, each a separate process. (XCUITest's runner is sandboxed
/// and can't start the harness, whose own sandbox it would have to inherit.) The harness is
/// signed like the widget extension, with the same App Group, and runs the intent's own
/// `perform()`; it also reads back what the app recorded and stored.
@Suite("Round trip", .serialized)
@MainActor
struct RoundTripTests {
  /// Makkah's Asr on 14 October 2026, Umm al-Qura, from the package.
  static func asr() throws -> Date {
    let location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262, timeZone: TimeZone(identifier: "Asia/Riyadh") ?? .gmt,
      countryCode: "SA", name: "Makkah")
    let schedule = PrayerSchedule(
      source: CalculationSource(CalculationSettings(method: .ummAlQura)), location: location)
    return try #require(schedule.day(CivilDay(year: 2026, month: 10, day: 14)).day?[.asr]?.time)
  }

  /// The quiet launch: zero volume, notifications in memory, Makkah in English, alerts off,
  /// and the app's tone for alerts.
  static let quiet = [
    "-muted", "-notifications", "memory", "-place", "makkah", "-method", "ummAlQura",
    "-language", "en", "-alerts", "off", "-tone", "on", "-AppleLanguages", "(en)",
  ]

  // MARK: - The stop round trip (proposal §7.3, Live state)

  /// The 0.3.0 gate: the widget intent's code, run in a separate process, stops the running
  /// app's tone; the app republishes, and the widget's timeline, built by the extension's code
  /// from what's stored, drops the Stop button.
  @Test("the widget's stop code stops the running app, which republishes")
  func widgetStop() async throws {
    let app = try await RunningApp.launch(Self.quiet + ["-playTestTone", "repeating"])
    defer { app.quit() }
    let playing = try await Harness.waitForState(of: app) { $0.nowPlaying != nil }
    #expect(playing.widget?.showsStopButton == true)

    _ = try Harness.run("stop")
    let after = try await Harness.waitForState(of: app) {
      $0.nowPlaying == nil && $0.records(since: playing).contains { $0.event == "published" }
    }
    let records = after.records(since: playing)
    #expect(records.map(\.event) == ["stopSignal", "stopped", "published"], "\(records)")
    #expect(records.first { $0.event == "stopped" }?.detail == "signal wasPlaying=true")
    #expect(records.last?.detail?.hasPrefix("playing=false") == true)
    #expect(after.widget?.showsStopButton == false)
    #expect(after.widget?.firstEntry == "available")
    #expect(app.isRunning)
  }

  /// The intent's cleared value can reach the app after the signal does. Here the harness posts
  /// only the signal, so the stored value still says the tone plays: the app stops anyway, and
  /// its republish clears the value, which nothing else wrote.
  @Test("the app acts on the signal, not on the stored value")
  func signalAlone() async throws {
    let app = try await RunningApp.launch(Self.quiet + ["-playTestTone", "repeating"])
    defer { app.quit() }
    let playing = try await Harness.waitForState(of: app) { $0.nowPlaying != nil }

    let signalled = try Harness.run("signal")
    #expect(signalled.signalAccepted == true)
    // The app saves the cleared value before it records "published": wait for both.
    let after = try await Harness.waitForState(of: app) {
      $0.nowPlaying == nil && $0.records(since: playing).contains { $0.event == "published" }
    }
    let records = after.records(since: playing)
    #expect(records.map(\.event) == ["stopSignal", "stopped", "published"], "\(records)")
    #expect(records.last?.detail == "playing=false changed=true")
    #expect(after.widget?.showsStopButton == false)
  }

  // MARK: - Sleep, wake and clock changes, injected

  /// The harness's `sleep` makes the app move its clock three minutes ahead and post NSWorkspace's
  /// wake notification to itself: launched a minute before Asr, the app catches Asr's alert up
  /// after the wake and plays the tone.
  @Test("a wake after sleeping through Asr catches its alert up")
  func wake() async throws {
    let asr = try Self.asr()
    let app = try await RunningApp.launch(
      Self.quiet + [
        "-alerts", "on", "-reminder", "off", "-testEvents", "-now",
        asr.addingTimeInterval(-60).formatted(.iso8601),
      ])
    defer { app.quit() }
    let launched = try await Harness.waitForState(of: app) {
      $0.records.contains { $0.event == "replanned" }
    }

    let woke = try Harness.run("sleep")
    #expect(woke.signalAccepted == true)
    // The app records "started", then saves what plays, then replans: wait for all three.
    let after = try await Harness.waitForState(of: app) { state in
      let events = state.records(since: launched).map(\.event)
      return events.contains("started") && events.contains("replanned")
        && state.nowPlaying != nil
    }
    let records = after.records(since: launched)
    let events = records.map(\.event)
    let systemEvent = try #require(events.firstIndex(of: "systemEvent"), "\(records)")
    let started = try #require(events.firstIndex(of: "started"), "\(records)")
    #expect(records[systemEvent].detail == "wake")
    #expect(systemEvent < started, "the tone started after the wake, not on time: \(records)")
    #expect(records[started].detail == "asr atTime")
    #expect(events.contains("replanned"))
    let title = records.first { $0.event == "displayRefreshed" }?.detail
    #expect(title == "Asr +2m" || title == "Asr +3m", "\(records)")
    #expect(after.nowPlaying?.alert?.prayer == "asr")
  }

  /// The harness's `clock` makes the app move its clock ten minutes ahead and post
  /// NSSystemClockDidChange: Asr's alert is beyond its five-minute grace, so nothing plays, and
  /// the display plans again from the new time.
  @Test("a clock change beyond the grace skips the alert and replans")
  func clockChange() async throws {
    let asr = try Self.asr()
    let app = try await RunningApp.launch(
      Self.quiet + [
        "-alerts", "on", "-reminder", "off", "-testEvents", "-now",
        asr.addingTimeInterval(-60).formatted(.iso8601),
      ])
    defer { app.quit() }
    let launched = try await Harness.waitForState(of: app) {
      $0.records.contains { $0.event == "replanned" }
    }

    let changed = try Harness.run("clock")
    #expect(changed.signalAccepted == true)
    let after = try await Harness.waitForState(of: app) {
      $0.records(since: launched).contains { $0.event == "replanned" }
    }
    let records = after.records(since: launched)
    #expect(records.first?.event == "systemEvent" && records.first?.detail == "clockChange")
    // Launched a minute before Asr, then ten minutes ahead: nine minutes and some seconds since.
    let title = records.first { $0.event == "displayRefreshed" }?.detail
    #expect(title == "Asr +9m" || title == "Asr +10m", "\(records)")
    #expect(!records.contains { $0.event == "started" }, "\(records)")
    #expect(after.nowPlaying == nil)
  }
}

/// The build's products folder, where Xcode puts the app, the harness and this test bundle.
nonisolated private final class ProductsMarker {}

nonisolated enum Products {
  static var folder: URL {
    Bundle(for: ProductsMarker.self).bundleURL.deletingLastPathComponent()
  }
}

/// The app, started with launch arguments.
@MainActor
final class RunningApp {
  static let bundleIdentifier = "io.github.salah-kit.MenuBar"

  private let process: Process
  /// The launch's identifier in the app's diagnostics log, once the harness has read it.
  var launchID: String?
  /// The launch identifier the log had before this launch.
  let previousLaunchID: String?

  private init(_ process: Process, previousLaunchID: String?) {
    self.process = process
    self.previousLaunchID = previousLaunchID
  }

  /// Starts the app's executable, after quitting any copy of it left running.
  ///
  /// The environment is this process's without XCTest's variables: an app that inherits
  /// `XCTestConfigurationFilePath` takes itself for a unit-test host and stays inert.
  static func launch(_ arguments: [String]) async throws -> RunningApp {
    for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    {
      running.forceTerminate()
    }
    let previous = try Harness.run("state").log?.launchID
    let process = Process()
    process.executableURL = Products.folder.appendingPathComponent(
      "MenuBar.app/Contents/MacOS/MenuBar")
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.filter { key, _ in
      !key.hasPrefix("XC") && !key.hasPrefix("DYLD_") && !key.contains("XCTest")
    }
    try process.run()
    return RunningApp(process, previousLaunchID: previous)
  }

  var isRunning: Bool { process.isRunning }

  /// Quits the app, and kills it after ten seconds.
  func quit() {
    process.terminate()
    let deadline = Date().addingTimeInterval(10)
    while process.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
  }
}

/// The stop harness, built beside the app: one command, one line of JSON.
nonisolated enum Harness {
  /// One record of the app's diagnostics log.
  struct Record: Decodable, CustomStringConvertible {
    var sequence: Int
    var date: Date
    var event: String
    var detail: String?
    var description: String { "\(sequence) \(event) \(detail ?? "")" }
  }

  struct Log: Decodable {
    var launchID: String
    var records: [Record]
  }

  struct Widget: Decodable {
    var entryCount: Int
    var showsStopButton: Bool
    var firstEntry: String
  }

  struct Playing: Decodable {
    struct Alert: Decodable {
      var prayer: String
      var kind: String
    }
    var alert: Alert?
    var startedAt: Date
  }

  /// A command's output.
  struct Output: Decodable {
    var command: String
    var date: Date
    var signalAccepted: Bool?
    var nowPlaying: Playing?
    var log: Log?
    var widget: Widget?

    var records: [Record] { log?.records ?? [] }

    /// The records the app added after an earlier `state` of the same launch.
    func records(since earlier: Output) -> [Record] {
      let last = earlier.log?.launchID == log?.launchID ? earlier.records.last?.sequence ?? 0 : 0
      return records.filter { $0.sequence > last }
    }
  }

  /// The harness's executable, in the products folder.
  static var executable: URL {
    Products.folder.appendingPathComponent(
      "MenuBarStopHarness.app/Contents/MacOS/MenuBarStopHarness")
  }

  /// Runs a command and decodes its output.
  static func run(_ command: String) throws -> Output {
    let process = Process()
    process.executableURL = executable
    process.arguments = [command]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "\(String(decoding: data, as: UTF8.self))")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(Output.self, from: data)
  }

  /// Runs `state` until it shows the app's current launch and `condition` holds, for up to
  /// fifteen seconds, and returns the last output.
  @MainActor
  static func waitForState(
    of app: RunningApp, _ condition: (Output) -> Bool
  ) async throws -> Output {
    let deadline = Date().addingTimeInterval(15)
    var state = try run("state")
    func current(_ state: Output) -> Bool {
      guard let id = state.log?.launchID, id != app.previousLaunchID else { return false }
      return app.launchID == nil || app.launchID == id
    }
    while !(current(state) && condition(state)), Date() < deadline {
      try await Task.sleep(for: .milliseconds(250))
      state = try run("state")
    }
    #expect(current(state) && condition(state), "\(state.records)")
    if app.launchID == nil, current(state) { app.launchID = state.log?.launchID }
    return state
  }
}
