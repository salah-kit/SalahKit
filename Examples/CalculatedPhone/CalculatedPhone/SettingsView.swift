import SalahCalculation
import SalahCore
import SalahTimes
import SwiftUI

/// The place, the alerts and every calculation control. Changes apply at once and are saved.
struct SettingsView: View {
  let store: SettingsStore
  let alerts: AlertCoordinator
  let strings: PhoneStrings
  @Environment(\.dismiss) private var dismiss

  private var settings: AppSettings { store.settings }
  private var parameters: CalculationParameters { settings.calculation.parameters }
  private var text: CalculationText { CalculationText(strings: strings) }

  var body: some View {
    NavigationStack {
      Form {
        placeSection
        alertsSection
        methodSection
        if settings.method == .custom {
          customSection
        }
        yourChoicesSection
        adjustmentsSection
        storageSection
      }
      .navigationTitle(Text(verbatim: strings("Settings")))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text(verbatim: strings("Done"))
          }
          .accessibilityIdentifier("settings.done")
        }
      }
    }
  }

  // MARK: Sections

  private var placeSection: some View {
    Section {
      Picker(selection: binding(\.place)) {
        ForEach(places) { place in
          Text(verbatim: PhoneSnapshot.placeName(place, strings: strings)).tag(place)
        }
      } label: {
        Text(verbatim: strings("Place"))
      }
      .pickerStyle(.navigationLink)
      .accessibilityIdentifier("settings.place")
    } footer: {
      Text(verbatim: placeFooter)
    }
  }

  private var alertsSection: some View {
    Section {
      Toggle(isOn: alertsBinding) {
        Text(verbatim: strings("Prayer alerts"))
      }
      .accessibilityIdentifier("settings.alerts")
      Picker(selection: reminderBinding) {
        ForEach(PhoneAlertOptions.reminderChoices, id: \.self) { minutes in
          Text(verbatim: reminderName(minutes)).tag(minutes)
        }
      } label: {
        Text(verbatim: strings("Reminder before each prayer"))
      }
      .pickerStyle(.navigationLink)
      .disabled(!settings.alerts.isOn)
      .accessibilityIdentifier("settings.reminder")
    } header: {
      Text(verbatim: strings("Alerts"))
    } footer: {
      Text(
        verbatim: strings(
          "Alerts are scheduled as notifications for the next 14 days, within iOS's limit on pending notifications, and the app schedules them again whenever it opens."
        ))
    }
  }

  private func reminderName(_ minutes: Int?) -> String {
    guard let minutes else { return strings("No reminder") }
    return strings("\(text.format.number(Double(minutes))) min")
  }

  private var alertsBinding: Binding<Bool> {
    Binding(
      get: { store.settings.alerts.isOn },
      set: { isOn in
        guard isOn else {
          store.update { $0.alerts.isOn = false }
          return
        }
        // The app asks for permission when the user turns alerts on, then plans them.
        Task {
          await alerts.requestPermissionIfNeeded()
          store.update { $0.alerts.isOn = true }
        }
      })
  }

  private var reminderBinding: Binding<Int?> {
    Binding(
      get: { store.settings.alerts.reminderMinutes },
      set: { minutes in store.update { $0.alerts.reminderMinutes = minutes } })
  }

  private var methodSection: some View {
    Section {
      Picker(selection: methodBinding) {
        ForEach(MethodChoice.all, id: \.self) { choice in
          Text(verbatim: text.name(of: choice)).tag(choice)
        }
      } label: {
        Text(verbatim: strings("Method"))
      }
      .pickerStyle(.navigationLink)
      .accessibilityIdentifier("settings.method")
      if let suggested = settings.suggestedMethod, settings.method != .preset(suggested) {
        Button {
          store.update { $0.choose(.preset(suggested)) }
        } label: {
          Text(verbatim: strings("Use the suggested method: \(text.name(of: suggested))"))
        }
        .accessibilityIdentifier("settings.suggested")
      }
      Titled(title: strings("Rounding")) {
        Picker(selection: customBinding(\.rounding)) {
          ForEach(Rounding.allCases, id: \.self) { rounding in
            Text(verbatim: roundingShortName(rounding)).tag(rounding)
          }
        } label: {
          Text(verbatim: strings("Rounding"))
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Text(verbatim: strings("Rounding")))
        .accessibilityIdentifier("settings.rounding")
      }
    } header: {
      Text(verbatim: strings("Method"))
    } footer: {
      Text(
        verbatim: strings(
          "A method sets the Fajr, Maghrib and Isha rules, the night, its own minutes and the rounding. Changing any of them switches to Custom."
        ))
    }
  }

  private var customSection: some View {
    Section {
      if case .angle(let angle) = parameters.fajr {
        Stepper(value: fajrAngleBinding(angle), in: 0...30, step: 0.5) {
          Text(verbatim: strings("Fajr angle: \(text.degrees(angle))"))
        }
        .accessibilityIdentifier("settings.fajrAngle")
      } else {
        LabeledContent {
          Button {
            store.update { $0.customize { $0.fajr = .angle(18) } }
          } label: {
            Text(verbatim: strings("Use an angle"))
          }
          .accessibilityIdentifier("settings.fajrUseAngle")
        } label: {
          Text(verbatim: strings("Fajr: \(text.text(parameters.fajr))"))
        }
      }
      Titled(title: strings("Isha rule")) {
        Picker(selection: ishaKindBinding) {
          Text(verbatim: strings("Angle")).tag(IshaKind.angle)
          Text(verbatim: strings("Minutes")).tag(IshaKind.interval)
          Text(verbatim: strings("Committee")).tag(IshaKind.committee)
        } label: {
          Text(verbatim: strings("Isha rule"))
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Text(verbatim: strings("Isha rule")))
        .accessibilityIdentifier("settings.ishaRule")
      }
      switch parameters.isha {
      case .angle(let angle):
        Stepper(value: ishaAngleBinding(angle), in: 0...30, step: 0.5) {
          Text(verbatim: strings("Isha angle: \(text.degrees(angle))"))
        }
        .accessibilityIdentifier("settings.ishaValue")
      case .minutesAfterMaghrib(let minutes):
        Stepper(value: ishaMinutesBinding(minutes), in: 0...180, step: 5) {
          Text(verbatim: strings("Isha: \(text.minutes(minutes)) after Maghrib"))
        }
        .accessibilityIdentifier("settings.ishaValue")
      case .moonsightingCommittee:
        Text(verbatim: strings("Isha: \(text.text(parameters.isha))"))
      }
      Picker(selection: customBinding(\.nightSpan)) {
        ForEach(NightSpan.allCases, id: \.self) { span in
          Text(verbatim: text.name(of: span)).tag(span)
        }
      } label: {
        Text(verbatim: strings("Night"))
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("settings.nightSpan")
    } header: {
      Text(verbatim: strings("Custom method"))
    } footer: {
      Text(verbatim: strings("Maghrib: \(text.text(parameters.maghrib))"))
    }
  }

  private var yourChoicesSection: some View {
    Section {
      Titled(title: strings("Asr (madhab)")) {
        Picker(selection: parameterBinding(\.madhab)) {
          ForEach(Madhab.allCases, id: \.self) { madhab in
            Text(verbatim: text.name(of: madhab)).tag(madhab)
          }
        } label: {
          Text(verbatim: strings("Asr (madhab)"))
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Text(verbatim: strings("Asr (madhab)")))
        .accessibilityIdentifier("settings.madhab")
      }
      Picker(selection: parameterBinding(\.highLatitudeRule)) {
        ForEach(HighLatitudeRule.allCases, id: \.self) { rule in
          Text(verbatim: text.name(of: rule)).tag(rule)
        }
      } label: {
        Text(verbatim: strings("High latitudes"))
      }
      .pickerStyle(.navigationLink)
      .accessibilityIdentifier("settings.highLatitudeRule")
      Toggle(isOn: ramadanBinding) {
        Text(verbatim: strings("Isha 120 min after Maghrib in Ramadan"))
      }
      .accessibilityIdentifier("settings.ramadanIsha")
    } header: {
      Text(verbatim: strings("Your choices"))
    } footer: {
      Text(
        verbatim: strings(
          "These stay when you change the method. The Ramadan rule changes only an Isha set in minutes after Maghrib."
        ))
    }
  }

  private var adjustmentsSection: some View {
    Section {
      ForEach(PrayerKind.allCases, id: \.self) { kind in
        let minutes = parameters.adjustments[kind]
        Stepper(value: adjustmentBinding(kind), in: -60...60) {
          Text(
            verbatim: strings(
              "\(strings.names.name(of: kind)): \(text.format.signed(minutes)) min"))
        }
        .accessibilityIdentifier("settings.adjust.\(kind.rawValue)")
      }
    } header: {
      Text(verbatim: strings("Your minutes"))
    } footer: {
      Text(verbatim: strings("Added on top of the method's own minutes."))
    }
  }

  private var storageSection: some View {
    Section {
      Text(verbatim: store.savedJSON)
        .font(.caption.monospaced())
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityIdentifier("settings.json")
    } header: {
      Text(verbatim: strings("Saved settings"))
    } footer: {
      Text(
        verbatim: strings(
          "Stored as JSON in UserDefaults and decoded at launch. The calculation is SalahCalculation's CalculationSettings, whole."
        ))
    }
  }

  // MARK: Values

  /// The presets, and the current place when it came from coordinates.
  private var places: [Place] {
    Place.presets.contains(settings.place) ? Place.presets : Place.presets + [settings.place]
  }

  private var placeFooter: String {
    let location = settings.place.location
    let format = text.format
    return strings(
      "\(format.number(location.latitude)), \(format.number(location.longitude)), \(location.timeZone.identifier)"
    )
  }

  private func roundingShortName(_ rounding: Rounding) -> String {
    switch rounding {
    case .nearest: strings("Nearest")
    case .up: strings("Up")
    case .none: strings("Seconds")
    }
  }

  private enum IshaKind: Hashable {
    case angle, interval, committee
  }

  // MARK: Bindings

  private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
    Binding(
      get: { store.settings[keyPath: keyPath] },
      set: { value in store.update { $0[keyPath: keyPath] = value } })
  }

  /// A parameter that is the user's own: changing it keeps the method.
  private func parameterBinding<Value>(
    _ keyPath: WritableKeyPath<CalculationParameters, Value>
  ) -> Binding<Value> {
    let parameters: WritableKeyPath<AppSettings, CalculationParameters> = \.calculation.parameters
    return binding(parameters.appending(path: keyPath))
  }

  /// A parameter that methods define: changing it switches to Custom.
  private func customBinding<Value: Equatable>(
    _ keyPath: WritableKeyPath<CalculationParameters, Value>
  ) -> Binding<Value> {
    Binding(
      get: { store.settings.calculation.parameters[keyPath: keyPath] },
      set: { value in
        guard value != store.settings.calculation.parameters[keyPath: keyPath] else { return }
        store.update { $0.customize { $0[keyPath: keyPath] = value } }
      })
  }

  private func fajrAngleBinding(_ angle: Double) -> Binding<Double> {
    Binding(
      get: { angle },
      set: { value in store.update { $0.customize { $0.fajr = .angle(value) } } })
  }

  private var methodBinding: Binding<MethodChoice> {
    Binding(
      get: { store.settings.method },
      set: { choice in store.update { $0.choose(choice) } })
  }

  private var ishaKindBinding: Binding<IshaKind> {
    Binding(
      get: {
        switch store.settings.calculation.parameters.isha {
        case .angle: .angle
        case .minutesAfterMaghrib: .interval
        case .moonsightingCommittee: .committee
        }
      },
      set: { kind in
        let rule: IshaRule =
          switch kind {
          case .angle: .angle(17)
          case .interval: .minutesAfterMaghrib(90)
          case .committee: .moonsightingCommittee(.general)
          }
        store.update { $0.customize { $0.isha = rule } }
      })
  }

  private func ishaAngleBinding(_ angle: Double) -> Binding<Double> {
    Binding(
      get: { angle },
      set: { value in store.update { $0.customize { $0.isha = .angle(value) } } })
  }

  private func ishaMinutesBinding(_ minutes: Int) -> Binding<Int> {
    Binding(
      get: { minutes },
      set: { value in store.update { $0.customize { $0.isha = .minutesAfterMaghrib(value) } } })
  }

  private var ramadanBinding: Binding<Bool> {
    Binding(
      get: { store.settings.calculation.parameters.ramadanIsha != .off },
      set: { on in
        store.update { $0.calculation.parameters.ramadanIsha = on ? AppSettings.ramadanRule : .off }
      })
  }

  private func adjustmentBinding(_ kind: PrayerKind) -> Binding<Int> {
    Binding(
      get: { store.settings.calculation.parameters.adjustments[kind] },
      set: { value in store.update { $0.calculation.parameters.adjustments[kind] = value } })
  }
}

/// A title above a segmented picker, which a Form doesn't show for that style. VoiceOver reads
/// the picker's own label instead.
private struct Titled<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: title)
        .accessibilityHidden(true)
      content
    }
  }
}

extension PrayerAdjustments {
  /// The minutes for a kind.
  nonisolated subscript(kind: PrayerKind) -> Int {
    get {
      switch kind {
      case .fajr: fajr
      case .sunrise: sunrise
      case .dhuhr: dhuhr
      case .asr: asr
      case .maghrib: maghrib
      case .isha: isha
      }
    }
    set {
      switch kind {
      case .fajr: fajr = newValue
      case .sunrise: sunrise = newValue
      case .dhuhr: dhuhr = newValue
      case .asr: asr = newValue
      case .maghrib: maghrib = newValue
      case .isha: isha = newValue
      }
    }
  }
}
