import SalahCore
import SalahUI
import SwiftUI
import WidgetKit

extension EntryContent {
  /// The language the entry is drawn in.
  nonisolated var language: NamesLanguage {
    switch self {
    case .setupRequired(let language): language
    case .timeline(_, let context): context.language
    }
  }

  /// The place's time zone, when the entry has a place.
  nonisolated var context: EntryContext? {
    if case .timeline(_, let context) = self { return context }
    return nil
  }
}

/// A widget entry in one family: the view the extension draws, and the one the app's "Widget
/// states" screen draws for every state.
///
/// The extension reads the family from WidgetKit's environment and passes it in; the app passes
/// each family in turn.
struct PrayerWidgetView: View {
  let entry: PrayerEntry
  let family: WidgetFamily
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let strings = WidgetStrings(language: entry.content.language)
    let palette = WidgetPalette.of(colorScheme)
    WidgetContent(entry: entry, family: family, strings: strings, palette: palette)
      .environment(\.locale, strings.locale)
      .environment(\.layoutDirection, strings.isRightToLeft ? .rightToLeft : .leftToRight)
      .containerBackground(for: .widget) {
        if family.isAccessory {
          AccessoryWidgetBackground()
        } else {
          palette.surface.color
        }
      }
  }
}

extension WidgetFamily {
  /// Whether the family is a Lock Screen accessory.
  var isAccessory: Bool {
    switch self {
    case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
    default: false
    }
  }
}

/// The entry's content, by display and family.
private struct WidgetContent: View {
  let entry: PrayerEntry
  let family: WidgetFamily
  let strings: WidgetStrings
  let palette: WidgetPalette

  var body: some View {
    let display = WidgetDisplay(entry.content)
    let context = entry.content.context
    let wording = WidgetWording(
      display, strings: strings, timeZone: context?.place.location.timeZone)
    switch display {
    case .times(let times):
      if let context {
        TimesView(
          times: times, context: context, wording: wording, family: family, strings: strings,
          palette: palette)
      }
    case .setupRequired:
      NoticeView(
        symbol: "mappin.and.ellipse", wording: wording, place: nil, family: family,
        palette: palette, tint: palette.accent)
    case .unavailable:
      NoticeView(
        symbol: "exclamationmark.triangle", wording: wording,
        place: context.map { strings.placeName($0.place) }, family: family, palette: palette,
        tint: palette.notice)
    case .expired:
      NoticeView(
        symbol: "clock.arrow.circlepath", wording: wording,
        place: context.map { strings.placeName($0.place) }, family: family, palette: palette,
        tint: palette.notice)
    }
  }
}

// MARK: Notices

/// Setup required, unavailable and expired: a symbol and the app's words, with no time and no
/// countdown.
private struct NoticeView: View {
  let symbol: String
  let wording: WidgetWording
  let place: String?
  let family: WidgetFamily
  let palette: WidgetPalette
  let tint: ThemeColor

