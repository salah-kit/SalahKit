import Foundation
import SalahCalculation
import SalahCore

/// The states the complication must draw, each from real inputs at a fixed instant, through
/// the same timeline code the extension runs. The watch app's states screen draws them, and
/// the tests check them.
nonisolated struct ComplicationSample: Identifiable, Sendable {
  /// A stable identifier for UI tests, such as `"ended"`.
  let id: String
  /// The inputs, or `nil` for a watch that has none.
  let inputs: WatchInputs?
  /// The entry the complication shows.
  let entry: ComplicationEntry

  /// The display of the entry.
  var display: ComplicationDisplay {
    ComplicationDisplay(entry.content, at: entry.date)
  }

  /// The samples, in the order the states screen shows them.
  static let all: [ComplicationSample] = [
    sample("setup", inputs: nil, at: "2026-10-14T14:00:00+03:00"),
    sample("next", inputs: makkah, at: "2026-10-14T14:00:00+03:00"),
    sample("partial", inputs: mosque, at: "2026-10-16T22:30:00+01:00"),
    sample("ended", inputs: mosque, at: "2026-10-17T10:00:00+01:00"),
    sample("unavailable", inputs: invalidPlace, at: "2026-10-14T14:00:00Z"),
    sample("expired", inputs: makkah, at: "2026-10-14T14:00:00+03:00", last: true),
  ]

  /// What the face gallery and widget previews show before any inputs: Makkah's next prayer
  /// from `now`, so its live countdown runs. The states screen keeps its fixed samples.
  static func placeholder(at now: Date) -> ComplicationEntry {
    ComplicationTimeline.entry(
      at: now, in: ComplicationTimeline.make(inputs: makkah, now: now).entries)
      ?? ComplicationEntry(date: now, content: .setupRequired, timeZone: .current)
  }

  /// Makkah, calculated.
  static let makkah = InputsPreset.makkah.inputs(today: Date())

  /// The sample mosque's timetable with rows for 14 to 16 October 2026.
  static let mosque = WatchInputs(
    location: InputsPreset.mosqueLocation,
    source: .timetable(
      InputsPreset.sampleTimetable(from: CivilDay(year: 2026, month: 10, day: 14), days: 3)))

  /// A latitude no calculation accepts.
  static let invalidPlace = WatchInputs(
    location: PrayerLocation(latitude: 95, longitude: 0, timeZone: .gmt, name: "Latitude 95°"),
    source: .calculated(settings: CalculationSettings(method: .muslimWorldLeague)))

  /// The sample whose entry is the one shown at `instant`, or the timeline's last entry.
  private static func sample(
    _ id: String, inputs: WatchInputs?, at instant: String, last: Bool = false
  ) -> ComplicationSample {
    let date = (try? Date(instant, strategy: .iso8601)) ?? Date(timeIntervalSince1970: 0)
    let entries = ComplicationTimeline.make(inputs: inputs, now: date).entries
    let entry =
      (last ? entries.last : ComplicationTimeline.entry(at: date, in: entries))
      ?? ComplicationEntry(date: date, content: .setupRequired, timeZone: .gmt)
    return ComplicationSample(id: id, inputs: inputs, entry: entry)
  }
}
