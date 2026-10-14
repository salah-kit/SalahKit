import XCTest

/// Tries to reach the complication outside the app: the watch face and the Smart Stack, through
/// the watch's home app. Diagnostics, not a journey: it prints what it finds and passes. Runs only
/// with `WATCHCOMPLICATION_PROBE=1` (through `TEST_RUNNER_`).
nonisolated final class FaceProbe: WatchJourneyCase {
  override func setUpWithError() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["WATCHCOMPLICATION_PROBE"] == "1",
      "The face probe runs only on request.")
  }

  @MainActor
  func testProbeTheFaceAndTheSmartStack() {
    let app = launch(["-preset", "makkah"])
    XCTAssertTrue(element("home.place", in: app).waitForExistence(timeout: 20))
    XCUIDevice.shared.press(.home)
    let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
    Thread.sleep(forTimeInterval: 3)
    print("WATCHCOMPLICATION face state=\(carousel.state.rawValue)")
    print("WATCHCOMPLICATION face:\n\(carousel.debugDescription)")
    screenshot("probe-1-face")

    // watchOS 10 and later: turning the crown up from the face opens the Smart Stack.
    XCUIDevice.shared.rotateDigitalCrown(delta: -1, velocity: .default)
    Thread.sleep(forTimeInterval: 3)
    print("WATCHCOMPLICATION stack:\n\(carousel.debugDescription)")
    screenshot("probe-2-smart-stack")
    XCUIDevice.shared.rotateDigitalCrown(delta: -1, velocity: .default)
    Thread.sleep(forTimeInterval: 3)
    print("WATCHCOMPLICATION stack 2:\n\(carousel.debugDescription)")
    screenshot("probe-3-smart-stack")

    // Back to the face, then a long press opens the face editor.
    XCUIDevice.shared.press(.home)
    Thread.sleep(forTimeInterval: 2)
    carousel.press(forDuration: 2)
    Thread.sleep(forTimeInterval: 3)
    print("WATCHCOMPLICATION editor:\n\(carousel.debugDescription)")
    screenshot("probe-4-face-editor")
  }
}
