import Foundation
import SalahCore
import SalahFixtures
import Testing

/// FixtureData.md is the provenance record of the fixtures, and these tests keep the fixtures
/// equal to its tables: every begin time, every published iqama and every moment.
@Suite struct FixtureDataTests {
  @Test func theRecordHasATableForEveryPlace() throws {
    let record = try FixtureRecord.load()
    #expect(Set(record.places.keys) == Set(PrayerFixtures.places.map(\.id)))
    #expect(record.moments.count == PrayerFixtures.moments.count)
  }

  @Test(arguments: PrayerFixtures.places.map(\.id))
  func beginTimesMatchTheRecord(_ placeID: String) throws {
    let place = try fixturePlace(placeID)
    let zone = place.location.timeZone
    let tables = try #require(try FixtureRecord.load().places[placeID])

    // The record lists the featured day and the two days on either side.
    let days = (-2...2).map { place.featuredDay.adding(days: $0) }
    #expect(tables.begin.map(\.day) == days)

    for row in tables.begin {
      let availability = place.schedule.day(row.day)
      guard !row.isMissing else {
        #expect(availability == .unavailable(.noPublishedData), "\(placeID) \(row.day)")
        continue
      }
      let events = availability.day?.events ?? []
      let shown = Dictionary(
        uniqueKeysWithValues: events.map {
          ($0.kind, wallText($0.time, owner: row.day, in: zone))
        })
      #expect(shown == row.times, "\(placeID) \(row.day)")
    }
  }

  @Test(arguments: PrayerFixtures.places.map(\.id))
  func iqamaMatchesTheRecord(_ placeID: String) throws {
    let place = try fixturePlace(placeID)
    let zone = place.location.timeZone
    let tables = try #require(try FixtureRecord.load().places[placeID])
    let documented = Dictionary(uniqueKeysWithValues: tables.iqama.map { ($0.day, $0.times) })

    for row in place.source.rows {
      let events = try #require(place.schedule.day(row.day).day).events
      let shown = Dictionary(
        uniqueKeysWithValues: events.compactMap { event in
          event.iqama.map { (event.kind, wallText($0, owner: row.day, in: zone)) }
        })
      // A place without an iqama table publishes none.
      #expect(shown == (documented[row.day] ?? [:]), "\(placeID) \(row.day)")
    }
    // The record lists the iqama of every published day, or none at all.
    #expect(documented.isEmpty || Set(documented.keys) == Set(place.source.rows.map(\.day)))
  }

  @Test(arguments: MomentCheck.all)
  func momentsMatchTheRecord(_ check: MomentCheck) throws {
    let moment = try fixtureMoment(check.id)
    let documented = try #require(try FixtureRecord.load().moments[check.id])
    #expect(documented.place == check.place)
    #expect(documented.place == moment.place.id)
    #expect(moment.date == (try instant(documented.local)))
    #expect(moment.date == (try instant(documented.utc)))
  }
}

/// The tables of FixtureData.md: for each place its begin times and iqama by day, and the
/// moments.
nonisolated struct FixtureRecord: Sendable {
  /// One row of a table: the day and its times by kind, without the `-` cells.
  nonisolated struct Row: Sendable {
    let day: CivilDay
    let times: [PrayerKind: String]
    /// The row of a day without data: all cells are `-` and the notes say there is no row.
    let isMissing: Bool
  }

  nonisolated struct Tables: Sendable {
    var begin: [Row] = []
    var iqama: [Row] = []
  }

  nonisolated struct MomentRow: Sendable {
    let place: String
    let local: String
    let utc: String
  }

  var places: [String: Tables] = [:]
  var moments: [String: MomentRow] = [:]

  /// The record next to the sources, found from this file's location.
  static func load() throws -> FixtureRecord {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources/SalahFixtures/FixtureData.md")
    return parse(try String(contentsOf: url, encoding: .utf8))
  }

  /// Reads the begin-time tables (`| Day | Weekday | Fajr ...`), the iqama tables
  /// (`| Day | Fajr | Dhuhr ...`) and the moments table (`| Moment | Place ...`).
  static func parse(_ text: String) -> FixtureRecord {
    enum Table { case begin, iqama, moments }
    var record = FixtureRecord()
    var place: String?
    var table: Table?
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix("### `") {
        place = String(line.dropFirst(5).prefix { $0 != "`" })
        table = nil
      } else if line.hasPrefix("| Day | Weekday |") {
        table = .begin
      } else if line.hasPrefix("| Day | Fajr |") {
        table = .iqama
      } else if line.hasPrefix("| Moment | Place |") {
        table = .moments
      } else if line.hasPrefix("| ---") {
        continue
      } else if line.hasPrefix("|"), let table {
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
          .dropFirst().dropLast()
          .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") }
        switch table {
        case .begin:
          guard let place, cells.count >= 8, let day = CivilDay(cells[0]) else { continue }
          let row = Row(
            day: day, times: times(cells[2..<8], kinds: PrayerKind.allCases),
            isMissing: cells.count > 8 && cells[8] == "no row for this day")
          record.places[place, default: Tables()].begin.append(row)
        case .iqama:
          guard let place, cells.count >= 6, let day = CivilDay(cells[0]) else { continue }
          let kinds: [PrayerKind] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
          let row = Row(day: day, times: times(cells[1..<6], kinds: kinds), isMissing: false)
          record.places[place, default: Tables()].iqama.append(row)
        case .moments:
          guard cells.count >= 4 else { continue }
          let id = cells[0].replacingOccurrences(of: "`", with: "")
          record.moments[id] = MomentRow(
            place: cells[1].replacingOccurrences(of: "`", with: ""),
            local: cells[2].replacingOccurrences(of: "`", with: ""),
            utc: cells[3].replacingOccurrences(of: "`", with: ""))
        }
      } else {
        table = nil
      }
    }
    return record
  }

  private static func times(
    _ cells: ArraySlice<String>, kinds: [PrayerKind]
  ) -> [PrayerKind: String] {
    var times: [PrayerKind: String] = [:]
    for (kind, cell) in zip(kinds, cells) where cell != "-" {
      times[kind] = cell
    }
    return times
  }
}
