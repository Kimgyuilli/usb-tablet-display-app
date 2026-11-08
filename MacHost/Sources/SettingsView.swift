import Cocoa
import SwiftUI

// MARK: - Layout constants

enum SettingsLayout {
    static let windowWidth: CGFloat = 820
    static let windowHeight: CGFloat = 600
    static let minWidth: CGFloat = 720
    static let minHeight: CGFloat = 520
    static let sidebarWidth: CGFloat = 230
}

// MARK: - Pages

enum SettingsPage: String, CaseIterable, Identifiable {
    case dashboard, general, display, streaming, input, wireless, status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .general: return "General"
        case .display: return "Display"
        case .streaming: return "Streaming"
        case .input: return "Touch Input"
        case .wireless: return "Wireless"
        case .status: return "Status"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .general: return "gearshape.fill"
        case .display: return "display"
        case .streaming: return "dot.radiowaves.left.and.right"
        case .input: return "hand.point.up.left.fill"
        case .wireless: return "wifi"
        case .status: return "waveform.path.ecg"
        }
    }

    /// Tinted rounded-square icon backgrounds, System Settings style.
    var tint: Color {
        switch self {
        case .dashboard: return .indigo
        case .general: return .gray
        case .display: return .blue
        case .streaming: return .purple
        case .input: return .orange
        case .wireless: return .teal
        case .status: return .green
        }
    }
}

// MARK: - Root view

struct SettingsView: View {
    @ObservedObject var settings: DisplaySettings
    @ObservedObject var updater = AppUpdater.shared
    @AppStorage("SideScreen_lastPage") private var page: SettingsPage = .dashboard

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(settings: settings, updater: updater, page: $page)
                .frame(width: SettingsLayout.sidebarWidth)

            Divider().ignoresSafeArea()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .frame(minWidth: SettingsLayout.minWidth, minHeight: SettingsLayout.minHeight)
        .onAppear {
            if LiveSession.demoRequested && !settings.clientConnected {
                settings.clientConnected = true
                LiveSession.shared.startDemo()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.title)
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 4)

            Group {
                switch page {
                case .dashboard: DashboardPage(settings: settings)
                case .general: GeneralPage(settings: settings, page: $page)
                case .display: DisplayPage(settings: settings)
                case .streaming: StreamingPage(settings: settings)
                case .input: InputPage(settings: settings)
                case .wireless: WirelessPage(settings: settings)
                case .status: StatusPage(settings: settings)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Sidebar

struct SettingsSidebar: View {
    @ObservedObject var settings: DisplaySettings
    @ObservedObject var updater: AppUpdater
    @Binding var page: SettingsPage
    @State private var showAbout = false
    @State private var showResetConfirmation = false

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)

            VStack(alignment: .leading, spacing: 0) {
                // Room for the traffic lights.
                Color.clear.frame(height: 44)

                Button { page = .dashboard } label: {
                    ConnectionCard(settings: settings)
                }
                .buttonStyle(.plain)
                .help("Open Dashboard")
                .padding(.horizontal, 12)
                    .padding(.bottom, 12)

                VStack(spacing: 2) {
                    ForEach(SettingsPage.allCases) { item in
                        SidebarRow(page: item,
                                   isSelected: page == item,
                                   badge: badge(for: item)) {
                            page = item
                        }
                    }
                }
                .padding(.horizontal, 10)

                Spacer(minLength: 12)

                footer
                    .padding(12)
            }
        }
    }

