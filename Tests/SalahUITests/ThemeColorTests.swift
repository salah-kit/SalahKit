import Foundation
import Testing

@testable import SalahUI

/// Salah's color math as imported at `4bc00e9` (`Shared/WidgetUI/GuidanceWidgetTheme.swift`,
/// lines 8-63), copied verbatim apart from formatting, as the reference `ThemeColor` matches.
/// Its contrast fix still matches on Salah's own surfaces; elsewhere, `ThemeColor` takes the
/// nearer direction (#57).
private struct SalahColorSpec {
  var red: Double
  var green: Double
  var blue: Double
  var opacity: Double

  init(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.opacity = opacity
  }

  var relativeLuminance: Double {
    func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
  }

  static func contrastRatio(_ a: SalahColorSpec, _ b: SalahColorSpec) -> Double {
    let la = a.relativeLuminance
    let lb = b.relativeLuminance
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  }

  func adjustedForContrast(against surface: SalahColorSpec, ratio target: Double = 4.5)
    -> SalahColorSpec
  {
    if Self.contrastRatio(self, surface) >= target { return self }
    let towardLight = surface.relativeLuminance < 0.5
    var best = self
    for step in 1...20 {
      let t = Double(step) / 20.0
      let candidate = SalahColorSpec(
        red + (towardLight ? (1 - red) : -red) * t,
        green + (towardLight ? (1 - green) : -green) * t,
        blue + (towardLight ? (1 - blue) : -blue) * t,
        opacity)
      best = candidate
      if Self.contrastRatio(candidate, surface) >= target { break }
    }
    return best
  }

  func distance(to other: SalahColorSpec) -> Double {
    let dr = red - other.red
    let dg = green - other.green
    let db = blue - other.blue
    return (dr * dr + dg * dg + db * db).squareRoot()
  }
}

extension ThemeColor {
  fileprivate var salah: SalahColorSpec { SalahColorSpec(red, green, blue, opacity) }
}

@Suite("ThemeColor")
struct ThemeColorTests {
  static let black = ThemeColor(red: 0, green: 0, blue: 0)
  static let white = ThemeColor(red: 1, green: 1, blue: 1)

  /// Every color of an 11-step grid, as a sample of in-range colors.
  static let grid: [ThemeColor] = {
    let steps = (0...10).map { Double($0) / 10 }
    return steps.flatMap { red in
      steps.flatMap { green in steps.map { blue in ThemeColor(red: red, green: green, blue: blue) }
      }
    }
  }()

  /// Salah's palette colors and functional hues, which its editor checked against each other.
  static let salahColors: [ThemeColor] = [
    ThemeColor(red: 0.88, green: 0.69, blue: 0.29),
    ThemeColor(red: 0.04, green: 0.52, blue: 1.00),
    ThemeColor(red: 0.075, green: 0.094, blue: 0.180),
    ThemeColor(red: 0.027, green: 0.035, blue: 0.078),
    ThemeColor(red: 0.62, green: 0.45, blue: 0.12),
    ThemeColor(red: 0.00, green: 0.40, blue: 0.85),
    ThemeColor(red: 0.992, green: 0.976, blue: 0.945),
    ThemeColor(red: 0.953, green: 0.925, blue: 0.875),
    ThemeColor(red: 1.00, green: 0.27, blue: 0.23),
    ThemeColor(red: 0.20, green: 0.84, blue: 0.29),
    ThemeColor(red: 1.00, green: 0.62, blue: 0.04),
    ThemeColor(red: 0.75, green: 0.35, blue: 0.95),
  ]

  @Test("luminance and contrast at the ends of the scale")
  func ends() {
    #expect(Self.black.relativeLuminance == 0)
    #expect(Self.white.relativeLuminance == 1)
    #expect(ThemeColor.contrastRatio(Self.black, Self.white) == 21)
    #expect(ThemeColor.contrastRatio(Self.white, Self.black) == 21)
    #expect(ThemeColor.contrastRatio(Self.white, Self.white) == 1)
  }

  @Test("WCAG's well-known grey: #767676 on white is just over 4.5")
  func knownContrast() {
    let grey = ThemeColor(red: 118 / 255, green: 118 / 255, blue: 118 / 255)
    let ratio = ThemeColor.contrastRatio(grey, Self.white)
    #expect(ratio > 4.5 && ratio < 4.55)
  }

