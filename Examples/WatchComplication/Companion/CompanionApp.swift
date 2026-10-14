import SwiftUI
import WatchConnectivity

@main
struct CompanionApp: App {
  @State private var model = CompanionModel(
    options: LaunchOptions(arguments: ProcessInfo.processInfo.arguments))

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        CompanionView(model: model)
      }
      .environment(\.locale, model.strings.locale)
      .environment(\.layoutDirection, model.strings.isRightToLeft ? .rightToLeft : .leftToRight)
    }
  }
}

/// Picks a preset, sends it to the watch and shows the session's state and what was sent.
struct CompanionView: View {
  @Bindable var model: CompanionModel

  private var strings: AppStrings { model.strings }

  var body: some View {
    List {
      Section {
        ForEach(InputsPreset.allCases, id: \.self) { preset in
          Button {
            model.preset = preset
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title(of: preset))
                  .foregroundStyle(.primary)
                Text(verbatim: detail(of: preset))
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              if model.preset == preset {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
                  .accessibilityHidden(true)
              }
            }
            .contentShape(Rectangle())
          }
          .accessibilityAddTraits(model.preset == preset ? .isSelected : [])
          .accessibilityIdentifier("preset.\(preset.rawValue)")
        }
        Button {
          model.send()
        } label: {
          Label {
            Text(verbatim: strings("Send to Apple Watch"))
          } icon: {
            Image(systemName: "applewatch")
          }
        }
        .accessibilityIdentifier("send")
      } header: {
        Text(verbatim: strings("Inputs"))
      } footer: {
        Text(
          verbatim: strings(
            "The watch keeps its own copy and works from it while this app is closed."))
      }

      if let send = model.lastSend {
        Section {
          row(strings("Preset"), title(of: send.preset), id: "sent.preset")
          row(strings("Inputs"), send.fingerprint, id: "sent.fingerprint")
          row(strings("Sent"), strings.dateTime(send.sentAt, in: .current), id: "sent.time")
          row(
            strings("Result"),
            send.error.map { strings("Not sent: \($0)") } ?? strings("Queued for the watch"),
            id: "sent.result")
        } header: {
          Text(verbatim: strings("Last send"))
        }
      }

      Section {
        row(strings("Session"), activationText, id: "session.activation")
        row(strings("Paired"), yesNo(model.link.isPaired), id: "session.paired")
        row(
          strings("Watch app installed"), yesNo(model.link.isWatchAppInstalled),
          id: "session.installed")
        row(strings("Reachable"), yesNo(model.link.isReachable), id: "session.reachable")
        row(
          strings("Current context"), model.link.pendingFingerprint ?? strings("None"),
          id: "session.context")
      } header: {
        Text(verbatim: strings("Apple Watch"))
      }
    }
    .navigationTitle(Text(verbatim: strings("Watch inputs")))
  }

  private func row(_ label: String, _ value: String, id: String) -> some View {
    LabeledContent {
      Text(verbatim: value)
        .multilineTextAlignment(.trailing)
        .accessibilityIdentifier(id)
    } label: {
      Text(verbatim: label)
    }
  }

  private func yesNo(_ value: Bool) -> String {
    value ? strings("Yes") : strings("No")
  }

  private var activationText: String {
    guard model.link.supported else { return strings("Unsupported") }
    switch model.link.activation {
    case .activated: return strings("Activated")
    case .inactive: return strings("Inactive")
    case .notActivated: return strings("Not activated")
    @unknown default: return strings("Unknown")
    }
  }

  private func title(of preset: InputsPreset) -> String {
    switch preset {
    case .makkah: strings("Makkah, calculated")
    case .mosque: strings("Sample Mosque, three days")
    case .mosqueEnded: strings("Sample Mosque, ended")
    }
  }

  private func detail(of preset: InputsPreset) -> String {
    switch preset {
    case .makkah: strings("Umm al-Qura on the watch; never runs out")
    case .mosque: strings("A published timetable from today; runs out in three days")
    case .mosqueEnded: strings("A published timetable whose last day was yesterday")
    }
  }
}
