import Charts
import SwiftUI

// MARK: - Dashboard page

struct DashboardPage: View {
    @ObservedObject var settings: DisplaySettings
    @ObservedObject var session = LiveSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if settings.clientConnected {
                    DeviceHeroCard(settings: settings, session: session)
                    MetricGrid(settings: settings, session: session)
                    HistoryChartCard(settings: settings, session: session)
                    StreamDetailsCard(settings: settings, session: session)
                } else {
                    DashboardEmptyState(settings: settings, session: session)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Card container

struct DashboardCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

// MARK: - Health

enum StreamHealth {
    case smooth, good, struggling, measuring

    /// Based on Mac-side latency and drops over the last few seconds. FPS is
    /// deliberately not used: a static screen legitimately sends few frames.
    static func evaluate(_ samples: [LiveSession.Sample]) -> StreamHealth {
        let recent = samples.suffix(5)
        guard recent.count >= 3 else { return .measuring }
        let active = recent.filter { $0.fps > 0 }
        let latency = active.isEmpty ? 0 : active.map(\.latencyMs).reduce(0, +) / Double(active.count)
        let drops = recent.map(\.dropped).reduce(0, +)
        if latency < 16 && drops == 0 { return .smooth }
        if latency < 33 && drops <= 5 { return .good }
        return .struggling
    }

    var label: String {
        switch self {
        case .smooth: return "Smooth"
        case .good: return "Good"
        case .struggling: return "Struggling"
        case .measuring: return "Measuring…"
        }
    }

    var color: Color {
        switch self {
        case .smooth: return .green
        case .good: return .yellow
        case .struggling: return .red
        case .measuring: return .secondary
        }
    }
}

// MARK: - Device hero

struct DeviceHeroCard: View {
    @ObservedObject var settings: DisplaySettings
    @ObservedObject var session: LiveSession

    private var title: String {
        session.deviceName ?? session.tablet?.model ?? "Android tablet"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let t = session.tablet {
            let device = [t.manufacturer, t.model].compactMap { $0 }.joined(separator: " ")
            if !device.isEmpty { parts.append(device) }
            if let v = t.androidVersion { parts.append("Android \(v)") }
        }
        if parts.isEmpty {
            parts.append(settings.connectionMode == .usb ? "Connected over USB" : "Connected over Wi‑Fi")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let health = StreamHealth.evaluate(session.samples)

        DashboardCard(padding: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "ipad.landscape")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .shadow(color: .blue.opacity(0.25), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Chip(icon: settings.connectionMode == .usb ? "cable.connector" : "wifi",
                             text: settings.connectionMode == .usb ? "USB" : "Wi‑Fi")
                        if let since = session.connectedSince {
                            Chip(icon: "clock") {
                                Text(since, style: .timer).monospacedDigit()
                            }
                        }
                        if let level = session.tablet?.batteryLevel {
                            let charging = session.tablet?.isCharging == true
                            Chip(icon: batterySymbol(level: level, charging: charging),
                                 text: "\(level)%",
                                 tint: level <= 15 && !charging ? .red : nil)
                        }
                        if let temp = session.tablet?.temperatureC {
                            Chip(icon: "thermometer.medium",
                                 text: String(format: "%.0f°C", temp),
                                 tint: temp >= 42 ? .orange : nil)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(health.color).frame(width: 8, height: 8)
                        Text(health.label)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(health.color.opacity(0.14)))
                    Text("Stream health")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func batterySymbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch level {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }
}

struct Chip<Label: View>: View {
    let icon: String
    var tint: Color?
    @ViewBuilder let label: Label

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            label.font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint ?? .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill((tint ?? .primary).opacity(0.08)))
    }
}

extension Chip where Label == Text {
    init(icon: String, text: String, tint: Color? = nil) {
        self.icon = icon
        self.tint = tint
        self.label = Text(text)
    }
}

// MARK: - Metric tiles

struct MetricGrid: View {
    @ObservedObject var settings: DisplaySettings
    @ObservedObject var session: LiveSession

    var body: some View {
        let s = session.samples
        let latest = session.latest
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricTile(title: "Frame rate", icon: "film.stack", color: .blue,
                       value: latest.map { String(format: "%.0f", $0.fps) } ?? "–", unit: "fps",
                       caption: "Target \(settings.effectiveRefreshRate) Hz",
                       series: s.map { ($0.id, $0.fps) })
            MetricTile(title: "Bitrate", icon: "arrow.up.arrow.down", color: .purple,
                       value: latest.map { String(format: $0.mbps < 10 ? "%.1f" : "%.0f", $0.mbps) } ?? "–", unit: "Mbps",
                       caption: "Cap \(settings.effectiveBitrate) Mbps",
                       series: s.map { ($0.id, $0.mbps) })
            MetricTile(title: "Mac latency", icon: "timer", color: .orange,
                       value: latest.map { $0.fps > 0 ? String(format: "%.1f", $0.latencyMs) : "–" } ?? "–", unit: "ms",
                       caption: "Capture → send on this Mac",
                       series: s.filter { $0.fps > 0 }.map { ($0.id, $0.latencyMs) })
            MetricTile(title: "Dropped frames", icon: "exclamationmark.arrow.triangle.2.circlepath", color: .red,
                       value: latest.map { "\($0.dropped)" } ?? "–", unit: "/ s",
                       caption: "\(session.totalDropped) this session",
                       series: s.map { ($0.id, Double($0.dropped)) })
        }
    }
}

struct MetricTile: View {
    let title: String
    let icon: String
    let color: Color
    let value: String
    let unit: String
    let caption: String
    let series: [(Int, Double)]

    var body: some View {
        DashboardCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Sparkline(points: series, color: color)
                    .frame(height: 34)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct Sparkline: View {
    let points: [(Int, Double)]
    let color: Color

    var body: some View {
        if points.count < 2 {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.05))
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
        } else {
            Chart {
                ForEach(points, id: \.0) { p in
                    AreaMark(x: .value("t", p.0), y: .value("v", p.1))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.0)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("t", p.0), y: .value("v", p.1))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: true))
            .chartLegend(.hidden)
        }
    }
}

