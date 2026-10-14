#if canImport(WidgetKit)
  import Foundation
  import SalahCore
  import WidgetKit

  @available(visionOS 26.0, *)
  nonisolated extension PrayerTimelineBuilder {
    /// A WidgetKit timeline from `now` through `now + horizon`, with your entry type.
    ///
    /// The entries are those of ``timeline(from:horizon:)``: each refresh-plan date with its
    /// schedule state, then ``PrayerTimelineState/expired(knownThrough:)`` at the end of the
    /// timeline's validity. The reload policy asks for the next timeline halfway there,
    /// `.after(_:)` the timeline's ``PrayerTimeline/reloadDate``.
    ///
    /// ```swift
    /// func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
    ///   completion(builder.timeline(from: .now) { date, state in
    ///     PrayerEntry(date: date, content: .timeline(state))
    ///   })
    /// }
    /// ```
    ///
    /// A horizon that isn't positive, a ``limit`` below 2 or an invalid `steps` strategy can't
    /// be planned. The timeline then holds a single expired entry at `now` and the policy
    /// `.never`, so the widget shows the problem until the app reloads it; call
    /// ``timeline(from:horizon:)`` to get the error instead.
    ///
    /// - Parameters:
    ///   - now: The first entry's date, usually the moment WidgetKit asked for the timeline.
    ///   - horizon: How far the timeline looks ahead.
    ///   - entry: Makes your entry for a date and what it shows.
    /// - Returns: The timeline for WidgetKit.
    public func timeline<Entry: TimelineEntry>(
      from now: Date, horizon: Duration = defaultHorizon,
      entry: (_ date: Date, _ state: PrayerTimelineState) -> Entry
    ) -> Timeline<Entry> {
      do {
        let timeline = try timeline(from: now, horizon: horizon)
        return Timeline(
          entries: timeline.entries.map { entry($0.date, $0.state) },
          policy: .after(timeline.reloadDate))
      } catch {
        return Timeline(entries: [entry(now, .expired(knownThrough: now))], policy: .never)
      }
    }
  }
#endif
