#if canImport(SwiftUI) && os(macOS)
  import Foundation
  import SalahCore
  import SalahFixtures
  import SwiftUI
  import Testing

  @testable import SalahUI

  @Suite("Missing row rendering")
  @MainActor
  struct MissingRowsRenderingTests {
    let names = PrayerNames(locale: Locale(identifier: "en"))
    let locale = Locale(identifier: "en_GB")

    func partialList() throws -> PrayerTimesList {
      let moment = PrayerFixtures.justStarted
      var day = try #require(moment.schedule.day(containing: moment.date).day)
      day.events = day.events.filter { $0.kind == .dhuhr || $0.kind == .asr }
      return PrayerTimesList(
        day: day, state: moment.state().prayerState, names: names, countdown: .staticText,
        missing: [
          .fajr: .calculationUnavailable, .sunrise: .noPublishedData,
          .maghrib: .invalidData, .isha: .unresolvedWallTime,
        ])
    }

    @Test("the transparent rows resolve the caller's style and pass no invented facts")
    func configurations() throws {
      let record = RowRecord()
      let list = try partialList()
      let content = VStack {
        list.rows
      }
      .prayerRowStyle(CapturingStyle(record: record))
      .environment(\.locale, locale)
      #expect(Snapshot.render(content, width: 300) != nil)
      #expect(record.rows.keys.sorted() == PrayerKind.allCases)
      for kind in [PrayerKind.fajr, .sunrise, .maghrib, .isha] {
        let configuration = try #require(record.rows[kind])
        #expect(configuration.event == nil)
        #expect(configuration.time == nil)
        #expect(configuration.status == nil)
        #expect(configuration.countdown == nil)
        #expect(configuration.dayOffset == 0)
        #expect(configuration.dayOffsetText == nil)
        #expect(configuration.gapReason != nil)
      }
      #expect(record.rows[.fajr]?.gapReason == .calculationUnavailable)
      #expect(record.rows[.sunrise]?.gapReason == .noPublishedData)
      #expect(record.rows[.maghrib]?.gapReason == .invalidData)
      #expect(record.rows[.isha]?.gapReason == .unresolvedWallTime)
      #expect(record.rows[.dhuhr]?.event?.kind == .dhuhr)
      #expect(record.rows[.dhuhr]?.time != nil)
      #expect(record.rows[.dhuhr]?.gapReason == nil)
      #expect(record.rows[.asr]?.status == .next(approaching: false))
      #expect(record.rows[.asr]?.countdown != nil)
    }

    @Test("missing kinds use a dash in the plain style")
    func plainMissing() throws {
      let day = PrayerDay(day: CivilDay(year: 2026, month: 10, day: 14), timeZone: .gmt, events: [])
      let list = PrayerTimesList(
        day: day, state: nil, names: names, missing: [.isha: .noPublishedData])
      let expected = PlainPrayerRowStyle().makeBody(
        configuration: PrayerRowConfiguration(
          kind: .isha, event: nil, gapReason: .noPublishedData, status: nil,
          name: Text(verbatim: "Isha"), time: Text(verbatim: "–"),
          dayOffset: 0, dayOffsetText: nil, countdown: nil))
      let actual = try #require(Snapshot.render(list, width: 300))
      let reference = try #require(Snapshot.render(expected, width: 300))
      #expect(Snapshot.compare(actual, reference) == nil)
    }

    @Test("a parent stack gives flexible rows equal height and expands its focus independently")
    func directChildGeometry() throws {
      let list = try partialList()
      let actual = VStack(spacing: 0) { list.rows }
        .prayerRowStyle(GeometryStyle())
        .frame(width: 40, height: 300)
      let expected = VStack(spacing: 0) {
        ForEach(PrayerKind.allCases, id: \.self) { kind in
          GeometryStyle.row(kind)
        }
      }
      .frame(width: 40, height: 300)
      let actualImage = try #require(Snapshot.render(actual, width: 40))
      let reference = try #require(Snapshot.render(expected, width: 40))
      #expect(actualImage.height == 600)
      #expect(Snapshot.compare(actualImage, reference) == nil)
      let pixels = try #require(Snapshot.rgba(actualImage))
      // Five flexible siblings are 40 points each; the Dhuhr focus retains 100 points.
      // These bounds catch a list stack around all rows, even if the total height stays 300.
      func color(at y: Int) -> ArraySlice<UInt8> {
        let start = (y * actualImage.width + 20) * 4
        return pixels[start..<(start + 3)]
      }
      #expect(color(at: 10) == color(at: 79))
      #expect(color(at: 79) != color(at: 80))
      #expect(color(at: 80) == color(at: 159))
      #expect(color(at: 159) != color(at: 160))
      #expect(color(at: 160) == color(at: 359))
      #expect(color(at: 359) != color(at: 360))
      #expect(color(at: 360) == color(at: 439))
      #expect(color(at: 440) == color(at: 519))
      #expect(color(at: 520) == color(at: 599))
    }
  }

  @MainActor
  private final class RowRecord {
    var rows: [PrayerKind: PrayerRowConfiguration] = [:]
  }

  private struct CapturingStyle: PrayerRowStyle {
    let record: RowRecord

    func makeBody(configuration: Configuration) -> some View {
      record.rows[configuration.kind] = configuration
      return configuration.name
    }
  }

  private struct GeometryStyle: PrayerRowStyle {
    func makeBody(configuration: Configuration) -> some View {
      Self.row(configuration.kind)
    }

    @ViewBuilder static func row(_ kind: PrayerKind) -> some View {
      let color: Color =
        switch kind {
        case .fajr: .red
        case .sunrise: .green
        case .dhuhr: .blue
        case .asr: .yellow
        case .maghrib: .cyan
        case .isha: .pink
        }
      if kind == .dhuhr {
        Rectangle().fill(color).frame(height: 100).layoutPriority(1)
      } else {
        Rectangle().fill(color).frame(minHeight: 10, maxHeight: .infinity)
      }
    }
  }
#endif
