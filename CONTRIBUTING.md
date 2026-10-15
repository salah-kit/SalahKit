# Contributing to SalahKit

Thanks for helping. This page covers building, testing, formatting and releasing this
repository. The organization's code of conduct, security policy, support page and issue and
pull-request templates live once, in [salah-kit/.github](https://github.com/salah-kit/.github),
and apply here.

## Requirements

- Swift 6.2 or later (`swift-tools-version: 6.2`). CI uses the newest Xcode 26 on macOS, and the
  `swift:6.2-noble` and `swift:latest` images on Linux.
- Xcode 26 or later for the Apple-platform builds and the documentation.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), only to regenerate an example's project.
- Python 3.10 or later, only to regenerate the vectors (standard library only).

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
SALAHKIT_DEFAULT_ISOLATION=MainActor swift build --build-tests --build-path .build/mainactor
```

The variable makes the manifest apply `MainActor` default isolation to SalahKit's own targets,
tests included; SalahTimes builds as it does in an app. Don't pass `-Xswiftc -default-isolation`
instead: it reaches SalahTimes too and makes its types main-actor-isolated (RFC 0001, section
6.3). A separate build path keeps the two configurations from sharing a cache. Public types are
`nonisolated` and `Sendable`, so they behave the same under either setting.

## Format

The repository uses `swift format` with the shared `.swift-format` configuration (identical in
every salah-kit repository). CI fails on any finding:

```sh
scripts/lint.sh                                                            # what CI runs
swift format --in-place --recursive Sources Tests Package.swift Examples    # fix findings
```

## Examples

Every example in `Examples/` is an Xcode project that
[XcodeGen](https://github.com/yonaskolb/XcodeGen) generates from its `project.yml`; both the spec
and the generated project are committed. After changing a spec or adding, moving or removing a file,
run `xcodegen` in the example's folder from a clone whose folder is named `SalahKit` (the project
records that folder's name, and XcodeGen resolves symbolic links), and commit both. CI regenerates
each project and fails if anything differs, builds it under both default-isolation settings and runs
its tests on a simulator or on the runner's Mac (build-only, with a warning, where a runner lacks
the destination). Each example's README lists its tests and how to run them.

| Example | Platform | Needs a signing team to run locally |
|---|---|---|
| `CalculatedPhone` | iOS simulator | No |
| `MosqueBoard` | iPadOS and tvOS simulators | No |
| `PhoneWidgets` | iOS simulator | No |
| `WatchComplication` | iOS and watchOS simulators | No |
| `MenuBar` | macOS | For the sandboxed App Group its app, widget extension and stop harness share; its tests also run unsigned |

Simulator builds need no signing. To sign an example, copy its `Config/Local.xcconfig.example` to
`Config/Local.xcconfig` (gitignored) and set your team there; never commit a team.

## Vectors

The JSON vectors in `Vectors/` pin the package's behavior across platforms and implementations.
`Vectors/README.md` documents their schema. `swift test` runs every file.

- `Vectors/state/` and `Vectors/refresh/` are written by hand.
- `Vectors/alerts/` and `Vectors/reconciliation/` are generated: change
  `Vectors/alerts/generator/`, then run `python3 Vectors/alerts/generator/generate.py`.
- `Vectors/calculation/` is generated from SalahTimes' reference results:
  `Vectors/calculation/generator/README.md` says how, with a SalahTimes checkout.

The generators rewrite their files byte for byte, so commit the generator and its output together. A
change to an existing vector needs a written reason in the Changes section of the RFC it belongs to,
in the same pull request: [RFC 0001](docs/rfcs/0001-core.md#10-changes-after-the-vector-review) for
`state/` and `refresh/`, [RFC 0002](docs/rfcs/0002-calculation.md#10-changes-after-review) for
`calculation/`, and [RFC 0003](docs/rfcs/0003-alerts.md#10-changes-after-review) for `alerts/` and
`reconciliation/`. Adding a vector needs no entry, but never reuse or rename an id.

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
- User-visible changes: record them in `CHANGELOG.md` under Unreleased.
- Public API and behavior: write or amend an RFC first (below). Public API stays small and needs
  a consumer that justifies it: an example, Salah, or an app outside this organization.

### RFCs

Public API changes to a package go through a short RFC (STANDARD.md, Governance). The RFCs live
in [`docs/rfcs/`](docs/rfcs/) and are discussed in
[GitHub Discussions](https://github.com/salah-kit/SalahKit/discussions), in the Ideas category:

| RFC | Products | Discussion |
|---|---|---|
| [0001](docs/rfcs/0001-core.md) | SalahCore, SalahFixtures | [#6](https://github.com/salah-kit/SalahKit/discussions/6) |
| [0002](docs/rfcs/0002-calculation.md) | SalahCalculation | [#7](https://github.com/salah-kit/SalahKit/discussions/7) |
| [0003](docs/rfcs/0003-alerts.md) | SalahAlerts | [#8](https://github.com/salah-kit/SalahKit/discussions/8) |
| [0004](docs/rfcs/0004-widgets-and-ui.md) | SalahWidgets, SalahUI | [#9](https://github.com/salah-kit/SalahKit/discussions/9) |

To change the API:

1. **Start a discussion** in the Ideas category, titled `RFC: <what changes>`: the consumer that
   needs the change, what it can't do today, and the API you propose. A small amendment to an
   existing RFC can go in that RFC's discussion instead.
2. **Write the RFC** in a pull request: a new `docs/rfcs/NNNN-title.md` with the next free
   number, or an amendment to an existing RFC in its "Changes" section. Start from the existing
   RFCs' shape: status, products, summary, scope, the API and its behavior, open questions and
   consumer findings. Link the discussion.
3. **One week for comments.** The pull request stays open for at least seven days after the
   discussion starts, so people outside the project can answer. Changes to `Vectors/` need a
   written reason in the RFC.
4. **Implement** in the same or a later pull request: the code, its tests and vectors, its DocC
   documentation, and a working consumer. Every public symbol has a DocC comment.
5. **Update the RFC's status line** when the change ships, with the version.

Before 1.0, a minor release may change the API; every change is listed in the CHANGELOG. The
RFCs stay open to findings from real adopters until 1.0 (STANDARD.md, Releases).

## Checks that need a device or a native speaker

Some behavior can only be checked on real hardware, over days, or by a native speaker: alerts on
an iPhone with the app closed, widgets left alone for a week, a real Apple Watch, Apple TV or
Mac sleep, VoiceOver, and the translations. Each such check is an issue labelled
[`help wanted`][help-wanted], with the steps, what to record and how to report it.
[`good first issue`][good-first-issue] marks the small ones, and [`translation`][translation] the
language reviews. Results go in a comment on the issue.

[help-wanted]: https://github.com/salah-kit/SalahKit/labels/help%20wanted
[good-first-issue]: https://github.com/salah-kit/SalahKit/labels/good%20first%20issue
[translation]: https://github.com/salah-kit/SalahKit/labels/translation

## Releasing

A maintainer releases from `main`. Versions follow Semantic Versioning, and tags have no `v`
(`0.4.0`). The package stays below 1.0 until the conditions in
[STANDARD.md](https://github.com/salah-kit/.github/blob/main/STANDARD.md#releases) hold.

1. **Prepare the release** in a pull request: move the CHANGELOG's Unreleased entries into a new
   `## [X.Y.Z] - YYYY-MM-DD` section and update the links at its end (`[Unreleased]` compares
   `X.Y.Z...HEAD`, and a new `[X.Y.Z]` compares the previous tag with `X.Y.Z`), update the
   version in the README's installation snippet, and update the status line of every RFC whose
   change ships.
2. **Merge it, and wait for CI and Docs to pass** on the commit you'll tag.
3. **Tag that commit** and push the tag:
   ```sh
   git tag -a X.Y.Z -m "SalahKit X.Y.Z"
   git push origin X.Y.Z
   ```
   Apps pin tags, so never move or delete one; a mistake is fixed with a new release.
4. **Publish a GitHub release** for the tag, with three headings:
   - **Proven:** the gates and their evidence, such as the CI runs on the tagged commit and what
     ran on which simulator or device;
   - **Pending:** what still needs a person, a device or elapsed time, each item linked to the
     `help wanted` issue that tracks it (open one if none exists);
   - **Known limitations.**

   A check that didn't run is never listed as proven.
5. **Check the documentation site** at https://salah-kit.github.io/SalahKit/ once the Docs
   workflow has deployed `main`.
