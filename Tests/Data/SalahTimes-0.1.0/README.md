# SalahTimes 0.1.0 vectors

Copies of SalahTimes' language-neutral prayer-time vectors, for `Tests/SalahCalculationTests/GoldenTests.swift`. That test runs every vector through `CalculationSource` and checks that each time SalahTimes expects comes out unchanged, or that its kind is missing for a reason in RFC 0002, section 4.5 (`docs/rfcs/0002-calculation.md`).

- **Source:** [salah-kit/SalahTimes](https://github.com/salah-kit/SalahTimes), tag `0.1.0`, commit `42a291cab2034a1b1ee35166697748ef348a620c`.
- **Files:** `Vectors/times/*.json` (11 files, 1196 prayer-time vectors) as `times/`, and `Vectors/methods.json`, the method presets that vectors naming a `method` start from. Both are unchanged. SalahTimes' `Vectors/README.md` documents their format.
- **License:** MIT, Copyright (c) 2026 The Salah Kit Authors, the same as this repository.

The files live outside every target, so SwiftPM doesn't bundle them; the test reads them through its own file path.

## Refreshing

When SalahKit moves to a new SalahTimes release (RFC 0002, section 6):

1. Rename this folder to `SalahTimes-<version>` and replace `times/*.json` and `methods.json` with that tag's `Vectors/times/*.json` and `Vectors/methods.json`.
2. Update the tag, commit and counts above, and the folder name, file list and vector count in `GoldenTests.swift`.
3. Run `swift test --filter GoldenTests`. The `summary` test prints how many days were complete and why each missing kind is missing.
