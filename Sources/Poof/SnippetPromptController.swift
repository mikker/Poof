import AppKit
import SwiftUI

/// Asks for the values of a snippet's `{{prompt:...}}` tokens, then hands focus
/// back to the app the expansion started in before reporting the answers.
@MainActor
final class SnippetPromptController: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private var completion: (([String: String]) -> Void)?
  private var previousApp: NSRunningApplication?

  func requestAnswers(
    title: String,
    questions: [String],
    completion: @escaping ([String: String]) -> Void
  ) {
    guard window == nil, !questions.isEmpty else { return }

    previousApp = NSWorkspace.shared.frontmostApplication
    self.completion = completion

    let view = SnippetPromptView(
      questions: questions,
      onSubmit: { [weak self] answers in
        self?.finish(with: answers)
      },
      onCancel: { [weak self] in
        self?.finish(with: nil)
      }
    )

    let window = NSWindow(contentViewController: NSHostingController(rootView: view))
    window.styleMask = [.titled, .closable]
    window.title = title
    window.level = .floating
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    self.window = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    finish(with: nil)
  }

  private func finish(with answers: [String: String]?) {
    guard let window else { return }

    let completion = self.completion
    self.window = nil
    self.completion = nil
    window.delegate = nil
    window.close()

    restoreFocus {
      guard let answers else { return }
      completion?(answers)
    }
  }

  private func restoreFocus(then work: @escaping @MainActor () -> Void) {
    let app = previousApp
    previousApp = nil

    Task { @MainActor in
      if let app, !app.isTerminated, !app.isActive {
        app.activate()

        var attempts = 0
        while !app.isActive, attempts < 40 {
          try? await Task.sleep(for: .milliseconds(25))
          attempts += 1
        }
      }

      // Let the reactivated app restore its own first responder before typing into it.
      try? await Task.sleep(for: .milliseconds(60))
      work()
    }
  }
}

// MARK: - Prompt View

private struct SnippetPromptView: View {
  let questions: [String]
  let onSubmit: ([String: String]) -> Void
  let onCancel: () -> Void

  @State private var answers: [String]
  @FocusState private var focusedIndex: Int?

  init(
    questions: [String],
    onSubmit: @escaping ([String: String]) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.questions = questions
    self.onSubmit = onSubmit
    self.onCancel = onCancel
    _answers = State(initialValue: Array(repeating: "", count: questions.count))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(questions.indices, id: \.self) { index in
        VStack(alignment: .leading, spacing: 4) {
          Text(questions[index].isEmpty ? "Value" : questions[index])
            .font(.callout)
            .foregroundStyle(.secondary)
          TextField("", text: $answers[index])
            .textFieldStyle(.roundedBorder)
            .focused($focusedIndex, equals: index)
            .onSubmit(submit)
        }
      }

      HStack {
        Spacer()
        Button("Cancel", action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button("Insert", action: submit)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 360)
    .onAppear { focusedIndex = 0 }
  }

  private func submit() {
    onSubmit(Dictionary(zip(questions, answers), uniquingKeysWith: { first, _ in first }))
  }
}
