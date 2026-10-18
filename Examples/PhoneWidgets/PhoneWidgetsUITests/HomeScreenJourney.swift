import XCTest

/// The real widget extension on the Home Screen, driven through Springboard.
///
/// The journey adds the medium widget the way a person does (Edit, Add Widget, the app, the
/// medium size, Add Widget, Done), then checks what the real extension produced: in Springboard's
/// accessibility tree, which exposes the widget's text and identifiers, and in the diagnostics log
/// the extension writes to the App Group, which the app's "Widget log" screen shows.
///
/// It runs on a simulator in English with the app's language set to Arabic, so Arabic names on the
/// Home Screen come from the extension's explicit-locale catalog lookup, not the system language.
///
/// Hosted CI runners skip it (`PHONEWIDGETS_SKIP_HOME_SCREEN=1`, set by the workflow through
/// `TEST_RUNNER_PHONEWIDGETS_SKIP_HOME_SCREEN`): Springboard's editing UI and WidgetKit's timing
/// on a cold hosted simulator aren't something a pull request should wait on or fail for.
nonisolated final class HomeScreenJourney: JourneyCase {
  /// How long a changed save may take to produce a new timeline in the extension.
  static let reloadWait: TimeInterval = 60
  /// How long an unchanged save is watched for a timeline it shouldn't cause.
  static let quietWait: TimeInterval = 30

  @MainActor
  override func setUp() async throws {
    if ProcessInfo.processInfo.environment["PHONEWIDGETS_SKIP_HOME_SCREEN"] == "1" {
      throw XCTSkip(
        "Skipped on hosted CI runners: the Springboard journey runs on a local simulator.")
    }
  }

  @MainActor
  func testRealExtensionOnTheHomeScreen() throws {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    // (d) A fresh start: no settings in the App Group, as on a fresh install.
    var app = launch([], clean: true)
    XCTAssertTrue(element("setup.waiting", in: app).exists)
    app.terminate()
    removeWidgets(from: springboard)
    addMediumWidget(to: springboard)
    XCTAssertEqual(widgetText("widget.title", in: springboard), "Choose a place")
    XCTAssertEqual(
      widgetText("widget.message", in: springboard), "Open PhoneWidgets to choose a place.")
    screenshot("10-home-setup-required")

    // Setting up in the app reloads the widget: Makkah, English names.
    app = launch(["-place", "makkah", "-method", "ummAlQura", "-language", "en"])
    XCTAssertEqual(label("save.status", in: app), "Save 1: changed, widget reload requested.")
    let english = waitForRecord(of: app, fingerprint: label("settings.fingerprint", in: app))
    XCTAssertEqual(english.fajrName, "Fajr")
    XCTAssertTrue(english.locale.hasPrefix("en"))
    goBack(in: app)
    showWidget(on: springboard)
    XCTAssertTrue(widgetText("widget.row.fajr", in: springboard).hasPrefix("Fajr"))
    // The live countdown says what it counts.
    let countdown = widgetText("widget.next.countdown", in: springboard)
    XCTAssertTrue(countdown.hasPrefix("Time remaining: "), countdown)

    // (a) Arabic names in the extension while the simulator runs in English.
    app.activate()
    chooseLanguage("العربية", in: app)
    XCTAssertEqual(
      label("save.status", in: app), "الحفظ ٢: تغيّرت الإعدادات، وطُلبت إعادة تحميل الأداة.")
    let arabic = waitForRecord(of: app, fingerprint: label("settings.fingerprint", in: app))
    XCTAssertEqual(arabic.fajrName, "الفجر")
    XCTAssertTrue(arabic.locale.hasPrefix("ar"))
    XCTAssertGreaterThan(arabic.sequence, english.sequence)
    // (c) The timeline the extension produced, from its log.
    attach(arabic.details, named: "extension-timeline-arabic")
    screenshot("11-widget-log")
    goBack(in: app)
    showWidget(on: springboard)
    let fajr = widgetText("widget.row.fajr", in: springboard)
    XCTAssertTrue(fajr.hasPrefix("الفجر"), fajr)
    // VoiceOver's label joins the name and time with the Arabic comma, as the extension's
    // language writes it, though the device runs in English.
    XCTAssertTrue(fajr.contains("،") && !fajr.contains(","), fajr)
    let arabicCountdown = widgetText("widget.next.countdown", in: springboard)
    XCTAssertTrue(arabicCountdown.hasPrefix("الوقت المتبقي: "), arabicCountdown)
    XCTAssertEqual(widgetText("widget.place", in: springboard), "مكة المكرمة")
    screenshot("12-home-arabic")

    // (b) Reload gating: saving the same settings asks for no reload, and the extension builds
    // no new timeline in the window.
    app.activate()
    open("save.again", in: app)
    XCTAssertEqual(
      label("save.status", in: app), "الحفظ ٣: لم تتغيّر الإعدادات، ولم تُطلب إعادة تحميل.")
    open("open.log", in: app)
    let before = latestSequence(in: app)
    XCTAssertEqual(before, arabic.sequence, "a timeline was built before the unchanged save")
    let quiet = Date().addingTimeInterval(Self.quietWait)
    while Date() < quiet {
      XCTAssertEqual(latestSequence(in: app), before, "the unchanged save produced a timeline")
      sleep(3)
    }
    goBack(in: app)

    // Back to English. WidgetKit lets the first reload of a foreground session through at
    // once and holds later ones until the app goes to the background (or about 90 seconds), so
    // the journey goes to the Home Screen after each change it waits for.
    chooseLanguage("English", in: app)
    XCTAssertEqual(label("save.status", in: app), "Save 4: changed, widget reload requested.")
    XCTAssertEqual(
      waitForRecord(of: app, fingerprint: label("settings.fingerprint", in: app)).fajrName, "Fajr")
    goBack(in: app)
    showWidget(on: springboard)
    XCTAssertTrue(widgetText("widget.row.fajr", in: springboard).hasPrefix("Fajr"))

    // (d) The unavailable view: invalid coordinates.
    app.activate()
    pick("Invalid coordinates", from: "settings.place", of: app)
    XCTAssertEqual(label("save.status", in: app), "Save 5: changed, widget reload requested.")
    let invalid = waitForRecord(of: app, fingerprint: label("settings.fingerprint", in: app))
    XCTAssertTrue(invalid.states.hasPrefix("available 0 · partial 0 · unavailable"))
    attach(invalid.details, named: "extension-timeline-invalid")
    goBack(in: app)
    showWidget(on: springboard)
    XCTAssertEqual(widgetText("widget.title", in: springboard), "No prayer times")
    XCTAssertEqual(
      widgetText("widget.message", in: springboard), "The place or the settings aren't valid.")
    screenshot("13-home-unavailable")

    // Every record this run, for the generation time and memory numbers.
    app.activate()
    open("open.log", in: app)
    attach(label("log.all", in: app), named: "extension-log")
    goBack(in: app)
    removeWidgets(from: springboard)
  }

  // MARK: Springboard

  /// Adds the medium PhoneWidgets widget to the Home Screen.
  @MainActor
  private func addMediumWidget(to springboard: XCUIApplication) {
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    // A long press on empty space between the icons and the dock opens editing.
    springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
      .press(forDuration: 1.5)
    tap("Edit", in: springboard)
    tap("Add Widget", in: springboard)

    let gallery = springboard.descendants(matching: .any)["add-sheet-collection-view"]
    XCTAssertTrue(gallery.waitForExistence(timeout: 10), springboard.debugDescription)
    let row = gallery.descendants(matching: .any).matching(identifier: "PhoneWidgets").firstMatch
    for _ in 0..<10 where !(row.exists && row.isHittable) {
      gallery.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(row.isHittable, springboard.debugDescription)
    row.tap()

    // The sizes are pages: small, medium, large.
    let preview = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label == 'PhoneWidgets, PhoneWidgets'")).firstMatch
    XCTAssertTrue(preview.waitForExistence(timeout: 10), springboard.debugDescription)
    for _ in 0..<3 where !((preview.value as? String)?.contains("Medium") ?? false) {
      preview.swipeLeft()
    }
    XCTAssertEqual(preview.value as? String, "Widget, Medium")
    let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget'"))
      .firstMatch
    XCTAssertTrue(add.waitForExistence(timeout: 5), springboard.debugDescription)
    add.tap()
    tap("Done", in: springboard)
  }

  /// Removes every PhoneWidgets widget from the Home Screen, so a rerun starts from none.
  @MainActor
  private func removeWidgets(from springboard: XCUIApplication) {
    for _ in 0..<3 {
      guard showWidget(on: springboard) else { return }
      placedWidget(in: springboard).press(forDuration: 1.5)
      tap("Remove Widget", in: springboard)
      tap("Remove", in: springboard)
    }
  }

  @MainActor
  private func tap(_ label: String, in springboard: XCUIApplication) {
    let element = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", label)).firstMatch
    XCTAssertTrue(
      element.waitForExistence(timeout: 10), "\(label): \(springboard.debugDescription)")
    element.tap()
  }

  /// The placed widget on the page on screen: Springboard names it after the app and gives it
  /// the value "Widget". On a page off screen it has neither the value nor a frame.
  @MainActor
  private func placedWidget(in springboard: XCUIApplication) -> XCUIElement {
    springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == 'PhoneWidgets' AND value == 'Widget'"))
      .firstMatch
  }

  /// Goes to the Home Screen and to the page that holds the widget: Springboard comes back to
  /// the page of apps, not always to the page the widget was added to.
  @MainActor
  @discardableResult
  private func showWidget(on springboard: XCUIApplication) -> Bool {
    XCUIDevice.shared.press(.home)
    let widget = placedWidget(in: springboard)
    if widget.waitForExistence(timeout: 3) && widget.isHittable { return true }
    // Toward the first page, then back the other way.
    let swipes: [() -> Void] =
      Array(repeating: { springboard.swipeRight() }, count: 2)
      + Array(repeating: { springboard.swipeLeft() }, count: 4)
    for swipe in swipes {
      swipe()
      if widget.waitForExistence(timeout: 2) && widget.isHittable { return true }
    }
    return false
  }

  /// The label of an element of the placed widget, waiting for the widget to show it.
  @MainActor
  private func widgetText(_ identifier: String, in springboard: XCUIApplication) -> String {
    let element = springboard.descendants(matching: .any).matching(identifier: identifier)
      .firstMatch
    XCTAssertTrue(
      element.waitForExistence(timeout: 30), "\(identifier): \(springboard.debugDescription)")
    return Self.clean(element.label)
  }

  // MARK: The extension's log

  struct Record {
    var sequence: Int
    var fajrName: String
    var locale: String
    var states: String
    var details: String
  }

  @MainActor
  private func latestSequence(in app: XCUIApplication) -> Int {
    Int(label("log.latestSequence", in: app)) ?? 0
  }

  /// Opens the log and waits for the extension's latest record to have read `fingerprint`.
  @MainActor
  private func waitForRecord(of app: XCUIApplication, fingerprint: String) -> Record {
    open("open.log", in: app)
    let deadline = Date().addingTimeInterval(Self.reloadWait)
    while Date() < deadline {
      let latest = element("log.latest.fingerprint", in: app)
      if latest.exists && Self.clean(latest.label) == fingerprint { break }
      sleep(2)
    }
    XCTAssertEqual(
      label("log.latest.fingerprint", in: app), fingerprint,
      "the extension built no timeline for the saved settings within \(Self.reloadWait) s")
    let fields = [
      "call", "fingerprint", "settings", "locale", "fajrName", "names", "entryCount", "first",
      "last", "validUntil", "reloadDate", "truncated", "states", "generation", "footprint",
      "entries",
    ]
    let details = fields.map { "\($0): \(label("log.latest.\($0)", in: app))" }
      .joined(separator: "\n")
    return Record(
      sequence: latestSequence(in: app), fajrName: label("log.latest.fajrName", in: app),
      locale: label("log.latest.locale", in: app), states: label("log.latest.states", in: app),
      details: details)
  }
}
