// swift-tools-version: 6.2

import PackageDescription

// SalahKit's own targets, tests included, default to nonisolated code. CI's isolation job sets
// SALAHKIT_DEFAULT_ISOLATION=MainActor to compile them as a module that defaults to the main
// actor (docs/rfcs/0001-core.md, section 6.3). Dependencies such as SalahTimes build as they
// always do, as they would in an app.
let defaultIsolation: [SwiftSetting] =
  Context.environment["SALAHKIT_DEFAULT_ISOLATION"] == "MainActor"
  ? [.defaultIsolation(MainActor.self)] : []

let package = Package(
  name: "SalahKit",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
    .watchOS(.v9),
    .tvOS(.v16),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "SalahCore", targets: ["SalahCore"]),
    .library(name: "SalahCalculation", targets: ["SalahCalculation"]),
    .library(name: "SalahFixtures", targets: ["SalahFixtures"]),
  ],
  dependencies: [
    // Up to the next minor version: before 1.0, a minor release of SalahTimes may change its
    // API (docs/rfcs/0002-calculation.md).
    .package(url: "https://github.com/salah-kit/SalahTimes.git", .upToNextMinor(from: "0.1.0"))
  ],
  targets: [
    .target(
      name: "SalahCore",
      // Copied, not processed: SalahCore reads the catalog as JSON on every platform
      // (docs/rfcs/0001-core.md, section 6.1).
      resources: [.copy("Resources/Localizable.xcstrings")],
      swiftSettings: defaultIsolation
    ),
    .target(
      name: "SalahCalculation",
      dependencies: ["SalahCore", .product(name: "SalahTimes", package: "SalahTimes")],
      swiftSettings: defaultIsolation
    ),
    .target(
      name: "SalahFixtures",
      dependencies: ["SalahCore"],
      // The provenance record of the fixture data is documentation, not a resource.
      exclude: ["FixtureData.md"],
      swiftSettings: defaultIsolation
    ),
    .testTarget(
      name: "SalahCoreTests",
      dependencies: ["SalahCore"],
      swiftSettings: defaultIsolation
    ),
    .testTarget(
      name: "SalahCalculationTests",
      dependencies: [
        "SalahCalculation", "SalahCore", .product(name: "SalahTimes", package: "SalahTimes"),
      ],
      swiftSettings: defaultIsolation
    ),
    .testTarget(
      name: "SalahFixturesTests",
      dependencies: ["SalahCore", "SalahFixtures"],
      swiftSettings: defaultIsolation
    ),
  ]
)
