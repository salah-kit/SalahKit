import XCTest

/// What the iPad and the tvOS journeys share: how they launch the board and read it.
///
/// The members are `@MainActor`, so they compile under both default isolation settings.
extension XCTestCase {
  /// Launches the real app on a board, with its clock frozen at an ISO 8601 instant and its
  /// names, digits and dates in `language`, and waits until the board is on screen.
  @MainActor
  func launchBoard(_ board: String, at instant: String, language: String = "en")
    -> XCUIApplication
  {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-board", board, "-now", instant, "-frozen", "-language", language,
      "-AppleLanguages", "(\(language))", "-AppleLocale", language,
    ]
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(element("header.title", in: app).waitForExistence(timeout: 30))
    return app
  }

  @MainActor
  func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// The element's accessibility label, without the directional isolates (U+2068, U+2069) that
  /// Foundation puts around arguments interpolated into right-to-left strings.
  @MainActor
  func label(_ identifier: String, in app: XCUIApplication) -> String {
    let element = element(identifier, in: app)
    XCTAssertTrue(element.waitForExistence(timeout: 10), "\(identifier) is missing")
    return element.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
  }

  @MainActor
  func assertMissing(_ identifier: String, in app: XCUIApplication) {
    XCTAssertFalse(element(identifier, in: app).exists, "\(identifier) shouldn't be shown")
  }

  /// The screen as a person sees it. `XCUIScreen` keeps landscape screenshots upright.
  @MainActor
  func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
