import Foundation
import Testing

/// Checks that the Swift code of the article "Styling rows and cards", and README.md's blocks
/// about SalahUI, is the code that `UIDocumentationExamples` compiles and runs.
@Suite struct UIDocumentationTests {
  nonisolated static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  nonisolated static let readme = "README.md"
  nonisolated static let article =
    "Sources/SalahUI/SalahUI.docc/StylingRowsAndCards.md"

  /// Whether a README block is about SalahUI; SalahCore's, SalahCalculation's and SalahWidgets'
  /// documentation tests check the others.
  nonisolated static func isUI(_ block: String) -> Bool {
    [
      "PrayerTimesList", "NextPrayerView", "PrayerCountdown", "PrayerRowStyle", "NextPrayerStyle",
      "ThemeColor", "ContrastCheck",
    ].contains { block.contains($0) }
  }

  @Test(arguments: [readme, article])
  func swiftBlocksAreTestedExamples(_ path: String) throws {
    let examples = try String(
      contentsOf: Self.root.appendingPathComponent(
        "Tests/SalahUITests/UIDocumentationExamples.swift"),
      encoding: .utf8)
    let haystack = "\n\(Self.normalized(examples))\n"
    var blocks = try Self.swiftBlocks(in: path).filter { !$0.contains(".package(url:") }
    if path == Self.readme { blocks = blocks.filter(Self.isUI) }
    #expect(!blocks.isEmpty, "\(path) has no SalahUI code")
    for block in blocks {
      #expect(
        haystack.contains("\n\(Self.normalized(block))\n"),
        "\(path) has a Swift block that UIDocumentationExamples.swift doesn't run:\n\(block)"
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
