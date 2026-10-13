// swift-tools-version: 6.2

import PackageDescription

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
    .library(name: "SalahFixtures", targets: ["SalahFixtures"]),
  ],
  targets: [
    .target(
      name: "SalahCore",
      // Copied, not processed: SalahCore reads the catalog as JSON on every platform
      // (docs/rfcs/0001-core.md, section 6.1).
      resources: [.copy("Resources/Localizable.xcstrings")]
    ),
    .target(
      name: "SalahFixtures",
      dependencies: ["SalahCore"],
      // The provenance record of the fixture data is documentation, not a resource.
      exclude: ["FixtureData.md"]
    ),
    .testTarget(
      name: "SalahCoreTests",
      dependencies: ["SalahCore"]
    ),
    .testTarget(
      name: "SalahFixturesTests",
      dependencies: ["SalahCore", "SalahFixtures"]
    ),
  ]
)
