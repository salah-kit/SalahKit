import SalahCore
import SwiftUI

/// Redraws every second for the clock and the countdown, which also covers every state change
/// (`ScheduleState.changesAt`) within a second. A frozen clock draws once.
struct SecondsSchedule: TimelineSchedule {
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

/// The main screen: the place and date, the next and latest prayers, today's schedule, the
/// alerts and the calculation that produced the times.
struct TodayView: View {
  let settings: AppSettings
  let clock: AppClock
  let strings: PhoneStrings
  let alerts: AlertCoordinator

  var body: some View {
    let settings = settings
    TimelineView(SecondsSchedule(frozen: clock.frozen)) { context in
      TodayContent(
        snapshot: PhoneSnapshot.make(
          settings: settings, at: clock.now(at: context.date), strings: strings),
        alerts: AlertsSnapshot.make(
          options: settings.alerts, authorization: alerts.authorization, plan: alerts.plan,
          report: alerts.report, pending: alerts.pending, fromFixture: alerts.usesFixture,
          probe: alerts.probe, strings: strings, timeZone: settings.place.location.timeZone,
          now: context.date),
        strings: strings)
    }
  }
}

struct TodayContent: View {
  let snapshot: PhoneSnapshot
  var alerts: AlertsSnapshot?
  let strings: PhoneStrings

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HeaderCard(snapshot: snapshot)
        if let banner = snapshot.banner {
          BannerCard(banner: banner)
        }
        NowCard(snapshot: snapshot, strings: strings)
        ScheduleCard(snapshot: snapshot, strings: strings)
        if let alerts {
          AlertsCard(snapshot: alerts, strings: strings)
        }
        CalculationCard(rows: snapshot.calculation, strings: strings)
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
  }
}

/// A rounded section with an optional heading.
struct Card<Content: View>: View {
  var title: String?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let title {
        Text(verbatim: title)
          .font(.headline)
          .foregroundStyle(Color.secondary)
          .accessibilityAddTraits(.isHeader)
      }
      content
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
  }
}

private struct HeaderCard: View {
  let snapshot: PhoneSnapshot

  var body: some View {
    Card {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          place
          Spacer(minLength: 12)
          clock
        }
        VStack(alignment: .leading, spacing: 4) {
          place
          clock
        }
      }
      Text(verbatim: snapshot.gregorianDate)
        .font(.body)
        .accessibilityIdentifier("header.date")
      Text(verbatim: snapshot.hijriDate)
        .font(.body)
        .foregroundStyle(Color.secondary)
        .accessibilityIdentifier("header.hijri")
    }
  }

  private var place: some View {
    Text(verbatim: snapshot.place)
      .font(.title.bold())
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("header.place")
  }

  private var clock: some View {
    Text(verbatim: snapshot.clock)
      .font(.title.monospacedDigit())
      .accessibilityIdentifier("header.clock")
  }
}

/// The owning day of an event that belongs to another day's schedule: "Sunday's".
private struct OwningDayTag: View {
  let moment: PhoneSnapshot.Moment
  let identifier: String

  var body: some View {
    if let owningDay = moment.owningDay {
      Text(verbatim: owningDay)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(Color.secondary, lineWidth: 1))
        .accessibilityLabel(Text(verbatim: moment.owningDayLabel ?? owningDay))
        .accessibilityIdentifier(identifier)
    }
  }
}

/// The next prayer and its countdown, the latest prayer, or why they can't be named.
private struct NowCard: View {
  let snapshot: PhoneSnapshot
  let strings: PhoneStrings

  var body: some View {
    Card(title: strings("Next prayer")) {
      switch snapshot.next {
      case .prayer(let moment, let countdown, let spoken):
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(verbatim: moment.name)
            .font(.largeTitle.bold())
            .accessibilityIdentifier("next.name")
          OwningDayTag(moment: moment, identifier: "next.owningDay")
          Spacer(minLength: 8)
          Text(verbatim: moment.time)
            .font(.title2.monospacedDigit())
            .accessibilityLabel(Text(verbatim: strings("At \(moment.time)")))
            .accessibilityIdentifier("next.time")
        }
        Text(verbatim: countdown)
          .font(.system(.largeTitle, design: .rounded).monospacedDigit().weight(.semibold))
          .accessibilityLabel(Text(verbatim: strings("Time remaining: \(spoken)")))
          .accessibilityIdentifier("next.countdown")
      case .unknown(let message, let reason):
        Label {
          Text(verbatim: message)
            .accessibilityIdentifier("next.unknown")
        } icon: {
          Image(systemName: "questionmark.circle")
            .accessibilityHidden(true)
        }
        .font(.title3.weight(.semibold))
        if let reason {
          Text(verbatim: reason)
            .font(.callout)
            .accessibilityIdentifier("next.reason")
        }
      }
      if let started = snapshot.justStarted {
        Text(verbatim: started)
          .font(.headline)
          .accessibilityIdentifier("now.justStarted")
      }
      if let latest = snapshot.latest {
        Divider()
        MomentLine(
          title: strings("Latest prayer"), moment: latest, strings: strings, identifier: "latest")
      }
      if let previous = snapshot.previous {
        MomentLine(
          title: strings("Latest event"), moment: previous, strings: strings,
          identifier: "previous")
      }
    }
  }
}

