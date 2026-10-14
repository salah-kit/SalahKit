#if canImport(SwiftUI) && os(macOS)
  import SwiftUI
  import Testing

  /// The snapshot comparison catches the smallest change that matters: one digit of a time or
  /// a day offset. It once allowed 0.1 % of an image to differ, which let a time a minute late
  /// pass.
  @Suite("Snapshot comparison")
  @MainActor
  struct SnapshotComparisonTests {
    func image(_ text: String, _ font: Font) throws -> CGImage {
      try #require(Snapshot.render(Text(verbatim: text).font(font), width: 200))
    }

    @Test("the same view renders identically")
    func identical() throws {
      #expect(Snapshot.compare(try image("7:28 PM", .body), try image("7:28 PM", .body)) == nil)
    }

    @Test(
      "one changed digit fails",
      arguments: [
        ("7:28 PM", "7:29 PM", Font.body), ("10:00", "10:01", .footnote), ("+1", "+2", .caption2),
        ("٧:٢٨ م", "٧:٢٩ م", .body),
      ])
    func oneDigit(_ first: String, _ second: String, _ font: Font) throws {
      #expect(Snapshot.compare(try image(first, font), try image(second, font)) != nil)
    }
  }
#endif