    private func badge(for item: SettingsPage) -> Int {
        guard item == .status else { return 0 }
        var count = 0
        if !settings.hasScreenRecordingPermission { count += 1 }
        if !settings.displaysHaveSeparateSpaces { count += 1 }
        return count
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { settings.toggleServer() }
            } label: {
                Label(settings.isRunning ? "Stop" : "Start Streaming",
                      systemImage: settings.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.isRunning ? .red : .accentColor)
            .controlSize(.large)
            .disabled(!settings.hasScreenRecordingPermission)
            .help(settings.hasScreenRecordingPermission
                  ? (settings.isRunning ? "Stop streaming" : "Start streaming to the tablet")
                  : "Grant Screen Recording permission first (see Status)")

            Menu {
                Button("About Side Screen") { showAbout = true }
                Button("Check for Updates…") { AppUpdater.shared.checkForUpdates(nil) }
                    .disabled(!updater.canCheckForUpdates)
                Divider()
                Button("Reset All Settings…") { showResetConfirmation = true }
                Button("Restart App") { restartApp() }
                Divider()
                Button("Quit Side Screen") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.primary.opacity(0.06)))
            .help("More")
            .popover(isPresented: $showAbout, arrowEdge: .top) {
                AboutPopover(updater: updater)
            }
        }
        .alert("Reset all settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
                if let window = NSApp.windows.first(where: { $0.title == "Side Screen" }) {
                    window.center()
                }
            }
        } message: {
            Text("All settings will return to their default values.")
        }
    }

    /// Restart the app by launching a new instance and terminating the current one.
    private func restartApp() {
        let appPath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5 && open \"\(appPath)\""]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            print("❌ Failed to restart: \(error)")
        }
    }
}

struct SidebarRow: View {
    let page: SettingsPage
    let isSelected: Bool
    var badge: Int = 0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(page.tint.gradient))

                Text(page.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                Spacer()

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (hovering ? Color.primary.opacity(0.06) : .clear))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Live connection summary at the top of the sidebar.
struct ConnectionCard: View {
    @ObservedObject var settings: DisplaySettings

    private enum Phase { case stopped, waiting, connected }

    private var state: Phase {
        if settings.clientConnected { return .connected }
        return settings.isRunning ? .waiting : .stopped
    }

    private var color: Color {
        switch state {
        case .stopped: return .secondary
        case .waiting: return .orange
        case .connected: return .green
        }
    }

    private var title: String {
        switch state {
        case .stopped: return "Not streaming"
        case .waiting: return "Waiting for tablet"
        case .connected: return settings.currentWirelessDevice ?? "Tablet connected"
        }
    }

    private var subtitle: String {
        let mode = settings.connectionMode == .usb ? "USB" : "Wi‑Fi"
        switch state {
        case .stopped:
            return "\(mode) · \(settings.resolution.replacingOccurrences(of: "x", with: "×"))\(settings.hiDPI ? " HiDPI" : "")"
        case .waiting:
            return "\(mode) · port \(settings.port)"
        case .connected:
            return "\(mode) · \(Int(settings.currentFPS.rounded())) fps · \(String(format: "%.0f", settings.currentBitrate)) Mbps"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 30, height: 30)
                Image(systemName: settings.connectionMode == .usb ? "cable.connector" : "wifi")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .animation(.easeInOut(duration: 0.2), value: settings.isRunning)
        .animation(.easeInOut(duration: 0.2), value: settings.clientConnected)
    }
}

// MARK: - Shared building blocks

/// Title + secondary description, used as a Form row label.
struct RowLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Inline notice for warnings / required actions.
struct Callout: View {
    enum Kind { case warning, info }
    let kind: Kind
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    private var color: Color { kind == .warning ? .orange : .blue }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(color)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// Small "?" button that shows a longer explanation.
struct HintButton: View {
    let hint: String
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(hint)
        .popover(isPresented: $show, arrowEdge: .top) {
            Text(hint)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(12)
        }
    }
}

struct StatusRow: View {
    let title: String
    let status: String
    let color: Color
    var hint: String?

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(status).foregroundStyle(color == .secondary ? Color.secondary : Color.primary)
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if let hint { HintButton(hint: hint) }
            }
        }
    }
}

enum SystemSettingsLink {
    static func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
    static let screenRecording = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    static let accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    static let desktopDock = "x-apple.systempreferences:com.apple.Desktop-Settings.extension"
    static let displays = "x-apple.systempreferences:com.apple.preference.displays?displayArrangement"
}

