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
  func testWidgetStatesInEnglish() throws {
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
    // VoiceOver says what the number is, and the time left in words.
    XCTAssertEqual(
      text("widget.next.countdown", in: normal), "Time remaining: 1 hour, 27 minutes")
    XCTAssertEqual(
      text("widget.next.countdown", in: state("normal", .rectangular, in: app)),
      "Time remaining: 1 hour, 27 minutes")
    XCTAssertEqual(
      text("widget.next", in: state("normal", .circular, in: app)),
      "Asr, Time remaining: 1 hour, 27 minutes")
    // The time has a narrow no-break space before "AM", as the locale writes it.
    XCTAssertEqual(text("widget.row.fajr", in: normal), "Fajr, 5:00\u{202F}AM")
    // The medium widget reads its card before its list, not line by line across both.
    let order = identifiers(in: normal)
    XCTAssertLessThan(
      try XCTUnwrap(order.firstIndex(of: "widget.next.countdown")),
      try XCTUnwrap(order.firstIndex(of: "widget.row.fajr")), "\(order)")
    // The setup notice's symbol is decoration, so VoiceOver doesn't read its name.
    XCTAssertEqual(state("setup", .rectangular, in: app).images.count, 0)
    XCTAssertEqual(state("setup", .circular, in: app).images.count, 0)
    // Every family names the next prayer in full for VoiceOver, the circular one too, although
    // it shows only the abbreviation ("A").
    assertNamesPrayer("Asr", in: "normal", of: app)

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
    // The circular widget shows "–" and "Unknown"; VoiceOver reads a sentence instead.
    XCTAssertEqual(
      text("widget.next", in: state("unknownNext", .circular, in: app)), "Next prayer unknown")
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
    // Arabic labels join their parts with the Arabic comma, and say "Time remaining".
    let fajr = text("widget.row.fajr", in: normal)
    XCTAssertTrue(fajr.hasPrefix("الفجر، "), fajr)
    XCTAssertFalse(fajr.contains(","), fajr)
    XCTAssertTrue(text("widget.next.countdown", in: normal).hasPrefix("الوقت المتبقي: "))
    XCTAssertEqual(text("widget.place", in: normal), "مكة المكرمة")
    assertNamesPrayer("العصر", in: "normal", of: app)
    screenshot("07-states-arabic")
    let unknown = state("unknownNext", .large, in: app)
    XCTAssertEqual(text("widget.next.unknown", in: unknown), "الصلاة التالية غير معروفة")
    let unavailable = state("unavailable", .medium, in: app)
    XCTAssertEqual(text("widget.message", in: unavailable), "المكان أو الإعدادات غير صالحة.")
    let expired = state("expired", .medium, in: app)
    XCTAssertEqual(text("widget.title", in: expired), "الأوقات بحاجة إلى تحديث")
  }

  /// 4. At the largest text size the samples are drawn as WidgetKit draws the widgets, so
  /// every state's text stays inside its widget in every family, in English and Arabic.
  @MainActor
  func testWidgetStatesAtTheLargestTextSize() {
    for language in ["en", "ar"] {
      // At this size the save status is below the fold, so the launch waits for the app only.
      let app = XCUIApplication()
      app.launchArguments = [
        "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-cleanStart", "-now",
        Self.makkahAfternoon, "-frozen", "-language", language,
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      ]
      app.launch()
      XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
      open("open.states", in: app)
      for id in ["setup", "normal", "partial", "unknownNext", "unavailable", "expired"] {
        for family in [Family.small, .medium, .large, .circular, .rectangular, .inline] {
          let container = state(id, family, in: app)
          let bounds = container.frame.insetBy(dx: -1, dy: -1)
          let texts = container.descendants(matching: .any).allElementsBoundByIndex
          for text in texts where !text.frame.isEmpty {
            XCTAssertTrue(
              bounds.contains(text.frame),
              "\(language) \(id) \(family.rawValue): \"\(text.label)\" at \(text.frame) is outside \(bounds)"
            )
          }
        }
        if id == "normal" || id == "expired" {
          scrollDown(to: id, in: app)
          screenshot("08-states-largest-text-\(id)-\(language)")
        }
      }
      app.terminate()
    }
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

  /// Asserts that VoiceOver reads the prayer's full name in every family of a state: some
  /// element of each family's sample has a label that contains it.
  @MainActor
  private func assertNamesPrayer(_ name: String, in id: String, of app: XCUIApplication) {
    for family in [Family.small, .medium, .large, .circular, .rectangular, .inline] {
      let container = state(id, family, in: app)
      let named = container.descendants(matching: .any)
        .matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
      XCTAssertTrue(
        named.exists, "\(family.rawValue) doesn't read \(name): \(container.debugDescription)")
    }
  }

  /// The identifiers in a container, in the order VoiceOver reads them.
  @MainActor
  private func identifiers(in container: XCUIElement) -> [String] {
    guard let root = try? container.snapshot() else { return [] }
    var order: [String] = []
    var pending = [root]
    while let next = pending.popLast() {
      if !next.identifier.isEmpty { order.append(next.identifier) }
      pending.append(contentsOf: next.children.reversed())
    }
    return order
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