// MARK: - History chart

struct HistoryChartCard: View {
    @ObservedObject var settings: DisplaySettings
    @ObservedObject var session: LiveSession
    @State private var metric: Metric = .fps

    enum Metric: String, CaseIterable, Identifiable {
        case fps = "Frame rate", mbps = "Bitrate", latency = "Latency"
        var id: String { rawValue }
        var unit: String {
            switch self {
            case .fps: return "fps"
            case .mbps: return "Mbps"
            case .latency: return "ms"
            }
        }
        var color: Color {
            switch self {
            case .fps: return .blue
            case .mbps: return .purple
            case .latency: return .orange
            }
        }
    }

    private func value(_ s: LiveSession.Sample) -> Double {
        switch metric {
        case .fps: return s.fps
        case .mbps: return s.mbps
        case .latency: return s.latencyMs
        }
    }

    var body: some View {
        let firstID = session.samples.first?.id ?? 0
        let points = session.samples.filter { metric != .latency || $0.fps > 0 }
        let values = points.map(value)
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)

        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last \(LiveSession.historyLength) seconds")
                            .font(.system(size: 13, weight: .semibold))
                        Text(values.isEmpty ? "Collecting data…"
                             : String(format: "Avg %.1f %@ · Peak %.1f %@", avg, metric.unit, values.max() ?? 0, metric.unit))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Picker("", selection: $metric) {
                        ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                Chart {
                    ForEach(points) { s in
                        let x = s.id - firstID  // one sample per second
                        AreaMark(x: .value("Time", x), y: .value(metric.rawValue, value(s)))
                            .foregroundStyle(LinearGradient(colors: [metric.color.opacity(0.22), metric.color.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", x), y: .value(metric.rawValue, value(s)))
                            .foregroundStyle(metric.color)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    if metric == .fps {
                        RuleMark(y: .value("Target", settings.effectiveRefreshRate))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Target \(settings.effectiveRefreshRate)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .chartXAxis(.hidden)
                .chartXScale(domain: 0...(LiveSession.historyLength - 1))
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        AxisValueLabel()
                    }
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .frame(height: 170)
                .animation(.easeInOut(duration: 0.25), value: metric)

                if metric == .fps {
                    Text("Frame rate follows screen activity — a still screen sends fewer frames, which is normal.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Stream details

struct StreamDetailsCard: View {
    @ObservedObject var settings: DisplaySettings
    @ObservedObject var session: LiveSession

    private func size(_ s: (width: Int, height: Int)?) -> String {
        guard let s else { return "—" }
        return "\(s.width) × \(s.height)"
    }

    private var qualityName: String {
        switch settings.effectiveQuality {
        case "ultralow": return "Ultra Low latency"
        case "low": return "Low latency"
        case "medium": return "Medium"
        case "high": return "High quality"
        default: return settings.effectiveQuality
        }
    }

    var body: some View {
        let desktop = settings.resolution.replacingOccurrences(of: "x", with: " × ")
        let rows: [(String, String, String)] = [
            ("Codec", session.codec ?? "—", "cpu"),
            ("Stream resolution", size(session.encodeSize), "rectangle.on.rectangle"),
            ("Desktop", desktop + (settings.hiDPI ? " · HiDPI" : ""), "macwindow"),
            ("Tablet panel", session.tablet?.panelSize ?? "—", "ipad.landscape"),
            ("Tablet decoder max", size(session.decoderLimit), "memorychip"),
            ("Encoder", qualityName + (settings.gamingBoost ? " · Gaming Boost" : ""), "dial.medium"),
        ]

        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stream details")
                    .font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .topLeading),
                                    GridItem(.flexible(), spacing: 16, alignment: .topLeading)],
                          alignment: .leading, spacing: 14) {
                    ForEach(rows, id: \.0) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: row.2)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.0)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(row.1)
                                    .font(.system(size: 13, weight: .medium))
                                    .monospacedDigit()
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                if settings.connectionMode == .wireless {
                    Text("Battery, temperature and panel details are read over USB only.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Empty state

struct DashboardEmptyState: View {
    @ObservedObject var settings: DisplaySettings
    @ObservedObject var session: LiveSession

    var body: some View {
        DashboardCard(padding: 32) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 88, height: 88)
                    Image(systemName: settings.isRunning ? "antenna.radiowaves.left.and.right" : "ipad.landscape")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }

                Text(settings.isRunning ? "Waiting for your tablet" : "No tablet connected")
                    .font(.system(size: 17, weight: .semibold))

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.isRunning {
                    ProgressView().controlSize(.small).padding(.top, 2)
                } else {
                    Button {
                        settings.toggleServer()
                    } label: {
                        Label("Start Streaming", systemImage: "play.fill")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!settings.hasScreenRecordingPermission)
                    .padding(.top, 4)
                }

                if let last = session.deviceName {
                    Text("Last connected: \(last)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var message: String {
        if !settings.hasScreenRecordingPermission {
            return "Grant Screen Recording permission first — see the Status page."
        }
        if !settings.isRunning {
            return "Start streaming, then open Side Screen on the tablet. Live performance shows up here once it connects."
        }
        return settings.connectionMode == .usb
            ? "Open Side Screen on the tablet and tap Connect. Keep the USB cable plugged in."
            : "Open Side Screen on the tablet and reconnect, or scan the QR code on the Wireless page."
    }
}
