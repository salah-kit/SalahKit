import XCTest

/// The alerts journey on an iPhone simulator, with the real clock (RFC 0003 §8):
///
/// 1. turn alerts on in Settings, allow notifications through Springboard, and wait until the
///    app has an alert confirmed;
/// 2. relaunch and schedule alerts a minute or two ahead from the fixture timetable
///    (`-alertFixtureIn`), so a slow permission prompt can't use up their lead;
/// 3. terminate the app;
/// 4. watch the first alert arrive through Springboard;
/// 5. relaunch with the fixture's times moved, and read the pending requests back: the same
///    requests, at the new times;
/// 6. relaunch with Dhuhr's add failing (`-failAlertAdds`), and read back again: Dhuhr's old
///    request is still there, unconfirmed, and the scheduled coverage stops before it;
/// 7. turn alerts off, which removes the app's requests, and measure how many pending requests
///    the system keeps for one app (`-probeNotificationLimit`).
///
/// Every launch names the fixture's owning day, so the requests keep their identities even if
/// the journey crosses midnight.
nonisolated final class AlertJourneys: XCTestCase {
  @MainActor
  private func launch(_ arguments: [String]) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      ["-language", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en", "-place", "makkah"]
      + arguments
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(element("header.place", in: app).waitForExistence(timeout: 30))
    return app
  }

  @MainActor
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// The element's label without directional isolates, once it exists and is visible.
  @MainActor
  private func label(_ identifier: String, in app: XCUIApplication) -> String {
    let element = element(identifier, in: app)
    XCTAssertTrue(element.waitForExistence(timeout: 30), "\(identifier) is missing")
    return element.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
  }

  /// Waits until an element's label satisfies `condition`.
  @MainActor
  private func waitForLabel(
    _ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 30,
    _ condition: (String) -> Bool
  ) -> String {
    let deadline = Date().addingTimeInterval(timeout)
    var last = ""
    while Date() < deadline {
      let element = element(identifier, in: app)
      if element.exists {
        last = element.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
        if condition(last) { return last }
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    let failures = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "alerts.failure."))
      .allElementsBoundByIndex.map(\.label)
    XCTFail(
      "\(identifier) never satisfied the condition; last label: \(last); failures: \(failures)")
    return last
  }

  /// Scrolls the screen until the element is visible.
  @MainActor
  private func reveal(_ identifier: String, in app: XCUIApplication) {
    let element = element(identifier, in: app)
    for _ in 0..<10 where !(element.exists && element.isHittable) {
      app.swipeUp(velocity: .slow)
    }
  }

  @MainActor
  private func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// The fixture's owning day: today in Makkah.
  private static func makkahDay() -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Riyadh") ?? .gmt
    let parts = calendar.dateComponents([.year, .month, .day], from: Date())
    return String(
      format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  private static let prayers = ["fajr", "dhuhr", "asr", "maghrib", "isha"]

  @MainActor
  func testAlertsArriveWithTheAppClosedAndReadBackAfterChanges() throws {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let day = Self.makkahDay()
    // Step 1 turns alerts on through the interface. The later launches say so too, so they
    // don't depend on how soon the settings reached the disk before the app was terminated.
    let fixture = ["-alerts", "on", "-alertFixtureDay", day]
    func row(_ prayer: String) -> String { "alerts.request.\(day)/\(prayer)/atTime" }

    // 1. Alerts on, permission through Springboard.
    let settings = launch(["-resetSettings"])
    element("settings.open", in: settings).tap()
    let toggle = settings.switches["settings.alerts"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    // The switch itself takes the tap; a tap on the middle of its row doesn't toggle it.
    let knob = toggle.switches.firstMatch
    (knob.exists ? knob : toggle).tap()
    // The app asks for permission when alerts are turned on, and the switch turns on once the
    // request is answered. Springboard shows the request: on a simulator that has just booted,
    // only after a minute or two; on one that already allowed the app, never.
    let allow = springboard.alerts.buttons["Allow"]
    let deadline = Date().addingTimeInterval(180)
    while Date() < deadline, toggle.value as? String != "1" {
      if allow.exists {
        screenshot("alerts-1-permission")
        allow.tap()
        break
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    XCTAssertTrue(waitForValue(toggle, "1"), "alerts didn't turn on")
    element("settings.done", in: settings).tap()
    XCTAssertEqual(label("alerts.status", in: settings), "Notifications are allowed.")
    // The system can reject the first requests after the permission ("Source is not
    // authorized"); the app tries them again until one is confirmed.
    let confirmed = settings.descendants(matching: .any)
      .matching(
        NSPredicate(
          format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@ AND label == %@",
          "alerts.request.", ".status", "Confirmed")
      ).firstMatch
    if !confirmed.waitForExistence(timeout: 180) {
      let failures = settings.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier BEGINSWITH %@", "alerts.failure."))
        .allElementsBoundByIndex.map(\.label)
      XCTFail("no alert was confirmed after the permission; failures: \(failures)")
    }
    screenshot("alerts-1-confirmed")
    settings.terminate()

    // 2. Five requests, a minute apart, confirmed by the read-back.
    let app = launch(["-alertFixtureIn", "100"] + fixture)
    reveal(row("isha"), in: app)
    XCTAssertEqual(label("alerts.status", in: app), "Notifications are allowed.")
    var firstTimes: [String: String] = [:]
    for prayer in Self.prayers {
      _ = waitForLabel("\(row(prayer)).status", in: app) { $0 == "Confirmed" }
      firstTimes[prayer] = label("\(row(prayer)).time", in: app)
    }
    XCTAssertEqual(Set(firstTimes.values).count, 5)
    screenshot("alerts-2-scheduled")

    // 3. The app is closed. 4. The first alert arrives through Springboard.
    app.terminate()
    // The body is "It's time for Fajr (…)", with directional isolates around the name.
    let banner = springboard.descendants(matching: .any)
      .matching(
        NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "It's time for", "Fajr")
      ).firstMatch
    XCTAssertTrue(banner.waitForExistence(timeout: 180), "no Fajr notification arrived")
    screenshot("alerts-3-delivered")

    // 5. A time change: the fixture's times move. The same requests are pending at the new
    // times, and every one is confirmed.
    let moved = launch(["-alertFixtureIn", "600"] + fixture)
    reveal(row("isha"), in: moved)
    var movedTimes: [String: String] = [:]
    for prayer in Self.prayers {
      movedTimes[prayer] = waitForLabel("\(row(prayer)).time", in: moved) {
        $0 != firstTimes[prayer]
      }
      XCTAssertEqual(label("\(row(prayer)).status", in: moved), "Confirmed")
    }
    let scheduled = label("alerts.scheduledUntil", in: moved)
    let planned = label("alerts.plannedUntil", in: moved)
    XCTAssertEqual(
      scheduled.replacingOccurrences(of: "Scheduled", with: ""),
      planned.replacingOccurrences(of: "Planned", with: ""))
    screenshot("alerts-4-moved")
    moved.terminate()

    // 6. An injected failure: Dhuhr's add fails. Its old request stays, unconfirmed; the
    // others move; the scheduled coverage now ends before the planned one.
    let failing = launch(["-alertFixtureIn", "900", "-failAlertAdds", "dhuhr"] + fixture)
    reveal(row("isha"), in: failing)
    _ = waitForLabel("\(row("dhuhr")).status", in: failing) { $0 == "Couldn't be scheduled" }
    XCTAssertEqual(label("\(row("dhuhr")).time", in: failing), movedTimes["dhuhr"])
    for prayer in ["asr", "maghrib", "isha"] {
      _ = waitForLabel("\(row(prayer)).time", in: failing) { $0 != movedTimes[prayer] }
      XCTAssertEqual(label("\(row(prayer)).status", in: failing), "Confirmed")
    }
    let shortened = label("alerts.scheduledUntil", in: failing)
    XCTAssertNotEqual(
      shortened.replacingOccurrences(of: "Scheduled", with: ""),
      label("alerts.plannedUntil", in: failing).replacingOccurrences(of: "Planned", with: ""))
    screenshot("alerts-5-failure")
    failing.terminate()

    // 7. Alerts off removes the app's requests, which leaves the simulator clean. With none
    // pending, the probe measures how many requests the system keeps for one app.
    let off = launch(["-alerts", "off", "-probeNotificationLimit", "70"])
    _ = waitForLabel("alerts.status", in: off) { $0.hasPrefix("Alerts are off") }
    reveal("alerts.probe", in: off)
    let probe = waitForLabel("alerts.probe", in: off, timeout: 60) {
      $0.hasPrefix("The system kept")
    }
    let attachment = XCTAttachment(string: probe)
    attachment.name = "pending-request-probe"
    attachment.lifetime = .keepAlways
    add(attachment)
    screenshot("alerts-6-probe")
    off.terminate()
  }

  @MainActor
  private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline {
      if element.value as? String == value { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    return false
  }
}
