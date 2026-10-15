import XCTest

/// Journeys through the real tvOS app, with the iPad journeys' boards, instants and expectations.
///
/// A TV board can't scroll, because nothing on it takes focus, so each journey also checks that
/// the whole board fits on the screen.
///
/// The class is `nonisolated` and its members `@MainActor`, so it compiles under both default
/// isolation settings: XCTestCase's initializers and `setUp` aren't main-actor isolated.
nonisolated final class MosqueBoardTVJourneys: XCTestCase {
  /// The footer, the board's last element, ends inside the safe area. The board starts at the
  /// safe area's top edge, and tvOS's safe area leaves as much room at the bottom as at the top
  /// (60 points at 1080p), for TVs that overscan.
  @MainActor
  private func assertFitsOnScreen(_ app: XCUIApplication) {
    let window = app.windows.firstMatch.frame
    let top = element("header.title", in: app).frame.minY
    XCTAssertGreaterThan(top, 0, "the board starts at the screen's edge")
    let bottom = window.maxY - top
    for identifier in ["footer.policy", "footer.attribution"] {
      let footer = element(identifier, in: app)
      if footer.exists {
        XCTAssertLessThanOrEqual(footer.frame.maxY, bottom, "\(identifier) is below the safe area")
      }
    }
    XCTAssertTrue(element("footer.policy", in: app).exists)
  }

  /// A normal MUIS day: the app's iqama rules, a passed row, the next row and the countdown,
  /// with the next-prayer panel beside the table.
  @MainActor
  func testMuisNormalDay() {
    let app = launchBoard("muis", at: "2026-10-14T14:00:00+08:00")
    XCTAssertEqual(label("header.title", in: app), "Singapore")
    XCTAssertEqual(label("header.clock", in: app), "14:00")
    XCTAssertTrue(label("header.gregorian", in: app).contains("October 14, 2026"))
    XCTAssertTrue(label("header.hijri", in: app).contains("1448"))
    XCTAssertEqual(label("row.fajr.time", in: app), "Begins 05:31")
    XCTAssertEqual(label("row.fajr.iqama", in: app), "Iqama 05:51")
    XCTAssertEqual(label("row.fajr.status", in: app), "Passed")
    XCTAssertEqual(label("row.dhuhr.status", in: app), "Passed")
    XCTAssertEqual(label("row.asr.status", in: app), "Next")
    XCTAssertEqual(label("row.isha.status", in: app), "Upcoming")
    assertMissing("row.sunrise.iqama", in: app)
    XCTAssertEqual(label("next.name", in: app), "Asr")
    XCTAssertEqual(label("next.time", in: app), "Begins 16:06")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 2 hours, 6 minutes")
    XCTAssertTrue(label("footer.policy", in: app).contains("this app's own settings"))
    XCTAssertTrue(label("footer.attribution", in: app).contains("Singapore Open Data Licence"))
    assertMissing("coverage.banner", in: app)
    XCTAssertGreaterThan(
      element("next.name", in: app).frame.minX, element("row.fajr.status", in: app).frame.maxX)
    // The countdown is the board's largest text, not shrunk to fit the screen.
    XCTAssertGreaterThan(
      element("next.countdown", in: app).frame.height,
      element("next.name", in: app).frame.height * 1.5)
    assertFitsOnScreen(app)
    screenshot("tv-01-muis-normal-day")
  }

  /// Jumu'ah only where declared: a MUIS Friday by app policy, and not the Thursday before.
  @MainActor
  func testDeclaredJumuah() {
    var app = launchBoard("muis", at: "2026-10-16T12:30:00+08:00")
    XCTAssertEqual(label("row.dhuhr.name", in: app), "Jumuah")
    XCTAssertEqual(label("row.dhuhr.iqama", in: app), "Iqama 13:22")
    XCTAssertEqual(label("next.name", in: app), "Jumuah")
    assertFitsOnScreen(app)
    screenshot("tv-02-muis-friday-jumuah")
    app.terminate()

    app = launchBoard("muis", at: "2026-10-15T12:30:00+08:00")
    XCTAssertEqual(label("row.dhuhr.name", in: app), "Dhuhr")
    XCTAssertEqual(label("row.dhuhr.iqama", in: app), "Iqama 13:02")
    XCTAssertEqual(label("next.name", in: app), "Dhuhr")
  }

  /// Expired coverage: on 1 January 2027 the MUIS timetable has ended, and the banner says so
  /// instead of naming a prayer.
  @MainActor
  func testExpiredCoverage() {
    let app = launchBoard("muis", at: "2027-01-01T09:00:00+08:00")
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
    assertFitsOnScreen(app)
    screenshot("tv-03b-muis-expired")
  }

  /// Isha after midnight on the Edinburgh board: before midnight it's the next prayer on the
  /// next day; after midnight the board shows 22 June and the Isha of 21 June's timetable.
  @MainActor
  func testOvernightIsha() {
    var app = launchBoard("edinburgh", at: "2026-06-21T23:30:00+01:00")
    XCTAssertEqual(label("next.name", in: app), "Isha")
    XCTAssertEqual(label("next.time", in: app), "Begins 01:15")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 1 hour, 45 minutes")
    XCTAssertEqual(label("row.isha.nextDay", in: app), "Next day")
    XCTAssertEqual(label("row.maghrib.status", in: app), "Passed")
    assertMissing("next.owningDay", in: app)
    // A row with a "Next day" mark still fits.
    assertFitsOnScreen(app)
    app.terminate()

    app = launchBoard("edinburgh", at: "2026-06-22T00:30:00+01:00")
    XCTAssertTrue(label("header.gregorian", in: app).contains("June 22, 2026"))
    XCTAssertEqual(label("next.name", in: app), "Isha")
    XCTAssertEqual(label("next.countdown", in: app), "Time remaining: 45 minutes")
    XCTAssertEqual(
      label("next.owningDay", in: app), "From the timetable of Sunday, June 21, 2026")
    XCTAssertEqual(label("row.fajr.time", in: app), "Begins 03:32")
    XCTAssertEqual(label("row.fajr.status", in: app), "Upcoming")
    assertFitsOnScreen(app)
    screenshot("tv-04b-edinburgh-after-midnight")
  }

  /// The tallest board, every night from Isha to its iqama: "Isha has started", the next
  /// Fajr with its countdown, and the timetable it comes from, in English and Arabic. The
  /// licence's attribution still ends inside the safe area.
  @MainActor
  func testIshaJustStarted() {
    var app = launchBoard("muis", at: "2026-10-14T20:05:00+08:00")
    XCTAssertEqual(label("next.justStarted", in: app), "Isha has started")
    XCTAssertEqual(label("next.name", in: app), "Fajr")
    XCTAssertEqual(
      label("next.owningDay", in: app), "From the timetable of Thursday, October 15, 2026")
    assertFitsOnScreen(app)
    screenshot("tv-05-muis-isha-started")
    app.terminate()

    app = launchBoard("muis", at: "2026-10-14T20:05:00+08:00", language: "ar")
    XCTAssertTrue(element("next.justStarted", in: app).exists)
    XCTAssertEqual(label("next.name", in: app), "الفجر")
    XCTAssertTrue(element("next.owningDay", in: app).exists)
    assertFitsOnScreen(app)
    screenshot("tv-05-muis-isha-started-arabic")
  }

  /// The partial row of 24 June: Isha isn't published, so the board names no next prayer and no
  /// status, and shows why instead of a time.
  @MainActor
  func testPartialRow() {
    let app = launchBoard("edinburgh", at: "2026-06-24T23:00:00+01:00")
    XCTAssertEqual(
      label("coverage.gap.0", in: app), "Wednesday, June 24, 2026: Isha (not published)")
    XCTAssertEqual(label("row.isha.time", in: app), "Begin time: not published")
    assertMissing("row.isha.iqama", in: app)
    assertMissing("next.name", in: app)
    assertMissing("next.countdown", in: app)
    XCTAssertEqual(label("row.fajr.status", in: app), "Unknown")
    assertFitsOnScreen(app)
    screenshot("tv-06a-edinburgh-partial-row")
  }

  /// Arabic: names, Arabic-Indic digits and a right-to-left layout.
  @MainActor
  func testArabic() {
    let app = launchBoard("muis", at: "2026-10-14T14:00:00+08:00", language: "ar")
    XCTAssertEqual(label("header.title", in: app), "سنغافورة")
    XCTAssertEqual(label("header.clock", in: app), "١٤:٠٠")
    XCTAssertEqual(label("row.fajr.name", in: app), "الفجر")
    XCTAssertEqual(label("row.fajr.time", in: app), "الأذان ٠٥:٣١")
    XCTAssertEqual(label("row.fajr.status", in: app), "انقضت")
    XCTAssertEqual(label("next.name", in: app), "العصر")
    XCTAssertTrue(label("header.hijri", in: app).contains("١٤٤٨"))
    // Right to left: the name column sits to the right of the time column, and the
    // next-prayer panel to the left of the table.
    let name = element("row.fajr.name", in: app).frame
    let time = element("row.fajr.time", in: app).frame
    XCTAssertGreaterThan(name.minX, time.maxX)
    XCTAssertLessThan(
      element("next.name", in: app).frame.maxX, element("row.fajr.status", in: app).frame.minX)
    assertFitsOnScreen(app)
    screenshot("tv-07-muis-arabic")
  }
}
