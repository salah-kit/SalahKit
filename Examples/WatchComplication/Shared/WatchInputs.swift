import Foundation
import SalahCalculation
import SalahCore

/// Everything the watch needs to build its own schedule: the place and where its times come
/// from.
///
/// The companion sends it over WatchConnectivity, the watch app stores it in the watch's App
/// Group, and the complication extension reads it from there. The watch never asks the iPhone
/// for times: a calculated source keeps working for as long as the watch runs, and a published
/// timetable works until its last row.
nonisolated struct WatchInputs: Codable, Equatable, Sendable {
  /// Where the times come from.
  enum Source: Codable, Equatable, Sendable {
    /// Times calculated on the watch with SalahCalculation.
    case calculated(settings: CalculationSettings)
    /// Times published by a mosque, a few days of rows that run out.
    case timetable(TimetableSource)
  }

  /// The place, with the time zone its days and times are read in.
  var location: PrayerLocation
  /// Where the times come from.
  var source: Source

  /// The schedule the watch app and the complication build from these inputs.
  var schedule: PrayerSchedule {
    switch source {
    case .calculated(let settings):
      PrayerSchedule(source: CalculationSource(settings), location: location)
    case .timetable(let timetable):
      PrayerSchedule(source: timetable, location: location)
    }
  }

  /// The day of the timetable's last row, or `nil` for a calculated source.
  var lastPublishedDay: CivilDay? {
    if case .timetable(let timetable) = source { return timetable.lastDay }
    return nil
  }

  /// The inputs as JSON with sorted keys, the same bytes for equal inputs.
  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }

  /// A short, stable fingerprint of the inputs for logs and diagnostics: the 64-bit FNV-1a
  /// hash of ``encoded()`` in hexadecimal, or `"unencodable"`.
  var fingerprint: String {
    guard let data = try? encoded() else { return "unencodable" }
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in data {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    let hex = String(hash, radix: 16)
    return String(repeating: "0", count: 16 - hex.count) + hex
  }
}
