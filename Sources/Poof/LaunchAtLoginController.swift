import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
  @Published private(set) var isEnabled = false
  @Published private(set) var statusMessage: String?
  @Published private(set) var errorMessage: String?

  init() {
    refresh()
  }

  func refresh() {
    updateStatus(clearError: true)
  }

  func setEnabled(_ enabled: Bool) {
    guard #available(macOS 13.0, *) else { return }

    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }

    updateStatus(clearError: false)
  }

  private func updateStatus(clearError: Bool) {
    if clearError {
      errorMessage = nil
    }

    guard #available(macOS 13.0, *) else {
      isEnabled = false
      statusMessage = "Launch at login requires macOS 13+."
      return
    }

    let status = SMAppService.mainApp.status
    isEnabled = status == .enabled

    switch status {
    case .enabled:
      statusMessage = nil
    case .requiresApproval:
      statusMessage = "Enable Poof in System Settings > General > Login Items."
    case .notFound:
      statusMessage = "Unavailable in this run mode. Works from installed app bundle."
    case .notRegistered:
      statusMessage = nil
    @unknown default:
      statusMessage = nil
    }
  }
}
