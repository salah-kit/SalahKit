import SalahCore
import SwiftUI

/// Redraws every second for the countdown, which also covers every state change
/// (`ScheduleState.changesAt`) within a second. A frozen clock draws once.
struct BoardTimelineSchedule: TimelineSchedule {
  let frozen: Bool

  func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
    var next: Date? = startDate
    let frozen = frozen
    return AnyIterator {
      defer { next = frozen ? nil : next?.addingTimeInterval(1) }
      return next
    }
  }
}

/// The board's sizes and colors: an iPad's, or a TV's, which people read from across a room.
///
/// tvOS's text styles are already sized for the distance, so the TV uses smaller styles than
/// the iPad to fit the whole board on one screen: a TV board can't scroll, because nothing on
/// it takes focus. tvOS has no Dynamic Type setting and no system background colors.
nonisolated enum BoardStyle {
  #if os(tvOS)
    static let spacing: CGFloat = 20
    static let padding: CGFloat = 0
    static let background = Color.clear
    static let panel = Color.primary.opacity(0.1)
    static let title = Font.title.bold()
    static let clock = Font.title.monospacedDigit()
    static let subtitle = Font.callout
    static let date = Font.headline
    static let columnHeading = Font.callout
    static let row = Font.title3
    static let missing = Font.callout
    static let status = Font.headline
    static let message = Font.headline
    static let nextName = Font.title.bold()
    static let nextTime = Font.title3
    static let countdown = Font.system(size: 120, weight: .bold).monospacedDigit()
    /// The TV board is fitted to the screen, where a countdown that may shrink is the first
    /// text SwiftUI shrinks. The panel is wide enough for any countdown at full size.
    static let countdownMinimumScale: CGFloat = 1
    /// The next-prayer panel's spacing. The TV's tallest panel, every night from Isha to its
    /// iqama ("Isha has started", the next Fajr, its countdown and the timetable it comes
    /// from), must leave room for the footer inside the safe area.
    static let panelSpacing: CGFloat = 6
    static let gap = Font.callout
    static let timeWidth: CGFloat = 170
    static let statusWidth: CGFloat = 280
    static let rowPadding: CGFloat = 4
  #else
    static let spacing: CGFloat = 24
    static let padding: CGFloat = 24
    static let background = Color(.systemBackground)
    static let panel = Color(.secondarySystemBackground)
    static let title = Font.largeTitle.bold()
    static let clock = Font.largeTitle.monospacedDigit()
    static let subtitle = Font.title3
    static let date = Font.title2
    static let columnHeading = Font.headline
    static let row = Font.title
    static let missing = Font.title3
    static let status = Font.title3
    static let message = Font.title2
    static let nextName = Font.system(.largeTitle, weight: .bold)
    static let nextTime = Font.title2
    static let countdown = Font.system(size: 64, weight: .bold).monospacedDigit()
    static let countdownMinimumScale: CGFloat = 0.5
    static let panelSpacing: CGFloat = 12
    static let gap = Font.body
    static let timeWidth: CGFloat = 96
    static let statusWidth: CGFloat = 150
    static let rowPadding: CGFloat = 8
  #endif
}

/// The whole board: header, the day's prayers, the next prayer or the coverage banner.
struct BoardView: View {
  let board: Board
  let clock: BoardClock
  let strings: BoardStrings

  var body: some View {
    TimelineView(BoardTimelineSchedule(frozen: clock.frozen)) { context in
      BoardContent(
        snapshot: BoardSnapshot.make(
          board: board, at: clock.now(at: context.date), strings: strings),
        strings: strings)
    }
  }
}

struct BoardContent: View {
  let snapshot: BoardSnapshot
  let strings: BoardStrings
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: BoardStyle.spacing) {
          HeaderView(snapshot: snapshot)
          // At the accessibility text sizes the panel goes above the table, as in portrait:
          // beside it, neither would have room for its words.
          if geometry.size.width > geometry.size.height && !dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: BoardStyle.spacing) {
              PrayerTable(snapshot: snapshot, strings: strings)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)
              // VoiceOver reads the panel first, as in portrait, then the table row by row,
              // rather than mixing the two by height.
              StatusPanel(snapshot: snapshot, strings: strings)
                .frame(maxWidth: geometry.size.width * 0.38)
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(1)
            }
            .accessibilityElement(children: .contain)
          } else {
            StatusPanel(snapshot: snapshot, strings: strings)
            PrayerTable(snapshot: snapshot, strings: strings)
          }
          FooterView(snapshot: snapshot)
        }
        .padding(BoardStyle.padding)
        .frame(minHeight: geometry.size.height, alignment: .top)
      }
    }
    .background(BoardStyle.background)
    .foregroundStyle(Color.primary)
  }
}

