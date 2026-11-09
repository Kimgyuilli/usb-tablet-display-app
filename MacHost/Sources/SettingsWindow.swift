import Cocoa
import SwiftUI

// MARK: - Display Settings

class DisplaySettings: ObservableObject {
    private let defaults = UserDefaults.standard
    private let keyPrefix = "SideScreen_"

    @Published var resolution: String {
        didSet { save("resolution", resolution) }
    }
    @Published var refreshRate: Int {
        didSet { save("refreshRate", refreshRate) }
    }
    @Published var hiDPI: Bool {
        didSet { save("hiDPI", hiDPI) }
    }
    @Published var bitrate: Int {
        didSet { save("bitrate", bitrate) }
    }
    @Published var quality: String {
        didSet { save("quality", quality) }
    }
    @Published var gamingBoost: Bool {
        didSet { save("gamingBoost", gamingBoost) }
    }
    @Published var port: UInt16 {
        didSet { save("port", Int(port)) }
    }
    @Published var rotation: Int {
        didSet { save("rotation", rotation) }
    }
    @Published var flipHorizontal: Bool {
        didSet { save("flipHorizontal", flipHorizontal) }
    }
    @Published var flipVertical: Bool {
        didSet { save("flipVertical", flipVertical) }
    }
    @Published var showAllResolutions: Bool {
        didSet { save("showAllResolutions", showAllResolutions) }
    }
    @Published var customWidth: Int {
        didSet { save("customWidth", customWidth) }
    }
    @Published var customHeight: Int {
        didSet { save("customHeight", customHeight) }
    }
    @Published var touchEnabled: Bool {
        didSet { save("touchEnabled", touchEnabled) }
    }
    @Published var connectionMode: ConnectionMode {
        didSet { save("connectionMode", connectionMode.rawValue) }
    }
    @Published var autoStartStreamingOnLaunch: Bool {
        didSet { save("autoStartStreamingOnLaunch", autoStartStreamingOnLaunch) }
    }
    @Published var startupMode: ConnectionMode {
        didSet { save("startupMode", startupMode.rawValue) }
    }

    // Runtime state (not persisted)
    @Published var displayCreated = false
    @Published var clientConnected = false
    /// Device name of the wireless client currently streaming (nil when none).
    /// WirelessSection reads this to show a "Connected" badge on the matching row.
    @Published var currentWirelessDevice: String?
    /// One-time wireless pairing code (issue #35). Non-nil only while the
    /// server is running in wireless mode; never persisted.
    @Published var pairingCode: String?
    @Published var hasScreenRecordingPermission = false
    @Published var hasAccessibilityPermission = false
    /// Mirrors `NSScreen.screensHaveSeparateSpaces`. When the user has turned
    /// off "Displays have separate Spaces", macOS blanks every other display
    /// (including our virtual one) whenever any app goes fullscreen — the
    /// tablet shows black while the stream keeps flowing (issue #50). The
    /// setting only takes effect after logout, so this is a per-session fact.
    @Published var displaysHaveSeparateSpaces = true
    @Published var adbInstalled = false
    @Published var adbReverseConfigured = false
    @Published var usbDeviceConnected = false
    @Published var wifiConnected = false
    @Published var listeningAddress: String?
    @Published var isRunning = false
    @Published var currentFPS: Double = 0
    @Published var currentBitrate: Double = 0
    @Published var captureMethod: String = "Initializing..."

    /// Edge of the Mac's screen the tablet sits against: the live arrangement
    /// while streaming, otherwise the last known (or pending) choice.
    @Published var displaySide: DisplaySide?

    var onToggleServer: (() -> Void)?
    var onArrange: ((DisplaySide) -> Void)?

