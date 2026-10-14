import XCTest

/// Helpers shared by the journeys. The class is `nonisolated` and its members `@MainActor`, so
/// it compiles under both default isolation settings: XCTestCase's initializers and `setUp`
/// aren't main-actor isolated.
nonisolated class JourneyCase: XCTestCase {
  /// Makkah, 14:00 on Wednesday 14 October 2026.
  static let makkahAfternoon = "2026-10-14T14:00:00+03:00"

  @MainActor
  func launch(_ arguments: [String], clean: Bool = false) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + (clean ? ["-cleanStart"] : [])
      + arguments
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(element("save.status", in: app).waitForExistence(timeout: 30))
    return app
  }

  @MainActor
  func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// The element's label, without the directional isolates (U+2068, U+2069) that Foundation puts
  /// around arguments interpolated into strings.
  @MainActor
  func label(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 10) -> String {
    let element = element(identifier, in: app)
    if !element.waitForExistence(timeout: timeout) {
      reveal(element, in: app)
    }
    XCTAssertTrue(element.exists, "\(identifier) is missing")
    return Self.clean(element.label)
  }

  static func clean(_ text: String) -> String {
    text.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
  }

  @MainActor
  func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func attach(_ text: String, named name: String) {
    let attachment = XCTAttachment(string: text)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Chooses an option of a picker that pushes a list, and waits to come back.
  @MainActor
  func pick(_ option: String, from identifier: String, of app: XCUIApplication) {
    let picker = element(identifier, in: app)
    reveal(picker, in: app)
    picker.tap()
    let row = app.buttons[option].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "\(option) isn't offered")
    row.tap()
    XCTAssertTrue(app.navigationBars["PhoneWidgets"].waitForExistence(timeout: 10))
  }

  /// Taps a segment of the language picker.
  @MainActor
  func chooseLanguage(_ name: String, in app: XCUIApplication) {
    let control = app.segmentedControls["settings.language"]
    reveal(control, in: app)
    control.buttons[name].tap()
    XCTAssertTrue(control.buttons[name].isSelected)
  }

  /// Goes back to the settings screen.
  @MainActor
  func goBack(in app: XCUIApplication) {
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.navigationBars["PhoneWidgets"].waitForExistence(timeout: 10))
  }

  /// Scrolls until the element is hittable: back toward the top first, then down. Lists load
  /// their rows lazily, so a row off screen may not exist until it's scrolled to.
  @MainActor
  func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    if element.waitForExistence(timeout: 2) && element.isHittable { return }
    for _ in 0..<3 where !(element.exists && element.isHittable) {
      app.swipeDown(velocity: .fast)
    }
    for _ in 0..<25 where !(element.exists && element.isHittable) {
      app.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(element.exists, "\(element) is missing")
  }

  /// Scrolls to a navigation link of the settings screen and opens it.
  @MainActor
  func open(_ identifier: String, in app: XCUIApplication) {
    let link = element(identifier, in: app)
    reveal(link, in: app)
    link.tap()
  }
}
