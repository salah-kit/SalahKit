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

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HeaderView(snapshot: snapshot)
          if geometry.size.width > geometry.size.height {
            HStack(alignment: .top, spacing: 24) {
              PrayerTable(snapshot: snapshot, strings: strings)
                .frame(maxWidth: .infinity)
              StatusPanel(snapshot: snapshot, strings: strings)
                .frame(maxWidth: geometry.size.width * 0.38)
            }
          } else {
            StatusPanel(snapshot: snapshot, strings: strings)
            PrayerTable(snapshot: snapshot, strings: strings)
          }
          FooterView(snapshot: snapshot)
        }
        .padding(24)
        .frame(minHeight: geometry.size.height, alignment: .top)
      }
    }
    .background(Color(.systemBackground))
    .foregroundStyle(Color.primary)
  }
}

private struct HeaderView: View {
  let snapshot: BoardSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(verbatim: snapshot.title)
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("header.title")
        Spacer(minLength: 16)
        Text(verbatim: snapshot.clock)
          .font(.largeTitle.monospacedDigit())
          .accessibilityIdentifier("header.clock")
      }
      Text(verbatim: snapshot.subtitle)
        .font(.title3)
        .foregroundStyle(Color.secondary)
        .accessibilityIdentifier("header.subtitle")
      Text(verbatim: snapshot.gregorianDate)
        .font(.title2)
        .accessibilityIdentifier("header.gregorian")
      Text(verbatim: snapshot.hijriDate)
        .font(.title2)
        .accessibilityIdentifier("header.hijri")
    }
  }
}

private struct PrayerTable: View {
  let snapshot: BoardSnapshot
  let strings: BoardStrings
  @ScaledMetric(relativeTo: .title) private var timeWidth: CGFloat = 96
  @ScaledMetric(relativeTo: .title) private var statusWidth: CGFloat = 150

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let unavailable = snapshot.dayUnavailable {
        Text(verbatim: unavailable)
          .font(.title2)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
          .accessibilityIdentifier("day.unavailable")
      } else {
        HStack {
          Text(verbatim: strings("Prayer")).frame(maxWidth: .infinity, alignment: .leading)
          Text(verbatim: strings("Begins")).frame(width: timeWidth, alignment: .leading)
          Text(verbatim: strings("Iqama")).frame(width: timeWidth, alignment: .leading)
          Text(verbatim: strings("Status")).frame(width: statusWidth, alignment: .leading)
        }
        .font(.headline)
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
      Text(verbatim: row.name)
        .font(.title.weight(isNext ? .bold : .regular))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("\(id).name")
      VStack(alignment: .leading, spacing: 0) {
        if let time = row.time {
          Text(verbatim: time)
            .font(.title.monospacedDigit().weight(isNext ? .bold : .regular))
            .accessibilityLabel(Text(verbatim: strings("Begins \(time)")))
            .accessibilityIdentifier("\(id).time")
          if row.isNextDay {
            Text(verbatim: strings("Next day"))
              .font(.caption)
              .accessibilityIdentifier("\(id).nextDay")
          }
        } else {
          Text(verbatim: strings("Not published"))
            .font(.title3)
            .accessibilityLabel(
              Text(verbatim: strings("Begin time: \(row.missingReason ?? "")"))
            )
            .accessibilityIdentifier("\(id).time")
        }
      }
      .frame(width: timeWidth, alignment: .leading)
      Group {
        if let iqama = row.iqama {
          Text(verbatim: iqama)
            .font(.title.monospacedDigit())
            .accessibilityLabel(Text(verbatim: strings("Iqama \(iqama)")))
            .accessibilityIdentifier("\(id).iqama")
        } else {
          Text(verbatim: "–").font(.title).accessibilityHidden(true)
        }
      }
      .frame(width: timeWidth, alignment: .leading)
      StatusLabel(status: row.status, text: row.statusText)
        .frame(width: statusWidth, alignment: .leading)
        .accessibilityIdentifier("\(id).status")
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(
      isNext ? Color(.secondarySystemBackground) : Color.clear, in: .rect(cornerRadius: 12)
    )
    .overlay {
      if isNext {
        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary, lineWidth: 2)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(id)
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
    .font(.title3.weight(emphasized ? .semibold : .regular))
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
    VStack(alignment: .leading, spacing: 12) {
      if let started = snapshot.justStarted {
        Text(verbatim: started)
          .font(.title2.bold())
          .accessibilityIdentifier("next.justStarted")
      }
      if let banner = snapshot.banner {
        BannerView(banner: banner)
      }
      switch snapshot.next {
      case .prayer(let name, let time, let countdown, let spoken, let owningDay):
        Text(verbatim: strings("Next prayer"))
          .font(.headline)
          .foregroundStyle(Color.secondary)
        Text(verbatim: name)
          .font(.system(.largeTitle, weight: .bold))
          .accessibilityIdentifier("next.name")
        Text(verbatim: strings("Begins \(time)"))
          .font(.title2)
          .accessibilityIdentifier("next.time")
        Text(verbatim: countdown)
          .font(.system(size: 64, weight: .bold).monospacedDigit())
          .minimumScaleFactor(0.5)
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
          .font(.title2)
          .accessibilityIdentifier("next.unpublished")
      case nil:
        EmptyView()
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
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
      .font(.title2.bold())
      ForEach(banner.gaps.indices, id: \.self) { index in
        Text(verbatim: banner.gaps[index])
          .font(.body)
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
