import Foundation
import TOMLKit

enum SnippetFileParserError: Equatable, LocalizedError {
  case noSnippetsFound

  var errorDescription: String? {
    switch self {
    case .noSnippetsFound:
      return "no snippets found"
    }
  }
}

enum SnippetFileParser {
  private struct SnippetFile: Decodable {
    let snippets: [SnippetDefinition]?
    let snippet: [SnippetDefinition]?
  }

  private struct SnippetDefinition: Decodable {
    let trigger: String
    let replace: String
    let details: String?
    let caseSensitive: Bool?
    let disabled: Bool?

    enum CodingKeys: String, CodingKey {
      case trigger
      case replace
      case details = "description"
      case caseSensitive = "case_sensitive"
      case disabled
    }

    var asSnippet: Snippet? {
      guard disabled != true else { return nil }
      let normalizedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalizedTrigger.isEmpty else { return nil }

      return Snippet(
        trigger: normalizedTrigger,
        replacementTemplate: replace,
        details: details,
        caseSensitive: caseSensitive ?? true
      )
    }
  }

  static func parse(_ toml: String, decoder: TOMLDecoder = TOMLDecoder()) throws -> [Snippet] {
    if let file = try? decoder.decode(SnippetFile.self, from: toml) {
      let fileDefinitions = (file.snippets ?? []) + (file.snippet ?? [])
      if !fileDefinitions.isEmpty {
        let snippets = fileDefinitions.compactMap(\.asSnippet)
        guard !snippets.isEmpty else {
          throw SnippetFileParserError.noSnippetsFound
        }
        return snippets
      }
    }

    let definition = try decoder.decode(SnippetDefinition.self, from: toml)
    let snippets = [definition].compactMap(\.asSnippet)
    guard !snippets.isEmpty else {
      throw SnippetFileParserError.noSnippetsFound
    }

    return snippets
  }
}
