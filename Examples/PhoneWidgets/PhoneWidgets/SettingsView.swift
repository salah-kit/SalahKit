import SalahTimes
import SwiftUI
import WidgetKit

/// The widget's settings: the place, the method and the names' language. Every change is saved
/// to the App Group at once, and the screen says whether the save asked for a widget reload.
struct SettingsView: View {
  let store: SettingsStore
  let strings: WidgetStrings
  let clock: AppClock

  private var current: WidgetSettings { store.settings ?? .defaults }

  var body: some View {
    Form {
      if store.settings == nil {
        setupSection
      }
      Section {
        Picker(selection: binding(\.place)) {
          ForEach(Place.presets) { place in
            Text(verbatim: strings.placeName(place)).tag(place)
          }
        } label: {
          Text(verbatim: strings("Place"))
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier("settings.place")
        Picker(selection: methodBinding) {
          ForEach(WidgetSettings.methods, id: \.self) { method in
            Text(verbatim: strings.methodName(method)).tag(method)
          }
        } label: {
          Text(verbatim: strings("Method"))
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier("settings.method")
      } footer: {
        Text(
          verbatim: strings(
            "Tromsø has partial days around midsummer. The invalid coordinates show the unavailable view."
          ))
      }
      Section {
        Picker(selection: binding(\.language)) {
          ForEach(NamesLanguage.allCases, id: \.self) { language in
            Text(verbatim: WidgetStrings.endonym(language)).tag(language)
          }
        } label: {
          Text(verbatim: strings("Language"))
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Text(verbatim: strings("Language")))
        .accessibilityIdentifier("settings.language")
      } header: {
        Text(verbatim: strings("Language"))
      } footer: {
        Text(
          verbatim: strings("The widget's prayer names and words, whatever the phone's language."))
      }
      saveSection
      if let settings = store.settings {
        previewSection(settings)
      }
      Section {
        NavigationLink(value: Screen.states) {
          Text(verbatim: strings("Widget states"))
        }
        .accessibilityIdentifier("open.states")
        NavigationLink(value: Screen.log) {
          Text(verbatim: strings("Widget log"))
        }
        .accessibilityIdentifier("open.log")
      } footer: {
        Text(
          verbatim: strings(
            "Widget states draws the widget's views for every state. Widget log lists what the extension did on each timeline."
          ))
      }
    }
    .navigationTitle(Text(verbatim: "PhoneWidgets"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var setupSection: some View {
    Section {
      Text(verbatim: strings("The widget is waiting for a place."))
        .accessibilityIdentifier("setup.waiting")
      Button {
        store.update { _ in }
      } label: {
        Text(verbatim: strings("Set up with Makkah"))
      }
      .accessibilityIdentifier("setup.start")
    }
  }

  private var saveSection: some View {
    Section {
      Text(verbatim: saveText)
        .accessibilityIdentifier("save.status")
      if store.settings != nil {
        Button {
          store.saveAgain()
        } label: {
          Text(verbatim: strings("Save the same settings again"))
        }
        .accessibilityIdentifier("save.again")
        LabeledContent {
          Text(verbatim: current.fingerprint)
            .font(.footnote.monospaced())
            .accessibilityIdentifier("settings.fingerprint")
        } label: {
          Text(verbatim: strings("Fingerprint"))
        }
      }
    } header: {
      Text(verbatim: strings("Widget"))
    } footer: {
      Text(
        verbatim: strings(
          "A save asks WidgetKit to reload the widget only when the stored settings change."))
    }
  }

  private func previewSection(_ settings: WidgetSettings) -> some View {
    Section {
      let entry = PrayerTimelineProvider.timeline(settings: settings, now: clock.now()).entries[0]
      WidgetFrame(entry: entry, family: .systemMedium)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    } header: {
      Text(verbatim: strings("Preview"))
    }
  }

  private var saveText: String {
    let count = store.saveCount.formatted(.number.locale(strings.locale))
    switch store.lastSave {
    case nil:
      return strings("Not saved in this session.")
    case .reloadRequested?:
      return strings("Save \(count): changed, widget reload requested.")
    case .unchanged?:
      return strings("Save \(count): unchanged, no reload requested.")
    case .failed(let reason)?:
      return strings("Save \(count) failed: \(reason)")
    }
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<WidgetSettings, Value>) -> Binding<Value> {
    Binding {
      current[keyPath: keyPath]
    } set: { value in
      store.update { $0[keyPath: keyPath] = value }
    }
  }

  private var methodBinding: Binding<CalculationMethod> {
    Binding {
      current.method
    } set: { method in
      store.update { $0.choose(method) }
    }
  }
}