  var body: some View {
    switch family {
    case .accessoryInline:
      Label {
        Text(verbatim: wording.short ?? wording.title ?? "")
          .accessibilityIdentifier("widget.short")
      } icon: {
        Image(systemName: symbol)
          .accessibilityHidden(true)
      }
    case .accessoryCircular:
      VStack(spacing: 2) {
        Image(systemName: symbol)
          .font(.title3)
          .widgetAccentable()
          .accessibilityHidden(true)
        Text(verbatim: wording.short ?? "")
          .font(.caption2)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(0.6)
          .accessibilityIdentifier("widget.short")
      }
      .accessibilityElement(children: .combine)
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Label {
          Text(verbatim: wording.title ?? "")
            .font(.headline)
            .accessibilityIdentifier("widget.title")
        } icon: {
          // The symbol is decoration: its default label, such as "Remove Map Pin" for
          // `mappin.and.ellipse`, isn't what the notice means.
          Image(systemName: symbol)
            .accessibilityHidden(true)
        }
        .widgetAccentable()
        Text(verbatim: wording.message ?? "")
          .font(.caption)
          .minimumScaleFactor(0.7)
          .accessibilityIdentifier("widget.message")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    default:
      VStack(alignment: .leading, spacing: 6) {
        Image(systemName: symbol)
          .font(family == .systemSmall ? .title2 : .title)
          .foregroundStyle(tint.color)
          .accessibilityHidden(true)
        Text(verbatim: wording.title ?? "")
          .font(.headline)
          .foregroundStyle(palette.ink.color)
          .accessibilityIdentifier("widget.title")
        Text(verbatim: wording.message ?? "")
          .font(family == .systemSmall ? .caption : .subheadline)
          .foregroundStyle(palette.secondaryInk.color)
          .minimumScaleFactor(0.7)
          .accessibilityIdentifier("widget.message")
        Spacer(minLength: 0)
        if let place {
          Text(verbatim: place)
            .font(.caption2)
            .foregroundStyle(palette.secondaryInk.color)
            .accessibilityIdentifier("widget.place")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

// MARK: Times

/// A known state: the next prayer from SalahUI's `NextPrayerView`, the day from its
/// `PrayerTimesList`, and the app's note for what isn't known.
private struct TimesView: View {
  @Environment(\.widgetCountdownMode) private var countdownMode
  let times: TimesDisplay
  let context: EntryContext
  let wording: WidgetWording
  let family: WidgetFamily
  let strings: WidgetStrings
  let palette: WidgetPalette

  private var zone: TimeZone { context.place.location.timeZone }

  var body: some View {
    switch family {
    case .accessoryInline:
      next.nextPrayerStyle(InlineNextStyle(strings: strings))
    case .accessoryCircular:
      next.nextPrayerStyle(CircularNextStyle(strings: strings, countdownMode: countdownMode))
    case .accessoryRectangular:
      next.nextPrayerStyle(
        RectangularNextStyle(strings: strings, note: wording.message, countdownMode: countdownMode))
    case .systemSmall:
      VStack(alignment: .leading, spacing: 4) {
        placeLine
        next.nextPrayerStyle(card(large: false))
        Spacer(minLength: 0)
        note
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    case .systemMedium:
      // VoiceOver reads the card, then the day's list: each column is its own container, so
      // their lines aren't interleaved by height.
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          placeLine
          next.nextPrayerStyle(card(large: false))
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
        dayList(font: .caption)
          .frame(maxWidth: .infinity)
          .accessibilityElement(children: .contain)
      }
      .frame(maxHeight: .infinity, alignment: .top)
    default:
      VStack(alignment: .leading, spacing: 8) {
        placeLine
        next.nextPrayerStyle(card(large: true))
        Divider()
        dayList(font: .body)
        Spacer(minLength: 0)
        note
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func card(large: Bool) -> CardNextStyle {
    CardNextStyle(strings: strings, palette: palette, large: large, countdownMode: countdownMode)
  }

  private var next: NextPrayerView {
    NextPrayerView(
      state: times.state, names: strings.names, timeZone: zone, countdown: countdownMode)
  }

  private var placeLine: some View {
    Text(verbatim: strings.placeName(context.place))
      .font(.caption)
      .fontWeight(.medium)
      .foregroundStyle(palette.secondaryInk.color)
      .lineLimit(1)
      .accessibilityIdentifier("widget.place")
  }

  @ViewBuilder private var note: some View {
    if let message = wording.message {
      Text(verbatim: message)
        .font(.caption2)
        .foregroundStyle(palette.secondaryInk.color)
        .minimumScaleFactor(0.7)
        .accessibilityIdentifier("widget.message")
    }
  }

  @ViewBuilder private func dayList(font: Font) -> some View {
    if let day = times.day {
      VStack(alignment: .leading, spacing: 2) {
        PrayerTimesList(
          day: day, state: times.state, names: strings.names, countdown: countdownMode
        )
        .prayerRowStyle(WidgetRowStyle(palette: palette, strings: strings))
        .font(font)
        if family == .systemMedium {
          note
        }
      }
    } else {
      note
    }
  }
}

// MARK: Styles

/// The Home Screen card: the just-started prayer, the next prayer's name, time and live
/// countdown. An unknown next prayer reads as unknown, with no countdown.
private struct CardNextStyle: NextPrayerStyle {
  let strings: WidgetStrings
  let palette: WidgetPalette
  let large: Bool
  let countdownMode: PrayerCountdown.Mode

  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      // The app's own sentence, in the chosen language's word order, from the state's event.
      if configuration.justStarted != nil, let started = configuration.state.justStarted {
        Text(verbatim: strings("\(strings.names.name(of: started)) has started"))
          .font(.caption2)
          .foregroundStyle(palette.accent.color)
          .accessibilityIdentifier("widget.justStarted")
      }
      if let name = configuration.name, let time = configuration.time {
        name
          .font(large ? .title2 : .headline)
          .foregroundStyle(palette.ink.color)
          .accessibilityIdentifier("widget.next.name")
        time
          .font(.subheadline)
          .monospacedDigit()
          .foregroundStyle(palette.secondaryInk.color)
          .accessibilityIdentifier("widget.next.time")
      } else {
        Text(verbatim: strings("Next prayer unknown"))
          .font(.headline)
          .foregroundStyle(palette.ink.color)
          .accessibilityIdentifier("widget.next.unknown")
      }
      if let countdown = configuration.countdown {
        countdown
          .font(large ? .largeTitle : .title2)
          .fontWeight(.semibold)
          .monospacedDigit()
          .foregroundStyle(palette.accent.color)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .accessibilityLabel(
            countdownLabel(configuration, strings: strings, mode: countdownMode) ?? countdown
          )
          .accessibilityIdentifier("widget.next.countdown")
      }
    }
    .accessibilityElement(children: .contain)
  }
}

/// The circular Lock Screen widget: the next prayer's abbreviation over its countdown.
private struct CircularNextStyle: NextPrayerStyle {
  let strings: WidgetStrings
  let countdownMode: PrayerCountdown.Mode

  func makeBody(configuration: Configuration) -> some View {
    ZStack {
      AccessoryWidgetBackground()
      VStack(spacing: 0) {
        (configuration.abbreviation ?? Text(verbatim: "–"))
          .font(.headline)
          .widgetAccentable()
          .accessibilityIdentifier("widget.next.abbreviation")
        if let countdown = configuration.countdown {
          countdown
            .font(.caption2)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.5)
            .accessibilityIdentifier("widget.next.countdown")
        } else {
          Text(verbatim: strings("Unknown"))
            .font(.caption2)
            .minimumScaleFactor(0.5)
            .accessibilityIdentifier("widget.next.unknown")
        }
      }
      .padding(4)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label(configuration))
    .accessibilityIdentifier("widget.next")
  }

  /// The full name and the time remaining, or that the next prayer is unknown, rather than a
  /// dash and "Unknown".
  @MainActor
  private func label(_ configuration: Configuration) -> Text {
    guard let name = configuration.name else {
      return Text(verbatim: strings("Next prayer unknown"))
    }
    guard let countdown = countdownLabel(configuration, strings: strings, mode: countdownMode)
    else { return name }
    return name + Text(verbatim: strings.labelSeparator) + countdown
  }
}

/// The rectangular Lock Screen widget: the next prayer's name and time, then the countdown or
/// the note.
private struct RectangularNextStyle: NextPrayerStyle {
  let strings: WidgetStrings
  let note: String?
  let countdownMode: PrayerCountdown.Mode

  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      if let name = configuration.name, let time = configuration.time {
        Text("\(name) \(time)")
          .font(.headline)
          .widgetAccentable()
          .accessibilityIdentifier("widget.next.name")
      } else {
        Text(verbatim: strings("Next prayer unknown"))
          .font(.headline)
          .widgetAccentable()
          .accessibilityIdentifier("widget.next.unknown")
      }
      if let countdown = configuration.countdown {
        countdown
          .monospacedDigit()
          .accessibilityLabel(
            countdownLabel(configuration, strings: strings, mode: countdownMode) ?? countdown
          )
          .accessibilityIdentifier("widget.next.countdown")
      } else if let note {
        Text(verbatim: note)
          .font(.caption)
          .minimumScaleFactor(0.7)
          .accessibilityIdentifier("widget.message")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The inline Lock Screen widget: one line, the next prayer and its time.
private struct InlineNextStyle: NextPrayerStyle {
  let strings: WidgetStrings

  func makeBody(configuration: Configuration) -> some View {
    if let name = configuration.name, let time = configuration.time {
      Text("\(name) \(time)")
        .accessibilityIdentifier("widget.next.name")
    } else {
      Text(verbatim: strings("Next prayer unknown"))
        .accessibilityIdentifier("widget.next.unknown")
    }
  }
}

/// A row of the day's list: the next prayer in the accent color, passed ones secondary.
private struct WidgetRowStyle: PrayerRowStyle {
  let palette: WidgetPalette
  let strings: WidgetStrings

  func makeBody(configuration: Configuration) -> some View {
    let color: ThemeColor
    let emphasized: Bool
    switch configuration.status {
    case .next?:
      color = palette.accent
      emphasized = true
    case .justStarted?:
      color = palette.ink
      emphasized = true
    case .passed?:
      color = palette.secondaryInk
      emphasized = false
    case .upcoming?, nil:
      color = palette.ink
      emphasized = false
    }
    return HStack(spacing: 4) {
      configuration.name
        .lineLimit(1)
      Spacer(minLength: 4)
      (configuration.time ?? Text(verbatim: "–"))
        .monospacedDigit()
        .lineLimit(1)
      if let offset = configuration.dayOffsetText {
        offset
          .font(.caption2)
      }
    }
    .fontWeight(emphasized ? .semibold : .regular)
    .foregroundStyle(color.color)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label(configuration))
    .accessibilityIdentifier("widget.row.\(configuration.kind.rawValue)")
  }

  /// The name, time and day offset, joined with the language's comma: "Fajr, 5:01 AM" or
  /// "الفجر، ٥:٠١ ص". Combining the children would join them with an ASCII comma. A row
  /// without a time says why instead of the "–" it shows.
  @MainActor
  private func label(_ configuration: Configuration) -> Text {
    let separator = Text(verbatim: strings.labelSeparator)
    var label =
      configuration.name + separator
      + (configuration.time ?? Text(verbatim: strings.missingTime(configuration.gapReason)))
    if let offset = configuration.dayOffsetText {
      label = label + separator + offset
    }
    return label
  }
}

/// VoiceOver's label for the countdown to the configuration's next prayer: "Time remaining",
/// then the time left. A live countdown's label holds a timer of its own, so it stays current;
/// one drawn at a fixed moment reads the time left in words. `nil` without a countdown.
@MainActor
private func countdownLabel(
  _ configuration: NextPrayerConfiguration, strings: WidgetStrings, mode: PrayerCountdown.Mode
) -> Text? {
  guard configuration.countdown != nil, let focus = configuration.focus, !focus.isCountUp
  else { return nil }
  let start = configuration.state.date
  let end = max(start, focus.event.time)
  switch mode {
  case .staticText:
    return Text(verbatim: strings.timeRemaining(from: start, until: end))
  case .live:
    let words = strings.timeRemainingAroundTimer
    return Text(verbatim: words.before)
      + Text(timerInterval: start...end, countsDown: true, showsHours: true)
      + Text(verbatim: words.after)
  }
}

extension EnvironmentValues {
  /// How the widget's countdowns update: live in the extension, where WidgetKit draws them
  /// against the real clock; the time left at the entry's date when the app draws an entry of
  /// a fixed moment, such as on the Widget states screen.
  var widgetCountdownMode: PrayerCountdown.Mode {
    get { self[WidgetCountdownModeKey.self] }
    set { self[WidgetCountdownModeKey.self] = newValue }
  }
}

private struct WidgetCountdownModeKey: EnvironmentKey {
  static var defaultValue: PrayerCountdown.Mode { .live }
}
