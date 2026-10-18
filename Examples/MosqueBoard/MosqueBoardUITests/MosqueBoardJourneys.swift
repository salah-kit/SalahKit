import XCTest

/// Journeys through the real app with an injected board and clock.
///
/// Every launch freezes the clock, so each assertion is about one known instant.
///
/// The class is `nonisolated` and its members `@MainActor`, so it compiles under both default
/// isolation settings: XCTestCase's initializers and `setUp` aren't main-actor isolated.
nonisolated final class MosqueBoardJourneys: XCTestCase {
  /// Launches the board in an orientation (`launchBoard` in JourneySupport).
  @MainActor
  private func launch(
    _ board: String, at instant: String, language: String = "en",
    orientation: UIDeviceOrientation = .portrait, arguments: [String] = []
  ) -> XCUIApplication {
    XCUIDevice.shared.orientation = orientation
    return launchBoard(board, at: instant, language: language, arguments: arguments)
  }

  /// 1. A normal MUIS day: the app's iqama rules, a passed row, the next row and the countdown.
  @MainActor
  func testMuisNormalDay() {
    let app = launch("muis", at: "2026-10-14T14:00:00+08:00", orientation: .landscapeLeft)
    XCTAssertEqual(label("header.title", in: app), "Singapore")
    XCTAssertTrue(label("header.gregorian", in: app).contains("October 14, 2026"))
    XCTAssertTrue(label("header.hijri", in: app).contains("1448"))
    XCTAssertEqual(label("row.fajr.time", in: app), "Begins 05:31")
    XCTAssertEqual(label("row.fajr.iqama", in: app), "Iqama 05:51")
    XCTAssertEqual(label("row.fajr.status", in: app), "Passed")
    XCTAssertEqual(label("row.dhuhr.status", in: app), "Passed")
    XCTAssertEqual(label("row.asr.status", in: app), "Next")
    XCTAssertEqual(label("row.isha.status", in: app), "Upcoming")
    assertMissing("row.sunrise.iqama", in: app)
    // Sunrise has no iqama, and its empty cell says so rather than reading a dash.
    XCTAssertEqual(label("row.sunrise.noIqama", in: app), "No iqama")
    XCTAssertEqual(label("next.name", in: app), "Asr")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 2 hours, 6 minutes")
    XCTAssertTrue(label("footer.policy", in: app).contains("this app's own settings"))
    XCTAssertTrue(label("footer.attribution", in: app).contains("Singapore Open Data Licence"))
    assertMissing("coverage.banner", in: app)
    // Landscape: the next-prayer panel sits beside the table, to its right.
    XCTAssertGreaterThan(
      element("next.name", in: app).frame.minX, element("row.fajr.status", in: app).frame.maxX)
    screenshot("01-muis-normal-day")
  }

  /// 2. Jumu'ah only where declared: a MUIS Friday by app policy, and not the Thursday before.
  @MainActor
  func testDeclaredJumuah() {
    var app = launch("muis", at: "2026-10-16T12:30:00+08:00")
    XCTAssertEqual(label("row.dhuhr.name", in: app), "Jumuah")
    XCTAssertEqual(label("row.dhuhr.iqama", in: app), "Iqama 13:22")
    XCTAssertEqual(label("next.name", in: app), "Jumuah")
    screenshot("02-muis-friday-jumuah")
    app.terminate()

    app = launch("muis", at: "2026-10-15T12:30:00+08:00")
    XCTAssertEqual(label("row.dhuhr.name", in: app), "Dhuhr")
    XCTAssertEqual(label("row.dhuhr.iqama", in: app), "Iqama 13:02")
    XCTAssertEqual(label("next.name", in: app), "Dhuhr")
  }

  /// 3. Expired coverage: no invented next prayer after the last Isha, then the banner.
  @MainActor
  func testExpiredCoverage() {
    var app = launch("muis", at: "2026-12-31T21:00:00+08:00")
    XCTAssertEqual(label("next.unpublished", in: app), "The next prayer isn't published yet")
    XCTAssertEqual(label("row.isha.status", in: app), "Passed")
    assertMissing("next.name", in: app)
    assertMissing("next.countdown", in: app)
    screenshot("03a-muis-after-last-isha")
    app.terminate()

    app = launch("muis", at: "2027-01-01T09:00:00+08:00")
    XCTAssertTrue(element("coverage.banner", in: app).exists)
    XCTAssertEqual(label("coverage.title", in: app), "The timetable doesn't cover this time")
    let gap = label("coverage.gap.0", in: app)
    XCTAssertTrue(gap.hasPrefix("Friday, January 1, 2027: Fajr"), gap)
    XCTAssertTrue(gap.hasSuffix("(not published)"), gap)
    XCTAssertEqual(
      label("day.unavailable", in: app), "The timetable publishes no times for this day.")
    assertMissing("row.fajr", in: app)
    assertMissing("next.name", in: app)
    assertMissing("next.countdown", in: app)
    screenshot("03b-muis-expired")
  }

  /// 4. Isha after midnight: next across midnight, and owned by the previous day after it.
  @MainActor
  func testOvernightIsha() {
    var app = launch("edinburgh", at: "2026-06-21T23:30:00+01:00")
    XCTAssertEqual(label("next.name", in: app), "Isha")
    XCTAssertEqual(label("next.time", in: app), "Begins 01:15")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 1 hour, 45 minutes")
    XCTAssertEqual(label("row.isha.nextDay", in: app), "Next day")
    // The begin time's mark covers an iqama on the same night.
    assertMissing("row.isha.iqamaNextDay", in: app)
    XCTAssertEqual(label("row.maghrib.status", in: app), "Passed")
    assertMissing("next.owningDay", in: app)
    screenshot("04a-edinburgh-before-midnight")
    app.terminate()

    app = launch("edinburgh", at: "2026-06-22T00:30:00+01:00")
    XCTAssertTrue(label("header.gregorian", in: app).contains("June 22, 2026"))
    XCTAssertEqual(label("next.name", in: app), "Isha")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 45 minutes")
    XCTAssertEqual(
      label("next.owningDay", in: app), "From the timetable of Sunday, June 21, 2026")
    XCTAssertEqual(label("row.fajr.time", in: app), "Begins 03:32")
    XCTAssertEqual(label("row.fajr.status", in: app), "Upcoming")
    screenshot("04b-edinburgh-after-midnight")
    app.terminate()

    // Isha begins before midnight and its iqama is after it: the iqama carries the mark.
    app = launch("edinburgh", at: "2026-04-30T22:00:00+01:00")
    XCTAssertEqual(label("row.isha.time", in: app), "Begins 23:48")
    assertMissing("row.isha.nextDay", in: app)
    XCTAssertEqual(label("row.isha.iqama", in: app), "Iqama 00:00")
    XCTAssertEqual(label("row.isha.iqamaNextDay", in: app), "Next day")
  }

  /// 5. Countdowns across both 2026 clock changes count elapsed time, not wall-clock time.
  @MainActor
  func testCountdownAcrossClockChanges() {
    var app = launch("edinburgh", at: "2026-03-28T23:00:00Z")
    XCTAssertEqual(label("next.name", in: app), "Fajr")
    XCTAssertEqual(label("next.time", in: app), "Begins 05:17")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 5 hours, 17 minutes")
    screenshot("05-edinburgh-spring-forward")
    app.terminate()

    app = launch("edinburgh", at: "2026-10-24T23:00:00+01:00")
    XCTAssertEqual(label("next.time", in: app), "Begins 05:02")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 7 hours, 2 minutes")
  }

  /// 6. A partial row and a missing day show the coverage banner, never invented times.
  @MainActor
  func testPartialRowAndMissingDay() {
    var app = launch("edinburgh", at: "2026-06-24T23:00:00+01:00")
    XCTAssertEqual(
      label("coverage.gap.0", in: app), "Wednesday, June 24, 2026: Isha (not published)")
    XCTAssertEqual(label("row.isha.time", in: app), "Begin time: not published")
    assertMissing("row.isha.iqama", in: app)
    assertMissing("next.countdown", in: app)
    // The schedule can't say which prayer is current, so no row claims a status.
    XCTAssertEqual(label("row.fajr.status", in: app), "Unknown")
    screenshot("06a-edinburgh-partial-row")
    assertReadingOrder(in: app)
    app.terminate()

    // In landscape the banner sits beside the table; VoiceOver still reads each in one piece.
    app = launch("edinburgh", at: "2026-06-24T23:00:00+01:00", orientation: .landscapeLeft)
    assertReadingOrder(in: app)
    app.terminate()

    app = launch("edinburgh", at: "2026-06-26T12:00:00+01:00")
    XCTAssertTrue(element("coverage.banner", in: app).exists)
    XCTAssertTrue(label("coverage.gap.0", in: app).hasPrefix("Friday, June 26, 2026:"))
    XCTAssertTrue(element("day.unavailable", in: app).exists)
    assertMissing("row.dhuhr", in: app)
    screenshot("06b-edinburgh-missing-day")
  }

  /// 7. Arabic: names, Arabic-Indic digits and a right-to-left layout.
  @MainActor
  func testArabic() {
    let app = launch(
      "muis", at: "2026-10-14T14:00:00+08:00", language: "ar", orientation: .landscapeLeft)
    XCTAssertEqual(label("header.title", in: app), "سنغافورة")
    XCTAssertEqual(label("row.fajr.name", in: app), "الفجر")
    XCTAssertEqual(label("row.fajr.time", in: app), "الأذان ٠٥:٣١")
    XCTAssertEqual(label("row.fajr.status", in: app), "انقضت")
    XCTAssertEqual(label("next.name", in: app), "العصر")
    XCTAssertTrue(label("header.hijri", in: app).contains("١٤٤٨"))
    // Right to left: the name column sits to the right of the time column.
    let name = element("row.fajr.name", in: app).frame
    let time = element("row.fajr.time", in: app).frame
    XCTAssertGreaterThan(name.minX, time.maxX)
    // In landscape the next-prayer panel sits on the left, beside the table.
    XCTAssertLessThan(
      element("next.name", in: app).frame.maxX, element("row.fajr.status", in: app).frame.minX)
    screenshot("07-muis-arabic")
  }

  /// 8. At the largest text size every prayer's name, times and status show in full, in both
  /// orientations and both languages: the table stacks each row's parts, the clock goes below
  /// the title when it must, and the next-prayer panel goes above the table.
  @MainActor
  func testLargestTextSize() {
    let largest = [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    let boards = [
      ("muis", "2026-10-14T14:00:00+08:00"), ("edinburgh", "2026-06-24T23:00:00+01:00"),
    ]
    for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
      for language in ["en", "ar"] {
        for (board, instant) in boards {
          let app = launch(
            board, at: instant, language: language, orientation: orientation,
            arguments: largest)
          let window = app.windows.firstMatch.frame
          for kind in ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"] {
            assertShownWhole("row.\(kind).name", .title1, within: window, in: app)
            assertShownWhole("row.\(kind).time", .title1, within: window, in: app)
            // Edinburgh's Isha isn't published, so it has no status.
            if board == "muis" || kind != "isha" {
              assertShownWhole("row.\(kind).status", .title3, within: window, in: app)
            }
          }
          assertShownWhole("header.clock", .largeTitle, within: window, in: app)
          if board == "muis" {
            assertShownWhole("next.name", .largeTitle, within: window, in: app)
            assertShownWhole("next.time", .title2, within: window, in: app)
          } else {
            assertShownWhole("coverage.title", .title2, within: window, in: app)
            assertShownWhole("coverage.gap.0", .body, within: window, in: app)
          }
          assertReadingOrder(in: app)
          let side = orientation == .portrait ? "portrait" : "landscape"
          screenshot("08-largest-text-\(board)-\(side)-\(language)")
          app.terminate()
        }
      }
    }
    XCUIDevice.shared.orientation = .portrait
  }

  /// Asserts that an element is inside the window and isn't broken inside a word: it's at
  /// least as wide as its widest word in `style` at the largest text size.
  @MainActor
  private func assertShownWhole(
    _ identifier: String, _ style: UIFont.TextStyle, within window: CGRect,
    in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) {
    let element = element(identifier, in: app)
    XCTAssertTrue(element.waitForExistence(timeout: 10), "\(identifier) is missing")
    let text = element.label.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
    let frame = element.frame
    XCTAssertTrue(
      frame.minX >= window.minX - 1 && frame.maxX <= window.maxX + 1,
      "\(identifier) goes past the window's edge: \(frame)", file: file, line: line)
    // A time's label is "Begins 05:31"; in the table only the time is shown, so the check
    // uses the label's last word, which both layouts show whole.
    var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    if identifier.hasSuffix(".time") || identifier.hasSuffix(".iqama") {
      words = Array(words.suffix(1))
    }
    let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
    let font = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
    let widest =
      words.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    XCTAssertGreaterThanOrEqual(
      frame.width, widest - 1, "\(identifier) breaks a word of \"\(text)\": \(frame)",
      file: file, line: line)
  }

  /// Asserts that VoiceOver reads the next-prayer panel or the banner first, then the table in
  /// one piece, row by row, each row's times before its status.
  @MainActor
  private func assertReadingOrder(
    in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) {
    guard let root = try? app.snapshot() else {
      return XCTFail("No snapshot of the board", file: file, line: line)
    }
    var order: [String] = []
    var pending = [root]
    while let next = pending.popLast() {
      if !next.identifier.isEmpty { order.append(next.identifier) }
      pending.append(contentsOf: next.children.reversed())
    }
    let rows = order.indices.filter { order[$0].hasPrefix("row.") }
    guard let first = rows.first, let last = rows.last else {
      return XCTFail("No rows: \(order)", file: file, line: line)
    }
    // The rows' hidden status symbols are in the tree too, but VoiceOver doesn't read them.
    let others = ["header.", "next.", "coverage.", "day.", "footer."]
    let between = order[first...last].filter { id in others.contains { id.hasPrefix($0) } }
    XCTAssertEqual(between, [], "read between the rows: \(order)", file: file, line: line)
    let panel = order.indices.filter {
      order[$0].hasPrefix("next.") || order[$0].hasPrefix("coverage.")
    }
    XCTAssertFalse(panel.isEmpty, "no panel: \(order)", file: file, line: line)
    XCTAssertTrue(
      panel.allSatisfy { $0 < first }, "panel after the table: \(order)", file: file, line: line)
    for kind in ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"] {
      guard let time = order.firstIndex(of: "row.\(kind).time"),
        let status = order.firstIndex(of: "row.\(kind).status")
      else { continue }
      XCTAssertLessThan(
        time, status, "\(kind)'s status before its time: \(order)", file: file, line: line)
    }
  }
}
