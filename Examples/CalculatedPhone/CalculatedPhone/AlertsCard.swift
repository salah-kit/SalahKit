import SwiftUI

/// The alerts: whether they're on and allowed, until when they're scheduled, and the next
/// pending requests as the app read them back.
struct AlertsCard: View {
  let snapshot: AlertsSnapshot
  let strings: PhoneStrings

  var body: some View {
    Card(title: strings("Alerts")) {
      Text(verbatim: snapshot.status)
        .font(.callout)
        .accessibilityIdentifier("alerts.status")
      if snapshot.fromFixture {
        Text(verbatim: strings("Planned from the fixture timetable of this run."))
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .accessibilityIdentifier("alerts.fixture")
      }
      if let scheduledUntil = snapshot.scheduledUntil {
        Text(verbatim: scheduledUntil)
          .font(.callout.weight(.semibold))
          .accessibilityIdentifier("alerts.scheduledUntil")
      }
      if let plannedUntil = snapshot.plannedUntil {
        Text(verbatim: plannedUntil)
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .accessibilityIdentifier("alerts.plannedUntil")
      }
      if let pendingCount = snapshot.pendingCount {
        Text(verbatim: pendingCount)
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .accessibilityIdentifier("alerts.pendingCount")
      }
      ForEach(snapshot.rows) { row in
        Divider()
        AlertRowView(row: row)
      }
      if let probe = snapshot.probe {
        Text(verbatim: probe)
          .font(.footnote)
          .accessibilityIdentifier("alerts.probe")
      }
      ForEach(snapshot.failures.indices, id: \.self) { index in
        Text(verbatim: snapshot.failures[index])
          .font(.footnote)
          .accessibilityIdentifier("alerts.failure.\(index)")
      }
    }
  }
}

/// "Dhuhr · Wednesday 12:07 · Confirmed".
private struct AlertRowView: View {
  let row: AlertsSnapshot.Row

  var body: some View {
    let id = "alerts.request.\(row.id)"
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        title(id)
        Spacer(minLength: 8)
        time(id)
        status(id)
      }
      VStack(alignment: .leading, spacing: 2) {
        title(id)
        time(id)
        status(id)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(id)
  }

  private func title(_ id: String) -> some View {
    Text(verbatim: row.title)
      .fontWeight(.semibold)
      .accessibilityIdentifier("\(id).title")
  }

  private func time(_ id: String) -> some View {
    Text(verbatim: row.time)
      .monospacedDigit()
      .accessibilityIdentifier("\(id).time")
  }

  private func status(_ id: String) -> some View {
    Text(verbatim: row.status)
      .font(.footnote)
      .foregroundStyle(Color.secondary)
      .accessibilityIdentifier("\(id).status")
  }
}
