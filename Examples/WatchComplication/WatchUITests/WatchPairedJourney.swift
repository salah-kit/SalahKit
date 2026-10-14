import XCTest

/// The watch's side of the paired journey. `Scripts/paired-journeys.sh` runs its steps in order,
/// one `xcodebuild test` at a time, between the companion's steps on the paired iPhone
/// simulator; it sets `WATCHCOMPLICATION_PAIRED=1` (through `TEST_RUNNER_`). Without it, the
/// steps skip: they need an iPhone that sends.
nonisolated final class WatchPairedJourney: WatchJourneyCase {
  override func setUpWithError() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["WATCHCOMPLICATION_PAIRED"] == "1",
      "Paired journey steps run only from Scripts/paired-journeys.sh.")
  }

  /// Polls, relaunching the app now and then, until `condition` holds or `timeout` passes.
  /// WatchConnectivity delivers between simulators within seconds, not instantly.
  @MainActor
  private func wait(
    timeout: TimeInterval, in app: inout XCUIApplication,
    until condition: (XCUIApplication) -> Bool
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    var relaunch = Date().addingTimeInterval(30)
    while Date() < deadline {
      if condition(app) { return true }
      if Date() > relaunch {
        app.terminate()
        app = launch([])
        relaunch = Date().addingTimeInterval(30)
      }
      Thread.sleep(forTimeInterval: 2)
    }
    return condition(app)
  }

  /// Step 1, on a fresh install before the iPhone sent anything: no inputs.
  @MainActor
  func test1FreshWatchHasNoSettings() {
    let app = launch([])
    XCTAssertEqual(label("setup.title", in: app), "No settings yet")
    app.descendants(matching: .any).matching(identifier: "nav.states").firstMatch.tap()
    assertLabel("states.now.rectangular", in: app, contains: ["No settings yet"])
    screenshot("paired-1-watch-no-settings")
  }

  /// Step 2, after the iPhone sent the ended timetable: received, stored and shown as ended.
  @MainActor
  func test2ReceivesTheEndedTimetable() {
    var app = launch([])
    let received = wait(timeout: 180, in: &app) {
      self.element("home.place", in: $0).exists
        && self.element("home.place", in: $0).label == "Sample Mosque"
    }
    XCTAssertTrue(received, "The watch didn't receive the timetable")
    XCTAssertEqual(label("home.title", in: app), "Timetable ended")
    assertLabel("home.received", in: app, contains: ["Received", "changed"])
    screenshot("paired-2-watch-timetable-ended")
    element("nav.states", in: app).tap()
    assertLabel(
      "states.now.rectangular", in: app,
      contains: ["Timetable ended", "Send new times from the iPhone"])
  }

  /// Step 3, after the iPhone sent different inputs: the watch updates to them.
  @MainActor
  func test3ReceivesMakkah() {
    var app = launch([])
    let received = wait(timeout: 180, in: &app) {
      self.element("home.place", in: $0).exists
        && self.element("home.place", in: $0).label == "Makkah"
    }
    XCTAssertTrue(received, "The watch didn't receive Makkah")
    XCTAssertTrue(element("home.next", in: app).waitForExistence(timeout: 10))
    assertLabel("home.received", in: app, contains: ["Received", "changed"])
    screenshot("paired-3-watch-makkah")
  }

  /// Step 4, with the companion terminated: a new launch shows the schedule from storage.
  @MainActor
  func test4WorksWithThePhoneAppClosed() {
    let app = launch([])
    XCTAssertEqual(label("home.place", in: app), "Makkah")
    XCTAssertEqual(label("home.source", in: app), "Calculated on the watch")
    XCTAssertTrue(element("home.next", in: app).waitForExistence(timeout: 10))
    // The label names the next prayer, whichever it is at the moment of the run.
    let next = label("home.next", in: app)
    XCTAssertTrue(
      ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].contains { next.hasPrefix($0) },
      "home.next is “\(next)”, without a prayer's name")
    print("WATCHCOMPLICATION home.next: \(label("home.next", in: app))")
    print("WATCHCOMPLICATION home.phone: \(label("home.phone", in: app))")
    screenshot("paired-4-watch-phone-app-closed")
    element("nav.diagnostics", in: app).tap()
    print("WATCHCOMPLICATION diagnostics: \(label("diagnostics.count", in: app))")
  }
}
