import AppKit
import Carbon.HIToolbox
import Foundation

final class TextInjector {
  func replaceTypedText(
    deleteCount: Int,
    replacementText: String,
    cursorOffsetFromEnd: Int?
  ) {
    guard deleteCount >= 0 else { return }

    sendBackspaces(count: deleteCount)

    let injectedByKeystrokes = injectTextByKeystroke(replacementText)
    if !injectedByKeystrokes {
      injectTextByClipboardPaste(replacementText)
    }

    if let cursorOffsetFromEnd, cursorOffsetFromEnd > 0 {
      moveCursorLeft(count: cursorOffsetFromEnd)
    }
  }

  private func sendBackspaces(count: Int) {
    guard count > 0 else { return }
    for _ in 0..<count {
      postKeyPress(keyCode: CGKeyCode(kVK_Delete), flags: [])
      usleep(1_500)
    }
  }

  private func injectTextByKeystroke(_ text: String) -> Bool {
    guard !text.isEmpty else { return true }

    for chunk in text.chunked(maxCharacters: 20) {
      guard
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Space), keyDown: true),
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Space), keyDown: false)
      else {
        return false
      }

      keyDown.keyboardSetUnicodeString(stringLength: chunk.utf16.count, unicodeString: Array(chunk.utf16))
      keyDown.post(tap: .cghidEventTap)
      keyUp.post(tap: .cghidEventTap)
      usleep(1_500)
    }

    return true
  }

  private func injectTextByClipboardPaste(_ text: String) {
    let snapshot = PasteboardSnapshot.capture(from: NSPasteboard.general)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    let insertedChangeCount = pasteboard.changeCount

    postKeyPress(keyCode: CGKeyCode(kVK_ANSI_V), flags: [.maskCommand])

    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
      let pasteboard = NSPasteboard.general
      // Don't overwrite clipboard contents if the user copied something else after expansion.
      guard pasteboard.changeCount == insertedChangeCount else { return }
      snapshot.restore(to: pasteboard)
    }
  }

  private func moveCursorLeft(count: Int) {
    guard count > 0 else { return }
    for _ in 0..<count {
      postKeyPress(keyCode: CGKeyCode(kVK_LeftArrow), flags: [])
      usleep(1_000)
    }
  }

  private func postKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
    guard
      let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else {
      return
    }

    keyDown.flags = flags
    keyUp.flags = flags
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
  }
}

private struct PasteboardSnapshot: Sendable {
  struct Item: Sendable {
    struct Representation: Sendable {
      let type: String
      let data: Data
    }

    let representations: [Representation]
  }

  let items: [Item]

  static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
    let copiedItems = (pasteboard.pasteboardItems ?? []).map { item in
      var representations: [Item.Representation] = []
      for type in item.types {
        if let data = item.data(forType: type) {
          representations.append(.init(type: type.rawValue, data: data))
        }
      }
      return Item(representations: representations)
    }
    return PasteboardSnapshot(items: copiedItems)
  }

  func restore(to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    guard !items.isEmpty else { return }

    let restoredItems = items.map { item in
      let pasteboardItem = NSPasteboardItem()
      for representation in item.representations {
        pasteboardItem.setData(
          representation.data,
          forType: NSPasteboard.PasteboardType(representation.type)
        )
      }
      return pasteboardItem
    }

    pasteboard.writeObjects(restoredItems)
  }
}

private extension String {
  func chunked(maxCharacters: Int) -> [String] {
    guard maxCharacters > 0 else { return [self] }

    var chunks: [String] = []
    var start = startIndex

    while start < endIndex {
      let end = index(start, offsetBy: maxCharacters, limitedBy: endIndex) ?? endIndex
      chunks.append(String(self[start..<end]))
      start = end
    }

    return chunks
  }
}
