import SwiftUI

@main
struct MosqueBoardApp: App {
  private let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

  var body: some Scene {
    WindowGroup {
      RootView(options: options)
    }
  }
}

/// Loads the chosen board and shows it, or says why it couldn't.
struct RootView: View {
  let options: LaunchOptions
  private let strings: BoardStrings
  private let clock: BoardClock
  private let board: Result<Board, any Error>

  init(options: LaunchOptions) {
    self.options = options
    strings = BoardStrings(language: options.language)
    clock = BoardClock(start: options.now, frozen: options.frozen)
    board = Result { try Board.load(options.board) }
  }

  var body: some View {
    Group {
      switch board {
      case .success(let board):
        BoardView(board: board, clock: clock, strings: strings)
      case .failure(let error):
        Text(verbatim: strings("The timetable couldn't be loaded: \(String(describing: error))"))
          .padding()
      }
    }
    .environment(\.locale, strings.locale)
    .environment(\.layoutDirection, strings.isRightToLeft ? .rightToLeft : .leftToRight)
  }
}
