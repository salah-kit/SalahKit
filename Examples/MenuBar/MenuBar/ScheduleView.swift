import AppKit
import SalahCalculation
import SalahCore
import SalahTimes
import SalahUI
import SwiftUI
import UserNotifications

/// The dropdown: what plays, the next prayer, the day's times, the alerts and the settings.
///
/// Every time and countdown is static text from the display's refresh-plan entry, so the
/// dropdown changes when the menu bar's title does.
struct ScheduleView: View {
  let model: AppModel

  var body: some View {
    let strings = MenuBarStrings(language: model.settings.language)
    VStack(alignment: .leading, spacing: 12) {
      header(strings)
      if let playing = model.live.nowPlaying {
        PlayingBanner(nowPlaying: playing, strings: strings) { model.live.stop() }
      }
      ScheduleSection(content: model.display.content, settings: model.settings, strings: strings)
      Divider()
      AlertsSection(model: model, strings: strings)
      Divider()
      SettingsSection(model: model, strings: strings)
      Divider()
      HStack {
        Button(strings("Play test tone")) { model.playTestTone() }
          .disabled(model.live.nowPlaying != nil)
          .accessibilityIdentifier("playTestTone")
        Spacer()
        Button(strings("Quit")) { NSApplication.shared.terminate(nil) }
          .accessibilityIdentifier("quit")
      }
    }
    .padding(14)
    .frame(width: 330)
    .environment(\.locale, strings.locale)
    .environment(\.layoutDirection, strings.language.isRightToLeft ? .rightToLeft : .leftToRight)
  }

  private func header(_ strings: MenuBarStrings) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: strings.placeName(model.settings.place))
        .font(.headline)
      Text(verbatim: strings.methodName(model.settings.method))
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("header")
  }
}

/// What plays, with the app's own Stop button.
private struct PlayingBanner: View {
  let nowPlaying: NowPlaying
  let strings: MenuBarStrings
  let stop: () -> Void

  var body: some View {
    HStack {
      Image(systemName: "speaker.wave.2.fill")
        .accessibilityHidden(true)
      Text(verbatim: description)
        .accessibilityIdentifier("playingText")
      Spacer()
      Button(strings("Stop"), action: stop)
        .accessibilityLabel(Text(verbatim: strings("Stop the tone")))
        .accessibilityIdentifier("stopButton")
    }
    .padding(8)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("playingBanner")
  }

  private var description: String {
    guard let alert = nowPlaying.alert else { return strings("Playing the test tone") }
    let name = strings.names.name(of: alert.prayer)
    switch alert.kind {
    case .atTime: return strings("Playing the tone for \(name)")
    case .before: return strings("Playing the reminder for \(name)")
    case .after: return strings("Playing the after-reminder for \(name)")
    }
  }
}

/// The next prayer and the day's times, or why they're unknown.
private struct ScheduleSection: View {
  let content: DisplayContent?
  let settings: MenuBarSettings
  let strings: MenuBarStrings

  var body: some View {
    let zone = settings.place.location.timeZone
    VStack(alignment: .leading, spacing: 8) {
      if let content {
        switch content.state {
        case .available(let state, _):
          NextPrayerView(state: state, names: strings.names, timeZone: zone, countdown: .staticText)
            .accessibilityIdentifier("nextPrayer")
        case .unavailable(let coverage, _):
          GapList(
            gaps: coverage.gaps, strings: strings, title: strings("No prayer times are known now"))
        }
        DayList(content: content, strings: strings)
      } else {
        Text(verbatim: strings("The schedule couldn't be planned."))
      }
    }
  }
}

/// The day's times, with the missing ones and why.
private struct DayList: View {
  let content: DisplayContent
  let strings: MenuBarStrings

