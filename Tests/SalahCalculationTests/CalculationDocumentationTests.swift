import Foundation
import Testing

/// Checks that the Swift code about calculation in README.md and in the DocC article "A
/// calculated prayer app with Core and Calculation" is the code that
/// `CalculationDocumentationExamples` compiles and runs.
///
/// README blocks that mention `CalculationSource` or `CalculationSettings` are checked here;
/// SalahCore's `DocumentationTests` checks the others.
@Suite struct CalculationDocumentationTests {
  nonisolated static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  nonisolated static let readme = "README.md"
  nonisolated static let article =
    "Sources/SalahCalculation/SalahCalculation.docc/CalculatedPrayerApp.md"

  /// Whether a Swift block belongs to SalahCalculation's documentation.
  nonisolated static func isCalculation(_ block: String) -> Bool {
    block.contains("CalculationSource") || block.contains("CalculationSettings")
  }

  @Test(arguments: [readme, article])
  func swiftBlocksAreTestedExamples(_ path: String) throws {
    let examples = try String(
      contentsOf: Self.root.appendingPathComponent(
        "Tests/SalahCalculationTests/CalculationDocumentationExamples.swift"),
      encoding: .utf8)
    let haystack = "\n\(Self.normalized(examples))\n"
    var blocks = try Self.swiftBlocks(in: path).filter { !$0.contains(".package(url:") }
    if path == Self.readme { blocks = blocks.filter(Self.isCalculation) }
    #expect(!blocks.isEmpty, "\(path) has no calculation code")
    for block in blocks {
      #expect(
        haystack.contains("\n\(Self.normalized(block))\n"),
        "\(path) has a Swift block that CalculationDocumentationExamples.swift doesn't run:\n\(block)"
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

  /// Code without indentation, blank lines and imports, so a block matches the same lines
  /// inside a test function.
  nonisolated static func normalized(_ code: String) -> String {
    code.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("import ") }
      .joined(separator: "\n")
  }
}
