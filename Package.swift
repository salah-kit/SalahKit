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
    .library(name: "SalahAlerts", targets: ["SalahAlerts"]),
    .library(name: "SalahWidgets", targets: ["SalahWidgets"]),
    .library(name: "SalahUI", targets: ["SalahUI"]),
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
    .target(
      name: "SalahAlerts",
      dependencies: ["SalahCore"],
      swiftSettings: defaultIsolation
    ),
    .target(
      name: "SalahWidgets",
      dependencies: ["SalahCore"],
      // SharedValue reads and writes App Group defaults, so the product declares that reason
      // (1C8F.1) in its own privacy manifest (proposal section 7.3, Privacy).
      resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
      swiftSettings: defaultIsolation
    ),
    .target(
      name: "SalahUI",
      dependencies: ["SalahCore"],
      swiftSettings: defaultIsolation
    ),
    // Xcode previews of every SalahUI component at every SalahFixtures moment. It isn't a
    // product, so apps that link SalahUI never link the fixtures; the snapshot tests render the
    // same gallery.
    .target(
      name: "SalahUIPreviews",
      dependencies: ["SalahCore", "SalahFixtures", "SalahUI"],
      swiftSettings: defaultIsolation
    ),
    // A separate process for DarwinSignal's cross-process tests: it posts, or waits for, a
    // signal by name.
    .executableTarget(
      name: "DarwinSignalHelper",
      dependencies: ["SalahWidgets"],
      path: "Tests/DarwinSignalHelper",
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
    .testTarget(
      name: "SalahAlertsTests",
      // SalahCalculation runs the alert vectors that use a calculated source (Kazan).
      dependencies: ["SalahAlerts", "SalahCalculation", "SalahCore"],
      swiftSettings: defaultIsolation
    ),
    .testTarget(
      name: "SalahWidgetsTests",
      dependencies: [
        "DarwinSignalHelper", "SalahCalculation", "SalahCore", "SalahFixtures", "SalahWidgets",
        .product(name: "SalahTimes", package: "SalahTimes"),
      ],
      swiftSettings: defaultIsolation
    ),
    .testTarget(
      name: "SalahUITests",
      dependencies: ["SalahCore", "SalahFixtures", "SalahUI", "SalahUIPreviews"],
      // The reference images are read from the source tree, not from a resource bundle.
      exclude: ["Snapshots"],
      swiftSettings: defaultIsolation
    ),
  ]
)