  var body: some View {
    switch content.day {
    case .available(let day, let coverage):
      PrayerTimesList(
        day: day, state: content.state.prayerState, names: strings.names, countdown: .staticText
      )
      .accessibilityIdentifier("dayList")
      if case .partial(let missing) = coverage {
        ForEach(missing.keys.sorted(), id: \.self) { kind in
          if let reason = missing[kind] {
            Text(verbatim: "\(strings.names.name(of: kind)): \(strings.reason(reason))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    case .unavailable(let reason):
      Text(verbatim: strings.reason(reason))
        .foregroundStyle(.secondary)
    }
  }
}

/// The gaps of an unavailable state.
private struct GapList: View {
  let gaps: [ScheduleGap]
  let strings: MenuBarStrings
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: title)
        .font(.headline)
      ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
        let kinds = gap.kinds.sorted().map(strings.names.name(of:)).joined(separator: ", ")
        Text(verbatim: "\(kinds): \(strings.reason(gap.reason))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("gaps")
  }
}

/// The alerts: on or off, and how far they reach.
private struct AlertsSection: View {
  let model: AppModel
  let strings: MenuBarStrings

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Toggle(
        strings("Prayer alerts"),
        isOn: Binding(
          get: { model.settings.alerts.enabled }, set: { model.setAlertsEnabled($0) })
      )
      .accessibilityIdentifier("alertsToggle")
      // Without the app's tone, notifications play the system's sound.
      Toggle(
        strings("Play the app's tone"),
        isOn: Binding(
          get: { model.settings.alerts.playsTone },
          set: { playsTone in model.change { $0.alerts.playsTone = playsTone } })
      )
      .disabled(!model.settings.alerts.enabled)
      .accessibilityIdentifier("toneToggle")
      Text(verbatim: status)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("alertsStatus")
    }
  }

  private var status: String {
    let zone = model.settings.place.location.timeZone
    guard model.settings.alerts.enabled else { return strings("Alerts are off.") }
    if model.authorization == .denied {
      return strings("Notifications aren't allowed. Allow them in System Settings.")
    }
    var lines: [String] = []
    if let engine = model.alerts.engineSchedule {
      lines.append(strings("Following \(engine.alerts.count) alerts while the app runs."))
    }
    if let report = model.alerts.report {
      let count = report.confirmed.count
      if let until = report.confirmedCoveredUntil {
        lines.append(
          strings("\(count) notifications confirmed until \(strings.dayAndTime(until, in: zone))."))
      } else {
        lines.append(strings("\(count) notifications confirmed."))
      }
    }
    return lines.joined(separator: "\n")
  }
}

/// The place, method, language and reminder.
private struct SettingsSection: View {
  let model: AppModel
  let strings: MenuBarStrings

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Picker(
        strings("Place"),
        selection: Binding(
          get: { model.settings.place.id },
          set: { id in model.change { if let place = Place.preset(id) { $0.place = place } } })
      ) {
        ForEach(Place.presets) { place in
          Text(verbatim: strings.placeName(place)).tag(place.id)
        }
      }
      .accessibilityIdentifier("placePicker")
      Picker(
        strings("Method"),
        selection: Binding(
          get: { model.settings.method }, set: { method in model.change { $0.choose(method) } })
      ) {
        ForEach(MenuBarSettings.methods, id: \.self) { method in
          Text(verbatim: strings.methodName(method)).tag(method)
        }
      }
      .accessibilityIdentifier("methodPicker")
      Picker(
        strings("Language"),
        selection: Binding(
          get: { model.settings.language },
          set: { language in model.change { $0.language = language } })
      ) {
        ForEach(NamesLanguage.allCases, id: \.self) { language in
          Text(verbatim: MenuBarStrings.endonym(language)).tag(language)
        }
      }
      .accessibilityIdentifier("languagePicker")
      Picker(
        strings("Reminder"),
        selection: Binding(
          get: { model.settings.alerts.reminderMinutes ?? 0 },
          set: { minutes in
            model.change { $0.alerts.reminderMinutes = minutes == 0 ? nil : minutes }
          })
      ) {
        Text(verbatim: strings("None")).tag(0)
        ForEach(AlertPreferences.reminderChoices, id: \.self) { minutes in
          Text(verbatim: strings("\(minutes) minutes before")).tag(minutes)
        }
      }
      .accessibilityIdentifier("reminderPicker")
    }
    .pickerStyle(.menu)
  }
}
