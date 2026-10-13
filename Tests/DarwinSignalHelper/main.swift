// A separate process for DarwinSignal's cross-process tests.
//
//   DarwinSignalHelper post <name>             posts the signal once and exits 0
//   DarwinSignalHelper wait <name> <seconds>   prints "ready" once it observes, then exits 0 and
//                                              prints "received" when the signal arrives, or
//                                              exits 1 after the given seconds

import Foundation

#if canImport(notify)
  import SalahWidgets

  func say(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
  }

  let arguments = CommandLine.arguments.dropFirst()
  switch (arguments.first, arguments.dropFirst().first) {
  case ("post", let name?):
    exit(DarwinSignal(name: name).post() ? 0 : 3)
  case ("wait", let name?):
    let seconds = arguments.dropFirst(2).first.flatMap(Double.init) ?? 10
    let observation = DarwinSignal(name: name).observe {
      say("received")
      exit(0)
    }
    guard observation.isActive else {
      say("not observing")
      exit(3)
    }
    say("ready")
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
      say("timed out")
      exit(1)
    }
    withExtendedLifetime(observation) { dispatchMain() }
  default:
    say("usage: DarwinSignalHelper post <name> | wait <name> <seconds>")
    exit(2)
  }
#else
  FileHandle.standardError.write(Data("DarwinSignalHelper needs notify(3)\n".utf8))
  exit(2)
#endif