  @Test("luminance, contrast and distance equal Salah's on a grid and its palette")
  func matchesSalah() {
    let colors = Self.grid + Self.salahColors
    for color in colors {
      #expect(color.relativeLuminance == color.salah.relativeLuminance)
    }
    for first in Self.salahColors {
      for second in colors {
        #expect(
          ThemeColor.contrastRatio(first, second)
            == SalahColorSpec.contrastRatio(first.salah, second.salah))
        #expect(first.distance(to: second) == first.salah.distance(to: second.salah))
      }
    }
  }

  /// The surfaces Salah's editor fixes a color against: the tops and bottoms of its widget's
  /// three background bases (midnight, sand and graphite) in dark and light, plus black and
  /// white. On these, only one direction can reach a ratio above about 1.33, the one Salah's
  /// rule (toward white below a luminance of 0.5) takes, so the two rules agree.
  static let salahSurfaces: [ThemeColor] = [
    black, white,
    ThemeColor(red: 0.075, green: 0.094, blue: 0.180),
    ThemeColor(red: 0.027, green: 0.035, blue: 0.078),
    ThemeColor(red: 0.992, green: 0.976, blue: 0.945),
    ThemeColor(red: 0.953, green: 0.925, blue: 0.875),
    ThemeColor(red: 0.16, green: 0.13, blue: 0.11),
    ThemeColor(red: 0.09, green: 0.07, blue: 0.055),
    ThemeColor(red: 0.992, green: 0.952, blue: 0.890),
    ThemeColor(red: 0.968, green: 0.910, blue: 0.820),
    ThemeColor(red: 0.13, green: 0.13, blue: 0.15),
    ThemeColor(red: 0.07, green: 0.07, blue: 0.085),
    ThemeColor(red: 0.962, green: 0.962, blue: 0.972),
    ThemeColor(red: 0.900, green: 0.900, blue: 0.920),
  ]

  @Test("the contrast fix equals Salah's on a grid against its surfaces, at 3 and 4.5")
  func adjustmentMatchesSalah() {
    for color in Self.grid + Self.salahColors {
      for surface in Self.salahSurfaces {
        for ratio in [3.0, 4.5] {
          let ours = color.adjustedForContrast(against: surface, ratio: ratio)
          let theirs = color.salah.adjustedForContrast(against: surface.salah, ratio: ratio)
          #expect([ours.red, ours.green, ours.blue] == [theirs.red, theirs.green, theirs.blue])
        }
      }
    }
  }

  @Test("the contrast fix reaches the ratio wherever Salah's did, on every surface")
  func adjustmentReachesWhereSalahsDid() {
    let surfaces = [Self.black, Self.white] + Self.salahColors
    for color in Self.grid + Self.salahColors {
      for surface in surfaces {
        for ratio in [3.0, 4.5] {
          let theirs = color.salah.adjustedForContrast(against: surface.salah, ratio: ratio)
          guard SalahColorSpec.contrastRatio(theirs, surface.salah) >= ratio else { continue }
          let ours = color.adjustedForContrast(against: surface, ratio: ratio)
          #expect(ThemeColor.contrastRatio(ours, surface) >= ratio)
        }
      }
    }
  }

  @Test("the contrast fix keeps a passing color, lightens on dark, darkens on light")
  func adjustment() {
    let surface = ThemeColor(red: 0.075, green: 0.094, blue: 0.180)
    let passing = ThemeColor(red: 0.88, green: 0.69, blue: 0.29, opacity: 0.5)
    #expect(passing.adjustedForContrast(against: surface) == passing)

    let dim = ThemeColor(red: 0.2, green: 0.2, blue: 0.4, opacity: 0.8)
    let lighter = dim.adjustedForContrast(against: surface)
    #expect(ThemeColor.contrastRatio(lighter, surface) >= 4.5)
    #expect(lighter.red > dim.red && lighter.blue > dim.blue)
    #expect(lighter.opacity == 0.8)

    let pale = ThemeColor(red: 0.9, green: 0.85, blue: 0.7)
    let darker = pale.adjustedForContrast(against: Self.white)
    #expect(ThemeColor.contrastRatio(darker, Self.white) >= 4.5)
    #expect(darker.red < pale.red)
  }

  @Test("on a mid-tone surface the contrast fix goes the way that reaches the ratio (#57)")
  func midToneSurface() {
    let color = ThemeColor(red: 0.45, green: 0.45, blue: 0.55)
    // Relative luminance 0.32 and 0.45: white reaches only 2.85 and 2.11 on them.
    for grey in [0.6, 0.7] {
      let surface = ThemeColor(red: grey, green: grey, blue: grey)
      let fixed = color.adjustedForContrast(against: surface)
      #expect(ThemeColor.contrastRatio(fixed, surface) >= 4.5, "\(grey)")
      #expect(fixed.red < color.red && fixed.blue < color.blue, "\(grey)")
    }
  }

  @Test("when both ways reach the ratio, the nearer candidate wins")
  func nearerCandidate() {
    func grey(_ value: Double) -> ThemeColor { ThemeColor(red: value, green: value, blue: value) }
    func expectNear(_ color: ThemeColor, _ value: Double, _ comment: Comment) {
      for component in [color.red, color.green, color.blue] {
        #expect(abs(component - value) < 1e-9, comment)
      }
    }
    // On a 0.5 grey at 2.5:1, a lighter grey moves 0.0625 toward white rather than 0.525
    // toward black, and a darker one 0.045 toward black rather than 0.525 toward white.
    let lighter = grey(0.75).adjustedForContrast(against: grey(0.5), ratio: 2.5)
    expectNear(lighter, 0.8125, "0.75 on 0.5")
    #expect(ThemeColor.contrastRatio(lighter, grey(0.5)) >= 2.5)
    let darker = grey(0.3).adjustedForContrast(against: grey(0.5), ratio: 2.5)
    expectNear(darker, 0.255, "0.3 on 0.5")
    #expect(ThemeColor.contrastRatio(darker, grey(0.5)) >= 2.5)
    // Fewer steps would go the other way here: 14 big steps toward black against 15 small
    // ones toward white.
    let pale = grey(0.8).adjustedForContrast(against: grey(0.55), ratio: 3)
    expectNear(pale, 0.95, "0.8 on 0.55")
    #expect(ThemeColor.contrastRatio(pale, grey(0.55)) >= 3)
  }

  @Test("equally near candidates go toward whichever of white and black contrasts more")
  func tie() {
    func grey(_ value: Double) -> ThemeColor { ThemeColor(red: value, green: value, blue: value) }
    // A 0.5 grey reaches the ratio after 13 steps each way on a 0.46 grey at 3:1, where white
    // contrasts more (4.59 against 4.58), and after 11 on a 0.47 grey at 2.5:1, where black
    // does (4.75 against 4.42).
    let towardWhite = grey(0.5).adjustedForContrast(against: grey(0.46), ratio: 3)
    #expect(abs(towardWhite.red - 0.825) < 1e-9)
    #expect(ThemeColor.contrastRatio(towardWhite, grey(0.46)) >= 3)
    let towardBlack = grey(0.5).adjustedForContrast(against: grey(0.47), ratio: 2.5)
    #expect(abs(towardBlack.red - 0.225) < 1e-9)
    #expect(ThemeColor.contrastRatio(towardBlack, grey(0.47)) >= 2.5)
  }

  @Test("the contrast fix leaves a color alone at a ratio of 1 or less, and clamps its input")
  func adjustmentEdges() {
    let color = ThemeColor(red: 0.3, green: 0.4, blue: 0.5, opacity: 0.7)
    for ratio in [1.0, 0.5, 0] {
      #expect(color.adjustedForContrast(against: color, ratio: ratio) == color)
    }
    let odd = ThemeColor(red: 2, green: -1, blue: .nan)
    let fixed = odd.adjustedForContrast(against: ThemeColor(red: 0.5, green: 0.5, blue: 0.5))
    for component in [fixed.red, fixed.green, fixed.blue] {
      #expect((0...1).contains(component))
    }
  }

  @Test("a ratio out of reach ends at whichever of white and black contrasts more")
  func unreachable() {
    let grey = ThemeColor(red: 0.5, green: 0.5, blue: 0.5)
    let darkMidSurface = ThemeColor(red: 0.45, green: 0.45, blue: 0.45)
    let onDarkMid = grey.adjustedForContrast(against: darkMidSurface, ratio: 21)
    #expect([onDarkMid.red, onDarkMid.green, onDarkMid.blue] == [1, 1, 1])
    let lightMidSurface = ThemeColor(red: 0.6, green: 0.6, blue: 0.6)
    let onLightMid = grey.adjustedForContrast(against: lightMidSurface, ratio: 21)
    #expect([onLightMid.red, onLightMid.green, onLightMid.blue] == [0, 0, 0])
    let onLight = grey.adjustedForContrast(against: Self.white, ratio: 22)
    #expect([onLight.red, onLight.green, onLight.blue] == [0, 0, 0])
  }

  @Test("components outside 0...1 count as the nearest end; NaN counts as 0")
  func outOfRange() {
    let bright = ThemeColor(red: 2, green: 1.5, blue: 9)
    #expect(bright.relativeLuminance == Self.white.relativeLuminance)
    let dark = ThemeColor(red: -1, green: .nan, blue: -0.5)
    #expect(dark.relativeLuminance == 0)
    #expect(bright.distance(to: dark) == Self.white.distance(to: Self.black))
    #expect(ThemeColor.contrastRatio(bright, dark) == 21)
  }

  @Test("distance is symmetric and spans 0 to the square root of 3")
  func distance() {
    #expect(Self.white.distance(to: Self.white) == 0)
    #expect(Self.black.distance(to: Self.white) == 3.0.squareRoot())
    let red = ThemeColor(red: 1, green: 0, blue: 0)
    #expect(red.distance(to: Self.black) == Self.black.distance(to: red))
  }

  @Test("encodes its four components")
  func codable() throws {
    let color = ThemeColor(red: 0.04, green: 0.52, blue: 1, opacity: 0.5)
    let data = try JSONEncoder().encode(color)
    #expect(try JSONDecoder().decode(ThemeColor.self, from: data) == color)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Double])
    #expect(object == ["red": 0.04, "green": 0.52, "blue": 1, "opacity": 0.5])
  }
}

