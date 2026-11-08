// Renders the Side Screen app icon (1024×1024 PNG) with SwiftUI.
//
//   swift resources/logo/make_icon.swift <output.png>
//
// Concept: a MacBook and a tablet side by side, with one wallpaper flowing
// continuously across both screens — the "extended display" idea.
import AppKit
import SwiftUI

let canvas: CGFloat = 1024

// Geometry (Apple macOS icon grid: 824pt body inset 100pt).
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let macScreen = CGRect(x: 176, y: 330, width: 492, height: 330)
let tablet = CGRect(x: 690, y: 362, width: 200, height: 298)
let tabletBezel: CGFloat = 12
let bezel: CGFloat = 16

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// One wallpaper spanning the whole device area; masked by both screens.
struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x30357A), Color(hex: 0x3A2C86)],
                           startPoint: .top, endPoint: .bottom)
            // Aurora blobs
            Ellipse()
                .fill(Color(hex: 0xFF5E8A))
                .frame(width: 520, height: 260)
                .offset(x: -120, y: 90)
                .blur(radius: 70)
            Ellipse()
                .fill(Color(hex: 0xFFB457))
                .frame(width: 360, height: 200)
                .offset(x: -230, y: 150)
                .blur(radius: 60)
            Ellipse()
                .fill(Color(hex: 0x5AC8FA))
                .frame(width: 520, height: 240)
                .offset(x: 230, y: -40)
                .blur(radius: 70)
            Ellipse()
                .fill(Color(hex: 0x8E7CFF))
                .frame(width: 420, height: 220)
                .offset(x: 40, y: -110)
                .blur(radius: 70)
            // Light ribbon sweeping from the Mac onto the tablet
            Capsule()
                .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.85), .white.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 900, height: 26)
                .rotationEffect(.degrees(-14))
                .offset(x: 30, y: 30)
                .blur(radius: 6)
        }
        .frame(width: 760, height: 380)
    }
}

struct Icon: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: canvas, height: canvas)

            // Body
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x4F8BFF), Color(hex: 0x5B5CF0), Color(hex: 0x7B3FE4)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    // Soft top sheen
                    RoundedRectangle(cornerRadius: 186, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)],
                                             startPoint: .top, endPoint: .center))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 186, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 3)
                }
                .frame(width: bodyRect.width, height: bodyRect.height)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 12)
                .offset(x: bodyRect.minX, y: bodyRect.minY)

            // Laptop base
            UnevenRoundedBase()
                .fill(LinearGradient(colors: [Color(hex: 0xF4F5FA), Color(hex: 0xB8BCCB)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: macScreen.width + 64, height: 30)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 8)
                .offset(x: macScreen.minX - 32, y: macScreen.maxY - 2)
            Capsule()
                .fill(Color(hex: 0x8C90A3))
                .frame(width: 96, height: 8)
                .offset(x: macScreen.midX - 48, y: macScreen.maxY)

            // Device bezels
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(hex: 0x14151C))
                .frame(width: macScreen.width, height: macScreen.height)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
                .offset(x: macScreen.minX, y: macScreen.minY)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: 0x14151C))
                .frame(width: tablet.width, height: tablet.height)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
                .offset(x: tablet.minX, y: tablet.minY)

            // Continuous wallpaper across both screens
            Wallpaper()
                .offset(x: macScreen.minX + bezel, y: macScreen.minY + bezel)
                .mask(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .frame(width: macScreen.width - 2 * bezel, height: macScreen.height - 2 * bezel)
                            .offset(x: macScreen.minX + bezel, y: macScreen.minY + bezel)
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .frame(width: tablet.width - 2 * tabletBezel, height: tablet.height - 2 * tabletBezel)
                            .offset(x: tablet.minX + tabletBezel, y: tablet.minY + tabletBezel)
                    }
                    .frame(width: canvas, height: canvas, alignment: .topLeading)
                }
                .frame(width: canvas, height: canvas, alignment: .topLeading)

            // Camera notch on the Mac
            Capsule()
                .fill(Color(hex: 0x14151C))
                .frame(width: 64, height: 12)
                .offset(x: macScreen.midX - 32, y: macScreen.minY + bezel - 1)
        }
        .frame(width: canvas, height: canvas, alignment: .topLeading)
    }
}

/// Laptop base: flat top, rounded bottom corners.
struct UnevenRoundedBase: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let rad: CGFloat = 14
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad * 1.6, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad * 1.6, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

@MainActor
func render(to path: String) {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    renderer.isOpaque = false
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png failed") }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(cg.width)x\(cg.height)")
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
MainActor.assumeIsolated { render(to: out) }
