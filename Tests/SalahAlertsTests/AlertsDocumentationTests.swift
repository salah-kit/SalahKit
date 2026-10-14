import Foundation
import SalahAlerts
import SalahCore
import Testing

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

  /// The article's plan with every reminder on, at midnight: the D7 example it describes.
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