@Suite("ContrastCheck")
struct ContrastCheckTests {
  /// Salah's functional hues (`AppearanceTab.swift`, lines 126-131 at `4bc00e9`).
  static let functional: [ThemeColor] = [
    ThemeColor(red: 1.00, green: 0.27, blue: 0.23),
    ThemeColor(red: 0.20, green: 0.84, blue: 0.29),
    ThemeColor(red: 1.00, green: 0.62, blue: 0.04),
    ThemeColor(red: 0.75, green: 0.35, blue: 0.95),
  ]
  static let midnight = ThemeColor(red: 0.075, green: 0.094, blue: 0.180)

  @Test("the defaults are Salah's thresholds: 3:1 contrast and 0.28 from reserved colors")
  func defaults() {
    let check = ContrastCheck()
    #expect(check.minimumContrast == 3)
    #expect(check.minimumReservedDistance == 0.28)
  }

  @Test("Salah's Nocturne accents pass on its midnight surface")
  func nocturnePasses() {
    let check = ContrastCheck()
    let brass = ThemeColor(red: 0.88, green: 0.69, blue: 0.29)
    let blue = ThemeColor(red: 0.04, green: 0.52, blue: 1.00)
    #expect(
      check.problems(foreground: brass, background: Self.midnight, reserved: Self.functional)
        .isEmpty)
    #expect(
      check.problems(foreground: blue, background: Self.midnight, reserved: Self.functional).isEmpty
    )
  }

  @Test("low contrast comes first, then each reserved color too close, in order")
  func problems() {
    let check = ContrastCheck()
    // About 0.20 from both the red and the orange.
    let nearRed = ThemeColor(red: 1.0, green: 0.45, blue: 0.15)
    let reserved = [Self.functional[2], Self.functional[1], Self.functional[0]]
    let problems = check.problems(foreground: nearRed, background: nearRed, reserved: reserved)
    #expect(problems.count == 3)
    #expect(problems.first == .lowContrast(1))
    #expect(
      Array(problems.dropFirst()) == [
        .tooCloseToReserved(Self.functional[2]), .tooCloseToReserved(Self.functional[0]),
      ])
  }

  @Test("exactly the thresholds passes")
  func boundaries() {
    let grey = ThemeColor(red: 0.5, green: 0.5, blue: 0.5)
    let ratio = ThemeColor.contrastRatio(grey, .init(red: 0, green: 0, blue: 0))
    let atContrast = ContrastCheck(minimumContrast: ratio)
    #expect(
      atContrast.problems(foreground: grey, background: .init(red: 0, green: 0, blue: 0)).isEmpty)

    let other = ThemeColor(red: 0.5, green: 0.5, blue: 0.9)
    let atDistance = ContrastCheck(
      minimumContrast: 1, minimumReservedDistance: grey.distance(to: other))
    #expect(atDistance.problems(foreground: grey, background: grey, reserved: [other]).isEmpty)
  }

  @Test("the large-text floor and the body-text level differ")
  func bodyText() {
    // About 3.5:1 on white: large text only.
    let grey = ThemeColor(red: 0.53, green: 0.53, blue: 0.53)
    let white = ThemeColor(red: 1, green: 1, blue: 1)
    #expect(ContrastCheck().problems(foreground: grey, background: white).isEmpty)
    let body = ContrastCheck(minimumContrast: 4.5).problems(foreground: grey, background: white)
    guard case .lowContrast(let ratio)? = body.first else {
      Issue.record("expected low contrast, got \(body)")
      return
    }
    #expect(ratio > 3 && ratio < 4.5)
  }
}
