import XCTest

/// Journeys through the app: settings, the reload gating it reports, and the widget's views for
/// every state, drawn by the extension's own view code.
nonisolated final class AppJourneys: JourneyCase {
  /// 1. Setting up, saving the same settings again, changing them, and a relaunch: each save
  /// reports whether it changed the stored value and so asked WidgetKit for a reload.
  @MainActor
  func testSettingsAndReloadGating() {
    let app = launch([], clean: true)
    XCTAssertEqual(label("save.status", in: app), "Not saved in this session.")
    XCTAssertTrue(element("setup.waiting", in: app).exists)

    open("setup.start", in: app)
    XCTAssertEqual(label("save.status", in: app), "Save 1: changed, widget reload requested.")
    XCTAssertFalse(element("setup.waiting", in: app).exists)
    let makkah = label("settings.fingerprint", in: app)

    open("save.again", in: app)
    XCTAssertEqual(label("save.status", in: app), "Save 2: unchanged, no reload requested.")
    XCTAssertEqual(label("settings.fingerprint", in: app), makkah)

    pick("London", from: "settings.place", of: app)
    XCTAssertEqual(label("save.status", in: app), "Save 3: changed, widget reload requested.")
    pick("Muslim World League", from: "settings.method", of: app)
    XCTAssertEqual(label("save.status", in: app), "Save 4: changed, widget reload requested.")
    screenshot("01-settings")

    // Arabic: the app follows the names' language, right to left with Arabic digits.
    chooseLanguage("العربية", in: app)
    XCTAssertEqual(
      label("save.status", in: app), "الحفظ ٥: تغيّرت الإعدادات، وطُلبت إعادة تحميل الأداة.")
    let arabic = label("settings.fingerprint", in: app)
    XCTAssertNotEqual(arabic, makkah)
    screenshot("02-settings-arabic")

    // The settings survive a relaunch, and launching saves nothing.
    app.terminate()
    let again = launch([])
    XCTAssertEqual(label("settings.fingerprint", in: again), arabic)
    XCTAssertEqual(label("save.status", in: again), "لم يُحفظ شيء في هذه الجلسة.")
  }

  /// 1b. Launch arguments apply once: the last change made after a launch with arguments
  /// survives a relaunch without them. (The app once made its store in a view's initializer;
  /// SwiftUI ran it again when the language changed, and the discarded store saved the launch
  /// arguments over the change.)
  @MainActor
  func testLaunchArgumentsApplyOnce() {
    let app = launch(["-place", "makkah", "-method", "ummAlQura", "-language", "en"], clean: true)
    XCTAssertEqual(label("save.status", in: app), "Save 1: changed, widget reload requested.")
    chooseLanguage("العربية", in: app)
    XCTAssertEqual(
      label("save.status", in: app), "الحفظ ٢: تغيّرت الإعدادات، وطُلبت إعادة تحميل الأداة.")
    let changed = label("settings.fingerprint", in: app)
    app.terminate()
    let again = launch([])
    XCTAssertEqual(label("settings.fingerprint", in: again), changed)
    XCTAssertEqual(label("save.status", in: again), "لم يُحفظ شيء في هذه الجلسة.")
  }

  /// 2. The widget's views for every state, in English: setup required, normal, partial (a
  /// partial day, and an unknown next prayer), unavailable and expired.
  @MainActor
  func testWidgetStatesInEnglish() {
    let app = launch(["-now", Self.makkahAfternoon, "-frozen", "-language", "en"], clean: true)
    open("open.states", in: app)

    let setup = state("setup", .small, in: app)
    XCTAssertEqual(text("widget.title", in: setup), "Choose a place")
    XCTAssertEqual(text("widget.message", in: setup), "Open PhoneWidgets to choose a place.")
    screenshot("03-states-setup-normal")

    let normal = state("normal", .medium, in: app)
    XCTAssertEqual(text("widget.next.name", in: normal), "Asr")
    XCTAssertEqual(text("widget.place", in: normal), "Makkah")
    // In the app the countdown is the time left at the entry's moment: 14:00 to Asr at 15:27.
    XCTAssertTrue(text("widget.next.countdown", in: normal).contains("27"))
    XCTAssertTrue(text("widget.row.fajr", in: normal).hasPrefix("Fajr"))

    // Tromsø's partial day: the known times, what can't be calculated, and a real countdown to
    // the known next prayer.
    let partial = state("partial", .large, in: app)
    scrollDown(to: "partial", in: app)
    XCTAssertEqual(text("widget.next.name", in: partial), "Asr")
    XCTAssertEqual(
      text("widget.message", in: partial),
      "Fajr, Sunrise, Maghrib, and Isha: can't be calculated today.")
    XCTAssertTrue(text("widget.row.dhuhr", in: partial).hasPrefix("Dhuhr"))
    XCTAssertFalse(partial.descendants(matching: .any)["widget.row.isha"].exists)
    // 15:00 to Asr at 17:58.
    XCTAssertTrue(text("widget.next.countdown", in: partial).contains("58"))

    // An unknown next prayer reads as unknown, with no countdown.
    let unknown = state("unknownNext", .large, in: app)
    XCTAssertEqual(text("widget.next.unknown", in: unknown), "Next prayer unknown")
    XCTAssertEqual(text("widget.message", in: unknown), "The next prayer isn't known.")
    XCTAssertTrue(text("widget.row.isha", in: unknown).hasPrefix("Isha"))
    XCTAssertFalse(unknown.descendants(matching: .any)["widget.next.countdown"].exists)
    XCTAssertEqual(
      text("widget.next.unknown", in: state("unknownNext", .circular, in: app)), "Unknown")
    screenshot("04-states-partial")

    let unavailable = state("unavailable", .medium, in: app)
    scrollDown(to: "unavailable", in: app)
    XCTAssertEqual(text("widget.title", in: unavailable), "No prayer times")
    XCTAssertEqual(
      text("widget.message", in: unavailable), "The place or the settings aren't valid.")
    XCTAssertEqual(
      text("widget.short", in: state("unavailable", .inline, in: app)), "Invalid place")
    screenshot("05-states-unavailable")

    let expired = state("expired", .medium, in: app)
    scrollDown(to: "expired", in: app)
    XCTAssertEqual(text("widget.title", in: expired), "Times need refreshing")
    XCTAssertTrue(text("widget.message", in: expired).hasPrefix("Known until Oct 16, 2026"))
    XCTAssertFalse(expired.descendants(matching: .any)["widget.next.countdown"].exists)
    screenshot("06-states-expired")
  }

  /// 3. The same states in Arabic, while the simulator runs in English.
  @MainActor
  func testWidgetStatesInArabic() {
    let app = launch(["-now", Self.makkahAfternoon, "-frozen", "-language", "ar"], clean: true)
    open("open.states", in: app)

    XCTAssertEqual(text("widget.title", in: state("setup", .small, in: app)), "اختر مكانًا")
    let normal = state("normal", .medium, in: app)
    XCTAssertEqual(text("widget.next.name", in: normal), "العصر")
    XCTAssertEqual(text("widget.place", in: normal), "مكة المكرمة")
    screenshot("07-states-arabic")
    let unknown = state("unknownNext", .large, in: app)
    XCTAssertEqual(text("widget.next.unknown", in: unknown), "الصلاة التالية غير معروفة")
    let unavailable = state("unavailable", .medium, in: app)
    XCTAssertEqual(text("widget.message", in: unavailable), "المكان أو الإعدادات غير صالحة.")
    let expired = state("expired", .medium, in: app)
    XCTAssertEqual(text("widget.title", in: expired), "الأوقات بحاجة إلى تحديث")
  }

  // MARK: Helpers

  enum Family: String {
    case small = "systemSmall"
    case medium = "systemMedium"
    case large = "systemLarge"
    case circular = "accessoryCircular"
    case rectangular = "accessoryRectangular"
    case inline = "accessoryInline"
  }

  @MainActor
  private func state(_ id: String, _ family: Family, in app: XCUIApplication) -> XCUIElement {
    let container = element("states.\(id).\(family.rawValue)", in: app)
    XCTAssertTrue(container.waitForExistence(timeout: 10), "states.\(id).\(family.rawValue)")
    return container
  }

  @MainActor
  private func text(_ identifier: String, in container: XCUIElement) -> String {
    let element = container.descendants(matching: .any).matching(identifier: identifier).firstMatch
    XCTAssertTrue(element.waitForExistence(timeout: 5), "\(identifier) is missing")
    return Self.clean(element.label)
  }

  /// Scrolls the states screen down until a state's title is near the top, for a screenshot.
  @MainActor
  private func scrollDown(to state: String, in app: XCUIApplication) {
    let title = element("states.\(state).title", in: app)
    // Drags of about a third of the screen, shorter than the band the title must land in.
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
    for _ in 0..<30 where !(title.isHittable && title.frame.minY < 400) {
      start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }
  }
}
