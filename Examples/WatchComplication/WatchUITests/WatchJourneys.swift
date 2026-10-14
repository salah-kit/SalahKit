import XCTest

/// Shared steps of the watch journeys.
///
/// The classes are `nonisolated` and their members `@MainActor`, so they compile under both
/// default isolation settings: XCTestCase's initializers and `setUp` aren't main-actor
/// isolated.
nonisolated class WatchJourneyCase: XCTestCase {
  /// 14:00 in Makkah on Wednesday 14 October 2026.
  static let makkahAfternoon = "2026-10-14T14:00:00+03:00"

  @MainActor
  func launch(_ arguments: [String], language: String = "en") -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      ["-language", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
      + arguments
    // A watch simulator on a busy machine sometimes doesn't bring the app up; one more launch
    // gets it there.
    app.launch()
    if !app.wait(for: .runningForeground, timeout: 60) {
      app.terminate()
      app.launch()
    }
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60))
    return app
  }

  @MainActor
  func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// The element's label, without the directional isolates (U+2068, U+2069) that Foundation
  /// puts around interpolated arguments.
  @MainActor
  func label(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 20) -> String {
    let element = element(identifier, in: app)
    XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(identifier) is missing")
    return element.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
  }

  @MainActor
  func assertLabel(
    _ identifier: String, in app: XCUIApplication, contains parts: [String],
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let text = label(identifier, in: app)
    for part in parts {
      XCTAssertTrue(
        text.contains(part), "\(identifier) is “\(text)”, without “\(part)”", file: file,
        line: line)
    }
  }

  @MainActor
  func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Scrolls until the element is on screen, for screenshots.
  @MainActor
  func scroll(to identifier: String, in app: XCUIApplication) {
    let target = element(identifier, in: app)
    XCTAssertTrue(target.waitForExistence(timeout: 10), "\(identifier) is missing")
    for _ in 0..<12 where !target.isHittable {
      app.swipeUp()
    }
  }
}

/// Journeys through the real watch app on a watch simulator, with no iPhone: missing inputs,
/// the complication states screen, and inputs kept in the watch's own storage across launches.
nonisolated final class WatchJourneys: WatchJourneyCase {
  /// A fresh watch has no inputs and says to open the iPhone app.
  @MainActor
  func testWithoutInputsTheWatchAsksForTheIPhoneApp() {
    let app = launch(["-resetInputs"])
    XCTAssertEqual(label("setup.title", in: app), "No settings yet")
    XCTAssertEqual(
      label("setup.detail", in: app),
      "Open WatchComplication on your iPhone to send a place and its times.")
    XCTAssertFalse(element("home.place", in: app).exists)
    screenshot("01-no-settings")
  }

  /// The states screen draws every state with the complication's own views.
  @MainActor
  func testTheStatesScreenDrawsEveryState() {
    let app = launch(["-resetInputs", "-now", Self.makkahAfternoon, "-screen", "states"])

    // Now, from the stored inputs: none, so the missing-settings view in every family.
    assertLabel(
      "states.now.rectangular", in: app, contains: ["No settings yet", "Open the iPhone app"])
    assertLabel("states.now.circular", in: app, contains: ["No settings yet"])
    assertLabel("states.now.corner", in: app, contains: ["No settings yet"])
    assertLabel("states.now.inline", in: app, contains: ["No settings yet"])
    screenshot("02-states-missing-settings")

    assertLabel("states.setup.rectangular", in: app, contains: ["No settings yet"])
    // Makkah at 14:00: Asr at 3:27 PM, 1 hour 27 minutes away.
    assertLabel("states.next.rectangular", in: app, contains: ["Asr", "3:27", "Makkah"])
    // The circular family has room for the abbreviation and the countdown only.
    assertLabel("states.next.circular", in: app, contains: ["A", "1 hour, 27 minutes"])
    assertLabel("states.next.inline", in: app, contains: ["Asr"])
    // Late on the timetable's last day: Isha is known, the next prayer isn't.
    assertLabel(
      "states.partial.rectangular", in: app,
      contains: ["Latest: Isha", "Next prayer unknown", "Send new times from the iPhone"])
    // The day after: the timetable ended, which only new times from the iPhone fix.
    assertLabel(
      "states.ended.rectangular", in: app,
      contains: ["Timetable ended", "Send new times from the iPhone"])
    assertLabel("states.ended.circular", in: app, contains: ["Timetable ended"])
    assertLabel("states.ended.corner", in: app, contains: ["Timetable ended"])
    assertLabel("states.ended.inline", in: app, contains: ["Timetable ended"])
    assertLabel(
      "states.unavailable.rectangular", in: app,
      contains: ["Times unavailable", "Invalid location or settings"])
    // The end of a timeline, which a reload fixes: worded apart from the ended timetable.
    assertLabel("states.expired.rectangular", in: app, contains: ["Times need refreshing"])
    XCTAssertFalse(label("states.expired.rectangular", in: app).contains("Timetable ended"))
    XCTAssertFalse(label("states.ended.rectangular", in: app).contains("refreshing"))

    scroll(to: "states.next.rectangular", in: app)
    screenshot("03-states-next-prayer")
    scroll(to: "states.ended.rectangular", in: app)
    screenshot("04-states-timetable-ended")
    scroll(to: "states.expired.rectangular", in: app)
    screenshot("05-states-timeline-expired")
  }

  /// Inputs stored once are read back from the watch's storage on every later launch.
  @MainActor
  func testStoredInputsShowTheScheduleOnLaterLaunches() {
    var app = launch(["-resetInputs", "-preset", "makkah", "-now", Self.makkahAfternoon])
    XCTAssertEqual(label("home.place", in: app), "Makkah")
    XCTAssertEqual(label("home.source", in: app), "Calculated on the watch")
    assertLabel("home.next", in: app, contains: ["Asr", "3:27"])
    assertLabel("home.received", in: app, contains: ["From launch arguments", "changed"])
    screenshot("06-makkah-next-prayer")

    // A later launch with no inputs given reads the stored ones.
    app.terminate()
    app = launch(["-now", Self.makkahAfternoon])
    XCTAssertEqual(label("home.place", in: app), "Makkah")
    assertLabel("home.next", in: app, contains: ["Asr", "3:27"])
  }

  /// A timetable past its last row shows the ended view, not a countdown.
  @MainActor
  func testAnEndedTimetableAsksForNewTimes() {
    let app = launch(["-resetInputs", "-preset", "mosqueEnded"])
    XCTAssertEqual(label("home.place", in: app), "Sample Mosque")
    assertLabel("home.source", in: app, contains: ["Timetable through"])
    XCTAssertEqual(label("home.title", in: app), "Timetable ended")
    assertLabel(
      "home.detail", in: app,
      contains: [
        "No published times from", "Open WatchComplication on your iPhone to send new times.",
      ])
    XCTAssertFalse(element("home.next", in: app).exists)
    screenshot("07-timetable-ended")
  }

  /// Arabic strings, names and digits, right to left.
  @MainActor
  func testArabic() {
    let app = launch(
      ["-resetInputs", "-preset", "makkah", "-now", Self.makkahAfternoon], language: "ar")
    XCTAssertEqual(label("home.place", in: app), "Makkah")
    assertLabel("home.next", in: app, contains: ["العصر", "٣:٢٧"])
    screenshot("08-makkah-arabic")
  }
}
