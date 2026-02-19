import XCTest
@testable import Poof

final class SnippetFileParserTests: XCTestCase {
  func testParseSnippetArrayDocument() throws {
    let toml = """
    [[snippets]]
    trigger = ":a"
    replace = "A"

    [[snippets]]
    trigger = ":b"
    replace = "B"
    disabled = true
    """

    let snippets = try SnippetFileParser.parse(toml)

    XCTAssertEqual(snippets.count, 1)
    XCTAssertEqual(snippets[0].trigger, ":a")
    XCTAssertEqual(snippets[0].replacementTemplate, "A")
  }

  func testParseSingleSnippetDocument() throws {
    let toml = """
    trigger = ":solo"
    replace = "value"
    case_sensitive = false
    """

    let snippets = try SnippetFileParser.parse(toml)

    XCTAssertEqual(snippets.count, 1)
    XCTAssertEqual(snippets[0].trigger, ":solo")
    XCTAssertEqual(snippets[0].caseSensitive, false)
  }

  func testParseThrowsWhenNoValidSnippetsExist() {
    let toml = """
    [[snippets]]
    trigger = "   "
    replace = "A"

    [[snippets]]
    trigger = ":disabled"
    replace = "B"
    disabled = true
    """

    XCTAssertThrowsError(try SnippetFileParser.parse(toml)) { error in
      XCTAssertEqual(error as? SnippetFileParserError, .noSnippetsFound)
    }
  }
}
