import Foundation
import SalahCore

/// One of the two timetables MosqueBoard can show, with the schedule built from it.
nonisolated struct Board: Sendable {
  /// The boards the app bundles, selected with `-board muis|edinburgh`.
  enum ID: String, CaseIterable, Sendable {
    /// MUIS's Muslim Prayer Timetable 2026 for Singapore (real, published data).
    case muis
    /// A synthetic timetable for a fictional mosque in Edinburgh.
    case edinburgh
  }

  enum LoadError: Error {
    case missingTimetable(String)
  }

  let id: ID
  let schedule: PrayerSchedule

  var location: PrayerLocation { schedule.location }

  /// The timetable file in the app bundle (`Timetables/<name>.json`).
  static func timetableName(for id: ID) -> String {
    switch id {
    case .muis: "muis-2026"
    case .edinburgh: "edinburgh-synthetic"
    }
  }

  /// Decodes a bundled timetable as published.
  static func timetable(_ id: ID, in bundle: Bundle = .main) throws -> TimetableSource {
    let name = timetableName(for: id)
    guard let url = bundle.url(forResource: name, withExtension: "json") else {
      throw LoadError.missingTimetable(name)
    }
    return try JSONDecoder().decode(TimetableSource.self, from: Data(contentsOf: url))
  }

  /// Loads a board: its timetable, its location and the mosque's own iqama settings.
  static func load(_ id: ID, from bundle: Bundle = .main) throws -> Board {
    let timetable = try timetable(id, in: bundle)
    switch id {
    case .muis:
      // App policy, not MUIS data: MUIS publishes neither iqama nor Jumu'ah, so MosqueBoard
      // declares Jumu'ah on Fridays and adds its own congregation rules, as a mosque would.
      let location = PrayerLocation(
        latitude: 1.3521, longitude: 103.8198, timeZone: zone("Asia/Singapore"),
        countryCode: "SG", name: "Singapore")
      let source = DeclaredJumuahSource(timetable: timetable)
      return Board(
        id: id, schedule: PrayerSchedule(source: source, location: location, iqama: muisIqama))
    case .edinburgh:
      // The synthetic timetable publishes its own iqama and declares Jumu'ah itself.
      let location = PrayerLocation(
        latitude: 55.9533, longitude: -3.1883, timeZone: zone("Europe/London"),
        countryCode: "GB", name: "Edinburgh")
      return Board(id: id, schedule: PrayerSchedule(source: timetable, location: location))
    }
  }

  /// MosqueBoard's own congregation settings for the MUIS board (app policy).
  ///
  /// Jumu'ah is 30 minutes after Dhuhr begins, leaving time for the khutbah.
  static let muisIqama = IqamaRules(
    rules: [
      .fajr: .after(minutes: 20),
      .dhuhr: .after(minutes: 10),
      .asr: .after(minutes: 10),
      .maghrib: .after(minutes: 5),
      .isha: .after(minutes: 10),
    ],
    jumuah: .after(minutes: 30))

  private static func zone(_ identifier: String) -> TimeZone {
    // Both identifiers are in every tz database; GMT only guards against a broken system.
    TimeZone(identifier: identifier) ?? .gmt
  }
}

/// App policy for the MUIS board: declares every Friday's Dhuhr as Jumu'ah.
///
/// MUIS's timetable publishes no Jumu'ah, and SalahCore never infers it from the weekday. This
/// mosque holds Jumu'ah every Friday, so the app declares it here, on top of the published times.
/// The published times themselves pass through unchanged.
nonisolated struct DeclaredJumuahSource: PrayerSource {
  let timetable: TimetableSource

  var expectedKinds: Set<PrayerKind> { timetable.expectedKinds }

  func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
    let availability = timetable.prayerDay(day, at: location)
    guard day.weekday == 6, case .available(var prayerDay, let coverage) = availability else {
      return availability
    }
    prayerDay.events = prayerDay.events.map { event in
      var event = event
      if event.kind == .dhuhr {
        event.observance = .jumuah
      }
      return event
    }
    return .available(prayerDay, coverage: coverage)
  }
}
