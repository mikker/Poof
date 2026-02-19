import AppKit
import Foundation

@MainActor
final class SnippetEngine {
  private let injector: TextInjector
  private var monitor: Any?
  private var triggerMode: ExpansionTriggerMode
  private var snippets: [Snippet] = []
  private var typedBuffer = ""
  private var ignoreEventsUntil = Date.distantPast

  private let delimiters: Set<Character> = [
    " ", "\n", "\r", "\t"
  ]

  init(triggerMode: ExpansionTriggerMode, injector: TextInjector = TextInjector()) {
    self.triggerMode = triggerMode
    self.injector = injector
  }

  func start() {
    stop()
    monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handle(event)
      }
    }
  }

  func stop() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }

  func updateSnippets(_ snippets: [Snippet]) {
    self.snippets = snippets
  }

  func updateTriggerMode(_ mode: ExpansionTriggerMode) {
    triggerMode = mode
    typedBuffer = ""
  }

  private func handle(_ event: NSEvent) {
    guard Date() >= ignoreEventsUntil else { return }

    // Ignore shortcuts and modifier combinations.
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
      typedBuffer = ""
      return
    }

    // If this app is focused, don't run expansion while editing settings.
    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
      return
    }

    switch event.keyCode {
    case 51:  // Backspace
      if !typedBuffer.isEmpty {
        typedBuffer.removeLast()
      }
      return
    case 123, 124, 125, 126, 53:  // Arrows + Escape
      typedBuffer = ""
      return
    default:
      break
    }

    guard let characters = event.characters, !characters.isEmpty else {
      return
    }

    for character in characters {
      process(character)
    }
  }

  private func process(_ character: Character) {
    switch triggerMode {
    case .delimiter:
      processDelimiterMode(character)
    case .immediate:
      processImmediateMode(character)
    }
  }

  private func processDelimiterMode(_ character: Character) {
    if delimiters.contains(character) {
      defer { typedBuffer = "" }

      guard let snippet = firstMatchingSnippet(for: typedBuffer) else { return }

      let rendered = SnippetTemplateRenderer.render(snippet.replacementTemplate)
      let delimiterText = String(character)
      let outputText = rendered.text + delimiterText
      let cursorOffset: Int?
      if let baseOffset = rendered.cursorOffsetFromEnd {
        cursorOffset = baseOffset + delimiterText.count
      } else {
        cursorOffset = nil
      }

      expand(
        deleteCount: snippet.trigger.count + delimiterText.count,
        replacementText: outputText,
        cursorOffsetFromEnd: cursorOffset
      )
      return
    }

    typedBuffer.append(character)
    trimBufferIfNeeded()
  }

  private func processImmediateMode(_ character: Character) {
    typedBuffer.append(character)
    trimBufferIfNeeded()

    guard let snippet = firstMatchingSnippet(for: typedBuffer) else { return }
    let rendered = SnippetTemplateRenderer.render(snippet.replacementTemplate)
    expand(
      deleteCount: snippet.trigger.count,
      replacementText: rendered.text,
      cursorOffsetFromEnd: rendered.cursorOffsetFromEnd
    )
    typedBuffer = ""
  }

  private func firstMatchingSnippet(for candidate: String) -> Snippet? {
    for snippet in snippets {
      if snippet.matchesSuffix(in: candidate) {
        return snippet
      }
    }
    return nil
  }

  private func trimBufferIfNeeded() {
    let maxLength = max(64, snippets.map(\.trigger.count).max() ?? 64)
    guard typedBuffer.count > maxLength else { return }
    typedBuffer = String(typedBuffer.suffix(maxLength))
  }

  private func expand(deleteCount: Int, replacementText: String, cursorOffsetFromEnd: Int?) {
    ignoreEventsUntil = Date().addingTimeInterval(0.35)
    injector.replaceTypedText(
      deleteCount: deleteCount,
      replacementText: replacementText,
      cursorOffsetFromEnd: cursorOffsetFromEnd
    )
  }
}
