#if canImport(SwiftUI) && os(macOS)
  import CoreGraphics
  import Foundation
  import ImageIO
  import SwiftUI
  import Testing

  /// Image snapshots of SwiftUI views, compared with reference PNGs in `Snapshots/<platform>/`.
  ///
  /// Views render with `ImageRenderer` at twice their size, in light mode, with a blue tint and a
  /// white background, so the image depends only on the view and the operating system's
  /// rendering. Each major macOS version has its own references, because system fonts change
  /// between versions.
  ///
  /// - Set `SALAHKIT_RECORD_SNAPSHOTS=1` to write the references for this macOS version.
  /// - A missing or different reference fails the test and writes the rendered image to
  ///   `.build/snapshot-failures/<platform>/`, which CI uploads.
  @MainActor
  enum Snapshot {
    /// The package's root directory.
    static let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Where the references of this macOS version are.
    static var references: URL {
      URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Snapshots").appendingPathComponent(platform)
    }

    /// Where failed comparisons leave the rendered image.
    static var failures: URL {
      root.appendingPathComponent(".build/snapshot-failures").appendingPathComponent(platform)
    }

    /// The macOS major version, such as `macOS-27`.
    static var platform: String {
      "macOS-\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"
    }

    static var isRecording: Bool {
      ProcessInfo.processInfo.environment["SALAHKIT_RECORD_SNAPSHOTS"] == "1"
    }

    /// Renders `view` at `width` points and compares it with the reference called `name`.
    ///
    /// A check that reuses another check's reference passes `recordable: false`, so recording
    /// never replaces that reference with its own image.
    static func check(
      _ view: some View, named name: String, width: CGFloat = 390, recordable: Bool = true,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      guard let image = render(view, width: width) else {
        Issue.record("\(name): the view didn't render", sourceLocation: sourceLocation)
        return
      }
      let reference = references.appendingPathComponent("\(name).png")
      if isRecording, recordable {
        write(image, to: reference)
        return
      }
      guard let expected = load(reference) else {
        write(image, to: failures.appendingPathComponent("\(name).png"))
        let message =
          "\(name): no reference for \(platform) at \(reference.path); record one with "
          + "SALAHKIT_RECORD_SNAPSHOTS=1 swift test"
        Issue.record("\(message)", sourceLocation: sourceLocation)
        return
      }
      if let difference = compare(image, expected) {
        write(image, to: failures.appendingPathComponent("\(name).png"))
        let message =
          "\(name): differs from its \(platform) reference: \(difference); the rendered image is "
          + "in \(failures.appendingPathComponent("\(name).png").path)"
        Issue.record("\(message)", sourceLocation: sourceLocation)
      }
    }

    /// The view as an image, `width` points wide and as tall as it needs, at scale 2.
    static func render(_ view: some View, width: CGFloat) -> CGImage? {
      let content =
        view
        .frame(width: width, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .tint(.blue)
      let renderer = ImageRenderer(content: content)
      renderer.scale = 2
      renderer.proposedSize = ProposedViewSize(width: width, height: nil)
      return renderer.cgImage
    }

    /// Why two images differ, or `nil` when every pixel's channels are within 2 of each other
    /// on at least 99.9 % of the pixels.
    static func compare(_ image: CGImage, _ reference: CGImage) -> String? {
      guard image.width == reference.width, image.height == reference.height else {
        return
          "size \(image.width)×\(image.height), reference \(reference.width)×\(reference.height)"
      }
      guard let pixels = rgba(image), let expected = rgba(reference) else {
        return "the pixels couldn't be read"
      }
      var differing = 0
      var largest: UInt8 = 0
      for pixel in stride(from: 0, to: pixels.count, by: 4) {
        var worst: UInt8 = 0
        for channel in 0..<4 {
          let a = pixels[pixel + channel]
          let b = expected[pixel + channel]
          worst = max(worst, a > b ? a - b : b - a)
        }
        largest = max(largest, worst)
        if worst > 2 { differing += 1 }
      }
      let total = image.width * image.height
      guard Double(differing) > Double(total) * 0.001 else { return nil }
      return "\(differing) of \(total) pixels differ, by up to \(largest)"
    }

    /// The image's pixels as 8-bit RGBA in the sRGB space.
    static func rgba(_ image: CGImage) -> [UInt8]? {
      var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
      let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return true
      }
      return drawn ? pixels : nil
    }

    static func load(_ url: URL) -> CGImage? {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
      return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func write(_ image: CGImage, to url: URL) {
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      guard
        let destination = CGImageDestinationCreateWithURL(
          url as CFURL, "public.png" as CFString, 1, nil)
      else { return }
      CGImageDestinationAddImage(destination, image, nil)
      CGImageDestinationFinalize(destination)
    }
  }
#endif
