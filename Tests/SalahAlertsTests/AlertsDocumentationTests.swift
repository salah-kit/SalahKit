import Foundation
import SalahCore
import Testing

@testable import SalahAlerts

/// Checks that the Swift code of the DocC article "Alerts within the 64-notification limit", and
/// the README's blocks that import SalahAlerts, is the code `AlertsDocumentationExamples`
/// compiles, and runs the parts that need no app.
@Suite struct AlertsDocumentationTests {
  nonisolated static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  nonisolated static let readme = "README.md"
  nonisolated static let article =
    "Sources/SalahAlerts/SalahAlerts.docc/AlertsWithinTheNotificationLimit.md"

  @Test(arguments: [readme, article])
  func swiftBlocksAreTestedExamples(_ path: String) throws {
    let examples = try String(
      contentsOf: Self.root.appendingPathComponent(
        "Tests/SalahAlertsTests/AlertsDocumentationExamples.swift"),
      encoding: .utf8)
    let haystack = "\n\(Self.normalized(examples))\n"
    var blocks = try Self.swiftBlocks(in: path)
    if path == Self.readme { blocks = blocks.filter { $0.contains("import SalahAlerts") } }
    #expect(!blocks.isEmpty, "\(path) has no alerts code")
    for block in blocks {
      #expect(
        haystack.contains("\n\(Self.normalized(block))\n"),
        "\(path) has a Swift block that AlertsDocumentationExamples.swift doesn't run:\n\(block)")
    }
  }

  /// The article's plan with every reminder on, at midnight: the arithmetic example of RFC 0003
  /// §4.4, which the article describes.
  @Test func theArticlesPlanRuns() throws {
    let now = Fixture.date(0, 0)
    let every: (AlertSubject) -> AlertSettings? = { subject in
      subject.prayer.isPrayer ? AlertSettings(before: .seconds(600), after: .seconds(300)) : nil
    }
    let (alerts, plan) = try AlertsDocumentationExamples.plan(
      Fixture.schedule, now: now, settings: every)
    #expect(plan.alerts.count == 60)
    #expect(plan.coveredUntil == Fixture.time(.fajr, dayOffset: 2).addingTimeInterval(-600))
    #expect(plan.coverageByKind[.atTime] == Fixture.time(.fajr, dayOffset: 8))
    AlertsDocumentationExamples.describe(plan)
    AlertsDocumentationExamples.explainGaps(alerts)

    let settings = AlertsDocumentationExamples.reminderSettings()
    let day = Fixture.day
    #expect(settings(AlertSubject(scheduleDay: day, prayer: .sunrise)) == nil)
    #expect(settings(AlertSubject(scheduleDay: day, prayer: .fajr))?.before == .seconds(1_800))
    let jumuah = AlertsDocumentationExamples.jumuahSettings(settings)
    let friday = AlertSubject(scheduleDay: day.adding(days: 3), prayer: .dhuhr, observance: .jumuah)
    #expect(jumuah(friday)?.before == .seconds(2_700))
  }

  @Test @MainActor func theArticlesRollbackPlanRuns() throws {
    let clock = ManualAlertClock(Fixture.time(.dhuhr))
    let engine = InProcessAlertEngine(clock: clock) { _ in }
    let alerts = try Fixture.alerts(
      from: Fixture.date(12, 0), to: Fixture.date(13, 0),
      settings: Fixture.settings(AlertSettings(), for: [.dhuhr]))
    engine.update(alerts)
    clock.now = Fixture.date(12, 15)
    let plan = AlertsDocumentationExamples.planAfterClockChange(
      alerts, engine: engine, now: clock.now)
    #expect(plan.alerts.isEmpty)
    #expect(plan.coveredUntil == Fixture.date(13, 0))
  }

  @Test @MainActor func theArticleKeepsNewEarlyRequestsButExcludesPriorClockChangeReports() throws {
    let fireDate = Fixture.time(.dhuhr)
    let clock = ManualAlertClock(fireDate.addingTimeInterval(-60))
    let engine = InProcessAlertEngine(clock: clock) { _ in }
    let alerts = try Fixture.alerts(
      from: Fixture.date(12, 0), to: Fixture.date(13, 0),
      settings: Fixture.settings(AlertSettings(), for: [.dhuhr]))
    engine.update(alerts)
    clock.now = fireDate.addingTimeInterval(-1)
    // A clock change with no prior report discovers an early alert and keeps its request.
    let newlyDue = AlertsDocumentationExamples.planAfterClockChange(
      alerts, engine: engine, now: clock.now)
    #expect(newlyDue.alerts == alerts.alerts)
    #expect(engine.handledOccurrences.count == 1)
    // An ordinary replan half a second later still preserves that pending request.
    clock.now = fireDate.addingTimeInterval(-0.5)
    let ordinary = AlertsDocumentationExamples.ordinaryPlan(alerts, engine: engine, now: clock.now)
    #expect(ordinary.alerts == alerts.alerts)
    // A clock-change mark excludes it regardless of the relation to its report time.
    let clockChange = AlertsDocumentationExamples.planAfterClockChange(
      alerts, engine: engine, now: clock.now)
    #expect(clockChange.alerts.isEmpty)
    #expect(clockChange.coveredUntil == Fixture.date(13, 0))
    let laterOrdinary = AlertsDocumentationExamples.ordinaryPlan(
      alerts, engine: engine, now: clock.now)
    #expect(laterOrdinary.alerts.isEmpty, "the engine retains the mark for later replans")
  }

  /// The contents of a document's fenced Swift blocks, in order.
  nonisolated static func swiftBlocks(in path: String) throws -> [String] {
    let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    var blocks: [String] = []
    var current: [String]?
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if var lines = current {
        if trimmed == "```" {
          blocks.append(lines.joined(separator: "\n"))
          current = nil
        } else {
          lines.append(String(line))
          current = lines
        }
      } else if trimmed == "```swift" {
        current = []
      }
    }
    return blocks
  }

  /// Code with indentation, blank lines and imports removed, so that a block matches the same
  /// lines inside a function.
  nonisolated static func normalized(_ code: String) -> String {
    code.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("import ") }
      .joined(separator: "\n")
  }
}
