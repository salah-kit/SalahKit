import Foundation
import SalahCore
import SalahFixtures
import Testing

/// The code of the DocC overview and of `PrayerFixtures`' documentation comment, compiled and
/// run against the public API only.
///
/// `DocumentationTests` checks that every Swift block in those two places appears here line for
/// line, so an edit to the documentation that isn't mirrored here fails the tests.
@Suite struct DocumentationExamples {
  @Test func overviewExample() throws {
    let place = PrayerFixtures.newYorkDSTChange
    let day = place.schedule.day(place.featuredDay)

    let moment = PrayerFixtures.beforeFajr
    if case .available(let state, _) = moment.state(), let fajr = state.nextPrayer {
      print(fajr.time.timeIntervalSince(moment.date))  // 12840.0
    }

    #expect(day.coverage == .complete)
    #expect(day.day?[.fajr]?.time == (try instant("2026-03-08T06:04:00-04:00")))
    let countdown = try #require(moment.state().prayerState?.nextPrayer)
    #expect(countdown.time.timeIntervalSince(moment.date) == 12_840)
  }
}

/// Checks that the Swift code in the documentation is the code that `DocumentationExamples`
/// compiles and runs.
@Suite struct DocumentationTests {
  /// A file of the repository whose fenced code blocks are documentation.
  nonisolated struct Document: Sendable, CustomTestStringConvertible {
    let path: String
    /// The prefix of a documentation comment's lines, such as `///`, or `nil` for Markdown.
    let commentPrefix: String?

    var testDescription: String { path }

    /// The contents of the fenced code blocks in a language, in document order.
    func blocks(_ language: String) throws -> [String] {
      let url = DocumentationTests.root.appendingPathComponent(path)
      var blocks: [String] = []
      var current: [String]?
      for line in try String(contentsOf: url, encoding: .utf8).split(
        separator: "\n", omittingEmptySubsequences: false)
      {
        var text = line.trimmingCharacters(in: .whitespaces)
        if let prefix = commentPrefix {
          guard text.hasPrefix(prefix) else { continue }
          text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        if var lines = current {
          if text == "```" {
            blocks.append(lines.joined(separator: "\n"))
            current = nil
          } else {
            lines.append(text)
            current = lines
          }
        } else if text == "```\(language)" {
          current = []
        }
      }
      return blocks
    }
  }

  nonisolated static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  nonisolated static let overview = Document(
    path: "Sources/SalahFixtures/SalahFixtures.docc/SalahFixtures.md", commentPrefix: nil)
  nonisolated static let comment = Document(
    path: "Sources/SalahFixtures/PrayerFixtures.swift", commentPrefix: "///")

  @Test(arguments: [overview, comment])
  func swiftBlocksAreTestedExamples(_ document: Document) throws {
    let examples = try String(
      contentsOf: Self.root.appendingPathComponent(
        "Tests/SalahFixturesTests/DocumentationTests.swift"),
      encoding: .utf8)
    let haystack = "\n\(Self.normalized(examples))\n"
    let blocks = try document.blocks("swift")
    #expect(!blocks.isEmpty)
    for block in blocks {
      #expect(
        haystack.contains("\n\(Self.normalized(block))\n"),
        "\(document.path) has a Swift block that DocumentationExamples doesn't run:\n\(block)")
    }
  }

  /// Code with indentation, blank lines and imports removed, so that a block matches the same
  /// lines inside a test function.
  nonisolated static func normalized(_ code: String) -> String {
    code.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("import ") }
      .joined(separator: "\n")
  }
}
