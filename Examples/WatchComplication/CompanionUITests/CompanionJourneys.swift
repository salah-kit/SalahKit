import XCTest

/// Shared steps of the companion journeys.
///
/// The classes are `nonisolated` and their members `@MainActor`, so they compile under both
/// default isolation settings.
nonisolated class CompanionJourneyCase: XCTestCase {
  @MainActor
  func launch(_ arguments: [String] = [], language: String = "en") -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      ["-language", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
      + arguments
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(element("send", in: app).waitForExistence(timeout: 30))
    return app
  }

  @MainActor
  func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @MainActor
  func label(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 15) -> String {
    let element = element(identifier, in: app)
    XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(identifier) is missing")
    return element.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
  }

  /// Waits until the element's label is `expected`.
  @MainActor
  func waitForLabel(
    _ identifier: String, _ expected: String, in app: XCUIApplication, timeout: TimeInterval
  ) -> Bool {
    let predicate = NSPredicate(format: "label == %@", expected)
    let expectation = XCTNSPredicateExpectation(
      predicate: predicate, object: element(identifier, in: app))
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  @MainActor
  func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

/// The companion on its own: presets, a send and the session's state, on any iPhone
/// simulator, paired or not.
nonisolated final class CompanionJourneys: CompanionJourneyCase {
  @MainActor
  func testChoosingAndSendingAPreset() {
    let app = launch()
    for preset in ["makkah", "mosque", "mosqueEnded"] {
      XCTAssertTrue(element("preset.\(preset)", in: app).exists, "preset.\(preset) is missing")
    }
    XCTAssertTrue(element("preset.makkah", in: app).isSelected)
    element("preset.mosque", in: app).tap()
    XCTAssertTrue(element("preset.mosque", in: app).isSelected)
    element("send", in: app).tap()
    XCTAssertEqual(label("sent.preset", in: app), "Sample Mosque, three days")
    XCTAssertEqual(label("sent.fingerprint", in: app).count, 16)
    // Without a paired watch with the app installed, WatchConnectivity refuses the context and
    // the companion says why; with one, it's queued.
    let result = label("sent.result", in: app)
    XCTAssertTrue(
      result == "Queued for the watch" || result.hasPrefix("Not sent: "), "Result: \(result)")
    XCTAssertFalse(label("session.activation", in: app).isEmpty)
    screenshot("companion-sent")
  }
}

/// The companion's side of the paired journey; `Scripts/paired-journeys.sh` runs its steps
/// between the watch's, with `WATCHCOMPLICATION_PAIRED=1`.
nonisolated final class CompanionPairedJourney: CompanionJourneyCase {
  override func setUpWithError() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["WATCHCOMPLICATION_PAIRED"] == "1",
      "Paired journey steps run only from Scripts/paired-journeys.sh.")
  }

  @MainActor
  private func send(_ preset: String, title: String, screenshotName: String) {
    let app = launch()
    XCTAssertTrue(
      waitForLabel("session.activation", "Activated", in: app, timeout: 60),
      "Session: \(label("session.activation", in: app))")
    XCTAssertTrue(
      waitForLabel("session.paired", "Yes", in: app, timeout: 60), "The iPhone isn't paired")
    XCTAssertTrue(
      waitForLabel("session.installed", "Yes", in: app, timeout: 120),
      "The watch app isn't installed on the paired watch")
    element("preset.\(preset)", in: app).tap()
    element("send", in: app).tap()
    XCTAssertEqual(label("sent.preset", in: app), title)
    XCTAssertEqual(label("sent.result", in: app), "Queued for the watch")
    XCTAssertEqual(label("session.context", in: app), label("sent.fingerprint", in: app))
    print("WATCHCOMPLICATION sent \(preset): \(label("sent.fingerprint", in: app))")
    screenshot(screenshotName)
  }

  /// Sends the timetable that ended yesterday.
  @MainActor
  func test1SendTheEndedTimetable() {
    send(
      "mosqueEnded", title: "Sample Mosque, ended", screenshotName: "paired-1-companion-sent-ended")
  }

  /// Sends Makkah, different inputs.
  @MainActor
  func test2SendMakkah() {
    send("makkah", title: "Makkah, calculated", screenshotName: "paired-2-companion-sent-makkah")
  }
}
