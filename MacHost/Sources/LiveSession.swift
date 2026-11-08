import Foundation

/// Everything the Dashboard shows about the current streaming session.
/// Written by AppDelegate from the streaming server callbacks; read by SwiftUI.
@MainActor
final class LiveSession: ObservableObject {
    static let shared = LiveSession()

    struct Sample: Identifiable {
        let id: Int
        let time: Date
        let fps: Double
        let mbps: Double
        /// Average capture → send age on the Mac, in milliseconds.
        let latencyMs: Double
        /// Frames dropped during this one-second window.
        let dropped: Int
    }

    struct TabletInfo: Equatable {
        var manufacturer: String?
        var model: String?
        var androidVersion: String?
        var panelSize: String?
        var batteryLevel: Int?
        var isCharging: Bool?
        var temperatureC: Double?
    }

    static let historyLength = 90

    @Published private(set) var deviceName: String?
    @Published private(set) var connectedSince: Date?
    @Published private(set) var codec: String?
    @Published private(set) var encodeSize: (width: Int, height: Int)?
    @Published private(set) var decoderLimit: (width: Int, height: Int)?
    @Published private(set) var samples: [Sample] = []
    @Published private(set) var tablet: TabletInfo?
    @Published private(set) var totalDropped = 0

    private var nextSampleID = 0
    private var pollTimer: Timer?
    private var pollInFlight = false
    fileprivate var demoTick: Double = 0

    var latest: Sample? { samples.last }

    // MARK: Updates from the server

    func setDeviceName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { deviceName = trimmed }
    }

    func clientConnected(mode: ConnectionMode) {
        connectedSince = Date()
        samples = []
        totalDropped = 0
        if mode == .usb { startTabletPolling() }
    }

    func codecNegotiated(_ codec: StreamCodec,
                         encodeSize: (width: Int, height: Int),
                         decoderLimit: (width: Int, height: Int)?) {
        self.codec = codec == .hevc ? "HEVC (H.265)" : "H.264"
        self.encodeSize = encodeSize
        self.decoderLimit = decoderLimit
    }

    func addSample(fps: Double, mbps: Double, latencyMs: Double, dropped: Int) {
        nextSampleID += 1
        samples.append(Sample(id: nextSampleID, time: Date(), fps: fps, mbps: mbps,
                              latencyMs: latencyMs, dropped: dropped))
        if samples.count > Self.historyLength {
            samples.removeFirst(samples.count - Self.historyLength)
        }
        totalDropped += dropped
    }

    func clientDisconnected() {
        stopTabletPolling()
        connectedSince = nil
        codec = nil
        encodeSize = nil
        decoderLimit = nil
        samples = []
        tablet = nil
        totalDropped = 0
        // Keep deviceName so the empty state can say "Last connected: …".
    }

    // MARK: Tablet details over adb (USB only)

    private func startTabletPolling() {
        stopTabletPolling()
        pollTablet()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollTablet() }
        }
    }

    private func stopTabletPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollTablet() {
        guard !pollInFlight else { return }
        pollInFlight = true
        Task.detached(priority: .utility) {
            let info = Self.readTabletInfo()
            await MainActor.run {
                self.pollInFlight = false
                // Only apply while still connected (the timer may race a disconnect).
                if self.connectedSince != nil, let info { self.tablet = info }
            }
        }
    }

    nonisolated private static func readTabletInfo() -> TabletInfo? {
        guard let adb = StatusDetector.adbExecutablePath(),
              let serial = StatusDetector.usbDevices().first else { return nil }

        // One adb round-trip; a marker line separates `dumpsys battery`.
        let script = """
        getprop ro.product.manufacturer; getprop ro.product.model; \
        getprop ro.build.version.release; wm size; echo __BATTERY__; dumpsys battery
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: adb)
        task.arguments = ["-s", serial, "shell", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return nil }
        return parse(output)
    }

    nonisolated static func parse(_ output: String) -> TabletInfo {
        let parts = output.components(separatedBy: "__BATTERY__")
        let head = parts[0].split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var info = TabletInfo()

        func line(_ i: Int) -> String? {
            guard i < head.count, !head[i].isEmpty else { return nil }
            return head[i]
        }
        info.manufacturer = line(0).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        info.model = line(1)
        info.androidVersion = line(2)
        if let size = head.first(where: { $0.hasPrefix("Physical size:") }) {
            // `wm size` reports the natural (usually portrait) orientation;
            // show it landscape-first like the stream resolution.
            let dims = size.replacingOccurrences(of: "Physical size:", with: "")
                .trimmingCharacters(in: .whitespaces)
                .split(separator: "x").compactMap { Int($0) }
            if dims.count == 2 {
                info.panelSize = "\(max(dims[0], dims[1])) × \(min(dims[0], dims[1]))"
            }
        }

        if parts.count > 1 {
            var powered = false
            for raw in parts[1].split(separator: "\n") {
                let kv = raw.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2 else { continue }
                switch kv[0] {
                case "level": info.batteryLevel = Int(kv[1])
                case "temperature": info.temperatureC = Double(kv[1]).map { $0 / 10 }
                case "status": info.isCharging = (kv[1] == "2" || kv[1] == "5") ? true : info.isCharging
                case "AC powered", "USB powered", "Wireless powered":
                    if kv[1] == "true" { powered = true }
                default: break
                }
            }
            if info.isCharging == nil { info.isCharging = powered }
        }
        return info
    }
}

// MARK: - Demo data (launch with `-SideScreenDashboardDemo YES` to preview the Dashboard)

extension LiveSession {
    static var demoRequested: Bool {
        UserDefaults.standard.bool(forKey: "SideScreenDashboardDemo")
    }

    func startDemo() {
        setDeviceName("Galaxy Tab S9")
        clientConnected(mode: .wireless) // no adb polling in demo
        connectedSince = Date().addingTimeInterval(-754)
        codecNegotiated(.hevc, encodeSize: (2880, 1800), decoderLimit: (4096, 2304))
        tablet = TabletInfo(manufacturer: "Samsung", model: "SM-X710", androidVersion: "16",
                            panelSize: "2560 × 1600", batteryLevel: 82, isCharging: true, temperatureC: 33.4)
        for _ in 0..<60 { demoTick += 1; addDemoSample(demoTick) }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                let session = LiveSession.shared
                session.demoTick += 1
                session.addDemoSample(session.demoTick)
            }
        }
    }

    fileprivate func addDemoSample(_ t: Double) {
        let activity = 0.55 + 0.45 * sin(t / 9)
        addSample(fps: max(4, 90 * activity + Double.random(in: -4...4)),
                  mbps: max(2, 38 * activity + Double.random(in: -3...3)),
                  latencyMs: 7.5 + Double.random(in: -1.2...2.4) + (t.truncatingRemainder(dividingBy: 23) < 1 ? 9 : 0),
                  dropped: t.truncatingRemainder(dividingBy: 31) < 1 ? 2 : 0)
    }
}
