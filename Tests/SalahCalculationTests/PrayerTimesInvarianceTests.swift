import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

/// Migrated from Salah's `PrayerTimesInvarianceTests` (Salah at 4bc00e9,
/// `GuidanceTests/PrayerTimesInvarianceTests.swift`), which guarded the app's calculation
/// against error handling that changes its output: valid coordinates, including the equator,
/// must always produce times, and the same input must always produce the same times.
///
/// Salah called adhan-swift, whose initializer returns `nil` on failure. Here the same promises
/// are checked through `CalculationSource`, where a failure would be an unavailable day.
@Suite struct PrayerTimesInvarianceTests {
  @Test func validCoordinatesProduceTimes() {
    let settings = CalculationSettings(method: .ummAlQura, madhab: .shafi)
    let availability = CalculationSource(settings)
      .prayerDay(Places.day("2026-05-30"), at: Places.makkah)
    #expect(availability.coverage == .complete, "Valid coordinates must produce prayer times")
  }

  /// The equator must not trip a failure: an over-eager check could reject valid latitudes.
  @Test func equatorProducesTimesOnSolstice() {
    let availability = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
      .prayerDay(Places.day("2026-06-21"), at: Places.equator)
    #expect(availability.coverage == .complete, "The equator should still produce prayer times")
  }

  @Test func calculationIsDeterministic() {
    let source = CalculationSource(CalculationSettings(method: .egyptian))
    let day = Places.day("2026-05-30")
    let first = source.prayerDay(day, at: Places.cairo).day
    let second = source.prayerDay(day, at: Places.cairo).day
    #expect(first != nil)
    #expect(first?[.fajr] == second?[.fajr])
    #expect(first?[.maghrib] == second?[.maghrib])
    #expect(first == second)
  }
}
