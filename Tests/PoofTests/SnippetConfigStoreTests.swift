import Foundation
import XCTest
@testable import Poof

final class SnippetConfigStoreTests: XCTestCase {
  private var tempDirectoryURL: URL!
  private var defaultsSuiteName: String!
  private var userDefaults: UserDefaults!

  override func setUpWithError() throws {
    defaultsSuiteName = "PoofTests.\(UUID().uuidString)"
    guard let userDefaults = UserDefaults(suiteName: defaultsSuiteName) else {
      throw NSError(domain: "SnippetConfigStoreTests", code: 1)
    }
    self.userDefaults = userDefaults

    tempDirectoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("PoofTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectoryURL)
    if let defaultsSuiteName {
      UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
    }
    tempDirectoryURL = nil
    userDefaults = nil
    defaultsSuiteName = nil
  }

  @MainActor
  func testReloadReportsDuplicateTriggersAndLastFileWins() throws {
    let snippetsDir = tempDirectoryURL.appendingPathComponent("snippets", isDirectory: true)
    try FileManager.default.createDirectory(at: snippetsDir, withIntermediateDirectories: true)

    try """
    [[snippets]]
    trigger = ":dup"
    replace = "first"
    """.write(to: snippetsDir.appendingPathComponent("a.toml"), atomically: true, encoding: .utf8)

    try """
    [[snippets]]
    trigger = ":dup"
    replace = "second"
    """.write(to: snippetsDir.appendingPathComponent("b.toml"), atomically: true, encoding: .utf8)

    let preferences = Preferences(userDefaults: userDefaults)
    preferences.configDirectoryURL = tempDirectoryURL
    let store = SnippetConfigStore(preferences: preferences)

    store.reload()

    XCTAssertEqual(store.snippets.count, 1)
    XCTAssertEqual(store.snippets.first?.replacementTemplate, "second")
    XCTAssertTrue(
      store.lastErrors.contains(where: { $0.contains("duplicate trigger ':dup' in b.toml; overriding a.toml") })
    )
  }

  @MainActor
  func testWatcherRecoversAfterDirectoryRename() async throws {
    let snippetsDir = tempDirectoryURL.appendingPathComponent("snippets", isDirectory: true)
    try FileManager.default.createDirectory(at: snippetsDir, withIntermediateDirectories: true)

    let watchedFile = snippetsDir.appendingPathComponent("watch.toml")
    try """
    [[snippets]]
    trigger = ":watch"
    replace = "first"
    """.write(to: watchedFile, atomically: true, encoding: .utf8)

    let preferences = Preferences(userDefaults: userDefaults)
    preferences.configDirectoryURL = tempDirectoryURL
    let store = SnippetConfigStore(preferences: preferences)
    store.reload()
    XCTAssertEqual(store.snippets.first?.replacementTemplate, "first")

    let refreshed = expectation(description: "watcher reloads snippets after directory is recreated")
    store.onUpdate = { snippets, _ in
      if snippets.contains(where: { $0.trigger == ":watch" && $0.replacementTemplate == "second" }) {
        refreshed.fulfill()
      }
    }
    store.startWatching()
    defer {
      store.stopWatching()
      store.onUpdate = nil
    }

    let movedDirectory = tempDirectoryURL
      .deletingLastPathComponent()
      .appendingPathComponent("\(tempDirectoryURL.lastPathComponent)-moved", isDirectory: true)
    try FileManager.default.moveItem(at: tempDirectoryURL, to: movedDirectory)
    defer {
      try? FileManager.default.removeItem(at: movedDirectory)
    }

    try FileManager.default.createDirectory(at: snippetsDir, withIntermediateDirectories: true)
    try """
    [[snippets]]
    trigger = ":watch"
    replace = "second"
    """.write(to: watchedFile, atomically: true, encoding: .utf8)

    // Allow restartWatching debounce to complete before triggering another write.
    try await Task.sleep(nanoseconds: 700_000_000)
    try """
    [[snippets]]
    trigger = ":watch"
    replace = "second"
    description = "updated"
    """.write(to: watchedFile, atomically: true, encoding: .utf8)

    await fulfillment(of: [refreshed], timeout: 3.0)
    XCTAssertEqual(store.snippets.first(where: { $0.trigger == ":watch" })?.replacementTemplate, "second")
  }
}
