# RFC 0004: SalahWidgets and SalahUI

- **Status:** Draft, shipped in 0.2.0. The 0.2 consumers, `PhoneWidgets` and `WatchComplication`, and the 0.3 consumer, `MenuBar`, have reported: their findings are in §9. Open to findings from Salah's migration and other adopters until 1.0 (STANDARD.md, Releases).
- **Products:** SalahWidgets, SalahUI.
- **Discussion:** [salah-kit/SalahKit#9](https://github.com/salah-kit/SalahKit/discussions/9).
- **Started:** 2026-10-14.
- **Supersedes:** the sketches in the SalahKit proposal, §7.3 and §7.4.
- **Depends on:** RFC 0001 (SalahCore: state §4.7, refresh planning §4.8, names and durations §4.9).

SalahWidgets turns SalahCore's refresh plans into widget timelines that the widget extension builds by itself, shares an app's inputs through an App Group, and signals a running app. SalahUI gives SwiftUI components that decide what a schedule's state lets a view show, with styles that decide how it looks, and the color math of Salah's theme editor. This RFC fixes their API and behavior.

References like "§7.3" point to the SalahKit proposal; "Core §4.8" points to RFC 0001.

---

## 1. Summary

An app saves its inputs (calculation settings or published rows) with `SharedValue`, which asks WidgetKit to reload only when the stored value changed. The widget extension loads them, builds a `PrayerSchedule` and asks `PrayerTimelineBuilder` for a timeline: SalahCore's refresh-plan entries over 48 hours, then an explicit `.expired(knownThrough:)` entry, with a reload requested halfway. No step depends on the app running since the last timeline. `DarwinSignal` covers the few actions that need a running app.

SalahUI's `PrayerTimesList`, `NextPrayerView` and `PrayerCountdown` read a `PrayerState` and give styles ready-made text, or `nil` wherever the state doesn't know. Times are written in the schedule's zone and the environment's locale. `ThemeColor` and `ContrastCheck` check a theme against WCAG contrast and an app's reserved colors.

## 2. Scope

In SalahWidgets 0.2:
- `SharedValue` and `SharedValueError`;
- `PrayerTimelineState`, `PrayerTimeline`, `PrayerTimelineBuilder` and its WidgetKit `Timeline`;
- `DarwinSignal` and its `Observation`;
- a privacy manifest declaring App Group `UserDefaults` access (`1C8F.1`).

In SalahUI 0.2:
- `PrayerTimesList`, `NextPrayerView`, `PrayerCountdown`;
- `PrayerRowStyle`, `PrayerRowConfiguration`, `PlainPrayerRowStyle`; `NextPrayerStyle`, `NextPrayerConfiguration`, `PlainNextPrayerStyle`; `prayerRowStyle(_:)` and `nextPrayerStyle(_:)`;
- `ThemeColor` (with `color` in SwiftUI) and `ContrastCheck`.

Not in these products:
- App Intents and widget configurations (the app's, as in the extraction plan; §3.1);
- interface text other than prayer names (each app's catalog); the components' default styles use only names, times, digits and a dash;
- Salah's palettes, fonts and widget designs, which stay in Salah (§7.4);
- a durable command queue between extension and app: a signal reaches only a running receiver (§5.3);
- notifications (SalahAlerts) and Live Activities (after 1.0).

## 3. Public API

```swift
import SalahCore

// MARK: SalahWidgets

nonisolated public struct SharedValue<Value: Codable & Equatable & Sendable>: Sendable {
  public let appGroup: String                         // the UserDefaults suite name
  public let key: String
  public init(appGroup: String, key: String)          // reloads through WidgetKit
  public init(appGroup: String, key: String,
              reloadTimelines: @escaping @Sendable (_ widgetKinds: [String]) -> Void)
  public func load() -> Value?                        // nil when missing or undecodable
  /// Returns whether the stored value changed; reloads exactly then, for non-empty kinds.
  @discardableResult
  public func save(_ value: Value?, reloading widgetKinds: [String] = []) throws(SharedValueError) -> Bool
}

nonisolated public enum SharedValueError: Error, Hashable, Sendable {
  case appGroupUnavailable(String)
  case encodingFailed(String)
}

nonisolated public enum PrayerTimelineState: Hashable, Sendable {
  case schedule(ScheduleState)
  case expired(knownThrough: Date)
  public var prayerState: PrayerState? { get }
}

nonisolated public struct PrayerTimeline: Hashable, Sendable {
  public struct Entry: Hashable, Sendable {
    public var date: Date
    public var state: PrayerTimelineState
    public init(date: Date, state: PrayerTimelineState)
  }
  public var horizon: DateInterval
  public var entries: [Entry]                         // ends with .expired at validUntil
  public var validUntil: Date
  public var reloadDate: Date                         // halfway from the first entry
  public var isTruncated: Bool { get }                // validUntil < horizon.end
}

nonisolated public struct PrayerTimelineBuilder: Sendable {
  public static let defaultHorizon: Duration          // 48 hours
  public let schedule: PrayerSchedule
  public let policy: StatePolicy
  public let strategy: RefreshStrategy
  public let limit: Int                               // counts the expired entry
  public init(schedule: PrayerSchedule, policy: StatePolicy = StatePolicy(),
              strategy: RefreshStrategy = .stateChanges, limit: Int = 96)
  public func timeline(from now: Date, horizon: Duration = defaultHorizon)
    throws(RefreshPlanError) -> PrayerTimeline
}

#if canImport(WidgetKit)
@available(visionOS 26.0, *)
extension PrayerTimelineBuilder {
  public func timeline<Entry: TimelineEntry>(
    from now: Date, horizon: Duration = defaultHorizon,
    entry: (_ date: Date, _ state: PrayerTimelineState) -> Entry) -> Timeline<Entry>
}
#endif

#if canImport(notify)
nonisolated public struct DarwinSignal: Hashable, Sendable {
  public let name: String
  public init(name: String)
  @discardableResult public func post() -> Bool
  @MainActor public func observe(_ handler: @escaping @MainActor () -> Void) -> Observation
  @MainActor public final class Observation {
    public var isActive: Bool { get }
    public func cancel()
  }
}
#endif

// MARK: SalahUI

#if canImport(SwiftUI)
public struct PrayerTimesList: View {
  public init(day: PrayerDay, state: PrayerState?, names: PrayerNames,
              countdown: PrayerCountdown.Mode = .live)
}
public struct NextPrayerView: View {
  public init(state: PrayerState, names: PrayerNames, timeZone: TimeZone,
              countdown: PrayerCountdown.Mode = .live)
}
public struct PrayerCountdown: View {
  nonisolated public enum Mode: Hashable, Sendable { case live, staticText }
  public init(to event: PrayerEvent, at date: Date, mode: Mode = .live)
}

@MainActor @preconcurrency public protocol PrayerRowStyle {
  associatedtype Body: View
  @ViewBuilder func makeBody(configuration: Configuration) -> Body
  typealias Configuration = PrayerRowConfiguration
}
public struct PrayerRowConfiguration {
  public let event: PrayerEvent
  public let status: PrayerEventStatus?               // nil without a known state
  public let name: Text
  public let time: Text
  public let dayOffset: Int                           // +1 after midnight, -1 before
  public let dayOffsetText: Text?
  public let countdown: Text?                         // the next event's row only
}
public struct PlainPrayerRowStyle: PrayerRowStyle { public init() }

@MainActor @preconcurrency public protocol NextPrayerStyle {
  associatedtype Body: View
  @ViewBuilder func makeBody(configuration: Configuration) -> Body
  typealias Configuration = NextPrayerConfiguration
}
public struct NextPrayerConfiguration {
  public let state: PrayerState
  public let name: Text?                              // nil when nextPrayer is unknown
  public let abbreviation: Text?
  public let time: Text?
  public let countdown: Text?                         // never made up
  public let justStarted: Text?
}
public struct PlainNextPrayerStyle: NextPrayerStyle { public init() }

extension PrayerRowStyle where Self == PlainPrayerRowStyle { public static var plain: Self { get } }
extension NextPrayerStyle where Self == PlainNextPrayerStyle { public static var plain: Self { get } }
extension View {
  public func prayerRowStyle(_ style: some PrayerRowStyle) -> some View
  public func nextPrayerStyle(_ style: some NextPrayerStyle) -> some View
}
#endif

nonisolated public struct ThemeColor: Codable, Hashable, Sendable {
  public var red, green, blue, opacity: Double
  public init(red: Double, green: Double, blue: Double, opacity: Double = 1)
  public var relativeLuminance: Double { get }
  public static func contrastRatio(_ first: ThemeColor, _ second: ThemeColor) -> Double
  public func adjustedForContrast(against surface: ThemeColor, ratio: Double = 4.5) -> ThemeColor
  public func distance(to other: ThemeColor) -> Double
}
// In SwiftUI: extension ThemeColor { public var color: Color { get } }

nonisolated public struct ContrastCheck: Hashable, Sendable {
  public enum Problem: Hashable, Sendable {
    case lowContrast(Double), tooCloseToReserved(ThemeColor)
  }
  public var minimumContrast: Double                  // 3
  public var minimumReservedDistance: Double          // 0.28
  public init(minimumContrast: Double = 3, minimumReservedDistance: Double = 0.28)
  public func problems(foreground: ThemeColor, background: ThemeColor,
                       reserved: [ThemeColor] = []) -> [Problem]
}
```

## 4. Behavior

### 4.1 `SharedValue`

- The value is stored as JSON data (`JSONEncoder` defaults) in `UserDefaults(suiteName: appGroup)` under `key`, read again on every call. Reads use the App Group's own storage (`persistentDomain(forName: appGroup)`): a default registered in the process or passed as a launch argument isn't shared, so it's neither loaded nor compared with. `load()` returns `nil` when nothing is stored or the data doesn't decode as `Value`.
- **Reload gating.** `save(v)` decodes what's stored and compares it with `v` by `==`. The stored value changed when nothing was stored, when the stored value differs, or when the stored data doesn't decode. An unchanged value isn't written and reloads nothing. A changed one is written, then `reloadTimelines(widgetKinds)` is called once when `widgetKinds` isn't empty. `save(nil)` removes the key; it changed when anything was stored. The return value is whether the stored value changed.
- **Errors.** `appGroupUnavailable` when `UserDefaults(suiteName:)` returns `nil` (for example `NSGlobalDomain`), and `encodingFailed` with the encoder's message (for example a `Double` that isn't finite). Either way nothing is written or reloaded. Encoding happens before any comparison.
- **Reloads.** `init(appGroup:key:)` reloads with `WidgetCenter.shared.reloadTimelines(ofKind:)` per kind, on iOS, macOS, watchOS and visionOS 26 or later. Without WidgetKit (tvOS, Linux) it stores only. The injected function of the other initializer replaces WidgetKit entirely.
- **Concurrency.** No locking: a read-compare-write from two processes at once can both report a change. Give each key one writer, usually the app. Cross-process visibility is the system's (`cfprefsd`).
- A generic type has no stored static properties, so a value declared once for app and extension is a computed `static var` in a constrained extension. The proposal's `static let` doesn't compile.
- **Targets that default to main-actor isolation** (new Xcode projects do). There, `struct S: Codable, Equatable, Sendable` gets main-actor-isolated conformances (isolated conformances, Swift 6.2), which can't satisfy `SharedValue`'s `Sendable` parameter, and a static in `extension SharedValue where Value == S` is main-actor-isolated. Declare both `nonisolated`, and the widget's provider and entry too, since WidgetKit calls them off the main thread. The article and the README show it.

### 4.2 Timelines

`timeline(from: n, horizon: h)` calls `schedule.refreshPlan(from: n, through: n + h, strategy:, policy:, limit:)` (Core §4.8) and returns:
- `horizon` and `validUntil`: the plan's;
- `entries`: each plan entry as `.schedule(state)` at its date, then `.expired(knownThrough: validUntil)` at `validUntil`. The plan reserves one slot for this entry, so a timeline holds at most `limit` entries;
- `reloadDate`: `horizon.start + (validUntil − horizon.start) / 2`;
- errors: the plan's (`nonPositiveHorizon`, `limitTooSmall`, `invalidStrategy`), in its order.

The states use Core §4.8's lookahead (`start(civil(end) + 2)`), so an entry near the end of the horizon still names a prayer just after it. Between two entries, the shown state is the earlier entry's, which by Core §4.7 equals `state(at:)` at every instant up to the next entry: the fixed-clock tests check exactly that.

The WidgetKit `timeline(from:horizon:entry:)` maps each entry through `entry` and uses the policy `.after(reloadDate)`. For inputs the plan rejects, it returns one entry, `entry(n, .expired(knownThrough: n))`, with the policy `.never`: a widget shows the problem instead of crashing, and the app's next changed save reloads it.

Distinct states, distinct meanings (§7.3):
- a source gap is a `.schedule(...)` state inside the timeline: partial (known previous, unknown next) or `.unavailable` with its coverage. A reload can't fill it;
- `.expired` is the end of this timeline's validity, even for a calculated source with no end of its own.

With `.stateChanges` and the default policy, a 48-hour timeline has 34 entries (three a prayer, plus sunrise, plus the start and the expired entry; 33 to 35 depending on the start). One-minute steps within 30 minutes of each prayer fill 96 entries in about 1.5 to 12 hours, depending on the place, the season and the start (the night after Isha has only coarse steps; measured over a week of starts at Makkah, Jakarta, Karachi, Cairo and London in winter); the timeline is then truncated and reloads after half of that. Such entries are closer than WidgetKit's guidance of about five minutes.

### 4.3 `DarwinSignal`

- `post()` is `notify_post(name)`; it returns whether the system accepted the post, not whether anyone observed it.
- `observe` registers with `notify_register_dispatch` on a private serial queue and calls the handler through `Task { @MainActor in … }`. Nothing assumes the main queue is the main thread: a process that calls `dispatchMain()` services the main queue from another thread, where `MainActor.assumeIsolated` traps and a block that inherits main-actor isolation fails the runtime's check (§6.3). The registration block is `@Sendable` for that reason.
- The hop holds the handler weakly through an object only the observation owns, so after `cancel()` or release, a signal that arrived while the main actor was busy calls nothing. `cancel()` is idempotent; `isActive` is `false` when registration failed or after cancel.
- No payload, no queueing, no launch: posts while nothing observes are lost, and close posts may coalesce. The receiver acts on the signal, not on a value stored beside it, which can lag across processes (Salah's stop button, §7.3 "Live state").
- Apple platforms only (`canImport(notify)`).

### 4.4 Components

- **`PrayerTimesList`** shows `day.events` in order, one row each. A row's `status` is `state?.status(of:)` (Core §4.7), `nil` without a state; its `countdown` is set only when the status is `.next`, from `state.date` to the event. `dayOffset` is `civil(event.time) − event.scheduleDay` in `day.timeZone`; `dayOffsetText` writes it with a sign in the locale's digits (`+1`, `+١`), `nil` for 0.
- **`NextPrayerView`** reads `state.nextPrayer`: its name (Jumu'ah when declared, Core §4.9), abbreviation, time and countdown, all `nil` when it's unknown; and `state.justStarted`'s name. The abbreviation's accessibility label is the full name, so VoiceOver says "Asr" where a compact style shows "A". An unavailable schedule state has no `PrayerState`; apps word it themselves.
- **`PrayerCountdown`** and every countdown text: `.live` is `Text(timerInterval: date...max(date, event.time), countsDown: true, showsHours: true)`; `.staticText` is `PrayerDurationFormat.string(seconds, locale:)` (compact, rounded down) with the spoken form as its accessibility label. Both show zero for an event already started.
- **Clock and locale.** Times are `Date.FormatStyle(date: .omitted, time: .shortened)` in the schedule's zone (`day.timeZone`, or `timeZone`) and the environment's locale and its calendar, never the device's zone. Names come from the `PrayerNames` passed in, in their own locale.

### 4.5 Styles

- The style protocols follow `ButtonStyle`: `@MainActor`, a `makeBody(configuration:)` and a `Configuration` alias. `prayerRowStyle(_:)` and `nextPrayerStyle(_:)` store a type-erased style in the environment, so a style applies to every list or view below it; without one, the plain style draws.
- `PlainPrayerRowStyle`: name leading; countdown, time and day offset trailing; next row semibold in the tint color, just-started semibold, passed rows secondary, rows without a status neutral; vertical padding of 3 points; one accessibility element (name, countdown, time, offset). The countdown and the time never wrap: a row too narrow for everything leaves out the countdown (`ViewThatFits`), so the name stays whole, and only a row too narrow for the name and the time truncates the name.
- `PlainNextPrayerStyle`: just-started name in the tint color (caption), name (headline) and time (subheadline, secondary), a dash for each when unknown, then the countdown (title 2, semibold) when known; one accessibility element. Each line stays one line and shrinks to fit (to 70 %, the countdown to 50 %).
- The default styles use only text styles, so they follow Dynamic Type, and only stacks, so they mirror for right-to-left layouts.

### 4.6 Theme tools

- `relativeLuminance` is WCAG 2's (`0.03928` threshold); `contrastRatio` is `(L1 + 0.05) / (L2 + 0.05)`; `distance` is the Euclidean distance of the sRGB components (0 to √3). All three equal Salah's `GuidanceColorSpec` at `4bc00e9` for components in 0…1; outside it, a component counts as the nearest end, and NaN as 0.
- `adjustedForContrast(against:ratio:)` returns the color unchanged when it reaches `ratio`; otherwise it moves the components toward white (surface luminance below 0.5) or black in 20 equal steps from the original color and returns the first step that reaches `ratio`, or the last one (white or black). Opacity is kept and ignored by the math.
- `ContrastCheck.problems` returns `.lowContrast(ratio)` when the ratio is below `minimumContrast`, then `.tooCloseToReserved(color)` for each reserved color closer than `minimumReservedDistance`, in the given order. The defaults are Salah's guardrails (`AppearanceTab.swift:87-156` at `4bc00e9`): 3:1 for the large countdown, 0.28 from its functional colors.

### 4.7 Isolation and platforms

- Values are `nonisolated` and `Sendable`, like SalahCore's; views and styles are main-actor-isolated, as SwiftUI's are. Both products build with nonisolated and with MainActor default isolation (CI builds both on macOS, where the SwiftUI and WidgetKit code compiles).
- Linux builds `SharedValue` (without reloads), the timeline types, `ThemeColor` and `ContrastCheck`, and runs their tests. SwiftUI, WidgetKit and `notify` code sits behind `canImport`.
- WidgetKit's types exist from visionOS 26 and not on tvOS, so the WidgetKit timeline is `@available(visionOS 26.0, *)`.

### 4.8 Privacy

SalahWidgets declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `1C8F.1` in `PrivacyInfo.xcprivacy`, a package resource, because `SharedValue` reads and writes App Group defaults. Apps still declare their own use in their own manifests. SalahUI uses no required-reason API.

## 5. Changes from the proposal's sketch

| Sketch | Now | Why |
|---|---|---|
| `save` returns `Bool` and doesn't throw | `throws(SharedValueError) -> Bool`: whether the stored value changed | A failed encode would otherwise read as "unchanged", and the widget would never reload. |
| No way to observe reloads | `init(appGroup:key:reloadTimelines:)` | Apps test what they save and when they ask for reloads (Salah's settings mirror, §10). |
| `static let rihla` in a constrained extension | a computed `static var` | Generic types can't have stored static properties. |
| `timeline(from:horizon:entry:) -> Timeline` only | also `timeline(from:horizon:) throws -> PrayerTimeline` with `validUntil`, `isTruncated` and `reloadDate`; the builder takes `limit` | §7.3 asks to expose the earlier cutoff; the value is testable without WidgetKit, on Linux too, and lets an app choose its own reload policy. |
| Reload policy unspecified | `.after(reloadDate)`, halfway to `validUntil` | Half a horizon of slack for a late reload; about one reload a day for a calculated widget. |
| Invalid inputs unspecified | one expired entry and `.never` (WidgetKit); the plan's errors (value) | No crash on a reachable path (STANDARD.md, Swift). |
| `observe` returns `AnyObject` | returns `DarwinSignal.Observation` with `cancel()` and `isActive`; `post()` returns `Bool` | A named type documents the token's ownership; explicit cancel; honest about a failed registration or post. |
| `PrayerTimesList(day:state:names:)` with a `PrayerState` | `state: PrayerState?`, and `countdown:` | An unavailable state has no `PrayerState`, but a partial day still has times to list (Core §9 #7). |
| `NextPrayerView(state:names:timeZone:)` | adds `countdown:` | A static-text widget needs static countdown text. |
| `PrayerRowConfiguration` | `status` optional; adds `dayOffset` and `dayOffsetText` | Rows without a state; an Isha after midnight or a Fajr before it is marked (CalculatedPhone's "Next day", B1). |
| `NextPrayerConfiguration` | adds `abbreviation` | Circular complications and Lock Screen widgets (PhoneWidgets, WatchComplication). |
| Style protocols only | adds `PlainPrayerRowStyle`, `PlainNextPrayerStyle` and `.plain` | The default look is documented and can be restored inside a styled subtree. |
| `ContrastCheck.minimumHueDistance` | `minimumReservedDistance` | It's a distance between sRGB components, not between hues. |
| `ThemeColor` | adds `color` (SwiftUI); clamps components in the math | Apps draw the colors they check; a decoded out-of-range value can't produce a ratio outside 1…21. |

## 6. Probes

### 6.1 Mechanisms (2026-10-14, Xcode 27.0, Swift 6.4, macOS 27)

- `#Preview` compiles under `swift build` in a package target (`SalahUIPreviews`).
- `ImageRenderer` renders SwiftUI in `swift test` on macOS. `Text(timerInterval:)` renders against the wall clock; `pauseTime` doesn't freeze an interval that's already in the past. Snapshot tests therefore freeze live countdowns through an internal environment value that counts the same length over an interval far in the future.
- `notify(3)` is the clang module `notify` in every Apple SDK. `UserDefaults` isn't `Sendable`, so `SharedValue` keeps the suite name and opens the defaults per call. WidgetKit is unavailable on tvOS and starts at visionOS 26.
- A test target that depends on an executable target gets it built beside the test bundle; the `DarwinSignal` tests run it as a separate process.

### 6.2 Found by the isolation builds

CI builds SalahKit's targets, tests included, with MainActor default isolation. That build found that the documentation's `PrayerSettings`, written as a plain `struct`, fails exactly as an adopter's main-actor target would ("main actor-isolated conformance of 'PrayerSettings' to 'Decodable' cannot satisfy conformance requirement for a 'Sendable' type parameter"), and that the WidgetKit `timeline(from:horizon:entry:)`, declared in an extension without `nonisolated`, became main-actor-isolated in that build. The extension is now `nonisolated`, like SalahCore's, and the documentation shows the `nonisolated` declarations (§4.1).

### 6.3 Found by the cross-process tests

The first `observe` called `MainActor.assumeIsolated` inside the main-queue block. In the helper process, which services the main queue with `dispatchMain()`, it trapped ("Incorrect actor executor assumption"). With a `Task` hop, the runtime still reported "data race detected: @MainActor function … was not called on the main thread", because the block passed to `notify_register_dispatch` inherited `observe`'s main-actor isolation. The block is now `@Sendable` and hops to the main actor. The cross-process test fails when the helper writes anything to standard error, and fails on the earlier code.

## 7. Tests and evidence

- `SharedValueTests`: round trip, gating (an unchanged save doesn't rewrite the stored bytes), removal (also of an object that isn't data), undecodable data, encoding failure, an unavailable suite, independent keys, and the privacy manifest's contents.
- `PrayerTimelineBuilderTests`: entries equal the plan's plus the expired entry, the 48-hour default and halfway reload, truncation at the first change left out, `steps` dates, an empty source, errors, and the WidgetKit timeline and its fallback.
- `SevenDayTimelineTests`: successive timelines over seven days with a fixed clock, through a model of the provider's host (`WidgetHost`): calculated (Makkah), `steps` (truncated timelines), high latitude (Tromsø with the rule disabled, Kazan's Fajr before midnight), a timetable with a partial row, a missing day and an end, initial missing data followed by an app reload, a provider call late by 30 hours (the expired entry shows exactly until it), and late calls within the slack. Each checks, every five minutes and a second either side of every entry and event, that the shown state equals the schedule's. Mutants (reload at `validUntil`, a dropped entry) fail them.
- `DarwinSignalTests`: a helper process posts and this one observes; this one posts and the helper observes (from a `dispatchMain()` process); cancel and release stop delivery, including of a signal that arrived while the main actor was busy (a hop that holds the handler strongly fails both); other names don't arrive.
- `ThemeColorTests` and `ContrastCheck` tests: equality with Salah's code (copied into the test) on an 11-step grid and Salah's palette, for luminance, contrast, distance and the contrast fix at 3 and 4.5; ends of the scale; WCAG's #767676; clamping; thresholds.
- `DisplayContentTests`: statuses, countdown placement, the schedule's zone across a clock change, day offsets both ways and in Arabic digits, declared Jumu'ah, and no countdown or name for an unknown next prayer.
- `SnapshotTests`: the default styles at every SalahFixtures moment in English (left to right) and Arabic (right to left), Reykjavik's times after midnight and a declared Jumu'ah, and SwiftUI time zones that must render the same image. References are kept per macOS major version; an image fails when more than 8 pixels differ by more than 2 in a channel, and `SnapshotComparisonTests` shows that one changed digit, even in a caption, changes about 90 pixels or more. CI runs the suite again in a process at UTC+14, whose images must equal the references rendered at UTC: formatting in the device's zone fails 18 of the 20 cases.
- `NarrowLayoutTests`: the plain styles at 140 and 56 points keep every time and countdown on one line; the snapshots `narrow-justStarted-en` and `narrow-beforeFajr-ar` show 140-point rows keeping the next prayer's name.
- Documentation: every Swift block of the two articles and of the README's widget and UI sections is compiled and run by tests.
- `Examples/PhoneWidgets` and `Examples/WatchComplication` exercise both products in real extensions (§9).

## 8. Open questions

1. **Count-up for a just-started prayer.** Salah counts up for 15 minutes after a prayer starts. The configuration names the just-started prayer, and a style can build its own timer from `state.justStarted`; whether `PrayerCountdown` should count up too waits for a consumer that needs it (Salah's migration).
2. **Rows for missing kinds.** The list shows known events only; CalculatedPhone shows a row with the reason for a kind that can't be calculated. A list option for such rows waits for a second consumer.
3. **Wording for gaps.** Every consumer turns `ScheduleGapReason` into a sentence. A summary of an unavailable state's coverage (Core §9 #8) would shorten that.
4. **Timeline size.** WidgetKit documents no entry limit. The default of 96 is Core's; a device run may show whether long timelines are cut.
5. **One writer per key.** `SharedValue` doesn't lock. If an extension needs to write a value the app also writes (an optimistic stop), a compare-and-swap API may be needed.
6. **Secondary text in the plain styles.** Passed rows and the next prayer's time use the system's secondary color: iOS's `secondaryLabel` over white is 3.30 to 3.44:1 in light mode (5.95 to 6.36:1 in dark mode), above `ContrastCheck`'s default floor of 3:1 but below WCAG's 4.5:1 for body text. Increase Contrast raises it. It follows the platform's convention for de-emphasized text; an app with stricter needs restyles. MosqueBoard and CalculatedPhone use the same color for secondary text.

## 9. Consumer findings

`Examples/PhoneWidgets` (an iPhone app and widget extension with a calculated source) and `Examples/WatchComplication` (a watch app and complication, with a companion iPhone app sending calculated or published inputs) use both products through the public API, in real extensions on simulators: PhoneWidgets' widget was added to the Home Screen by XCUITest, and the complication ran from the watch's Smart Stack. Their extensions built a timeline in 4.7 to 125 ms (median 7.5 ms, 36 entries, 34 calls) at a footprint of 7.4 to 18.5 MiB (iPhone 17 simulator, iOS 27), with one first call after the extension started cold at 356 ms, and under 30 ms at 12 to 15 MB (Apple Watch Series 11 simulator, watchOS 27), which answers the proposal's §14 risk for simulators; the oldest supported iPhone is still to measure. What they found:

1. **Main-actor targets need `nonisolated` declarations** (both): the shared value, its extension, the provider and the entry. Handled in the documentation (§4.1).
2. **Inspecting the timeline WidgetKit gets** (both). A `Timeline`'s reload policy can't be read back, so an extension that logs `validUntil`, `reloadDate` or `isTruncated` calls `timeline(from:horizon:)` and builds the `Timeline` itself, with its own handling of the errors. That's the documented path; a converter would save a line or two, and waits for a third use.
3. **No entry at midnight** (PhoneWidgets). `.stateChanges` adds no entry where only the civil date changes, so a widget that lists today's times would show yesterday's list until the next change, near Fajr. PhoneWidgets adds an entry at each midnight in the place's zone, with the state that holds then. A builder option, or day boundaries in Core's refresh plan, is a candidate for 0.3; the article tells adopters meanwhile.
4. **WidgetKit holds reloads while the app is in the foreground** (PhoneWidgets, iOS 27 simulator). The first request ran at once; later ones waited until the app went to the background or about 90 seconds passed. The article says so.
5. **Wording a source gap** (both). To say "timetable ended" rather than "can't be calculated", WatchComplication finds the gap containing the entry's date and reads its reason, where the gaps of neighboring days overlap; PhoneWidgets takes the most telling reason across all the state's gaps. The same need as Core §9 #7 and #8: a summary of the current gap would help both products.
6. **An unknown next prayer from a calculation** (PhoneWidgets). A kind a calculation can't produce, such as Tromsø's Maghrib in June, leaves the state unavailable for its whole window, so "latest known, next unknown" comes only from a published timetable that ends. `PrayerTimelineState`'s documentation says so.
7. **Compact styles and VoiceOver** (both, found in review). The circular styles showed `configuration.abbreviation`, which VoiceOver read as "A". The abbreviation now carries the full name as its accessibility label (§4.4), and the examples' journeys check the spoken labels.
8. **Text for sentences** (both). Configurations give `Text`, so an app sentence in its own word order ("Asr has started") or an inline "Asr 12m" composes `Text`s or reads `state` with `PrayerNames`. Waits for a consumer that needs strings.
9. **A fixed moment's live countdown** (PhoneWidgets). The app's widget-states screen draws entries at fixed moments, where a live timer would count from the wall clock; it uses `.staticText`. The test-only freeze stays internal.
10. **Bugs the journeys found in the examples' own code**: PhoneWidgets created its settings store in a view's initializer, which applied the launch arguments again after a language change; WatchComplication rebuilt its timeline from the clock on every redraw and never settled. Both are fixed, with regression journeys.

`Examples/MenuBar` (0.3.0, a macOS menu-bar app with a desktop widget) uses `SharedValue`, `DarwinSignal`, `PrayerTimelineBuilder` with `.steps`, and SalahUI's views with static countdowns. What it found:

11. **The stop signal between sandboxed processes on macOS.** The app and its stop harness, both signed with a team, sandboxed and sharing an App Group, exchanged the signal and the shared values on macOS 27 with no prompt; C1 had tested only unsandboxed processes. The harness runs the widget intent's own `perform()`; the widget extension that WidgetKit launches for a real tap is still to observe.
12. **Two writers of the live-state value** (§8 #5). The intent clears what plays and the app publishes it again after every signal, so the value has two writers. The app's write after each signal settles any race, so the pattern needs no compare-and-swap. `SharedValue`'s one-writer advice stands; the article "Lessons from Salah" names this exception.
13. **A `.steps` display outside WidgetKit.** The menu bar's title is static text refreshed at a `.steps` plan's dates, with a limit of 1,000 entries: a minute grid an hour either side of a prayer needs about 120 per prayer, and Core's default of 96 is WidgetKit's budget, not an app's. Like PhoneWidgets (#3), it refreshes at each midnight as well; a second consumer for day boundaries in the refresh plan.
14. **Static countdowns overstate by up to a step.** A `.staticText` countdown shows the time left at its entry's date, rounded down, so until the next entry the true time left is up to one step shorter. That's what static text means; a view that must never overstate uses the live countdown.

## 10. Changes after review

1. **Review round R1** (2026-10-14, session C1). The snapshot comparison allowed 0.1 % of an image to differ, which let a time a minute late pass; it now allows 8 pixels. The test of a device in another zone set only SwiftUI's environment, and the Mac that recorded the references was at Makkah's offset; CI now reruns the snapshots at UTC+14. The plain row style let a countdown or a time wrap mid-number in a narrow row ("4:14:0"); numbers no longer wrap. DarwinSignal now receives notify(3)'s callbacks on a private queue, which makes the weak hop testable: a signal that arrives while the main actor is busy no longer reaches a cancelled observation. `save(nil)` removes an object under the key that isn't data. The figures for `steps` timelines were corrected.
2. **Review round R2** (2026-10-14, session C1). R1's fix kept numbers from wrapping but let the next row's name shrink to "…" at 140 points, where the countdown and the time took the whole row; the row now leaves out its countdown first. `SharedValue` compares with, and loads, the App Group's own storage only, so a default registered in one process can't make every `save(nil)` reload or hide a value from the others. The `steps` figures now hold beyond Makkah.
