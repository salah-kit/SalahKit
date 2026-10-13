#if canImport(notify) && os(macOS)
  import Foundation
  import Testing

  @testable import SalahWidgets

  /// DarwinSignal across processes: `DarwinSignalHelper`, a separate executable, posts or
  /// observes while the test process does the other.
  @Suite("DarwinSignal", .serialized)
  @MainActor
  struct DarwinSignalTests {
    /// A name no other test or process uses.
    static func uniqueName() -> String {
      "io.github.salah-kit.tests.signal.\(UUID().uuidString)"
    }

    @Test("a helper process posts and this process observes")
    func observesAnotherProcess() async throws {
      let signal = DarwinSignal(name: Self.uniqueName())
      let received = Counter()
      let observation = signal.observe { received.increment() }
      #expect(observation.isActive)

      let helper = try Helper.run("post", signal.name)
      #expect(helper.terminationStatus == 0)
      #expect(await received.waitUntil { $0 >= 1 })
      observation.cancel()
    }

    /// The helper observes from a process that services the main queue with `dispatchMain()`,
    /// off the main thread. Observing there once trapped (`MainActor.assumeIsolated`) and then
    /// tripped the runtime's main-thread check, which the helper's standard error would show.
    @Test("this process posts and a helper process observes")
    func postsToAnotherProcess() async throws {
      let signal = DarwinSignal(name: Self.uniqueName())
      let helper = try Helper.start("wait", signal.name, "10")
      #expect(await helper.waitForLine("ready"))

      #expect(signal.post())
      #expect(await helper.waitForExit() == 0)
      #expect(helper.lines.contains("received"))
      #expect(helper.errors.isEmpty, "the helper wrote to standard error: \(helper.errors)")
    }

    @Test("a cancelled observation stops calling its handler")
    func cancelStopsDelivery() async throws {
      let signal = DarwinSignal(name: Self.uniqueName())
      let received = Counter()
      let observation = signal.observe { received.increment() }
      observation.cancel()
      #expect(observation.isActive == false)
      observation.cancel()

      // A second observation of the same name shows when the post has been delivered.
      let witness = Counter()
      let other = signal.observe { witness.increment() }
      #expect(try Helper.run("post", signal.name).terminationStatus == 0)
      #expect(await witness.waitUntil { $0 >= 1 })
      #expect(received.value == 0)
      other.cancel()
    }

    @Test("a released observation stops calling its handler")
    func releaseStopsDelivery() async throws {
      let signal = DarwinSignal(name: Self.uniqueName())
      let received = Counter()
      var observation: DarwinSignal.Observation? = signal.observe { received.increment() }
      #expect(observation?.isActive == true)
      observation = nil

      let witness = Counter()
      let other = signal.observe { witness.increment() }
      #expect(try Helper.run("post", signal.name).terminationStatus == 0)
      #expect(await witness.waitUntil { $0 >= 1 })
      #expect(received.value == 0)
      other.cancel()
    }

    @Test("signals with other names don't reach the handler")
    func otherNamesAreIgnored() async throws {
      let signal = DarwinSignal(name: Self.uniqueName())
      let other = DarwinSignal(name: Self.uniqueName())
      let received = Counter()
      let witness = Counter()
      let observation = signal.observe { received.increment() }
      let otherObservation = other.observe { witness.increment() }

      #expect(try Helper.run("post", other.name).terminationStatus == 0)
      #expect(await witness.waitUntil { $0 >= 1 })
      #expect(received.value == 0)
      observation.cancel()
      otherObservation.cancel()
    }
  }

  /// A count the main actor updates and the test waits on.
  @MainActor
  final class Counter {
    private(set) var value = 0

    func increment() { value += 1 }

    /// Waits, up to five seconds, for the count to satisfy `condition`.
    func waitUntil(_ condition: (Int) -> Bool) async -> Bool {
      for _ in 0..<500 {
        if condition(value) { return true }
        try? await Task.sleep(for: .milliseconds(10))
      }
      return condition(value)
    }
  }

  /// The DarwinSignalHelper executable, built beside the test bundle.
  @MainActor
  final class Helper {
    private let process = Process()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private var buffer = ""

    /// The lines the helper has printed so far.
    private(set) var lines: [String] = []

    private init(_ arguments: [String]) throws {
      // The test bundle and the helper are siblings in the build's products directory.
      let products = Bundle(for: Helper.self).bundleURL.deletingLastPathComponent()
      process.executableURL = products.appendingPathComponent("DarwinSignalHelper")
      process.arguments = arguments
      process.standardOutput = output
      process.standardError = errorOutput
      try process.run()
    }

    /// Runs the helper to completion.
    static func run(_ arguments: String...) throws -> Process {
      let helper = try Helper(arguments)
      helper.process.waitUntilExit()
      return helper.process
    }

    /// Starts the helper and returns while it runs.
    static func start(_ arguments: String...) throws -> Helper {
      try Helper(arguments)
    }

    /// Waits, up to ten seconds, for the helper to print `line`.
    func waitForLine(_ line: String) async -> Bool {
      for _ in 0..<1_000 {
        readAvailable()
        if lines.contains(line) { return true }
        if !process.isRunning {
          readAvailable()
          return lines.contains(line)
        }
        try? await Task.sleep(for: .milliseconds(10))
      }
      return false
    }

    /// What the helper wrote to standard error; read once it has exited.
    var errors: String {
      String(decoding: errorOutput.fileHandleForReading.availableDataIfAny(), as: UTF8.self)
    }

    /// Waits, up to fifteen seconds, for the helper to exit, and returns its status.
    func waitForExit() async -> Int32? {
      for _ in 0..<1_500 where process.isRunning {
        try? await Task.sleep(for: .milliseconds(10))
      }
      guard !process.isRunning else {
        process.terminate()
        return nil
      }
      readAvailable()
      return process.terminationStatus
    }

    private func readAvailable() {
      let data = output.fileHandleForReading.availableDataIfAny()
      buffer += String(decoding: data, as: UTF8.self)
      while let newline = buffer.firstIndex(of: "\n") {
        lines.append(String(buffer[..<newline]))
        buffer.removeSubrange(...newline)
      }
    }
  }

  extension FileHandle {
    /// The bytes ready to read, without blocking when there are none.
    fileprivate func availableDataIfAny() -> Data {
      var bytes = Data()
      let descriptor = fileDescriptor
      let flags = fcntl(descriptor, F_GETFL)
      _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
      defer { _ = fcntl(descriptor, F_SETFL, flags) }
      var chunk = [UInt8](repeating: 0, count: 4_096)
      while true {
        let count = Darwin.read(descriptor, &chunk, chunk.count)
        guard count > 0 else { break }
        bytes.append(contentsOf: chunk[0..<count])
      }
      return bytes
    }
  }
#endif
