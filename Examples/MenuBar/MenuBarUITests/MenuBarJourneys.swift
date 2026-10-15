import Foundation
import SalahCalculation
import SalahCore
import XCTest

/// Journeys through the real app on the Mac: its status item's title and the schedule window.
///
/// Every launch is quiet: the tone plays at zero volume, notifications go to an in-memory center
/// (no permission prompt, nothing in Notification Center), and the app opens its schedule in a
/// window, which the journeys read instead of the status item's dropdown. The status item's
/// title reads as its spoken label ("Asr in 27 minutes"), which the app sets from the same
/// refresh as the visible text.
///
/// The stop round trip and the simulated sleep and clock change are in `MenuBarRoundTripTests`:
/// Xcode runs these journeys in a sandboxed runner, which can't start the stop harness.
nonisolated final class MenuBarJourneys: XCTestCase {
  /// Makkah's prayer times on 14 October 2026, Umm al-Qura, from the package.
  static let day: PrayerDay? = {
    let location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262, timeZone: TimeZone(identifier: "Asia/Riyadh") ?? .gmt,
      countryCode: "SA", name: "Makkah")
    let schedule = PrayerSchedule(
      source: CalculationSource(CalculationSettings(method: .ummAlQura)), location: location)
    return schedule.day(CivilDay(year: 2026, month: 10, day: 14)).day
  }()

  static func time(of kind: PrayerKind) throws -> Date {
    try XCTUnwrap(day?[kind]?.time)
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// Launches the app with the quiet arguments and `arguments`, and its window open.
  @MainActor
  func launch(_ arguments: [String] = [], now: Date? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      [
        "-showWindow", "-muted", "-notifications", "memory", "-place", "makkah", "-method",
        "ummAlQura", "-language", "en", "-alerts", "off", "-tone", "on", "-AppleLanguages",
        "(en)",
      ] + (now.map { ["-now", $0.formatted(.iso8601)] } ?? []) + arguments
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    return app
  }

  /// The schedule window.
  @MainActor
  func window(_ app: XCUIApplication) -> XCUIElement {
    let window = app.windows["MenuBar"]
    XCTAssertTrue(window.waitForExistence(timeout: 30), app.debugDescription)
    return window
  }

  /// The first text under `root` that starts with `prefix`. On macOS a SwiftUI text's words are
  /// its value; SalahUI's rows and next prayer combine their texts into one, "Asr, 3:27 PM".
  @MainActor
  func text(_ root: XCUIElement, startingWith prefix: String) -> XCUIElement {
    root.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", prefix)).firstMatch
  }

  /// Waits for the status item's title to satisfy `condition`, and returns the last title seen.
  @MainActor
  func waitForTitle(
    _ app: XCUIApplication, timeout: TimeInterval, _ condition: (String) -> Bool
  ) -> String {
    let statusItem = app.statusItems.firstMatch
    XCTAssertTrue(statusItem.waitForExistence(timeout: 30), app.debugDescription)
    let deadline = Date().addingTimeInterval(timeout)
    var title = statusItem.title
    while !condition(title), Date() < deadline {
      Thread.sleep(forTimeInterval: 0.5)
      title = statusItem.title
    }
    return title
  }

  /// The window lists Makkah's day, and the status item names the next prayer and its time.
  @MainActor
  func testScheduleShowsTheDay() throws {
    let noon = try XCTUnwrap(try? Date("2026-10-14T12:30:00+03:00", strategy: .iso8601))
    let app = launch(now: noon)
    let window = window(app)
    XCTAssertTrue(text(window, startingWith: "Makkah").exists, window.debugDescription)
    for name in ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"] {
      XCTAssertTrue(text(window, startingWith: name).exists, "\(name)\n\(window.debugDescription)")
    }
    let next = window.staticTexts["nextPrayer"]
    XCTAssertTrue((next.value as? String)?.hasPrefix("Asr, ") == true, window.debugDescription)
    XCTAssertEqual(window.staticTexts["alertsStatus"].value as? String, "Alerts are off.")
    let title = waitForTitle(app, timeout: 10) { $0.hasPrefix("Asr at ") }
    XCTAssertTrue(title.hasPrefix("Asr at "), title)
    add(screenshot(window, named: "01-schedule-window"))
  }

  /// In Arabic, the window and the title use Arabic names and digits.
  @MainActor
  func testArabic() throws {
    let noon = try XCTUnwrap(try? Date("2026-10-14T12:30:00+03:00", strategy: .iso8601))
    let app = launch(["-language", "ar"], now: noon)
    let window = window(app)
    XCTAssertTrue(text(window, startingWith: "مكة").exists, window.debugDescription)
    XCTAssertTrue(text(window, startingWith: "العصر").exists, window.debugDescription)
    // Foundation wraps a localized format's arguments in bidi isolates (U+2068, U+2069).
    func unisolated(_ text: String) -> String {
      text.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
    }
    let title = waitForTitle(app, timeout: 10) { unisolated($0).hasPrefix("العصر") }
    XCTAssertTrue(unisolated(title).hasPrefix("العصر الساعة "), title)
    XCTAssertTrue(title.contains("٣"), "Arabic-Indic digits: \(title)")
    add(screenshot(window, named: "02-arabic"))
  }

  /// The title is static text refreshed at the `.steps` plan's dates: launched seconds before
  /// Asr, it turns to "Asr started 0 seconds ago" at Asr and "Asr started 1 minute ago" a minute
  /// later, with nothing touching the app.
  @MainActor
  func testTitleRefreshesOnTheMinute() throws {
    let asr = try Self.time(of: .asr)
    let app = launch(now: asr.addingTimeInterval(-3))
    let started = waitForTitle(app, timeout: 30) { $0 == "Asr started 0 seconds ago" }
    XCTAssertEqual(started, "Asr started 0 seconds ago")
    let minute = waitForTitle(app, timeout: 75) { $0 == "Asr started 1 minute ago" }
    XCTAssertEqual(minute, "Asr started 1 minute ago")
  }

  /// The app's own Stop button: the test tone plays, the window shows what plays, and Stop
  /// ends it.
  @MainActor
  func testAppStopButton() throws {
    let app = launch()
    let window = window(app)
    window.buttons["playTestTone"].click()
    let playing = window.staticTexts["playingText"]
    XCTAssertTrue(playing.waitForExistence(timeout: 10), window.debugDescription)
    XCTAssertEqual(playing.value as? String, "Playing the test tone")
    add(screenshot(window, named: "03-playing"))
    let stop = window.buttons["stopButton"]
    XCTAssertEqual(stop.label, "Stop the tone")
    stop.click()
    XCTAssertTrue(playing.waitForNonExistence(timeout: 10), window.debugDescription)
  }

  /// The tone switch turns the app's tone off and on, and is disabled once alerts are off.
  @MainActor
  func testToneToggle() throws {
    let app = launch(["-alerts", "on"])
    let window = window(app)
    let tone = window.checkBoxes["toneToggle"]
    XCTAssertTrue(tone.waitForExistence(timeout: 10), window.debugDescription)
    XCTAssertEqual(tone.label, "Play the app's tone")
    XCTAssertTrue(tone.isEnabled)
    XCTAssertEqual(tone.value as? Int, 1)
    tone.click()
    XCTAssertTrue(waitForValue(tone, 0), window.debugDescription)
    tone.click()
    XCTAssertTrue(waitForValue(tone, 1), window.debugDescription)
    window.checkBoxes["alertsToggle"].click()
    XCTAssertTrue(waitForDisabled(tone), window.debugDescription)
  }

  /// Waits for a checkbox to show `value`.
  @MainActor
  func waitForValue(_ element: XCUIElement, _ value: Int) -> Bool {
    let deadline = Date().addingTimeInterval(10)
    while element.value as? Int != value, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.2)
    }
    return element.value as? Int == value
  }

  /// Waits for an element to be disabled.
  @MainActor
  func waitForDisabled(_ element: XCUIElement) -> Bool {
    let deadline = Date().addingTimeInterval(10)
    while element.isEnabled, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.2)
    }
    return !element.isEnabled
  }

  @MainActor
  private func screenshot(_ element: XCUIElement, named name: String) -> XCTAttachment {
    let attachment = XCTAttachment(screenshot: element.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    return attachment
  }
}
