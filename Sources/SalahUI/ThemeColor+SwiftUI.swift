#if canImport(SwiftUI)
  import SwiftUI

  extension ThemeColor {
    /// The color to draw, in the sRGB color space.
    public var color: Color {
      Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
  }
#endif