/// "Latest prayer: Isha 00:19 (Sunday's)".
private struct MomentLine: View {
  let title: String
  let moment: PhoneSnapshot.Moment
  let strings: PhoneStrings
  let identifier: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(verbatim: title)
        .foregroundStyle(Color.secondary)
      Spacer(minLength: 8)
      Text(verbatim: moment.name)
        .fontWeight(.semibold)
        .accessibilityIdentifier("\(identifier).name")
      OwningDayTag(moment: moment, identifier: "\(identifier).owningDay")
      Text(verbatim: moment.time)
        .monospacedDigit()
        .accessibilityLabel(Text(verbatim: strings("At \(moment.time)")))
        .accessibilityIdentifier("\(identifier).time")
    }
    .font(.body)
  }
}

private struct BannerCard: View {
  let banner: PhoneSnapshot.Banner

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        Text(verbatim: banner.title)
          .accessibilityIdentifier("coverage.title")
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .accessibilityHidden(true)
      }
      .font(.headline)
      ForEach(banner.gaps.indices, id: \.self) { index in
        Text(verbatim: banner.gaps[index])
          .font(.callout)
          .accessibilityIdentifier("coverage.gap.\(index)")
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange, lineWidth: 2))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("coverage.banner")
  }
}

private struct ScheduleCard: View {
  let snapshot: PhoneSnapshot
  let strings: PhoneStrings

  var body: some View {
    Card(title: strings("Today")) {
      if let unavailable = snapshot.dayUnavailable {
        Text(verbatim: unavailable)
          .font(.callout)
          .accessibilityIdentifier("day.unavailable")
      }
      ForEach(snapshot.rows) { row in
        RowView(row: row)
        if row.kind != snapshot.rows.last?.kind {
          Divider()
        }
      }
    }
  }
}

private struct RowView: View {
  let row: PhoneSnapshot.Row

  private var isNext: Bool {
    if case .next = row.status { return true }
    return false
  }

  var body: some View {
    let id = "row.\(row.kind.rawValue)"
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: row.name)
          .font(.title3.weight(isNext ? .bold : .regular))
          .accessibilityIdentifier("\(id).name")
        StatusLabel(status: row.status, text: row.statusText)
          .accessibilityIdentifier("\(id).status")
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        if let time = row.time {
          Text(verbatim: time)
            .font(.title3.monospacedDigit().weight(isNext ? .bold : .regular))
            .accessibilityIdentifier("\(id).time")
        } else {
          Text(verbatim: row.missing ?? "")
            .font(.callout)
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.trailing)
            .accessibilityIdentifier("\(id).time")
        }
        if let marker = row.dayMarker {
          Text(verbatim: marker)
            .font(.caption)
            .accessibilityIdentifier("\(id).marker")
        }
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(id)
  }
}

private struct StatusLabel: View {
  let status: PhoneSnapshot.Status?
  let text: String?

  var body: some View {
    if let text {
      HStack(spacing: 4) {
        Image(systemName: symbol)
          .accessibilityHidden(true)
        Text(verbatim: text)
      }
      .font(.footnote.weight(emphasized ? .semibold : .regular))
      .foregroundStyle(status == .passed ? Color.secondary : Color.primary)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: text))
    }
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

/// Every parameter the times were calculated with.
private struct CalculationCard: View {
  let rows: [ParameterRow]
  let strings: PhoneStrings

  var body: some View {
    Card(title: strings("Calculation")) {
      ForEach(rows) { row in
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline) {
            title(row)
            Spacer(minLength: 12)
            value(row).multilineTextAlignment(.trailing)
          }
          VStack(alignment: .leading, spacing: 2) {
            title(row)
            value(row)
          }
        }
        .font(.callout)
      }
    }
  }

  private func title(_ row: ParameterRow) -> some View {
    Text(verbatim: row.title).foregroundStyle(Color.secondary)
  }

  private func value(_ row: ParameterRow) -> some View {
    Text(verbatim: row.value)
      .accessibilityLabel(Text(verbatim: "\(row.title): \(row.value)"))
      .accessibilityIdentifier("calc.\(row.id)")
  }
}