    init() {
        self.resolution = defaults.string(forKey: keyPrefix + "resolution") ?? "1920x1200"
        self.refreshRate = defaults.object(forKey: keyPrefix + "refreshRate") as? Int ?? 60  // Default: 60 — balanced for most tablets. 120 may saturate high-res panel pipelines.
        self.hiDPI = defaults.bool(forKey: keyPrefix + "hiDPI")
        self.bitrate = defaults.object(forKey: keyPrefix + "bitrate") as? Int ?? 1000  // Default: 1000 Mbps
        self.quality = defaults.string(forKey: keyPrefix + "quality") ?? "ultralow"  // Default: fastest encoding
        self.gamingBoost = defaults.bool(forKey: keyPrefix + "gamingBoost")
        // Default port 54321 (was 8888 in <=0.7.1; 8888 collides with jupyter/splunk/HP printers).
        // Existing users keep their saved value.
        self.port = UInt16(defaults.object(forKey: keyPrefix + "port") as? Int ?? 54321)
        self.rotation = defaults.object(forKey: keyPrefix + "rotation") as? Int ?? 0
        self.flipHorizontal = defaults.bool(forKey: keyPrefix + "flipHorizontal")
        self.flipVertical = defaults.bool(forKey: keyPrefix + "flipVertical")
        self.showAllResolutions = defaults.bool(forKey: keyPrefix + "showAllResolutions")
        self.customWidth = defaults.object(forKey: keyPrefix + "customWidth") as? Int ?? 1920
        self.customHeight = defaults.object(forKey: keyPrefix + "customHeight") as? Int ?? 1200
        self.touchEnabled = defaults.object(forKey: keyPrefix + "touchEnabled") as? Bool ?? true
        let modeRaw = defaults.string(forKey: keyPrefix + "connectionMode") ?? ConnectionMode.usb.rawValue
        self.connectionMode = ConnectionMode(rawValue: modeRaw) ?? .usb
        self.autoStartStreamingOnLaunch = defaults.object(forKey: keyPrefix + "autoStartStreamingOnLaunch") as? Bool ?? false
        let startupRaw = defaults.string(forKey: keyPrefix + "startupMode") ?? modeRaw
        self.startupMode = ConnectionMode(rawValue: startupRaw) ?? .usb

        self.displaySide = (defaults.string(forKey: keyPrefix + "pendingSide")
            ?? defaults.string(forKey: keyPrefix + "side")).flatMap(DisplaySide.init(rawValue:))

        print("Loaded settings: \(resolution) @ \(refreshRate)Hz, bitrate=\(bitrate), quality=\(quality)")
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: keyPrefix + key)
    }

    /// The tablet-specific slice of the settings, plus the display position
    /// VirtualDisplayManager last saved (same `SideScreen_` keys).
    var profileSettings: ProfileSettings {
        let hasPosition = defaults.bool(forKey: keyPrefix + "hasPosition")
        return ProfileSettings(
            resolution: resolution,
            refreshRate: refreshRate,
            hiDPI: hiDPI,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            bitrate: bitrate,
            quality: quality,
            gamingBoost: gamingBoost,
            touchEnabled: touchEnabled,
            positionX: hasPosition ? defaults.integer(forKey: keyPrefix + "positionX") : nil,
            positionY: hasPosition ? defaults.integer(forKey: keyPrefix + "positionY") : nil
        )
    }

    /// Make `profile` the current settings. Only changed values are assigned,
    /// so observers fire just for what actually differs.
    func apply(_ profile: ProfileSettings) {
        if resolution != profile.resolution { resolution = profile.resolution }
        if refreshRate != profile.refreshRate { refreshRate = profile.refreshRate }
        if hiDPI != profile.hiDPI { hiDPI = profile.hiDPI }
        if rotation != profile.rotation { rotation = profile.rotation }
        if flipHorizontal != profile.flipHorizontal { flipHorizontal = profile.flipHorizontal }
        if flipVertical != profile.flipVertical { flipVertical = profile.flipVertical }
        if bitrate != profile.bitrate { bitrate = profile.bitrate }
        if quality != profile.quality { quality = profile.quality }
        if gamingBoost != profile.gamingBoost { gamingBoost = profile.gamingBoost }
        if touchEnabled != profile.touchEnabled { touchEnabled = profile.touchEnabled }
        if let x = profile.positionX, let y = profile.positionY {
            save("positionX", x)
            save("positionY", y)
            save("hasPosition", true)
        } else {
            defaults.removeObject(forKey: keyPrefix + "hasPosition")
        }
    }

    struct ResolutionGroup: Identifiable {
        let id = UUID()
        let name: String
        let ratio: String
        let resolutions: [String]
    }

    static let resolutionGroups: [ResolutionGroup] = [
        ResolutionGroup(name: "16:10", ratio: "Widescreen", resolutions: [
            "1280x800", "1440x900", "1680x1050", "1920x1200", "2304x1440", "2560x1600"
        ]),
        ResolutionGroup(name: "16:9", ratio: "HD/4K", resolutions: [
            "1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"
        ]),
        ResolutionGroup(name: "4:3", ratio: "Classic", resolutions: [
            "1024x768", "1280x960", "1600x1200"
        ]),
        ResolutionGroup(name: "3:2", ratio: "Surface/Pixel", resolutions: [
            "1920x1280", "2160x1440", "2736x1824"
        ]),
        ResolutionGroup(name: "5:3", ratio: "Tablet Wide", resolutions: [
            "2000x1200", "2560x1536", "2800x1680"
        ]),
        ResolutionGroup(name: "4:3", ratio: "iPad", resolutions: [
            "2048x1536", "2224x1668", "2388x1668", "2732x2048"
        ])
    ]

    static let commonResolutions = [
        "1920x1080", "1920x1200", "2560x1440", "2560x1600"
    ]

    static var allResolutions: [String] {
        resolutionGroups.flatMap { $0.resolutions }
    }

    var effectiveBitrate: Int {
        return gamingBoost ? 1000 : bitrate
    }

    var effectiveQuality: String {
        return gamingBoost ? "ultralow" : quality
    }

    var effectiveRefreshRate: Int {
        return gamingBoost ? 120 : refreshRate
    }

    func toggleServer() {
        onToggleServer?()
    }

    func resetToDefaults() {
        let keys = ["resolution", "refreshRate", "hiDPI", "bitrate", "quality",
                    "gamingBoost", "port", "rotation", "flipHorizontal", "flipVertical", "showAllResolutions",
                    "customWidth", "customHeight", "touchEnabled", "autoStartStreamingOnLaunch", "startupMode"]
        for key in keys {
            defaults.removeObject(forKey: keyPrefix + key)
        }

        resolution = "1920x1200"
        refreshRate = 120  // Default: highest FPS
        hiDPI = false
        bitrate = 1000  // Default: 1000 Mbps
        quality = "ultralow"  // Default: fastest encoding
        gamingBoost = false
        port = 54321
        rotation = 0
        flipHorizontal = false
        flipVertical = false
        showAllResolutions = false
        customWidth = 1920
        customHeight = 1200
        touchEnabled = true
        autoStartStreamingOnLaunch = false
        startupMode = .usb

        print("Settings reset to defaults")
    }

    var resolutionSize: (width: Int, height: Int) {
        let parts = resolution.split(separator: "x")
        let baseWidth = Int(parts[0]) ?? 1920
        let baseHeight = Int(parts[1]) ?? 1200
        if rotation == 90 || rotation == 270 {
            return (baseHeight, baseWidth)
        }
        return (baseWidth, baseHeight)
    }

    static func isValidCustomResolution(width: Int, height: Int) -> Bool {
        width >= 640 && width <= 7680 && height >= 480 && height <= 4320
    }

    func applyCustomResolution() {
        if DisplaySettings.isValidCustomResolution(width: customWidth, height: customHeight) {
            resolution = "\(customWidth)x\(customHeight)"
        }
    }
}