private var isTahoeOrLater: Bool {
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
}

// MARK: - General

struct GeneralPage: View {
    @ObservedObject var settings: DisplaySettings
    @Binding var page: SettingsPage
    @State private var daemonEnabled = false

    var body: some View {
        Form {
            if !settings.hasScreenRecordingPermission {
                Section {
                    Callout(kind: .warning,
                            title: isTahoeOrLater ? "Screen & System Audio Recording required" : "Screen Recording required",
                            message: "Side Screen needs this permission to capture the virtual display.",
                            actionTitle: "Open System Settings") {
                        SystemSettingsLink.open(SystemSettingsLink.screenRecording)
                    }
                }
            }

            Section("Connection") {
                Picker(selection: $settings.connectionMode) {
                    Label("USB", systemImage: "cable.connector").tag(ConnectionMode.usb)
                    Label("Wireless", systemImage: "wifi").tag(ConnectionMode.wireless)
                } label: {
                    RowLabel(title: "Mode",
                             detail: settings.connectionMode == .usb
                                ? "Lowest latency. Uses adb over the cable."
                                : "Pair once with a QR code, then reconnect over Wi‑Fi.")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                if settings.connectionMode == .wireless {
                    Button("Show pairing QR code…") { page = .wireless }
                        .buttonStyle(.link)
                }
            }

            Section("Startup") {
                Toggle(isOn: Binding(
                    get: { daemonEnabled },
                    set: { newValue in
                        do {
                            if newValue { try DaemonManager.shared.enable() } else { try DaemonManager.shared.disable() }
                        } catch {
                            print("Daemon toggle failed: \(error)")
                        }
                        daemonEnabled = DaemonManager.shared.isEnabled
                    }
                )) {
                    RowLabel(title: "Launch at login",
                             detail: "Run Side Screen in the background after you log in.")
                }

                Toggle(isOn: $settings.autoStartStreamingOnLaunch) {
                    RowLabel(title: "Start streaming automatically",
                             detail: "The tablet can connect without touching the Mac.")
                }

                Picker("Startup mode", selection: $settings.startupMode) {
                    Text("USB").tag(ConnectionMode.usb)
                    Text("Wireless").tag(ConnectionMode.wireless)
                }
                .disabled(!settings.autoStartStreamingOnLaunch)
            }
        }
        .toggleStyle(.switch)
        .onAppear { daemonEnabled = DaemonManager.shared.isEnabled }
    }
}

// MARK: - Display

struct DisplayPage: View {
    @ObservedObject var settings: DisplaySettings
    // Plain strings for the custom resolution fields: TextField(value:format:)
    // only commits on Return/focus-loss and injects locale grouping separators.
    @State private var customWidthText = ""
    @State private var customHeightText = ""

    private var customWidthValue: Int? { Int(customWidthText.trimmingCharacters(in: .whitespaces)) }
    private var customHeightValue: Int? { Int(customHeightText.trimmingCharacters(in: .whitespaces)) }
    private var customResolutionValid: Bool {
        guard let w = customWidthValue, let h = customHeightValue else { return false }
        return DisplaySettings.isValidCustomResolution(width: w, height: h)
    }

    private var effectiveSize: String {
        let parts = settings.resolution.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { return "" }
        let scale = settings.hiDPI ? 2 : 1
        return "\(parts[0] * scale) × \(parts[1] * scale) px"
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.resolution) {
                    if !DisplaySettings.allResolutions.contains(settings.resolution) {
                        Text("\(pretty(settings.resolution)) (Custom)").tag(settings.resolution)
                        Divider()
                    }
                    ForEach(DisplaySettings.resolutionGroups) { group in
                        Section("\(group.name) · \(group.ratio)") {
                            ForEach(group.resolutions, id: \.self) { res in
                                Text(pretty(res)).tag(res)
                            }
                        }
                    }
                } label: {
                    RowLabel(title: "Resolution",
                             detail: settings.hiDPI ? "Rendered at \(effectiveSize)" : nil)
                }