private struct HeaderView: View {
  let snapshot: BoardSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // The clock goes below the title when both don't fit on one line. On one line each keeps
      // its full width (`fixedSize`), rather than the HStack sharing the width out.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          title.fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: 16)
          clock.fixedSize(horizontal: true, vertical: false)
        }
        VStack(alignment: .leading, spacing: 6) {
          title
          clock
        }
      }
      Text(verbatim: snapshot.subtitle)
        .font(BoardStyle.subtitle)
        .foregroundStyle(Color.secondary)
        .accessibilityIdentifier("header.subtitle")
      Text(verbatim: snapshot.gregorianDate)
        .font(BoardStyle.date)
        .accessibilityIdentifier("header.gregorian")
      Text(verbatim: snapshot.hijriDate)
        .font(BoardStyle.date)
        .accessibilityIdentifier("header.hijri")
    }
  }

  private var title: some View {
    Text(verbatim: snapshot.title)
      .font(BoardStyle.title)
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("header.title")
  }

  private var clock: some View {
    Text(verbatim: snapshot.clock)
      .font(BoardStyle.clock)
      .accessibilityIdentifier("header.clock")
  }
}

/// The day's prayers: a table with a column each for the name, the times and the status, or at
/// the accessibility text sizes a row each, with its parts stacked.
private struct PrayerTable: View {
  let snapshot: BoardSnapshot
  let strings: BoardStrings
  @ScaledMetric(relativeTo: .title) private var timeWidth = BoardStyle.timeWidth
  @ScaledMetric(relativeTo: .title) private var statusWidth = BoardStyle.statusWidth
  // The time and status columns grow with the text and would leave the names no room at these
  // sizes, so the rows stack instead.
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let unavailable = snapshot.dayUnavailable {
        Text(verbatim: unavailable)
          .font(BoardStyle.message)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(BoardStyle.panel, in: .rect(cornerRadius: 12))
          .accessibilityIdentifier("day.unavailable")
      } else if dynamicTypeSize.isAccessibilitySize {
        ForEach(snapshot.rows) { row in
          StackedPrayerRowView(row: row, strings: strings)
        }
      } else {
        HStack {
          Text(verbatim: strings("Prayer")).frame(maxWidth: .infinity, alignment: .leading)
          Text(verbatim: strings("Begins")).frame(width: timeWidth, alignment: .leading)
          Text(verbatim: strings("Iqama")).frame(width: timeWidth, alignment: .leading)
          Text(verbatim: strings("Status")).frame(width: statusWidth, alignment: .leading)
        }
        .font(BoardStyle.columnHeading)
        .foregroundStyle(Color.secondary)
        .accessibilityHidden(true)
        ForEach(snapshot.rows) { row in
          PrayerRowView(
            row: row, strings: strings, timeWidth: timeWidth, statusWidth: statusWidth)
        }
      }
    }
  }
}

private struct PrayerRowView: View {
  let row: BoardSnapshot.Row
  let strings: BoardStrings
  let timeWidth: CGFloat
  let statusWidth: CGFloat

  private var isNext: Bool {
    if case .next = row.status { return true }
    return false
  }

