import XCTest
@testable import Poof

final class SnippetTemplateRendererTests: XCTestCase {
  func testRenderCursorTokenTracksOffsetFromEnd() {
    let rendered = SnippetTemplateRenderer.render("Hello {{cursor}}world")

    XCTAssertEqual(rendered.text, "Hello world")
    XCTAssertEqual(rendered.cursorOffsetFromEnd, 5)
  }

  func testRenderUnknownTokenLeavesLiteralToken() {
    let rendered = SnippetTemplateRenderer.render("prefix {{unknown}} suffix")

    XCTAssertEqual(rendered.text, "prefix {{unknown}} suffix")
    XCTAssertNil(rendered.cursorOffsetFromEnd)
  }

  func testCaseInsensitiveSuffixMatching() {
    let snippet = Snippet(
      trigger: ":sig",
      replacementTemplate: "Best",
      details: nil,
      caseSensitive: false
    )

    XCTAssertTrue(snippet.matchesSuffix(in: "abc:SIG"))
  }
}
