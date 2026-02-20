import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
  init(model: AppModel) {
    let rootView = SettingsView(model: model)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
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

// MARK: - Settings View

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
    .frame(minWidth: 480, minHeight: 440)
    .onAppear {
      launchAtLogin.refresh()
      refreshPermissions()
    }
  }

  // MARK: - Permissions

  private var permissionsSection: some View {
    Section {
      permissionRow("Accessibility", granted: accessibilityTrusted)
      permissionRow("Input Monitoring", granted: inputMonitoringTrusted)

      HStack(spacing: 8) {
        Button("Open Accessibility") {
          openPrivacyPane("Privacy_Accessibility")
        }
        Button("Open Input Monitoring") {
          openPrivacyPane("Privacy_ListenEvent")
        }
        Spacer()
        Button("Request Prompts") {
          requestPermissionPrompts()
        }
        Button {
          refreshPermissions()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help("Refresh permission status")
      }
    } header: {
      Label("Permissions", systemImage: "lock.shield")
    }
  }

  private func permissionRow(_ name: String, granted: Bool) -> some View {
    LabeledContent(name) {
      HStack(spacing: 4) {
        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
          .foregroundStyle(granted ? .green : .orange)
          .imageScale(.small)
        Text(granted ? "Granted" : "Not Granted")
          .foregroundStyle(granted ? Color.secondary : Color.orange)
      }
    }
  }

  // MARK: - Startup

  private var startupSection: some View {
    Section {
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
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .font(.footnote)
          .foregroundStyle(.orange)
      }
    } header: {
      Label("Startup", systemImage: "power")
    }
  }

  // MARK: - Expansion

  private var expansionSection: some View {
    Section {
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
    } header: {
      Label("Expansion", systemImage: "text.badge.plus")
    }
  }

  // MARK: - Configuration

  private var configurationSection: some View {
    Section {
      LabeledContent("Folder") {
        Text(model.configDirectoryPath)
          .font(.footnote.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .multilineTextAlignment(.trailing)
      }

      HStack(spacing: 8) {
        Button("Choose\u{2026}") {
          model.chooseConfigDirectory()
        }
        Button("Reveal") {
          model.revealConfigDirectory()
        }
        Button("Reset") {
          model.resetConfigDirectory()
        }
        Spacer()
        Button {
          model.reload()
        } label: {
          Label("Reload Snippets", systemImage: "arrow.clockwise")
        }
      }
    } header: {
      Label("Configuration", systemImage: "folder")
    }
  }

  // MARK: - Status

  private var statusSection: some View {
    Section {
      LabeledContent("Active snippets") {
        Text("\(model.snippetCount)")
          .monospacedDigit()
      }

      if model.errors.isEmpty {
        Label("No config errors detected.", systemImage: "checkmark.circle")
          .foregroundStyle(.secondary)
          .font(.footnote)
      } else {
        ForEach(model.errors.prefix(8), id: \.self) { error in
          Label {
            Text(error)
          } icon: {
            Image(systemName: "exclamationmark.triangle")
          }
          .foregroundStyle(.orange)
          .font(.footnote)
        }
      }
    } header: {
      Label("Status", systemImage: "info.circle")
    }
  }

  // MARK: - Template Tokens

  private var templateTokensSection: some View {
    Section {
      FlowLayout(spacing: 6) {
        ForEach(Self.templateTokens, id: \.self) { token in
          Text(token)
            .font(.caption.monospaced())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
      }
      .textSelection(.enabled)
    } header: {
      Label("Template Tokens", systemImage: "curlybraces")
    }
  }

  private static let templateTokens = [
    "{{date}}", "{{time}}", "{{datetime}}", "{{date:yyyy-MM-dd}}",
    "{{clipboard}}", "{{uuid}}", "{{cursor}}",
  ]

  // MARK: - Helpers

  private func refreshPermissions() {
    accessibilityTrusted = AXIsProcessTrusted()
    inputMonitoringTrusted = Self.hasInputMonitoringPermission()
  }

  private func requestPermissionPrompts() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)

    _ = CGRequestListenEventAccess()

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
    return CGPreflightListenEventAccess()
  }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = arrange(proposal: proposal, subviews: subviews)
    return result.size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let result = arrange(proposal: proposal, subviews: subviews)
    for (index, position) in result.positions.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
        proposal: .unspecified
      )
    }
  }

  private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
    let maxWidth = proposal.width ?? .infinity
    var positions: [CGPoint] = []
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var lineHeight: CGFloat = 0
    var totalWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)

      if currentX + size.width > maxWidth, currentX > 0 {
        currentX = 0
        currentY += lineHeight + spacing
        lineHeight = 0
      }

      positions.append(CGPoint(x: currentX, y: currentY))
      lineHeight = max(lineHeight, size.height)
      currentX += size.width + spacing
      totalWidth = max(totalWidth, currentX - spacing)
    }

    return ArrangeResult(
      size: CGSize(width: totalWidth, height: currentY + lineHeight),
      positions: positions
    )
  }

  private struct ArrangeResult {
    var size: CGSize
    var positions: [CGPoint]
  }
}