  var body: some View {
    let id = "row.\(row.kind.rawValue)"
    HStack {
      // VoiceOver reads the row in column order, the name and times before the status, even
      // where a wrapped status starts higher than the times.
      Text(verbatim: row.name)
        .font(BoardStyle.row.weight(isNext ? .bold : .regular))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("\(id).name")
        .accessibilitySortPriority(4)
      VStack(alignment: .leading, spacing: 0) {
        if let time = row.time {
          Text(verbatim: time)
            .font(BoardStyle.row.monospacedDigit().weight(isNext ? .bold : .regular))
            .accessibilityLabel(Text(verbatim: strings("Begins \(time)")))
            .accessibilityIdentifier("\(id).time")
          if row.isNextDay {
            Text(verbatim: strings("Next day"))
              .font(.caption)
              .accessibilityIdentifier("\(id).nextDay")
          }
        } else {
          Text(verbatim: row.missingText ?? "")
            .font(BoardStyle.missing)
            .accessibilityLabel(
              Text(verbatim: strings("Begin time: \(row.missingReason ?? "")"))
            )
            .accessibilityIdentifier("\(id).time")
        }
      }
      .frame(width: timeWidth, alignment: .leading)
      .accessibilityElement(children: .contain)
      .accessibilitySortPriority(3)
      Group {
        if let iqama = row.iqama {
          VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: iqama)
              .font(BoardStyle.row.monospacedDigit())
              .accessibilityLabel(Text(verbatim: strings("Iqama \(iqama)")))
              .accessibilityIdentifier("\(id).iqama")
            if row.iqamaIsNextDay {
              Text(verbatim: strings("Next day"))
                .font(.caption)
                .accessibilityIdentifier("\(id).iqamaNextDay")
            }
          }
        } else if row.time == nil {
          // The begin time's label already says why the row has no times.
          Text(verbatim: "–").font(BoardStyle.row).accessibilityHidden(true)
        } else {
          Text(verbatim: "–")
            .font(BoardStyle.row)
            .accessibilityLabel(Text(verbatim: strings("No iqama")))
            .accessibilityIdentifier("\(id).noIqama")
        }
      }
      .frame(width: timeWidth, alignment: .leading)
      .accessibilityElement(children: .contain)
      .accessibilitySortPriority(2)
      StatusLabel(status: row.status, text: row.statusText)
        .frame(width: statusWidth, alignment: .leading)
        .accessibilityIdentifier("\(id).status")
        .accessibilitySortPriority(1)
    }
    .padding(.vertical, BoardStyle.rowPadding)
    .padding(.horizontal, 12)
    .background(isNext ? BoardStyle.panel : Color.clear, in: .rect(cornerRadius: 12))
    .overlay {
      if isNext {
        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary, lineWidth: 2)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(id)
  }
}

/// A row at the accessibility text sizes: the name, then the times, then the status, each
/// wrapping at word boundaries in the full width. The times carry their column's word, since no
/// column heading is shown.
private struct StackedPrayerRowView: View {
  let row: BoardSnapshot.Row
  let strings: BoardStrings

  private var isNext: Bool {
    if case .next = row.status { return true }
    return false
  }

  var body: some View {
    let id = "row.\(row.kind.rawValue)"
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: row.name)
        .font(BoardStyle.row.weight(isNext ? .bold : .regular))
        .accessibilityIdentifier("\(id).name")
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
          begins(id).fixedSize(horizontal: true, vertical: false)
          iqama(id).fixedSize(horizontal: true, vertical: false)
        }
        VStack(alignment: .leading, spacing: 6) {
          begins(id)
          iqama(id)
        }
      }
      StatusLabel(status: row.status, text: row.statusText)
        .accessibilityIdentifier("\(id).status")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, BoardStyle.rowPadding)
    .padding(.horizontal, 12)
    .background(isNext ? BoardStyle.panel : Color.clear, in: .rect(cornerRadius: 12))
    .overlay {
      if isNext {
        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary, lineWidth: 2)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(id)
  }

  @ViewBuilder private func begins(_ id: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if let time = row.time {
        Text(verbatim: strings("Begins \(time)"))
          .font(BoardStyle.row.monospacedDigit().weight(isNext ? .bold : .regular))
          .accessibilityIdentifier("\(id).time")
        if row.isNextDay {
          Text(verbatim: strings("Next day"))
            .font(.caption)
            .accessibilityIdentifier("\(id).nextDay")
        }
      } else {
        Text(verbatim: row.missingText ?? "")
          .font(BoardStyle.missing)
          .accessibilityLabel(Text(verbatim: strings("Begin time: \(row.missingReason ?? "")")))
          .accessibilityIdentifier("\(id).time")
      }
    }
  }

  @ViewBuilder private func iqama(_ id: String) -> some View {
    if let iqama = row.iqama {
      VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: strings("Iqama \(iqama)"))
          .font(BoardStyle.row.monospacedDigit())
          .accessibilityIdentifier("\(id).iqama")
        if row.iqamaIsNextDay {
          Text(verbatim: strings("Next day"))
            .font(.caption)
            .accessibilityIdentifier("\(id).iqamaNextDay")
        }
      }
    } else if row.time != nil {
      Text(verbatim: strings("No iqama"))
        .font(BoardStyle.row)
        .foregroundStyle(Color.secondary)
        .accessibilityIdentifier("\(id).noIqama")
    }
  }
}

