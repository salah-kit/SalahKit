# Contributing to SalahKit

Thanks for helping. This page covers building, testing and formatting this repository. The
organization's code of conduct, security policy, support page and issue and pull-request
templates live once, in [salah-kit/.github](https://github.com/salah-kit/.github), and apply here.

## Requirements

- Swift 6.2 or later (`swift-tools-version: 6.2`). CI uses the newest Xcode 26 on macOS, and the
  `swift:6.2-noble` and `swift:latest` images on Linux.
- Xcode 26 or later for the Apple-platform builds and the documentation.

## Build and test

```sh
swift build
swift test
```

Both run on macOS and on Linux. Code that needs an Apple-only framework sits behind
`#if canImport(…)`; pure logic stays outside those guards.

### Apple platforms

The package supports iOS 16, macOS 13, watchOS 9, tvOS 16 and visionOS 1. CI builds every
simulator platform with the package's `SalahKit-Package` scheme:

```sh
scripts/build-apple-platform.sh "iOS Simulator"
scripts/build-apple-platform.sh "watchOS Simulator"
scripts/build-apple-platform.sh "tvOS Simulator"
scripts/build-apple-platform.sh "visionOS Simulator"
```

These are generic-destination builds; they don't boot a simulator.

### Linux

CI builds and tests on Linux with `swift:6.2-noble`, the oldest toolchain the manifest allows, and
with `swift:latest`. You don't need Linux locally: open a pull request and the `linux` jobs run.

### Default isolation

Adopters' targets may default to `MainActor` isolation, so the package must build both ways:

```sh
swift build --build-tests
swift build --build-tests -Xswiftc -default-isolation -Xswiftc MainActor
```

Public types are `nonisolated` and `Sendable`, so they behave the same under either setting.

## Format

The repository uses `swift format` with the shared `.swift-format` configuration (identical in
every salah-kit repository). CI fails on any finding:

```sh
scripts/lint.sh                                                            # what CI runs
swift format --in-place --recursive Sources Tests Package.swift Examples    # fix findings
```

## Examples

`Examples/MosqueBoard` is an iPad app generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`; both the spec and the generated project are committed. After changing the spec
or adding a file, run `xcodegen` in `Examples/MosqueBoard` from a clone whose folder is named
`SalahKit` (the project records that folder's name), and commit both. CI regenerates the project
and fails if anything differs, then builds the app under both default-isolation settings and runs
its unit tests and journeys on an iPad simulator.

## Vectors

The JSON vectors in `Vectors/` pin the package's behavior across platforms and implementations.
`Vectors/README.md` documents their schema. A change to an existing vector needs a written reason
in [RFC 0001, section 10](docs/rfcs/0001-core.md#10-changes-after-the-vector-review), in the same
pull request.

## Documentation

Every public symbol has a DocC comment, and every module has a DocC catalog under
`Sources/<Module>/<Module>.docc`. The site at https://salah-kit.github.io/SalahKit/ is published
from `main`. Build it locally with Xcode:

```sh
scripts/build-docs.sh            # writes the site to .build/docs-site
```

The script runs `xcodebuild docbuild`, merges the module archives with `xcrun docc merge` and
transforms the result for static hosting. It fails on any DocC warning, such as an unresolved
symbol link; pull requests run the same build. To preview the site, serve the output directory
under the `/SalahKit` path, for example:

```sh
mkdir -p /tmp/salahkit-docs && ln -sfn "$PWD/.build/docs-site" /tmp/salahkit-docs/SalahKit
python3 -m http.server --directory /tmp/salahkit-docs 8000
# open http://localhost:8000/SalahKit/documentation/
```

## Proposing changes

- Small fixes: open a pull request. CI must pass.
- Public API and behavior: write or amend an RFC in [`docs/rfcs/`](docs/rfcs/) first. RFC 0001
  covers SalahCore and SalahFixtures. Public API stays small and needs a consumer that justifies
  it.
- Record user-visible changes in `CHANGELOG.md` under Unreleased.