                Toggle(isOn: $settings.hiDPI) {
                    RowLabel(title: "HiDPI (Retina)",
                             detail: settings.isRunning
                                ? "Stop streaming to change this."
                                : "Sharper text at 2× pixels. Pick a lower resolution to make things bigger.")
                }
                .disabled(settings.isRunning)

                LabeledContent("Custom size") {
                    HStack(spacing: 6) {
                        TextField("Width", text: $customWidthText)
                            .frame(width: 64)
                        Text("×").foregroundStyle(.secondary)
                        TextField("Height", text: $customHeightText)
                            .frame(width: 64)
                        Button("Apply") {
                            guard customResolutionValid,
                                  let w = customWidthValue,
                                  let h = customHeightValue else { return }
                            settings.customWidth = w
                            settings.customHeight = h
                            settings.applyCustomResolution()
                        }
                        .disabled(!customResolutionValid)
                    }
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                }
            } header: {
                Text("Resolution")
            } footer: {
                if !customWidthText.isEmpty && !customResolutionValid {
                    Text("Supported range: 640–7680 × 480–4320")
                        .foregroundStyle(.orange)
                }
            }

            Section("Orientation") {
                Picker("Rotation", selection: $settings.rotation) {
                    Text("0°").tag(0)
                    Text("90°").tag(90)
                    Text("180°").tag(180)
                    Text("270°").tag(270)
                }
                .pickerStyle(.segmented)

                Toggle("Flip horizontally", isOn: $settings.flipHorizontal)
                Toggle("Flip vertically", isOn: $settings.flipVertical)

                LabeledContent {
                    Button("Arrange Displays…") { SystemSettingsLink.open(SystemSettingsLink.displays) }
                } label: {
                    RowLabel(title: "Arrangement",
                             detail: "Place the tablet left or right of your Mac in System Settings.")
                }
            }

            Section {
                Picker("Frame rate", selection: $settings.refreshRate) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                    Text("90").tag(90)
                    Text("120").tag(120)
                    if ![30, 60, 90, 120].contains(settings.refreshRate) {
                        Text("\(settings.refreshRate)").tag(settings.refreshRate)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { Double(settings.refreshRate) },
                            set: {
                                let rate = Int($0.rounded())
                                if rate != settings.refreshRate { settings.refreshRate = rate }
                            }
                        ), in: 15...120)
                        Text("\(settings.refreshRate) Hz")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                } label: {
                    Text("Fine-tune")
                }
            } header: {
                Text("Refresh Rate")
            } footer: {
                Text("Lower the rate if your tablet shows artifacts at higher frame rates.")
            }
        }
        .toggleStyle(.switch)
        .onAppear {
            customWidthText = String(settings.customWidth)
            customHeightText = String(settings.customHeight)
        }
    }

    private func pretty(_ res: String) -> String {
        res.replacingOccurrences(of: "x", with: " × ")
    }
}

// MARK: - Streaming

struct StreamingPage: View {
    @ObservedObject var settings: DisplaySettings