private struct StatusLabel: View {
  let status: BoardSnapshot.Status?
  let text: String?

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .accessibilityHidden(true)
      Text(verbatim: text ?? "")
    }
    .font(BoardStyle.status.weight(emphasized ? .semibold : .regular))
    .foregroundStyle(status == .passed ? Color.secondary : Color.primary)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: text ?? ""))
  }

  private var emphasized: Bool {
    switch status {
    case .next, .justStarted: true
    default: false
    }
  }

  private var symbol: String {
    switch status {
    case .passed: "checkmark.circle"
    case .justStarted: "dot.radiowaves.left.and.right"
    case .next(approaching: true): "bell.circle.fill"
    case .next(approaching: false): "arrow.forward.circle.fill"
    case .upcoming: "circle"
    case nil: "questionmark.circle"
    }
  }
}

/// The next prayer and its countdown, the "not published" message, or the coverage banner.
private struct StatusPanel: View {
  let snapshot: BoardSnapshot
  let strings: BoardStrings

  var body: some View {
    VStack(alignment: .leading, spacing: BoardStyle.panelSpacing) {
      if let started = snapshot.justStarted {
        Text(verbatim: started)
          .font(BoardStyle.message.bold())
          .accessibilityIdentifier("next.justStarted")
      }
      if let banner = snapshot.banner {
        BannerView(banner: banner)
      }
      switch snapshot.next {
      case .prayer(let name, let time, let countdown, let spoken, let owningDay):
        Text(verbatim: strings("Next prayer"))
          .font(BoardStyle.columnHeading)
          .foregroundStyle(Color.secondary)
        Text(verbatim: name)
          .font(BoardStyle.nextName)
          .accessibilityIdentifier("next.name")
        Text(verbatim: strings("Begins \(time)"))
          .font(BoardStyle.nextTime)
          .accessibilityIdentifier("next.time")
        Text(verbatim: countdown)
          .font(BoardStyle.countdown)
          .minimumScaleFactor(BoardStyle.countdownMinimumScale)
          .lineLimit(1)
          .accessibilityLabel(Text(verbatim: strings("Time remaining: \(spoken)")))
          .accessibilityIdentifier("next.countdown")
        if let owningDay {
          Text(verbatim: owningDay)
            .font(.callout)
            .accessibilityIdentifier("next.owningDay")
        }
      case .unpublished(let message):
        Text(verbatim: message)
          .font(BoardStyle.message)
          .accessibilityIdentifier("next.unpublished")
      case nil:
        EmptyView()
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(BoardStyle.panel, in: .rect(cornerRadius: 16))
  }
}

private struct BannerView: View {
  let banner: BoardSnapshot.Banner

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        Text(verbatim: banner.title)
          .accessibilityIdentifier("coverage.title")
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .accessibilityHidden(true)
      }
      .font(BoardStyle.message.bold())
      ForEach(banner.gaps.indices, id: \.self) { index in
        Text(verbatim: banner.gaps[index])
          .font(BoardStyle.gap)
          .accessibilityIdentifier("coverage.gap.\(index)")
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary, lineWidth: 2))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("coverage.banner")
  }
}

private struct FooterView: View {
  let snapshot: BoardSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: snapshot.policy)
        .accessibilityIdentifier("footer.policy")
      if let attribution = snapshot.attribution {
        Text(verbatim: attribution)
          .environment(\.layoutDirection, .leftToRight)
          .accessibilityIdentifier("footer.attribution")
      }
    }
    .font(.footnote)
    .foregroundStyle(Color.secondary)
  }
}
