import Foundation
import SalahCore
import SalahUI
import SwiftUI
import Testing
import WidgetKit

@testable import MenuBar

/// Render the extension's production content with its actual plain styles and native button.
/// Recording backgrounds measure layout without changing the views' proposed or ideal sizes.
@Suite("Widget finite layouts")
@MainActor
struct WidgetLayoutTests {
  @Test(
    "the medium day and Stop stay inside the widget",
    arguments: [NamesLanguage.english, .arabic], [false, true])
  func medium(language: NamesLanguage, playing: Bool) throws {
    let record = try render(language: language, playing: playing, family: .systemMedium)
    let bounds = CGRect(x: 0, y: 0, width: 344, height: 164)
    try checkVisible(record.focus, within: bounds)
    #expect(Set(record.rows.keys) == Set(PrayerKind.allCases))
    for kind in PrayerKind.allCases {
      try checkVisible(record.rows[kind], within: bounds)
    }
    if playing {
      let stop = try #require(record.stop)
      try checkVisible(stop, within: bounds)
      for row in record.rows.values { #expect(!stop.intersects(row)) }
    } else {
      #expect(record.stop == nil)
    }
    let focus = try #require(record.focus)
    let first = try #require(record.rows[.fajr])
    // The focused prayer remains on the reading side in either layout direction.
    #expect(language.isRightToLeft ? focus.midX > first.midX : focus.midX < first.midX)
  }

  @Test(
    "the small focus and Stop stay inside the widget",
    arguments: [NamesLanguage.english, .arabic], [false, true])
  func small(language: NamesLanguage, playing: Bool) throws {
    let record = try render(language: language, playing: playing, family: .systemSmall)
    let bounds = CGRect(x: 0, y: 0, width: 164, height: 164)
    try checkVisible(record.focus, within: bounds)
    #expect(record.rows.isEmpty)
    if playing {
      try checkVisible(record.stop, within: bounds)
    } else {
      #expect(record.stop == nil)
    }
  }

  private func checkVisible(_ frame: CGRect?, within bounds: CGRect) throws {
    let frame = try #require(frame)
    #expect(frame.width > 0 && frame.height > 0)
    #expect(frame.minX.isFinite && frame.minY.isFinite)
    #expect(bounds.contains(frame), "Content \(frame) exceeds finite widget \(bounds)")
  }

  private func render(
    language: NamesLanguage, playing: Bool, family: WidgetFamily
  ) throws -> WidgetFrames {
    var settings = Fixture.makkah
    settings.language = language
    let fajr = try Fixture.event(.fajr, settings: settings)
    let now = fajr.time.addingTimeInterval(-4 * 3600 - 51 * 60)
    let playback = playing ? NowPlaying(alert: nil, startedAt: now) : nil
    let entry = MenuBarTimeline.timeline(settings: settings, nowPlaying: playback, now: now)
      .entries[0]
    let strings = MenuBarStrings(language: language)
    let record = WidgetFrames()
    let stop: AnyView
    if let playback {
      stop = AnyView(
        PrayerWidgetStopButton(nowPlaying: playback, strings: strings)
          .background { WidgetFrameReader(record: record, part: .stop) })
    } else {
      stop = AnyView(EmptyView())
    }
    let width: CGFloat = family == .systemMedium ? 344 : 164
    let content = PrayerWidgetContent(entry: entry, family: family, strings: strings, stop: stop)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .environment(\.locale, strings.locale)
      .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
      .prayerRowStyle(MeasuredWidgetRow(record: record))
      .nextPrayerStyle(MeasuredWidgetFocus(record: record))
      // The desktop host was 344×164, with 18-point content insets. Keep the outer
      // viewport finite too: an unconstrained-height renderer misses clipped content.
      .padding(18)
      .frame(width: width, height: 164)
      .coordinateSpace(name: WidgetFrames.coordinateSpace)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(width: width, height: 164)
    let image = try #require(renderer.cgImage)
    #expect(image.width == Int(width) && image.height == 164)
    return record
  }
}

@MainActor
private final class WidgetFrames {
  static let coordinateSpace = "menuBarWidgetBounds"
  var focus: CGRect?
  var rows: [PrayerKind: CGRect] = [:]
  var stop: CGRect?

  enum Part {
    case focus
    case row(PrayerKind)
    case stop
  }

  func record(_ frame: CGRect, for part: Part) {
    switch part {
    case .focus: focus = frame
    case .row(let kind): rows[kind] = frame
    case .stop: stop = frame
    }
  }
}

private struct WidgetFrameReader: View {
  let record: WidgetFrames
  let part: WidgetFrames.Part

  var body: some View {
    GeometryReader { proxy in
      let _ = record.record(proxy.frame(in: .named(WidgetFrames.coordinateSpace)), for: part)
      Color.clear
    }
  }
}

private struct MeasuredWidgetRow: PrayerRowStyle {
  let record: WidgetFrames

  func makeBody(configuration: Configuration) -> some View {
    PlainPrayerRowStyle().makeBody(configuration: configuration)
      .background { WidgetFrameReader(record: record, part: .row(configuration.kind)) }
  }
}

private struct MeasuredWidgetFocus: NextPrayerStyle {
  let record: WidgetFrames

  func makeBody(configuration: Configuration) -> some View {
    PlainNextPrayerStyle().makeBody(configuration: configuration)
      .background { WidgetFrameReader(record: record, part: .focus) }
  }
}
