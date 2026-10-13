import Foundation
import Testing

/// Checks that the Swift code in README.md and in the DocC articles is the code that
/// `DocumentationExamples` compiles and runs.
@Suite struct DocumentationTests {
  /// A Markdown document in the repository.
  nonisolated struct Document: Sendable, CustomTestStringConvertible {
    let path: String

    var testDescription: String { path }

    func text() throws -> String {
      try String(contentsOf: DocumentationTests.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The contents of the fenced code blocks in a language, in document order.
    func blocks(_ language: String) throws -> [String] {
      var blocks: [String] = []
      var current: [String]?
      for line in try text().split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if var lines = current {
          if trimmed == "```" {
            blocks.append(lines.joined(separator: "\n"))
            current = nil
          } else {
            lines.append(String(line))
            current = lines
          }
        } else if trimmed == "```\(language)" {
          current = []
        }
      }
      return blocks
    }

    func jsonBlocks() throws -> [Data] {
      try blocks("json").map { Data($0.utf8) }
    }
  }

  nonisolated static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  nonisolated static let readme = Document(path: "README.md")
  nonisolated static let article = Document(
    path: "Sources/SalahCore/SalahCore.docc/UsingAMosqueTimetable.md")

  @Test(arguments: [readme, article])
  func swiftBlocksAreTestedExamples(_ document: Document) throws {
    let examples = try String(
      contentsOf: Self.root.appendingPathComponent(
        "Tests/SalahCoreTests/DocumentationExamples.swift"),
      encoding: .utf8)
    let haystack = "\n\(Self.normalized(examples))\n"
    // Package manifest fragments aren't app code, and SalahCalculation's tests check the
    // calculation blocks (CalculationDocumentationTests).
    let blocks = try document.blocks("swift").filter {
      !$0.contains(".package(url:") && !$0.contains("CalculationSource")
        && !$0.contains("CalculationSettings")
    }
    #expect(!blocks.isEmpty)
    for block in blocks {
      #expect(
        haystack.contains("\n\(Self.normalized(block))\n"),
        "\(document.path) has a Swift block that DocumentationExamples.swift doesn't run:\n\(block)"
      )
    }
  }

  @Test func articleJSONDecodes() throws {
    #expect(try Self.article.jsonBlocks().count == 3)
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
