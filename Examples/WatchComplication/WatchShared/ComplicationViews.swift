import SalahCore
import SalahUI
import SwiftUI
import WidgetKit

/// The complication families the example supports.
nonisolated enum ComplicationFamily: String, CaseIterable, Sendable {
  case circular
  case rectangular
  case inline
  case corner

  /// The WidgetKit family.
  var widgetFamily: WidgetFamily {
    switch self {
    case .circular: .accessoryCircular
    case .rectangular: .accessoryRectangular
    case .inline: .accessoryInline
    case .corner: .accessoryCorner
    }
  }

  /// The family for a WidgetKit family; circular for one the example doesn't support.
  init(_ family: WidgetFamily) {
    switch family {
    case .accessoryRectangular: self = .rectangular
    case .accessoryInline: self = .inline
    case .accessoryCorner: self = .corner
    default: self = .circular
    }
  }
}

/// One complication entry in one family: the view the extension gives WidgetKit, and the view
/// the watch app's states screen draws with the same code.
struct ComplicationView: View {
  let display: ComplicationDisplay
  let family: ComplicationFamily
  let timeZone: TimeZone
  let placeName: String?
  let strings: AppStrings
  /// `.live` in the complication; `.staticText` where the clock is fixed, so text stays put.
  var countdown: PrayerCountdown.Mode = .live
  /// Whether the view is drawn inside the watch app, where a corner's curved label doesn't
  /// exist: the label is then drawn under the corner's content.
  var isInApp = false

  var body: some View {
    content
      .environment(\.locale, strings.locale)
      .environment(\.layoutDirection, strings.isRightToLeft ? .rightToLeft : .leftToRight)
  }

  @ViewBuilder private var content: some View {
    switch display {
    case .next(let state):
      NextPrayerView(state: state, names: strings.names, timeZone: timeZone, countdown: countdown)
        .nextPrayerStyle(
          ComplicationStyle(family: family, placeName: placeName, isInApp: isInApp))
    case .setupRequired:
      message(
        symbol: "iphone", short: strings("Set up"), title: strings("No settings yet"),
        detail: strings("Open the iPhone app"))
    case .partial(let state, let reason):
      partial(state, reason: reason)
    case .timetableEnded:
      message(
        symbol: "calendar.badge.exclamationmark", short: strings("Ended"),
        title: strings("Timetable ended"), detail: strings("Send new times from the iPhone"))
    case .unavailable(let reason):
      message(
        symbol: "exclamationmark.triangle", short: strings("No times"),
        title: strings("Times unavailable"), detail: strings.reason(reason))
    case .timelineExpired(let knownThrough):
      message(
        symbol: "arrow.clockwise", short: strings("Refresh"),
        title: strings("Times need refreshing"),
        detail: strings("Known through \(strings.time(knownThrough, in: timeZone))"))
    }
  }

  /// A state whose latest prayer is known and next one isn't.
  @ViewBuilder
  private func partial(_ state: PrayerState, reason: ScheduleGapReason?) -> some View {
    let latest = state.latestPrayer.map {
      "\(strings.names.name(of: $0)) \(strings.time($0.time, in: timeZone))"
    }
    let short = state.latestPrayer.map { strings.names.abbreviation(of: $0) } ?? "–"
    let detail =
      reason == .noPublishedData
      ? strings("Send new times from the iPhone") : strings.reason(reason)
    message(
      symbol: "questionmark.circle", short: short,
      title: latest.map { strings("Latest: \($0)") } ?? strings("Next prayer unknown"),
      detail: strings("Next prayer unknown") + " · " + detail)
  }

  /// A message in the family's shape: an icon and a word for small families, a title and a
  /// detail line for the rectangular one.
  @ViewBuilder
  private func message(symbol: String, short: String, title: String, detail: String)
    -> some View
  {
    switch family {
    case .circular:
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: 1) {
          Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .widgetAccentable()
          Text(verbatim: short)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(4)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: "\(title). \(detail)"))
    case .rectangular:
      VStack(alignment: .leading, spacing: 1) {
        Label {
          Text(verbatim: title)
        } icon: {
          Image(systemName: symbol)
        }
        .font(.headline)
        .widgetAccentable()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        Text(verbatim: detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
    case .inline:
      Label {
        Text(verbatim: title)
      } icon: {
        Image(systemName: symbol)
      }
    case .corner:
      if isInApp {
        VStack(spacing: 1) {
          Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
          Text(verbatim: title)
            .font(.system(size: 9))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
      } else {
        Image(systemName: symbol)
          .font(.system(size: 20, weight: .semibold))
          .widgetAccentable()
          .widgetLabel {
            Text(verbatim: title)
          }
          .accessibilityLabel(Text(verbatim: "\(title). \(detail)"))
      }
    }
  }
}

/// The next prayer in a complication's shape, from SalahUI's ready-made text: the name or
/// abbreviation, the time and the countdown, which SwiftUI keeps running by itself.
struct ComplicationStyle: NextPrayerStyle {
  let family: ComplicationFamily
  let placeName: String?
  let isInApp: Bool

  func makeBody(configuration: Configuration) -> some View {
    let abbreviation = configuration.abbreviation ?? Text(verbatim: "–")
    let name = configuration.name ?? Text(verbatim: "–")
    switch family {
    case .circular:
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: 0) {
          abbreviation
            .font(.system(size: 13, weight: .bold))
            .widgetAccentable()
          if let countdown = configuration.countdown {
            countdown
              .font(.system(size: 11, weight: .medium))
              .monospacedDigit()
              .multilineTextAlignment(.center)
              .lineLimit(1)
              .minimumScaleFactor(0.5)
          }
        }
        .padding(4)
      }
      .accessibilityElement(children: .combine)
    case .rectangular:
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
          name
            .font(.headline)
            .widgetAccentable()
          Spacer(minLength: 4)
          (configuration.time ?? Text(verbatim: "–"))
            .font(.headline)
            .monospacedDigit()
        }
        if let countdown = configuration.countdown {
          countdown
            .font(.title3)
            .fontWeight(.semibold)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        if let placeName {
          Text(verbatim: placeName)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
    case .inline:
      if let countdown = configuration.countdown {
        Text("\(name) \(countdown)")
      } else {
        name
      }
    case .corner:
      if isInApp {
        VStack(spacing: 0) {
          abbreviation
            .font(.system(size: 16, weight: .bold))
          if let countdown = configuration.countdown {
            countdown
              .font(.system(size: 9))
              .monospacedDigit()
              .lineLimit(1)
              .minimumScaleFactor(0.5)
          }
        }
        .accessibilityElement(children: .combine)
      } else {
        // One VoiceOver element: the prayer's name, and the time remaining as its value. The
        // curved label isn't a child the element could combine.
        abbreviation
          .font(.system(size: 20, weight: .bold))
          .widgetAccentable()
          .widgetLabel {
            configuration.countdown ?? name
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(name)
          .accessibilityValue(configuration.countdown ?? Text(verbatim: ""))
      }
    }
  }
}
