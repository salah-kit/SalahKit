#if canImport(SwiftUI)
  import SalahCore
  import SwiftUI

  /// The look of each row in a ``PrayerTimesList``.
  ///
  /// A style gets the row's facts and ready-made text, and decides only how they look. Which
  /// prayer is next, and whether a countdown can be shown at all, is decided before the style
  /// is called:
  ///
  /// ```swift
  /// struct LanternRow: PrayerRowStyle {
  ///   func makeBody(configuration: Configuration) -> some View {
  ///     HStack {
  ///       configuration.name.font(.title3)
  ///       Spacer()
  ///       configuration.time.monospacedDigit()
  ///     }
  ///     .padding(8)
  ///     .background(configuration.status == .next(approaching: true) ? .orange.opacity(0.2) : .clear,
  ///                 in: .capsule)
  ///   }
  /// }
  ///
  /// PrayerTimesList(day: day, state: state, names: names)
  ///   .prayerRowStyle(LanternRow())
  /// ```
  ///
  /// Without a style, rows use ``PlainPrayerRowStyle``.
  @MainActor @preconcurrency
  public protocol PrayerRowStyle {
    /// The view for one row.
    associatedtype Body: View

    /// Makes the view for one row.
    @ViewBuilder func makeBody(configuration: Configuration) -> Body

    /// The row's facts and text.
    typealias Configuration = PrayerRowConfiguration
  }

  /// What a ``PrayerRowStyle`` draws one row from.
  public struct PrayerRowConfiguration {
    /// The event the row shows.
    public let event: PrayerEvent

    /// How the event relates to the state: passed, just started, next or upcoming. `nil` when
    /// the list has no known state, as while the schedule is unavailable: show no status then.
    public let status: PrayerEventStatus?

    /// The event's name in the names' locale: Jumu'ah when the event declares it.
    public let name: Text

    /// The event's time, as the environment's locale writes a short time, in the day's time
    /// zone rather than the device's.
    public let time: Text

    /// The civil days from the event's owning day to the date it occurs on, in the day's time
    /// zone: 1 for an Isha after midnight, -1 for a Fajr before it, otherwise 0.
    public let dayOffset: Int

    /// The day offset as signed text in the locale's digits, such as `+1`; `nil` when the
    /// offset is 0.
    public let dayOffsetText: Text?

    /// The countdown to the event when it's the next one, live or static as the list was asked;
    /// otherwise `nil`.
    public let countdown: Text?
  }

  /// The default row: the name on the leading side, then the countdown and the time on the
  /// trailing side, in the system's fonts and colors.
  ///
  /// The next event is bold in the tint color, a prayer that just started is bold, and events
  /// that have passed are secondary. A time on another civil date than its owning day carries
  /// its offset, such as `+1`. The countdown and the time never wrap; in a narrow row the name
  /// truncates instead. The row reads as one element in VoiceOver: the name,
  /// the countdown on the next event's row, then the time and its offset. Statuses are visual
  /// only, because saying "next" or "passed" takes interface text, which is your app's; a style
  /// that announces them adds its own words with `accessibilityValue(_:)`.
  public struct PlainPrayerRowStyle: PrayerRowStyle {
    /// Creates the plain row style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
      let emphasized: Bool
      let foreground: AnyShapeStyle
      switch configuration.status {
      case .next?:
        emphasized = true
        foreground = AnyShapeStyle(.tint)
      case .justStarted?:
        emphasized = true
        foreground = AnyShapeStyle(.primary)
      case .passed?:
        emphasized = false
        foreground = AnyShapeStyle(.secondary)
      case .upcoming?, nil:
        emphasized = false
        foreground = AnyShapeStyle(.primary)
      }
      // Numbers never wrap: "4:14:00" broken over two lines could read as "4:14:0". When the
      // row is too narrow, the name truncates instead.
      return HStack(alignment: .firstTextBaseline, spacing: 8) {
        configuration.name
          .lineLimit(1)
        Spacer(minLength: 8)
        if let countdown = configuration.countdown {
          countdown
            .font(.footnote)
            .monospacedDigit()
            .fixedSize()
        }
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          configuration.time
            .monospacedDigit()
          if let offset = configuration.dayOffsetText {
            offset
              .font(.caption2)
          }
        }
        .fixedSize()
      }
      .fontWeight(emphasized ? .semibold : .regular)
      .foregroundStyle(foreground)
      .padding(.vertical, 3)
      .accessibilityElement(children: .combine)
    }
  }

  extension PrayerRowStyle where Self == PlainPrayerRowStyle {
    /// The default row style.
    public static var plain: PlainPrayerRowStyle { PlainPrayerRowStyle() }
  }

  extension View {
    /// Sets the style of the ``PrayerTimesList`` rows in this view.
    ///
    /// - Parameter style: The row style.
    public func prayerRowStyle(_ style: some PrayerRowStyle) -> some View {
      environment(\.prayerRowStyle, AnyPrayerRowStyle(style))
    }
  }

  /// A row style with its type erased, for the environment.
  struct AnyPrayerRowStyle {
    let makeBody: @MainActor (PrayerRowConfiguration) -> AnyView

    @MainActor
    init<Style: PrayerRowStyle>(_ style: Style) {
      makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }
  }

  extension EnvironmentValues {
    /// The row style set with `prayerRowStyle(_:)`, or `nil` for the plain style.
    var prayerRowStyle: AnyPrayerRowStyle? {
      get { self[PrayerRowStyleKey.self] }
      set { self[PrayerRowStyleKey.self] = newValue }
    }
  }

  private struct PrayerRowStyleKey: EnvironmentKey {
    static var defaultValue: AnyPrayerRowStyle? { nil }
  }
#endif
