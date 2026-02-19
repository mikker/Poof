import Darwin
import Foundation
import TOMLKit

@MainActor
final class SnippetConfigStore {
  private let fileManager: FileManager
  private let preferences: Preferences
  private let decoder = TOMLDecoder()

  private var directoryWatchFD: CInt = -1
  private var directoryWatchSource: DispatchSourceFileSystemObject?
  private var pendingReload: DispatchWorkItem?
  private var pendingWatchRestart: DispatchWorkItem?

  private(set) var snippets: [Snippet] = []
  private(set) var lastErrors: [String] = []

  var onUpdate: (([Snippet], [String]) -> Void)?

  init(preferences: Preferences, fileManager: FileManager = .default) {
    self.preferences = preferences
    self.fileManager = fileManager
  }

  var configDirectoryURL: URL {
    preferences.configDirectoryURL
  }

  func updateConfigDirectory(_ url: URL) {
    preferences.configDirectoryURL = url.standardizedFileURL
    ensureBootstrapFilesExist()
    reload()
    restartWatching()
  }

  func ensureBootstrapFilesExist() {
    do {
      try fileManager.createDirectory(
        at: configDirectoryURL,
        withIntermediateDirectories: true
      )

      let snippetsDirectory = configDirectoryURL.appendingPathComponent("snippets", isDirectory: true)
      try fileManager.createDirectory(at: snippetsDirectory, withIntermediateDirectories: true)

      let sampleFile = snippetsDirectory.appendingPathComponent("default.toml")
      if !fileManager.fileExists(atPath: sampleFile.path) {
        try defaultSnippetFileContents().write(to: sampleFile, atomically: true, encoding: .utf8)
      }
    } catch {
      lastErrors = ["Unable to prepare config directory: \(error.localizedDescription)"]
      onUpdate?(snippets, lastErrors)
    }
  }

  func reload() {
    let files = discoverConfigFiles()

    var deduplicatedSnippets: [String: Snippet] = [:]
    var triggerSources: [String: String] = [:]
    var discoveredErrors: [String] = []

    for fileURL in files {
      do {
        let data = try Data(contentsOf: fileURL)
        guard let toml = String(data: data, encoding: .utf8) else {
          throw CocoaError(.fileReadCorruptFile)
        }

        let loadedSnippets = try SnippetFileParser.parse(toml, decoder: decoder)
        for snippet in loadedSnippets {
          if let previousSource = triggerSources[snippet.trigger] {
            discoveredErrors.append(
              "duplicate trigger '\(snippet.trigger)' in \(fileURL.lastPathComponent); overriding \(previousSource)"
            )
          }

          deduplicatedSnippets[snippet.trigger] = snippet
          triggerSources[snippet.trigger] = fileURL.lastPathComponent
        }
      } catch {
        discoveredErrors.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
      }
    }

    snippets = deduplicatedSnippets.values.sorted {
      if $0.trigger.count == $1.trigger.count {
        return $0.trigger < $1.trigger
      }
      return $0.trigger.count > $1.trigger.count
    }

    lastErrors = discoveredErrors
    onUpdate?(snippets, lastErrors)
  }

  func startWatching() {
    stopWatching()

    ensureBootstrapFilesExist()

    let path = configDirectoryURL.path
    directoryWatchFD = open(path, O_EVTONLY)
    guard directoryWatchFD >= 0 else {
      scheduleWatchRestart()
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: directoryWatchFD,
      eventMask: [.write, .extend, .attrib, .delete, .rename],
      queue: .main
    )

    source.setEventHandler { [weak self, weak source] in
      guard let self, let source else { return }
      self.handleWatchEvent(source.data)
    }

    source.setCancelHandler { [fd = directoryWatchFD] in
      if fd >= 0 {
        close(fd)
      }
    }

    directoryWatchSource = source
    source.resume()
  }

  func stopWatching() {
    pendingReload?.cancel()
    pendingReload = nil
    pendingWatchRestart?.cancel()
    pendingWatchRestart = nil

    directoryWatchSource?.cancel()
    directoryWatchSource = nil
    directoryWatchFD = -1
  }

  func restartWatching() {
    stopWatching()
    startWatching()
  }

  private func scheduleReload() {
    pendingReload?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      Task { @MainActor [weak self] in
        self?.reload()
      }
    }

    pendingReload = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: workItem)
  }

  private func handleWatchEvent(_ event: DispatchSource.FileSystemEvent) {
    scheduleReload()
    if event.contains(.delete) || event.contains(.rename) {
      scheduleWatchRestart()
    }
  }

  private func scheduleWatchRestart() {
    pendingWatchRestart?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      self?.restartWatching()
    }

    pendingWatchRestart = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: workItem)
  }

  private func discoverConfigFiles() -> [URL] {
    guard fileManager.fileExists(atPath: configDirectoryURL.path) else { return [] }

    var files: [URL] = []
    if let enumerator = fileManager.enumerator(
      at: configDirectoryURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) {
      for case let fileURL as URL in enumerator {
        guard fileURL.pathExtension.lowercased() == "toml" else { continue }
        files.append(fileURL)
      }
    }

    return files.sorted { $0.path < $1.path }
  }

  private func defaultSnippetFileContents() -> String {
    """
    [[snippets]]
    trigger = ":date"
    replace = "{{date}}"
    description = "Current date"

    [[snippets]]
    trigger = ":time"
    replace = "{{time}}"
    description = "Current time"

    [[snippets]]
    trigger = ":clip"
    replace = "{{clipboard}}"
    description = "Paste current clipboard text"

    [[snippets]]
    trigger = ":sig"
    replace = "Best regards,\\nYour Name{{cursor}}"
    description = "Signature snippet with cursor placement"
    """
  }
}
