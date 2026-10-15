import XCTest

/// Journeys through the real app on an iPhone simulator, with the clock and location injected
/// by launch arguments.
///
/// Every launch freezes the clock, so each assertion is about one known instant. The expected
/// times are SalahTimes 0.1.0's, computed once through SalahCalculation's public API; the
/// README records how.
///
/// The class is `nonisolated` and its members `@MainActor`, so it compiles under both default
/// isolation settings: XCTestCase's initializers and `setUp` aren't main-actor isolated.
nonisolated final class CalculatedPhoneJourneys: XCTestCase {
  /// Makkah, 14:00 on Wednesday 14 October 2026.
  private static let makkahAfternoon = "2026-10-14T14:00:00+03:00"

  @MainActor
  private func launch(
    at instant: String, _ arguments: [String] = [], language: String = "en", reset: Bool = true
  ) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      ["-now", instant, "-frozen", "-language", language]
      + ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
      + (reset ? ["-resetSettings"] : []) + arguments
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(element("header.place", in: app).waitForExistence(timeout: 30))
    return app
  }

  @MainActor
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// The element's accessibility label, without the directional isolates (U+2068, U+2069) that
  /// Foundation puts around arguments interpolated into strings.
  @MainActor
  private func label(_ identifier: String, in app: XCUIApplication) -> String {
    let element = element(identifier, in: app)
    XCTAssertTrue(element.waitForExistence(timeout: 10), "\(identifier) is missing")
    return element.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
  }

  @MainActor
  private func assertMissing(_ identifier: String, in app: XCUIApplication) {
    XCTAssertFalse(element(identifier, in: app).exists, "\(identifier) shouldn't be shown")
  }

  /// The six rows' times, or their missing reasons, in canonical order.
  @MainActor
  private func times(in app: XCUIApplication) -> [String] {
    ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"].map {
      label("row.\($0).time", in: app)
    }
  }

  @MainActor
  private func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  // MARK: Settings

  @MainActor
  private func openSettings(_ app: XCUIApplication) {
    element("settings.open", in: app).tap()
    XCTAssertTrue(element("settings.done", in: app).waitForExistence(timeout: 10))
  }

  @MainActor
  private func closeSettings(_ app: XCUIApplication) {
    element("settings.done", in: app).tap()
    XCTAssertTrue(element("settings.done", in: app).waitForNonExistence(timeout: 10))
  }

  /// Scrolls the current list until the element is on screen. Lists load their rows lazily,
  /// so a row below the fold doesn't exist until it's scrolled to.
  @MainActor
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<15 where !(element.exists && element.isHittable) {
      app.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(element.exists, "\(element) is missing")
  }

  /// Taps a segment of a segmented picker.
  @MainActor
  private func select(_ option: String, in identifier: String, of app: XCUIApplication) {
    let control = app.segmentedControls[identifier]
    XCTAssertTrue(control.waitForExistence(timeout: 10), "\(identifier) is missing")
    control.buttons[option].tap()
    XCTAssertTrue(control.buttons[option].isSelected, "\(option) isn't selected in \(identifier)")
  }

  /// Chooses an option of a picker that pushes a list, and waits to come back.
  @MainActor
  private func pick(_ option: String, from identifier: String, of app: XCUIApplication) {
    let picker = element(identifier, in: app)
    XCTAssertTrue(picker.waitForExistence(timeout: 10), "\(identifier) is missing")
    picker.tap()
    let row = app.buttons[option].firstMatch
    if !row.waitForExistence(timeout: 2) {
      reveal(row, in: app)
    }
    XCTAssertTrue(row.exists, "\(option) isn't offered")
    row.tap()
    XCTAssertTrue(picker.waitForExistence(timeout: 10))
  }

  @MainActor
  private func step(_ identifier: String, _ button: String, times: Int, of app: XCUIApplication) {
    let stepper = app.steppers[identifier]
    XCTAssertTrue(stepper.waitForExistence(timeout: 10), "\(identifier) is missing")
    for _ in 0..<times {
      // SwiftUI names a stepper's buttons "<identifier>-Increment" and "<identifier>-Decrement".
      stepper.buttons["\(identifier)-\(button)"].tap()
    }
  }

  // MARK: Journeys

  /// 1. An ordinary day in Makkah with Umm al-Qura: six times, statuses, the next prayer and
  /// its countdown, and the calculation behind them.
  @MainActor
  func testOrdinaryDay() {
    let app = launch(
      at: Self.makkahAfternoon, ["-place", "makkah", "-method", "ummAlQura"])
    XCTAssertEqual(label("header.place", in: app), "Makkah")
    XCTAssertEqual(label("header.clock", in: app), "14:00")
    XCTAssertEqual(label("header.date", in: app), "Wednesday, October 14, 2026")
    XCTAssertTrue(label("header.hijri", in: app).contains("1448"))
    XCTAssertEqual(times(in: app), ["05:00", "06:16", "12:07", "15:27", "17:57", "19:27"])
    XCTAssertEqual(label("row.fajr.status", in: app), "Passed")
    XCTAssertEqual(label("row.dhuhr.status", in: app), "Passed")
    XCTAssertEqual(label("row.asr.status", in: app), "Next")
    XCTAssertEqual(label("row.isha.status", in: app), "Upcoming")
    assertMissing("row.isha.marker", in: app)
    XCTAssertEqual(label("next.name", in: app), "Asr")
    XCTAssertEqual(label("next.time", in: app), "At 15:27")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 1 hour, 27 minutes")
    assertMissing("next.owningDay", in: app)
    XCTAssertEqual(label("latest.name", in: app), "Dhuhr")
    XCTAssertEqual(label("latest.time", in: app), "At 12:07")
    assertMissing("coverage.banner", in: app)
    XCTAssertEqual(label("calc.method", in: app), "Method: Umm al-Qura")
    XCTAssertEqual(label("calc.fajr", in: app), "Fajr: 18.5°")
    XCTAssertEqual(label("calc.isha", in: app), "Isha: 90 min after Maghrib")
    XCTAssertEqual(label("calc.madhab", in: app), "Asr (madhab): Shafi'i")
    screenshot("01-makkah-ordinary-day")
  }

  /// 2a. Custom parameters through Settings: Hanafi moves Asr, a custom Fajr angle moves Fajr,
  /// rounding up moves every time with seconds; the Calculation section follows.
  @MainActor
  func testCustomParametersInSettings() {
    let app = launch(at: Self.makkahAfternoon, ["-place", "makkah", "-method", "ummAlQura"])

    openSettings(app)
    select("Hanafi", in: "settings.madhab", of: app)
    closeSettings(app)
    XCTAssertEqual(times(in: app), ["05:00", "06:16", "12:07", "16:19", "17:57", "19:27"])
    XCTAssertEqual(label("calc.madhab", in: app), "Asr (madhab): Hanafi")
    XCTAssertEqual(label("calc.method", in: app), "Method: Umm al-Qura")

    openSettings(app)
    pick("Custom", from: "settings.method", of: app)
    // Umm al-Qura's 18.5° down to 16°, half a degree at a time.
    step("settings.fajrAngle", "Decrement", times: 5, of: app)
    XCTAssertTrue(label("settings.fajrAngle", in: app).contains("16°"))
    closeSettings(app)
    XCTAssertEqual(times(in: app), ["05:10", "06:16", "12:07", "16:19", "17:57", "19:27"])
    XCTAssertEqual(label("calc.method", in: app), "Method: Custom")
    XCTAssertEqual(label("calc.fajr", in: app), "Fajr: 16°")

    openSettings(app)
    select("Up", in: "settings.rounding", of: app)
    screenshot("02a-settings-custom")
    closeSettings(app)
    XCTAssertEqual(times(in: app), ["05:11", "06:16", "12:07", "16:20", "17:58", "19:28"])
    XCTAssertEqual(label("calc.rounding", in: app), "Rounding: Up to the minute")
    XCTAssertEqual(label("calc.method", in: app), "Method: Custom")
    XCTAssertEqual(label("calc.fajr", in: app), "Fajr: 16°")
    XCTAssertEqual(label("calc.isha", in: app), "Isha: 90 min after Maghrib")
    XCTAssertEqual(label("calc.madhab", in: app), "Asr (madhab): Hanafi")
    XCTAssertEqual(label("next.name", in: app), "Asr")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 2 hours, 20 minutes")
    // The Calculation section lists every parameter, at the end of the screen.
    reveal(element("calc.ramadanIsha", in: app), in: app)
    screenshot("02b-makkah-custom-calculation")
  }

  /// 2b. Custom parameters from launch arguments.
  @MainActor
  func testCustomParametersFromLaunchArguments() {
    let app = launch(
      at: Self.makkahAfternoon,
      ["-place", "makkah", "-method", "muslimWorldLeague", "-fajrAngle", "15", "-ishaAngle", "15"])
    XCTAssertEqual(times(in: app), ["05:15", "06:16", "12:07", "15:27", "17:57", "18:58"])
    XCTAssertEqual(label("calc.method", in: app), "Method: Custom")
    XCTAssertEqual(label("calc.fajr", in: app), "Fajr: 15°")
    XCTAssertEqual(label("calc.isha", in: app), "Isha: 15°")
    XCTAssertEqual(label("calc.maghrib", in: app), "Maghrib: Sunset")
    XCTAssertEqual(label("calc.rounding", in: app), "Rounding: Nearest minute")
  }

  /// 3a. Kashgar keeps Beijing time: 21 June's Isha falls at 00:19 on 22 June. Just after
  /// midnight it's the next prayer, and after 00:19 the latest one, both owned by Sunday.
  @MainActor
  func testKashgarIshaAfterMidnight() {
    let kashgar = ["-place", "kashgar", "-method", "muslimWorldLeague"]
    var app = launch(at: "2026-06-22T00:05:00+08:00", kashgar)
    XCTAssertEqual(label("header.date", in: app), "Monday, June 22, 2026")
    XCTAssertEqual(label("next.name", in: app), "Isha")
    XCTAssertEqual(label("next.time", in: app), "At 00:19")
    XCTAssertEqual(label("next.owningDay", in: app), "From Sunday's schedule")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 14 minutes")
    XCTAssertEqual(label("latest.name", in: app), "Maghrib")
    XCTAssertEqual(label("latest.owningDay", in: app), "From Sunday's schedule")
    // Today's rows are Monday's: its own Isha is after the next midnight.
    XCTAssertEqual(times(in: app), ["05:28", "07:29", "14:58", "18:56", "22:27", "00:19"])
    XCTAssertEqual(label("row.isha.marker", in: app), "Next day")
    XCTAssertEqual(label("row.fajr.status", in: app), "Upcoming")
    screenshot("03a-kashgar-before-isha")
    app.terminate()

    app = launch(at: "2026-06-22T00:30:00+08:00", kashgar)
    XCTAssertEqual(label("latest.name", in: app), "Isha")
    XCTAssertEqual(label("latest.time", in: app), "At 00:19")
    XCTAssertEqual(label("latest.owningDay", in: app), "From Sunday's schedule")
    XCTAssertEqual(label("now.justStarted", in: app), "Isha has started")
    XCTAssertEqual(label("next.name", in: app), "Fajr")
    XCTAssertEqual(label("next.time", in: app), "At 05:28")
    assertMissing("next.owningDay", in: app)
    XCTAssertEqual(label("row.fajr.status", in: app), "Next")
    screenshot("03b-kashgar-after-isha")
  }

  /// 3b. Kazan's clock runs behind the Sun: with the middle-of-the-night rule, 21 June's Fajr
  /// falls at 23:45 on 20 June, and at 23:50 it's the latest prayer.
  @MainActor
  func testKazanFajrBeforeMidnight() {
    let app = launch(
      at: "2026-06-20T23:50:00+03:00",
      ["-place", "kazan", "-method", "muslimWorldLeague", "-highLatitudeRule", "middleOfTheNight"])
    XCTAssertEqual(label("header.date", in: app), "Saturday, June 20, 2026")
    XCTAssertEqual(label("latest.name", in: app), "Fajr")
    XCTAssertEqual(label("latest.time", in: app), "At 23:45")
    XCTAssertEqual(label("latest.owningDay", in: app), "From Sunday's schedule")
    XCTAssertEqual(label("now.justStarted", in: app), "Fajr has started")
    XCTAssertEqual(label("next.name", in: app), "Dhuhr")
    XCTAssertEqual(label("next.owningDay", in: app), "From Sunday's schedule")
    // Saturday's own Fajr fell at 23:45 on Friday evening.
    XCTAssertEqual(times(in: app), ["23:45", "02:58", "11:45", "16:17", "20:32", "23:45"])
    XCTAssertEqual(label("row.fajr.marker", in: app), "Previous evening")
    XCTAssertEqual(label("calc.highLatitudeRule", in: app), "High latitudes: Middle of the night")
    screenshot("03c-kazan-fajr-before-midnight")
  }

  /// 4a. Tromsø at midsummer: the Sun doesn't set, so four kinds can't be calculated. The app
  /// shows Dhuhr and Asr, and after Asr names no next prayer and explains the gap.
  @MainActor
  func testTromsoMidsummer() {
    let tromso = ["-place", "tromso", "-method", "muslimWorldLeague"]
    var app = launch(at: "2026-06-21T20:00:00+02:00", tromso)
    let unavailable = "Can't be calculated"
    XCTAssertEqual(
      times(in: app), [unavailable, unavailable, "12:46", "17:58", unavailable, unavailable])
    XCTAssertEqual(label("row.asr.status", in: app), "Unknown")
    XCTAssertEqual(label("next.unknown", in: app), "The next prayer can't be named.")
    XCTAssertEqual(
      label("next.reason", in: app),
      "Sunday, June 21, 2026: Maghrib and Isha (can't be calculated)")
    assertMissing("next.countdown", in: app)
    assertMissing("latest.name", in: app)
    XCTAssertEqual(label("coverage.title", in: app), "No current or next prayer can be named")
    XCTAssertEqual(
      label("coverage.gap.0", in: app),
      "Sunday, June 21, 2026: Maghrib and Isha (can't be calculated)")
    XCTAssertEqual(
      label("coverage.gap.1", in: app),
      "Monday, June 22, 2026: Fajr and Sunrise (can't be calculated)")
    screenshot("04a-tromso-after-asr")
    app.terminate()

    // Between Dhuhr and Asr the state is known, and the banner lists the day's missing kinds.
    app = launch(at: "2026-06-21T15:00:00+02:00", tromso)
    XCTAssertEqual(label("next.name", in: app), "Asr")
    XCTAssertEqual(label("latest.name", in: app), "Dhuhr")
    XCTAssertEqual(label("coverage.title", in: app), "Some of today's times are missing")
    XCTAssertEqual(
      label("coverage.gap.0", in: app),
      "Sunday, June 21, 2026: Fajr, Sunrise, Maghrib, and Isha (can't be calculated)")
  }

  /// 4b. A latitude of 95°: SalahTimes rejects it, so the whole day is unavailable as invalid
  /// input, with no times at all.
  @MainActor
  func testInvalidCoordinates() {
    let app = launch(
      at: "2026-06-21T12:00:00Z",
      ["-latitude", "95", "-longitude", "0", "-timeZone", "UTC", "-placeName", "Latitude 95"])
    XCTAssertEqual(label("header.place", in: app), "Latitude 95")
    XCTAssertEqual(
      label("day.unavailable", in: app),
      "Today's times can't be shown: invalid location or settings")
    XCTAssertEqual(times(in: app), Array(repeating: "Invalid location or settings", count: 6))
    XCTAssertEqual(label("next.unknown", in: app), "The next prayer can't be named.")
    assertMissing("next.countdown", in: app)
    XCTAssertEqual(label("coverage.title", in: app), "No current or next prayer can be named")
    XCTAssertTrue(label("coverage.gap.0", in: app).hasSuffix("(invalid location or settings)"))
    screenshot("04b-invalid-coordinates")
  }

  /// SalahUI supplies the polar-night gaps to the app's row style. All expected kinds keep
  /// their canonical positions, and no missing row displays a status or a borrowed time.
  @MainActor
  func testTromsoPolarNightMissingRows() {
    let app = launch(
      at: "2026-12-21T12:00:00+01:00",
      ["-place", "tromso", "-method", "muslimWorldLeague"])
    for kind in ["sunrise", "asr", "maghrib"] {
      XCTAssertEqual(label("row.\(kind).time", in: app), "Can't be calculated")
      assertMissing("row.\(kind).status", in: app)
      assertMissing("row.\(kind).marker", in: app)
    }
    let kinds = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
    let names = kinds.map { element("row.\($0).name", in: app) }
    for name in names {
      XCTAssertTrue(name.waitForExistence(timeout: 10))
    }
    for index in 0..<(names.count - 1) {
      XCTAssertLessThan(names[index].frame.minY, names[index + 1].frame.minY)
    }
    screenshot("04c-tromso-polar-night-missing-rows")
  }

  /// 5. Settings made in the app survive a relaunch without `-resetSettings`.
  @MainActor
  func testSettingsPersistAcrossRelaunch() {
    var app = launch(at: Self.makkahAfternoon, ["-place", "makkah", "-method", "ummAlQura"])
    openSettings(app)
    pick("Muslim World League", from: "settings.method", of: app)
    select("Hanafi", in: "settings.madhab", of: app)
    pick("London", from: "settings.place", of: app)
    closeSettings(app)
    XCTAssertEqual(label("header.place", in: app), "London")
    app.terminate()

    app = launch(at: "2026-10-14T14:00:00+01:00", reset: false)
    XCTAssertEqual(label("header.place", in: app), "London")
    XCTAssertEqual(label("calc.method", in: app), "Method: Muslim World League")
    XCTAssertEqual(label("calc.madhab", in: app), "Asr (madhab): Hanafi")
    XCTAssertEqual(label("row.dhuhr.time", in: app), "12:47")
    openSettings(app)
    reveal(element("settings.json", in: app), in: app)
    let json = label("settings.json", in: app)
    XCTAssertTrue(json.contains("\"london\""), json)
    XCTAssertTrue(json.contains("\"hanafi\""), json)
    XCTAssertTrue(json.contains("\"muslimWorldLeague\""), json)
    screenshot("05-settings-saved")
  }

  /// 6. Arabic: names, Arabic-Indic digits and a right-to-left layout.
  @MainActor
  func testArabic() {
    let app = launch(
      at: Self.makkahAfternoon, ["-place", "makkah", "-method", "ummAlQura"], language: "ar")
    XCTAssertEqual(label("header.place", in: app), "مكة المكرمة")
    XCTAssertEqual(label("row.fajr.name", in: app), "الفجر")
    XCTAssertEqual(label("row.fajr.time", in: app), "٠٥:٠٠")
    XCTAssertEqual(label("row.fajr.status", in: app), "انقضت")
    XCTAssertEqual(label("next.name", in: app), "العصر")
    XCTAssertTrue(label("header.hijri", in: app).contains("١٤٤٨"))
    XCTAssertEqual(label("calc.method", in: app), "طريقة الحساب: أم القرى")
    // Right to left: the name sits to the right of the time.
    let name = element("row.fajr.name", in: app).frame
    let time = element("row.fajr.time", in: app).frame
    XCTAssertGreaterThan(name.minX, time.maxX)
    screenshot("06-makkah-arabic")
  }
}
