import SalahCore
import SalahUI
import SwiftUI

/// The watch app's main screen: the stored inputs' current state, or the setup prompt.
struct HomeView: View {
  let model: WatchModel
  @Environment(\.scenePhase) private var scenePhase

  private var strings: AppStrings { model.strings }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        if let inputs = model.inputs {
          ScheduleSection(inputs: inputs, options: model.options, strings: strings)
        } else {
          setup
        }
        status
        NavigationLink(value: RootView.Screen.states) {
          Text(verbatim: strings("Complication states"))
        }
        .accessibilityIdentifier("nav.states")
        NavigationLink(value: RootView.Screen.diagnostics) {
          Text(verbatim: strings("Diagnostics"))
        }
        .accessibilityIdentifier("nav.diagnostics")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(Text(verbatim: strings("Prayers")))
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.reload() }
    }
  }

  /// What a watch without inputs shows.
  private var setup: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label {
        Text(verbatim: strings("No settings yet"))
      } icon: {
        Image(systemName: "iphone")
      }
      .font(.headline)
      .accessibilityIdentifier("setup.title")
      Text(
        verbatim: strings("Open WatchComplication on your iPhone to send a place and its times.")
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("setup.detail")
    }
  }

  /// Where the inputs came from and the iPhone session.
  private var status: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let receipt = model.receipt {
        Text(verbatim: receiptText(receipt))
          .accessibilityIdentifier("home.received")
        if receipt.origin != .reset {
          Text(verbatim: strings("Inputs \(receipt.fingerprint)"))
            .accessibilityIdentifier("home.fingerprint")
        }
      }
      if let problem = model.problem {
        Text(verbatim: strings("Rejected: \(problem)"))
          .accessibilityIdentifier("home.problem")
      }
      Text(verbatim: phoneText)
        .accessibilityIdentifier("home.phone")
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
  }

  private func receiptText(_ receipt: InputsReceipt) -> String {
    let time = strings.dateTime(receipt.receivedAt, in: .current)
    let change = receipt.changed ? strings("changed") : strings("unchanged")
    switch receipt.origin {
    case .companion: return strings("Received \(time), \(change)")
    case .launchArguments: return strings("From launch arguments \(time), \(change)")
    case .reset: return strings("Inputs cleared \(time)")
    }
  }

  private var phoneText: String {
    switch model.phone {
    case .unsupported: strings("No iPhone session")
    case .inactive: strings("iPhone session inactive")
    case .active(reachable: true): strings("iPhone reachable")
    case .active(reachable: false): strings("iPhone not reachable")
    }
  }
}

/// The stored inputs' place, source and current state, from the same timeline the
/// complication builds. With the real clock, it moves to each entry as its date comes and
/// builds the next timeline when this one ends; with `-now`, it shows the entry at that
/// instant.
///
/// The timeline is built once per inputs and timeline, not on every redraw: a schedule that
/// changed on each redraw would keep the timeline view redrawing.
struct ScheduleSection: View {
  let inputs: WatchInputs
  let options: LaunchOptions
  let strings: AppStrings
  @State private var built: Built?

  /// A timeline built from some inputs.
  struct Built: Equatable {
    var inputs: WatchInputs
    var start: Date
    var entries: [ComplicationEntry]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: inputs.location.name ?? strings("Unnamed place"))
        .font(.headline)
        .accessibilityIdentifier("home.place")
      Text(verbatim: sourceText)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("home.source")
      if let built, built.inputs == inputs {
        if options.now != nil {
          state(
            ComplicationTimeline.entry(at: built.start, in: built.entries),
            countdown: .staticText)
        } else {
          TimelineView(.explicit(built.entries.map(\.date))) { context in
            state(
              ComplicationTimeline.entry(at: context.date, in: built.entries), countdown: .live)
          }
        }
      }
    }
    .task(id: inputs) {
      // Build a timeline, wait until it ends, and build the next one, as WidgetKit would ask.
      while !Task.isCancelled {
        let start = options.date()
        let entries = ComplicationTimeline.make(inputs: inputs, now: start).entries
        built = Built(inputs: inputs, start: start, entries: entries)
        guard options.now == nil, let end = entries.last?.date, end > start else { return }
        try? await Task.sleep(for: .seconds(end.timeIntervalSince(start)))
      }
    }
  }

  private var sourceText: String {
    switch inputs.source {
    case .calculated: return strings("Calculated on the watch")
    case .timetable(let timetable):
      guard let last = timetable.lastDay else { return strings("Empty timetable") }
      return strings("Timetable through \(strings.day(last, in: inputs.location.timeZone))")
    }
  }

  @ViewBuilder
  private func state(_ entry: ComplicationEntry?, countdown: PrayerCountdown.Mode) -> some View {
    if let entry {
      let zone = inputs.location.timeZone
      switch ComplicationDisplay(entry.content, at: entry.date) {
      case .next(let state):
        NextPrayerView(state: state, names: strings.names, timeZone: zone, countdown: countdown)
          .accessibilityIdentifier("home.next")
      case .setupRequired:
        message(strings("No settings yet"), strings("Open the iPhone app"))
      case .partial(let state, let reason):
        let latest = state.latestPrayer.map {
          strings("Latest: \("\(strings.names.name(of: $0)) \(strings.time($0.time, in: zone))")")
        }
        message(
          latest ?? strings("Next prayer unknown"),
          strings("Next prayer unknown") + " · "
            + (reason == .noPublishedData
              ? strings("Send new times from the iPhone") : strings.reason(reason)))
      case .timetableEnded(let day):
        message(
          strings("Timetable ended"),
          (day.map { strings("No published times from \(strings.day($0, in: zone)).") + " " }
            ?? "") + strings("Open WatchComplication on your iPhone to send new times."))
      case .unavailable(let reason):
        message(strings("Times unavailable"), strings.reason(reason))
      case .timelineExpired(let knownThrough):
        message(
          strings("Times need refreshing"),
          strings("Known through \(strings.time(knownThrough, in: zone))"))
      }
    }
  }

  private func message(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: title)
        .font(.headline)
        .accessibilityIdentifier("home.title")
      Text(verbatim: detail)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("home.detail")
    }
  }
}
