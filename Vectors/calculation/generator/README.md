# Calculation vector generator

These scripts wrote `Vectors/calculation/*.json`. They are an independent model of RFC 0002 §4
and RFC 0001 §4.3–§4.8, written from the two RFCs without reading SalahCalculation's
implementation; the instants come from SalahTimes' Python reference implementation, not from the
Swift engine.

- `model.py`: the model. `CalculationSource` follows RFC 0002 §4.2–§4.3 on SalahTimes'
  reference results; `Schedule` follows RFC 0001 §4.6–§4.8 (context, missing-event windows with
  the 12-hour lead, coverage, state, `changesAt`, refresh plans).
- `cases.py`: the vectors, one `add(...)` call each.
- `generate.py`: runs the cases and writes the files. It refuses a case whose expectation could
  change if a rounded instant within a second of a rounding boundary rounded the other way, since
  the reference and the Swift engine agree within about half a second before rounding.

Regenerate with a SalahTimes 0.1.0 checkout (Python 3.10 or later, standard library only):

```sh
git clone --branch 0.1.0 https://github.com/salah-kit/SalahTimes.git /path/to/SalahTimes
SALAHTIMES_VECTORS=/path/to/SalahTimes/Vectors python3 generate.py ../
```

The output must match the committed files byte for byte; `swift test` then runs them through
`CalculationSource` (`Tests/SalahCalculationTests/CalculationVectorTests.swift`). A change to an
existing vector needs a written reason in RFC 0002 §10.
