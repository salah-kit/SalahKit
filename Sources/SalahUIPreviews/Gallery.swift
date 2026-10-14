#if canImport(SwiftUI)
  import SalahCore
  import SalahFixtures
  import SalahUI
  import SwiftUI

  /// Every SalahUI component at one SalahFixtures moment, with the default styles.
  ///
  /// It shows the moment's next prayer, both countdown modes when the next prayer is known, and
  /// the list of the moment's day. An unavailable state shows its gap reasons instead of a next
  /// prayer, and the day's list without statuses. The previews below and the snapshot tests
  /// render it.
  public struct MomentGallery: View {
    private let moment: PrayerFixtures.Moment
    private let locale: Locale

    /// Creates the gallery of a moment, with names and times in `locale`.
    public init(moment: PrayerFixtures.Moment, locale: Locale) {
      self.moment = moment
      self.locale = locale
    }

    public var body: some View {
      let zone = moment.place.location.timeZone
      let names = PrayerNames(locale: locale)
      let state = moment.state()
      VStack(alignment: .leading, spacing: 12) {
        Text(verbatim: "\(moment.id) · \(moment.place.id)")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
        switch state {
        case .available(let prayerState, _):
          NextPrayerView(state: prayerState, names: names, timeZone: zone)
          if let next = prayerState.nextPrayer {
            HStack(spacing: 16) {
              PrayerCountdown(to: next, at: prayerState.date)
              PrayerCountdown(to: next, at: prayerState.date, mode: .staticText)
            }
            .monospacedDigit()
          }
        case .unavailable(let coverage, _):
          GapSummary(coverage: coverage)
        }
        Divider()
        if let day = moment.schedule.day(containing: moment.date).day {
          PrayerTimesList(day: day, state: state.prayerState, names: names)
        } else {
          Text(verbatim: "∅ \(CivilDay(containing: moment.date, in: zone))")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
      .padding(16)
      .environment(\.locale, locale)
    }
  }

  /// A place's featured day with the default row style and no state, which shows the times,
  /// their day offsets and declared Jumu'ah.
  public struct PlaceGallery: View {
    private let place: PrayerFixtures.Place
    private let locale: Locale

    /// Creates the gallery of a place's featured day, with names and times in `locale`.
    public init(place: PrayerFixtures.Place, locale: Locale) {
      self.place = place
      self.locale = locale
    }

    public var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text(verbatim: "\(place.id) · \(place.featuredDay)")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
        if let day = place.schedule.day(place.featuredDay).day {
          PrayerTimesList(day: day, state: nil, names: PrayerNames(locale: locale))
        }
      }
      .padding(16)
      .environment(\.locale, locale)
    }
  }

  /// The reasons of an unavailable state's gaps, as their raw values; an app shows its own
  /// wording instead.
  private struct GapSummary: View {
    let coverage: ScheduleCoverage

    var body: some View {
      let reasons = Set(coverage.gaps.map(\.reason.rawValue)).sorted()
      Text(verbatim: "⚠︎ " + reasons.joined(separator: ", "))
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }
  }

  /// The locales the previews and snapshots use: English, left to right, and Arabic with its
  /// own digits, right to left.
  nonisolated public enum GalleryLocale {
    /// English, written left to right.
    public static let english = Locale(identifier: "en_US")
    /// Arabic with Arabic-Indic digits, written right to left.
    public static let arabic = PrayerLocale.resolved("ar")
  }

  #Preview("approaching") {
    MomentGallery(moment: PrayerFixtures.approaching, locale: GalleryLocale.english)
  }

  #Preview("justStarted") {
    MomentGallery(moment: PrayerFixtures.justStarted, locale: GalleryLocale.english)
  }

  #Preview("afterIsha") {
    MomentGallery(moment: PrayerFixtures.afterIsha, locale: GalleryLocale.english)
  }

  #Preview("beforeFajr") {
    MomentGallery(moment: PrayerFixtures.beforeFajr, locale: GalleryLocale.english)
  }

  #Preview("partialDay") {
    MomentGallery(moment: PrayerFixtures.partialDay, locale: GalleryLocale.english)
  }

  #Preview("missingDay") {
    MomentGallery(moment: PrayerFixtures.missingDay, locale: GalleryLocale.english)
  }

  #Preview("afterLastPublishedDay") {
    MomentGallery(moment: PrayerFixtures.afterLastPublishedDay, locale: GalleryLocale.english)
  }

  #Preview("Every moment, Arabic") {
    ScrollView {
      VStack(spacing: 0) {
        ForEach(PrayerFixtures.moments, id: \.id) { moment in
          MomentGallery(moment: moment, locale: GalleryLocale.arabic)
          Divider()
        }
      }
    }
    .environment(\.layoutDirection, .rightToLeft)
  }

  #Preview("After midnight and Jumu'ah") {
    VStack(spacing: 0) {
      PlaceGallery(place: PrayerFixtures.reykjavikJune, locale: GalleryLocale.english)
      PlaceGallery(place: PrayerFixtures.friday, locale: GalleryLocale.english)
    }
  }
#endif
