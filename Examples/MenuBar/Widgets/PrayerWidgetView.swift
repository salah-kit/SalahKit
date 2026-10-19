import AppIntents
import SalahCore
import SalahUI
import SwiftUI
import WidgetKit

/// One entry, in the small or medium family.
struct PrayerWidgetView: View {
  let entry: MenuBarEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    let language: NamesLanguage =
      if case .timeline(_, let context) = entry.content { context.language } else { .english }
    let strings = MenuBarStrings(language: language)
    PrayerWidgetContent(entry: entry, family: family, strings: strings, stop: stopButton(strings))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .environment(\.locale, strings.locale)
      .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
  }

  @ViewBuilder
  private func stopButton(_ strings: MenuBarStrings) -> some View {
    if let playing = entry.nowPlaying {
      PrayerWidgetStopButton(nowPlaying: playing, strings: strings)
    }
  }
}

/// The finite widget's content. Medium schedules keep their full day beside the focus and
/// playback control, so playing a tone does not take height away from the six prayer rows.
struct PrayerWidgetContent<Stop: View>: View {
  let entry: MenuBarEntry
  let family: WidgetFamily
  let strings: MenuBarStrings
  let stop: Stop

  @ViewBuilder var body: some View {
    switch entry.content {
    case .setupRequired:
      playbackColumn {
        Text(verbatim: strings("Open MenuBar to set up prayer times."))
          .font(.callout)
      }
    case .timeline(let state, let context):
      let zone = context.place.location.timeZone
      switch state {
      case .schedule(.available(let prayer, _)):
        HStack(alignment: .top, spacing: 12) {
          playbackColumn {
            NextPrayerView(
              state: prayer, names: strings.names, timeZone: zone, countdown: .staticText,
              selection: .justStartedOrNextEvent)
          }
          if family == .systemMedium, let day = context.day.day {
            PrayerTimesList(day: day, state: prayer, names: strings.names, countdown: .staticText)
              .font(.caption)
          }
        }
      case .schedule(.unavailable(let coverage, _)):
        playbackColumn {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: strings("No prayer times are known now"))
              .font(.callout)
            if let reason = coverage.gaps.first?.reason {
              Text(verbatim: strings.reason(reason))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      case .expired(let knownThrough):
        playbackColumn {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: strings("Open MenuBar to update."))
              .font(.callout)
            Text(
              verbatim: strings("Times shown until \(strings.dayAndTime(knownThrough, in: zone)).")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func playbackColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      content()
      Spacer(minLength: 0)
      stop
    }
  }
}

/// The Stop button: it runs ``StopPlaybackIntent`` in the extension's process.
struct PrayerWidgetStopButton: View {
  let nowPlaying: NowPlaying
  let strings: MenuBarStrings

  var body: some View {
    Button(intent: StopPlaybackIntent()) {
      Label {
        Text(verbatim: strings("Stop"))
      } icon: {
        Image(systemName: "stop.fill")
      }
    }
    .accessibilityLabel(Text(verbatim: label))
  }

  private var label: String {
    guard let alert = nowPlaying.alert else { return strings("Stop the tone") }
    return strings("Stop the tone for \(strings.names.name(of: alert.prayer))")
  }
}
