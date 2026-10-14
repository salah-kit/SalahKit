#if canImport(SwiftUI)
  import SalahCore
  import SwiftUI

  /// The look of a ``NextPrayerView``: a card, a widget's main content or a watch complication.
  ///
  /// The configuration's text is `nil` wherever the state doesn't know the next prayer, such as
  /// after the last published day of a timetable. A style must keep that uncertainty visible:
  /// show a placeholder or your own wording, never a time or a countdown of its own.
  ///
  /// ```swift
  /// struct CircularStyle: NextPrayerStyle {
  ///   func makeBody(configuration: Configuration) -> some View {
  ///     VStack {
  ///       configuration.abbreviation ?? Text(verbatim: "–")
  ///       configuration.countdown?.monospacedDigit()
  ///     }
  ///   }
  /// }
  ///
  /// NextPrayerView(state: state, names: names, timeZone: location.timeZone)
  ///   .nextPrayerStyle(CircularStyle())
  /// ```
  ///
  /// Without a style, the view uses ``PlainNextPrayerStyle``.
  @MainActor @preconcurrency
  public protocol NextPrayerStyle {
    /// The view for the next prayer.
    associatedtype Body: View

    /// Makes the view for the next prayer.
    @ViewBuilder func makeBody(configuration: Configuration) -> Body

    /// The state and ready-made text.
    typealias Configuration = NextPrayerConfiguration
  }

  /// What a ``NextPrayerStyle`` draws from.
  public struct NextPrayerConfiguration {
    /// The state the view shows.
    public let state: PrayerState

    /// The next prayer's name in the names' locale, Jumu'ah when the event declares it; `nil`
    /// when the next prayer isn't known.
    public let name: Text?

    /// The next prayer's abbreviation, for compact layouts; `nil` when the next prayer isn't
    /// known. VoiceOver reads it as the full name, so a circular complication that shows "A"
    /// still says "Asr".
    public let abbreviation: Text?

    /// The next prayer's time, as the environment's locale writes a short time, in the view's
    /// time zone; `nil` when the next prayer isn't known.
    public let time: Text?

    /// The countdown to the next prayer, live or static as the view was asked; `nil` when the
    /// next prayer isn't known. It's never made up.
    public let countdown: Text?

    /// The name of the prayer that just started, while it's inside its just-started window;
    /// otherwise `nil`.
    public let justStarted: Text?
  }

  /// The default look: the just-started prayer when there is one, then the next prayer's name,
  /// time and countdown, stacked, in the system's fonts.
  ///
  /// Where the next prayer isn't known, the name and time read as a dash and no countdown is
  /// shown. Each line stays one line and shrinks to fit a narrow space. The view reads as one
  /// element in VoiceOver.
  public struct PlainNextPrayerStyle: NextPrayerStyle {
    /// Creates the plain next-prayer style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
      // Each line stays one line and shrinks to fit, so a narrow complication never breaks a
      // time or a countdown in the middle.
      VStack(alignment: .leading, spacing: 2) {
        if let justStarted = configuration.justStarted {
          justStarted
            .font(.caption)
            .foregroundStyle(.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        (configuration.name ?? Text(verbatim: "–"))
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        (configuration.time ?? Text(verbatim: "–"))
          .font(.subheadline)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        if let countdown = configuration.countdown {
          countdown
            .font(.title2)
            .fontWeight(.semibold)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  extension NextPrayerStyle where Self == PlainNextPrayerStyle {
    /// The default next-prayer style.
    public static var plain: PlainNextPrayerStyle { PlainNextPrayerStyle() }
  }

  extension View {
    /// Sets the style of the ``NextPrayerView``s in this view.
    ///
    /// - Parameter style: The next-prayer style.
    public func nextPrayerStyle(_ style: some NextPrayerStyle) -> some View {
      environment(\.nextPrayerStyle, AnyNextPrayerStyle(style))
    }
  }

  /// A next-prayer style with its type erased, for the environment.
  struct AnyNextPrayerStyle {
    let makeBody: @MainActor (NextPrayerConfiguration) -> AnyView

    @MainActor
    init<Style: NextPrayerStyle>(_ style: Style) {
      makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }
  }

  extension EnvironmentValues {
    /// The style set with `nextPrayerStyle(_:)`, or `nil` for the plain style.
    var nextPrayerStyle: AnyNextPrayerStyle? {
      get { self[NextPrayerStyleKey.self] }
      set { self[NextPrayerStyleKey.self] = newValue }
    }
  }

  private struct NextPrayerStyleKey: EnvironmentKey {
    static var defaultValue: AnyNextPrayerStyle? { nil }
  }
#endif
