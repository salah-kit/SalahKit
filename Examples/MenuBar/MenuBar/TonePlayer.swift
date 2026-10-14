import AVFoundation
import Foundation

/// Plays the app's tone. The app holds one; tests inject a fake.
@MainActor
protocol TonePlaying: AnyObject {
  /// Whether a tone is playing.
  var isPlaying: Bool { get }
  /// Starts the tone, replacing one that plays. `onFinish` is called when it ends by itself,
  /// never after ``stop()``.
  ///
  /// - Parameter cycles: How many times the chime plays, or `nil` to repeat it until stopped.
  func play(cycles: Int?, onFinish: @escaping @MainActor () -> Void) throws
  /// Stops the tone. Stopping when nothing plays does nothing.
  func stop()
}

/// Why a tone couldn't start.
enum TonePlayerError: Error, Equatable {
  /// The audio player couldn't be made or refused to start.
  case cannotPlay
}

/// The tone through AVFoundation: a generated chime, no recording.
@MainActor
final class AudioTonePlayer: TonePlaying {
  private let data = ToneSynthesis.wav()
  private let volume: Float
  private var player: AVAudioPlayer?
  private var delegate: Delegate?

  /// Creates a player.
  ///
  /// - Parameter muted: Plays at zero volume, for unattended test runs. The player still runs,
  ///   so playback and stopping behave as they do with sound.
  init(muted: Bool = false) {
    volume = muted ? 0 : 0.8
  }

  var isPlaying: Bool { player != nil }

  func play(cycles: Int?, onFinish: @escaping @MainActor () -> Void) throws {
    stop()
    let player: AVAudioPlayer
    do {
      player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
    } catch {
      throw TonePlayerError.cannotPlay
    }
    player.numberOfLoops = cycles.map { max(0, $0 - 1) } ?? -1
    player.volume = volume
    let delegate = Delegate { [weak self, weak player] in
      // A player that was stopped or replaced is gone from `self.player`; its late callback
      // does nothing.
      guard let self, let player, self.player === player else { return }
      self.player = nil
      self.delegate = nil
      onFinish()
    }
    player.delegate = delegate
    guard player.play() else { throw TonePlayerError.cannotPlay }
    self.player = player
    self.delegate = delegate
  }

  func stop() {
    player?.delegate = nil
    player?.stop()
    player = nil
    delegate = nil
  }

  /// Forwards the end of playback to the main actor.
  private final class Delegate: NSObject, AVAudioPlayerDelegate {
    private let finished: @MainActor () -> Void

    init(finished: @escaping @MainActor () -> Void) {
      self.finished = finished
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
      Task { @MainActor [finished] in finished() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
      Task { @MainActor [finished] in finished() }
    }
  }
}

/// The chime, synthesized: three sine notes with a soft attack and a decaying tail, then a
/// pause, as 16-bit mono WAV data.
nonisolated enum ToneSynthesis {
  /// The samples per second.
  static let sampleRate = 44_100

  /// The notes: E5, G5 and C6, the last held longest.
  static let notes: [(frequency: Double, seconds: Double)] = [
    (659.26, 0.45), (783.99, 0.45), (1_046.50, 1.1),
  ]

  /// The silence after the notes, so a repeated chime breathes.
  static let pauseSeconds = 0.8

  /// The length of one chime, in seconds.
  static var cycleSeconds: Double {
    notes.reduce(0) { $0 + $1.seconds } + pauseSeconds
  }

  /// One chime's samples, between -1 and 1.
  static func samples() -> [Double] {
    var samples: [Double] = []
    for note in notes {
      let count = Int(note.seconds * Double(sampleRate))
      for index in 0..<count {
        let time = Double(index) / Double(sampleRate)
        let attack = min(1, time / 0.008)
        let decay = exp(-time / 0.35)
        let phase = 2 * Double.pi * note.frequency * time
        // The fundamental with a quiet octave above it, for a bell-like color.
        samples.append(0.45 * attack * decay * (sin(phase) + 0.25 * sin(2 * phase)))
      }
    }
    samples.append(contentsOf: repeatElement(0, count: Int(pauseSeconds * Double(sampleRate))))
    return samples
  }

  /// One chime as a WAV file's bytes.
  static func wav() -> Data {
    let pcm = samples().map { Int16((max(-1, min(1, $0)) * Double(Int16.max)).rounded()) }
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
      withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    let byteCount = UInt32(pcm.count * 2)
    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36) + byteCount)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    append(UInt32(16))  // the format chunk's size
    append(UInt16(1))  // PCM
    append(UInt16(1))  // mono
    append(UInt32(sampleRate))
    append(UInt32(sampleRate * 2))  // bytes per second
    append(UInt16(2))  // bytes per frame
    append(UInt16(16))  // bits per sample
    data.append(contentsOf: Array("data".utf8))
    append(byteCount)
    for sample in pcm { append(sample) }
    return data
  }
}