    private let presets = [100, 300, 500, 1000, 2000]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.gamingBoost) {
                    RowLabel(title: "Gaming Boost",
                             detail: "1000 Mbps, 120 Hz and the lowest-latency encoder. Overrides the settings below.")
                }
            }

            Section {
                LabeledContent("Bitrate") {
                    Text("\(settings.effectiveBitrate) Mbps")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }

                Picker("Preset", selection: $settings.bitrate) {
                    ForEach(presets, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    if !presets.contains(settings.bitrate) {
                        Text("\(settings.bitrate)").tag(settings.bitrate)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Fine-tune") {
                    Slider(value: Binding(
                        get: { Double(settings.bitrate) },
                        set: {
                            let value = Int(($0 / 10).rounded()) * 10
                            if value != settings.bitrate { settings.bitrate = value }
                        }
                    ), in: 20...5000) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("20").font(.system(size: 10)).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("5000").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }

                Picker(selection: $settings.quality) {
                    Text("Ultra Low").tag("ultralow")
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                } label: {
                    RowLabel(title: "Encoder latency",
                             detail: settings.quality == "ultralow" ? "Fastest encoding, lowest latency." : nil)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Video")
            } footer: {
                if settings.gamingBoost {
                    Label("Locked while Gaming Boost is on", systemImage: "bolt.fill")
                        .foregroundStyle(.orange)
                }
            }
            .disabled(settings.gamingBoost)

            Section {
                LabeledContent("Server port") {
                    TextField("Port", value: $settings.port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .labelsHidden()
                        .disabled(settings.isRunning)
                }
            } header: {
                Text("Network")
            } footer: {
                if settings.isRunning {
                    Text("Stop streaming to change the port.")
                } else if settings.connectionMode == .wireless {
                    Text("Changing the port invalidates existing pairings — re-scan the QR on each tablet.")
                } else if settings.port != 54321 {
                    Text("Custom port — the Android app must use the same port.")
                }
            }
        }
        .toggleStyle(.switch)
    }
}

// MARK: - Touch input

struct InputPage: View {
    @ObservedObject var settings: DisplaySettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.touchEnabled) {
                    RowLabel(title: "Control Mac from the tablet",
                             detail: settings.touchEnabled
                                ? "Taps and drags on the tablet move the Mac pointer."
                                : "The tablet is display-only.")
                }
            }

            Section("Permission") {
                StatusRow(title: "Accessibility",
                          status: settings.hasAccessibilityPermission ? "Granted" : "Not granted",
                          color: settings.hasAccessibilityPermission ? .green : .orange,
                          hint: "Required only for touch input. Streaming works without it.")
                if !settings.hasAccessibilityPermission {
                    Callout(kind: .info,
                            title: "Allow Accessibility to use touch",
                            message: "macOS requires this permission before another device can control the pointer.",
                            actionTitle: "Open System Settings") {
                        SystemSettingsLink.open(SystemSettingsLink.accessibility)
                    }
                }
            }
        }
        .toggleStyle(.switch)
    }
}

// MARK: - Status

struct StatusPage: View {
    @ObservedObject var settings: DisplaySettings

