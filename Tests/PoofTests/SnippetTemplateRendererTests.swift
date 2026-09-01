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

  func testPromptsAreCollectedInOrderWithoutRepeats() {
    let questions = SnippetTemplateRenderer.prompts(
      in: "Hi {{prompt: Their name }}, I'm {{prompt:Your name}}. Bye {{prompt:Their name}}")

    XCTAssertEqual(questions, ["Their name", "Your name"])
  }

  func testPromptsIgnoresNonPromptTokens() {
    XCTAssertEqual(SnippetTemplateRenderer.prompts(in: "{{date}} {{cursor}} {{unknown}}"), [])
  }

  func testRenderSubstitutesAnswersAndKeepsCursorOffset() {
    let rendered = SnippetTemplateRenderer.render(
      "Hi {{prompt:Name}},{{cursor}} bye {{prompt:Name}}",
      answers: ["Name": "Jamie"]
    )

    XCTAssertEqual(rendered.text, "Hi Jamie, bye Jamie")
    XCTAssertEqual(rendered.cursorOffsetFromEnd, 10)
  }

  func testRenderWithoutAnswerLeavesPromptEmpty() {
    let rendered = SnippetTemplateRenderer.render("Hi {{prompt:Name}}!")

    XCTAssertEqual(rendered.text, "Hi !")
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