// MARK: - Window Controller

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    convenience init(settings: DisplaySettings) {
        let window = ConstrainedWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Side Screen"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = false
        window.contentMinSize = NSSize(width: SettingsLayout.minWidth, height: SettingsLayout.minHeight)
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let screen = window.screen ?? NSScreen.main else { return }

        var frame = window.frame
        let visibleFrame = screen.visibleFrame
        let minVisibleWidth: CGFloat = 100
        let minVisibleHeight: CGFloat = 50

        if frame.maxX < visibleFrame.minX + minVisibleWidth {
            frame.origin.x = visibleFrame.minX - frame.width + minVisibleWidth
        } else if frame.minX > visibleFrame.maxX - minVisibleWidth {
            frame.origin.x = visibleFrame.maxX - minVisibleWidth
        }

        if frame.maxY < visibleFrame.minY + minVisibleHeight {
            frame.origin.y = visibleFrame.minY - frame.height + minVisibleHeight
        } else if frame.minY > visibleFrame.maxY - minVisibleHeight {
            frame.origin.y = visibleFrame.maxY - minVisibleHeight
        }

        if window.frame != frame {
            window.setFrame(frame, display: true)
        }
    }
}

class ConstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen = screen ?? self.screen ?? NSScreen.main else {
            return frameRect
        }

        var constrainedRect = frameRect
        let visibleFrame = screen.visibleFrame
        let minVisibleWidth: CGFloat = 100
        let minVisibleHeight: CGFloat = 50

        if constrainedRect.maxX < visibleFrame.minX + minVisibleWidth {
            constrainedRect.origin.x = visibleFrame.minX - constrainedRect.width + minVisibleWidth
        } else if constrainedRect.minX > visibleFrame.maxX - minVisibleWidth {
            constrainedRect.origin.x = visibleFrame.maxX - minVisibleWidth
        }

        if constrainedRect.maxY < visibleFrame.minY + minVisibleHeight {
            constrainedRect.origin.y = visibleFrame.minY - constrainedRect.height + minVisibleHeight
        } else if constrainedRect.minY > visibleFrame.maxY - minVisibleHeight {
            constrainedRect.origin.y = visibleFrame.maxY - minVisibleHeight
        }

        return constrainedRect
    }
}