    var body: some View {
        Form {
            if settings.clientConnected {
                Section("Performance") {
                    HStack(spacing: 0) {
                        Metric(title: "Frame rate", value: String(format: "%.0f", settings.currentFPS), unit: "fps")
                        Divider().frame(height: 36)
                        Metric(title: "Bitrate", value: String(format: "%.1f", settings.currentBitrate), unit: "Mbps")
                    }
                }
            }

            if !settings.hasScreenRecordingPermission || !settings.displaysHaveSeparateSpaces {
                Section("Needs attention") {
                    if !settings.hasScreenRecordingPermission {
                        Callout(kind: .warning,
                                title: isTahoeOrLater ? "Screen & System Audio Recording required" : "Screen Recording required",
                                message: "Required to capture the virtual display.",
                                actionTitle: "Open System Settings") {
                            SystemSettingsLink.open(SystemSettingsLink.screenRecording)
                        }
                    }
                    if !settings.displaysHaveSeparateSpaces {
                        Callout(kind: .warning,
                                title: "Tablet goes black in fullscreen apps",
                                message: "Turn on \"Displays have separate Spaces\" in Desktop & Dock → Mission Control, then log out and back in.",
                                actionTitle: "Open System Settings") {
                            SystemSettingsLink.open(SystemSettingsLink.desktopDock)
                        }
                    }
                }
            }

            Section("System") {
                StatusRow(title: "Virtual display",
                          status: settings.displayCreated ? "Active" : "Inactive",
                          color: settings.displayCreated ? .green : .secondary,
                          hint: "The macOS virtual display Side Screen renders into. Created when streaming starts.")
                StatusRow(title: "Tablet",
                          status: settings.clientConnected ? "Connected" : "Not connected",
                          color: settings.clientConnected ? .green : .secondary,
                          hint: "Whether the Android app currently has an active stream session.")
                StatusRow(title: isTahoeOrLater ? "Screen & System Audio" : "Screen Recording",
                          status: settings.hasScreenRecordingPermission ? "Granted" : "Required",
                          color: settings.hasScreenRecordingPermission ? .green : .red,
                          hint: "Privacy permission required to capture the virtual display.")
                StatusRow(title: "Accessibility",
                          status: settings.hasAccessibilityPermission ? "Granted" : "Optional",
                          color: settings.hasAccessibilityPermission ? .green : .orange,
                          hint: "Only needed for touch input from the tablet.")
                if settings.isRunning {
                    StatusRow(title: "Capture method",
                              status: settings.captureMethod,
                              color: settings.captureMethod.contains("fallback") ? .orange : .green,
                              hint: "SCStream is the modern path; CGDisplayStream is used as a fallback if SCStream fails.")
                }
            }

            Section(settings.connectionMode == .usb ? "USB" : "Wireless") {
                if settings.connectionMode == .usb {
                    StatusRow(title: "adb",
                              status: settings.adbInstalled ? "Installed" : "Missing",
                              color: settings.adbInstalled ? .green : .red,
                              hint: "USB mode tunnels the stream through the cable with `adb reverse`.")
                    if !settings.adbInstalled {
                        LabeledContent("Install with") {
                            Text("brew install android-platform-tools")
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    StatusRow(title: "adb reverse",
                              status: settings.adbReverseConfigured ? "Ready" : "Pending",
                              color: settings.adbReverseConfigured ? .green : .orange,
                              hint: "`adb reverse tcp:\(settings.port) tcp:\(settings.port)` — set up automatically when streaming starts.")
                    StatusRow(title: "USB device",
                              status: settings.usbDeviceConnected ? "Detected" : "Not detected",
                              color: settings.usbDeviceConnected ? .green : .red,
                              hint: "Plug in the tablet and tap Allow on its USB debugging prompt.")
                } else {
                    StatusRow(title: "Network",
                              status: settings.wifiConnected ? "Connected" : "Disconnected",
                              color: settings.wifiConnected ? .green : .red,
                              hint: "The Mac and the tablet must be on the same network.")
                    StatusRow(title: "Listening on",
                              status: settings.listeningAddress.map { "\($0):\(settings.port)" } ?? "—",
                              color: settings.listeningAddress != nil ? .green : .secondary,
                              hint: "The address embedded in the pairing QR code.")
                }
            }
        }
    }
}

struct Metric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

// MARK: - Wireless

struct WirelessPage: View {
    @ObservedObject var settings: DisplaySettings
    private let pairedDeviceStore: PairedDeviceStore =
        (NSApp.delegate as? AppDelegate)?.pairedDeviceStore ?? PairedDeviceStore()
    @State private var qrImage: NSImage?
    @State private var pairedDevices: [PairedDevice] = []
    @State private var showResetConfirm = false
    @State private var nowTick = Date()

    var body: some View {
        Form {
            if settings.connectionMode != .wireless {
                Section {
                    Callout(kind: .info,
                            title: "You're in USB mode",
                            message: "Switch to Wireless to pair a tablet over Wi‑Fi.",
                            actionTitle: "Switch to Wireless") {
                        settings.connectionMode = .wireless
                    }
                }
            } else {
                if !settings.isRunning {
                    Section {
                        Callout(kind: .info,
                                title: "Start streaming first",
                                message: "Side Screen must be listening before the tablet can connect.")
                    }
                }

                Section("Pair a tablet") {
                    HStack(alignment: .center, spacing: 20) {
                        Group {
                            if let qr = qrImage {
                                Image(nsImage: qr)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(width: 150, height: 150)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Open Side Screen on the tablet, go to the Wireless tab and scan this code.")
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(LANAddressResolver.primaryIPv4().map { "\($0):\(settings.port)" } ?? "No LAN address — check Wi‑Fi")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if let code = settings.pairingCode {
                                Divider().padding(.vertical, 2)
                                Text("No camera? Enter this code:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(PairingCode.display(code))
                                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                                    .kerning(2)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if pairedDevices.isEmpty {
                        Text("No devices paired yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(pairedDevices, id: \.name) { device in
                            let isLive = settings.currentWirelessDevice == device.name
                            LabeledContent {
                                Button("Forget") {
                                    pairedDeviceStore.forget(name: device.name)
                                    refreshPaired()
                                }
                                .controlSize(.small)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "ipad.landscape")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(device.name)
                                        HStack(spacing: 4) {
                                            Circle().fill(isLive ? Color.green : Color.secondary)
                                                .frame(width: 6, height: 6)
                                            Text(isLive ? "Connected" : relativeTimeString(from: device.lastConnected, to: nowTick))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Button("Forget All & Reset Token…", role: .destructive) { showResetConfirm = true }
                        .foregroundStyle(.red)
                } header: {
                    Text("Paired devices")
                }
            }
        }
        .onAppear {
            refreshQR()
            refreshPaired()
            nowTick = Date()
        }
        .onChange(of: settings.port) { _ in refreshQR() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { now in
            nowTick = now
            refreshPaired()
        }
        .alert("Reset token?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                _ = WirelessAuth.reset()
                pairedDeviceStore.clear()
                refreshQR()
                refreshPaired()
            }
        } message: {
            Text("All paired devices will be disconnected and must scan the new QR code.")
        }
    }

    private func refreshQR() {
        let token = WirelessAuth.loadOrCreate()
        let host = LANAddressResolver.primaryIPv4() ?? "0.0.0.0"
        let name = Host.current().localizedName ?? "Mac"
        let url = PairingURL.build(host: host, port: settings.port, token: token, name: name)
        qrImage = QRRenderer.render(url: url, size: 180)
    }

    private func refreshPaired() {
        pairedDevices = pairedDeviceStore.all()
    }

    private func relativeTimeString(from past: Date, to now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(past))
        if elapsed < 30 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed)) seconds ago" }
        if elapsed < 3600 {
            let m = Int(elapsed / 60)
            return "\(m) minute\(m == 1 ? "" : "s") ago"
        }
        if elapsed < 86400 {
            let h = Int(elapsed / 3600)
            return "\(h) hour\(h == 1 ? "" : "s") ago"
        }
        let d = Int(elapsed / 86400)
        return "\(d) day\(d == 1 ? "" : "s") ago"
    }
}

// MARK: - About

struct AboutPopover: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Side Screen").font(.system(size: 15, weight: .semibold))
                    Text("Version \(AppInfo.version)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check for Updates…") { AppUpdater.shared.checkForUpdates(nil) }
                    .disabled(!updater.canCheckForUpdates)
                    .help(updater.canCheckForUpdates
                          ? "Look for a newer version now. Side Screen also checks once a day."
                          : "Update checks are only available in the released build.")
            }

            Text("Turns an Android tablet or phone into a second display for your Mac — over USB or Wi‑Fi, with touch control. Free and open source.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                Link("Website", destination: AppInfo.website)
                Spacer()
                Link("GitHub", destination: AppInfo.github)
                Spacer()
                Link("What's New", destination: AppInfo.changelog)
                Spacer()
                Link("Report a Problem", destination: AppInfo.reportProblem)
            }
            .font(.system(size: 12))

            Divider()

            Text("If you find Side Screen useful, [support the developer](https://sidescreen.dev/donate.html).")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            Text("Developed by Tran Vuong Quoc Dat · UI refresh in this fork")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 400)
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
