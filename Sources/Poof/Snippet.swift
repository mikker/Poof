import AppKit
import Foundation

struct Snippet: Hashable {
  let trigger: String
  let replacementTemplate: String
  let details: String?
  let caseSensitive: Bool

  func matchesSuffix(in candidate: String) -> Bool {
    guard candidate.count >= trigger.count else { return false }

    if caseSensitive {
      return candidate.hasSuffix(trigger)
    }

    return candidate.lowercased().hasSuffix(trigger.lowercased())
  }
}

struct RenderedSnippet {
  let text: String
  let cursorOffsetFromEnd: Int?
}

enum SnippetTemplateRenderer {
  private enum Segment {
    case literal(String)
    case token(String)
  }

  private static let promptPrefix = "prompt:"

  /// The questions of every `{{prompt:...}}` token, in template order, without repeats.
  static func prompts(in template: String) -> [String] {
    var questions: [String] = []

    for case .token(let token) in segments(in: template) {
      guard let question = promptQuestion(in: token), !questions.contains(question) else {
        continue
      }
      questions.append(question)
    }

    return questions
  }

  static func render(_ template: String, answers: [String: String] = [:]) -> RenderedSnippet {
    var output = ""
    var cursorPosition: Int?

    for segment in segments(in: template) {
      switch segment {
      case .literal(let text):
        output += text
      case .token("cursor"):
        cursorPosition = output.count
      case .token(let token):
        if let question = promptQuestion(in: token) {
          output += answers[question] ?? ""
        } else {
          output += resolveToken(token)
        }
      }
    }

    if let cursorPosition {
      return RenderedSnippet(
        text: output, cursorOffsetFromEnd: max(0, output.count - cursorPosition))
    }

    return RenderedSnippet(text: output, cursorOffsetFromEnd: nil)
  }

  private static func segments(in template: String) -> [Segment] {
    var segments: [Segment] = []
    var cursor = template.startIndex

    while let openRange = template[cursor...].range(of: "{{"),
      let closeRange = template[openRange.upperBound...].range(of: "}}")
    {
      segments.append(.literal(String(template[cursor..<openRange.lowerBound])))
      segments.append(
        .token(
          template[openRange.upperBound..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)))
      cursor = closeRange.upperBound
    }

    if cursor < template.endIndex {
      segments.append(.literal(String(template[cursor...])))
    }

    return segments
  }

  private static func promptQuestion(in token: String) -> String? {
    guard token.hasPrefix(promptPrefix) else { return nil }
    return String(token.dropFirst(promptPrefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func resolveToken(_ token: String) -> String {
    switch token {
    case "date":
      return formatDate("yyyy-MM-dd")
    case "time":
      return formatDate("HH:mm")
    case "datetime":
      return formatDate("yyyy-MM-dd HH:mm")
    case "uuid":
      return UUID().uuidString
    case "clipboard":
      return NSPasteboard.general.string(forType: .string) ?? ""
    default:
      if token.hasPrefix("date:") {
        let format = String(token.dropFirst("date:".count))
        return formatDate(format)
      }
      return "{{\(token)}}"
    }
  }

  private static func formatDate(_ format: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format
    return formatter.string(from: Date())
  }
}
