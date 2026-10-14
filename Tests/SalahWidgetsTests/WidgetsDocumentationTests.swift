import Foundation
import Testing

/// Checks that the Swift code of the articles "Building widget timelines without daily app
/// launches" and "Lessons from Salah", and README.md's blocks about SalahWidgets, is the code
/// that `WidgetsDocumentationExamples` compiles and runs.
@Suite struct WidgetsDocumentationTests {
  nonisolated static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  nonisolated static let readme = "README.md"
  nonisolated static let article =
    "Sources/SalahWidgets/SalahWidgets.docc/BuildingWidgetTimelines.md"
  nonisolated static let lessons = "Sources/SalahWidgets/SalahWidgets.docc/LessonsFromSalah.md"
  /// The files the examples are in.
  nonisolated static let examples = [
    "Tests/SalahWidgetsTests/WidgetsDocumentationExamples.swift",
    "Tests/SalahWidgetsTests/LessonsDocumentationExamples.swift",
  ]

  /// Whether a README block is about SalahWidgets; SalahCore's, SalahCalculation's and SalahUI's
  /// documentation tests check the others.
  nonisolated static func isWidgets(_ block: String) -> Bool {
    ["SharedValue", "PrayerTimelineBuilder", "DarwinSignal"].contains { block.contains($0) }
  }

  @Test(arguments: [readme, article, lessons])
  func swiftBlocksAreTestedExamples(_ path: String) throws {
    let examples = try Self.examples.map {
      try String(contentsOf: Self.root.appendingPathComponent($0), encoding: .utf8)
    }
    let haystack = examples.map { "\n\(Self.normalized($0))\n" }.joined()
    var blocks = try Self.swiftBlocks(in: path).filter { !$0.contains(".package(url:") }
    if path == Self.readme { blocks = blocks.filter(Self.isWidgets) }
    #expect(!blocks.isEmpty, "\(path) has no SalahWidgets code")
    for block in blocks {
      #expect(
        haystack.contains("\n\(Self.normalized(block))\n"),
        "\(path) has a Swift block that the documentation examples don't run:\n\(block)"
      )
    }
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
  /// lines inside a test function.
  nonisolated static func normalized(_ code: String) -> String {
    code.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("import ") }
      .joined(separator: "\n")
  }
}
