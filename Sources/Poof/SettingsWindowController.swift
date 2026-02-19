import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
  init(model: AppModel) {
    let rootView = SettingsView(model: model)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Poof Settings"
    window.center()
    window.contentView = NSHostingView(rootView: rootView)

    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

private struct SettingsView: View {
  @ObservedObject var model: AppModel
  @StateObject private var launchAtLogin = LaunchAtLoginController()
  @State private var accessibilityTrusted = AXIsProcessTrusted()
  @State private var inputMonitoringTrusted = SettingsView.hasInputMonitoringPermission()

  var body: some View {
    Form {
      permissionsSection
      startupSection
      expansionSection
      configurationSection
      statusSection
      templateTokensSection
    }
    .formStyle(.grouped)
    .padding(18)
    .frame(minWidth: 720, minHeight: 440)
    .onAppear {
      launchAtLogin.refresh()
      refreshPermissions()
    }
  }

  private var permissionsSection: some View {
    Section("Permissions") {
      LabeledContent("Accessibility") {
        Text(accessibilityTrusted ? "Granted" : "Not granted")
          .foregroundStyle(accessibilityTrusted ? Color.secondary : Color.orange)
      }
      LabeledContent("Input Monitoring") {
        Text(inputMonitoringTrusted ? "Granted" : "Not granted")
          .foregroundStyle(inputMonitoringTrusted ? Color.secondary : Color.orange)
      }

      HStack {
        Button("Open Accessibility") {
          openPrivacyPane("Privacy_Accessibility")
        }
        Button("Open Input Monitoring") {
          openPrivacyPane("Privacy_ListenEvent")
        }
        Button("Request prompts") {
          requestPermissionPrompts()
        }
        Button("Refresh") {
          refreshPermissions()
        }
      }
    }
  }

  private var startupSection: some View {
    Section("Startup") {
      Toggle(
        "Launch Poof at login",
        isOn: Binding(
          get: { launchAtLogin.isEnabled },
          set: { launchAtLogin.setEnabled($0) }
        )
      )

      if let statusMessage = launchAtLogin.statusMessage {
        Text(statusMessage)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if let errorMessage = launchAtLogin.errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.orange)
      }
    }
  }

  private var expansionSection: some View {
    Section("Expansion") {
      Picker(
        "Trigger behavior",
        selection: Binding(
          get: { model.triggerMode },
          set: { model.setTriggerMode($0) }
        )
      ) {
        ForEach(ExpansionTriggerMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.radioGroup)
    }
  }

  private var configurationSection: some View {
    Section("Configuration") {
      LabeledContent("Folder") {
        Text(model.configDirectoryPath)
          .font(.footnote.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .multilineTextAlignment(.trailing)
      }

      HStack {
        Button("Choose…") {
          model.chooseConfigDirectory()
        }
        Button("Reveal") {
          model.revealConfigDirectory()
        }
        Button("Reset") {
          model.resetConfigDirectory()
        }
        Button("Reload snippets") {
          model.reload()
        }
      }
    }
  }

  private var statusSection: some View {
    Section("Status") {
      LabeledContent("Active snippets") {
        Text("\(model.snippetCount)")
      }

      if model.errors.isEmpty {
        Text("No config errors detected.")
          .foregroundStyle(.secondary)
      } else {
        Text("Config errors")
          .font(.headline)
        ForEach(model.errors.prefix(8), id: \.self) { error in
          Text(error)
            .foregroundStyle(.orange)
            .font(.footnote)
        }
      }
    }
  }

  private var templateTokensSection: some View {
    Section("Template tokens") {
      Text(
        """
        {{date}} {{time}} {{datetime}} {{date:yyyy-MM-dd}}
        {{clipboard}} {{uuid}} {{cursor}}
        """
      )
      .font(.footnote.monospaced())
      .textSelection(.enabled)
    }
  }

  private func refreshPermissions() {
    accessibilityTrusted = AXIsProcessTrusted()
    inputMonitoringTrusted = Self.hasInputMonitoringPermission()
  }

  private func requestPermissionPrompts() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)

    if #available(macOS 10.15, *) {
      _ = CGRequestListenEventAccess()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
      refreshPermissions()
    }
  }

  private func openPrivacyPane(_ pane: String) {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    else { return }
    NSWorkspace.shared.open(url)
  }

  private static func hasInputMonitoringPermission() -> Bool {
    if #available(macOS 10.15, *) {
      return CGPreflightListenEventAccess()
    }
    return true
  }
}
