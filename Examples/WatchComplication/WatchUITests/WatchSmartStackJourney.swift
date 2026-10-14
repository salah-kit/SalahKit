import XCTest

/// The complication outside the app: added to the Smart Stack through the watch's home app,
/// then fed the ended timetable and no inputs through the watch app's storage. The paired
/// script runs these steps after the companion closed, and checks the complication extension's
/// timeline log for each one; the screenshots show what the stack drew.
///
/// The home app exposes no accessibility elements in the Smart Stack and its editor, so the
/// steps tap coordinates measured on a 46 mm watch (Apple Watch Series 11) running watchOS 27,
/// and may need new ones on another watch or system. They skip unless
/// `WATCHCOMPLICATION_PAIRED=1`.
nonisolated final class WatchSmartStackJourney: WatchJourneyCase {
  override func setUpWithError() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["WATCHCOMPLICATION_PAIRED"] == "1",
      "Smart Stack steps run only from Scripts/paired-journeys.sh.")
  }

  @MainActor
  private var carousel: XCUIApplication {
    XCUIApplication(bundleIdentifier: "com.apple.Carousel")
  }

  @MainActor
  private func tap(x: CGFloat, y: CGFloat) {
    carousel.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
  }

  /// From the face, turning the crown opens the Smart Stack.
  @MainActor
  private func openTheSmartStack() {
    XCUIDevice.shared.press(.home)
    Thread.sleep(forTimeInterval: 3)
    XCUIDevice.shared.rotateDigitalCrown(delta: 1, velocity: .default)
    Thread.sleep(forTimeInterval: 8)
  }

  /// Step 8: adds the example's widget to the Smart Stack, which makes WidgetKit ask the
  /// extension for a timeline.
  @MainActor
  func test5AddTheComplicationToTheSmartStack() {
    let app = launch([])
    XCTAssertEqual(label("home.place", in: app), "Makkah")
    openTheSmartStack()
    tap(x: 0.5, y: 0.86)  // Edit, under the stack
    Thread.sleep(forTimeInterval: 4)
    tap(x: 0.5, y: 0.43)  // The add slot
    Thread.sleep(forTimeInterval: 4)
    for _ in 0..<6 {  // The example is last in the list of apps.
      carousel.swipeUp()
      Thread.sleep(forTimeInterval: 1.5)
    }
    tap(x: 0.5, y: 0.72)  // WatchComplication
    Thread.sleep(forTimeInterval: 4)
    screenshot("smartstack-1-gallery")
    tap(x: 0.5, y: 0.5)  // Its widget
    Thread.sleep(forTimeInterval: 4)
    tap(x: 0.15, y: 0.14)  // Done
    Thread.sleep(forTimeInterval: 6)
    openTheSmartStack()
    screenshot("smartstack-2-makkah")
  }

  /// Step 9: the watch app stores the ended timetable and reloads the complication.
  @MainActor
  func test6TheEndedTimetableReachesTheComplication() {
    let app = launch(["-preset", "mosqueEnded"])
    XCTAssertEqual(label("home.title", in: app), "Timetable ended")
    Thread.sleep(forTimeInterval: 5)
    openTheSmartStack()
    screenshot("smartstack-3-timetable-ended")
  }

  /// Step 10: the watch app removes its inputs and reloads the complication.
  @MainActor
  func test7MissingSettingsReachTheComplication() {
    let app = launch(["-resetInputs"])
    XCTAssertEqual(label("setup.title", in: app), "No settings yet")
    Thread.sleep(forTimeInterval: 5)
    openTheSmartStack()
    screenshot("smartstack-4-missing-settings")
  }
}
