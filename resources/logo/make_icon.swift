// Renders the Side Screen app icon (1024×1024 PNG) with SwiftUI.
//
//   swift resources/logo/make_icon.swift <variant> <output.png>
//   swift resources/logo/make_icon.swift sheet <output.png>   # side-by-side comparison
//
// Flat, geometric: a laptop screen and a tablet as plain shapes. No glows.
import AppKit
import SwiftUI

let canvas: CGFloat = 1024
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)

// Glyph geometry (shared by all variants)
let screen = CGRect(x: 200, y: 344, width: 440, height: 296)
let base = CGRect(x: 172, y: 658, width: 496, height: 24)
let tablet = CGRect(x: 678, y: 372, width: 178, height: 268)

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Variant: String, CaseIterable {
    case light, blue, dark
}

struct Placed<S: View>: View {
    let rect: CGRect
    let content: S
    var body: some View {
        content.frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
    }
}

struct Icon: View {
    let variant: Variant

    private var background: [Color] {
        switch variant {
        case .light: return [Color(hex: 0xFFFFFF), Color(hex: 0xEEF0F4)]
        case .blue: return [Color(hex: 0x3B7BF6), Color(hex: 0x2459DB)]
        case .dark: return [Color(hex: 0x23252C), Color(hex: 0x131418)]
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: canvas, height: canvas)

            Placed(rect: bodyRect, content:
                RoundedRectangle(cornerRadius: 186, style: .continuous)
                    .fill(LinearGradient(colors: background, startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: 186, style: .continuous)
                            .strokeBorder(Color.black.opacity(variant == .light ? 0.07 : 0), lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 10)
            )

            glyph
        }
        .frame(width: canvas, height: canvas, alignment: .topLeading)
    }

    @ViewBuilder private var glyph: some View {
        switch variant {
        case .light:
            // Ink laptop, blue tablet.
            let ink = Color(hex: 0x1D2029)
            Placed(rect: screen, content: RoundedRectangle(cornerRadius: 34, style: .continuous).fill(ink))
            Placed(rect: base, content: Capsule().fill(ink))
            Placed(rect: tablet, content: RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color(hex: 0x2F74F5)))
        case .blue:
            // White outline laptop, solid white tablet — "the extra screen".
            Placed(rect: screen, content: RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(.white, lineWidth: 30))
            Placed(rect: base, content: Capsule().fill(.white))
            Placed(rect: tablet, content: RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.white))
        case .dark:
            // Soft white laptop, accent tablet.
            Placed(rect: screen, content: RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color(hex: 0xF2F3F6)))
            Placed(rect: base, content: Capsule().fill(Color(hex: 0xF2F3F6)))
            Placed(rect: tablet, content: RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color(hex: 0x4C8DFF)))
        }
    }
}

struct Sheet: View {
    var body: some View {
        VStack(spacing: 40) {
            HStack(spacing: 60) {
                ForEach(Variant.allCases, id: \.self) { v in
                    VStack(spacing: 16) {
                        Icon(variant: v).scaleEffect(0.5).frame(width: 512, height: 512)
                        Text(v.rawValue.uppercased())
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.6))
                    }
                }
            }
            HStack(spacing: 60) {
                ForEach(Variant.allCases, id: \.self) { v in
                    HStack(spacing: 24) {
                        Icon(variant: v).scaleEffect(128 / 1024).frame(width: 128, height: 128)
                        Icon(variant: v).scaleEffect(64 / 1024).frame(width: 64, height: 64)
                        Icon(variant: v).scaleEffect(32 / 1024).frame(width: 32, height: 32)
                    }
                    .frame(width: 512)
                }
            }
        }
        .padding(60)
        .background(Color(hex: 0xE4E5EA))
    }
}

@MainActor
func write<V: View>(_ view: V, to path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    renderer.isOpaque = false
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
        fatalError("render failed")
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(cg.width)x\(cg.height)")
}

let args = CommandLine.arguments
let which = args.count > 1 ? args[1] : "light"
let out = args.count > 2 ? args[2] : "icon-\(which).png"
MainActor.assumeIsolated {
    if which == "sheet" {
        write(Sheet(), to: out)
    } else if let v = Variant(rawValue: which) {
        write(Icon(variant: v), to: out)
    } else {
        fatalError("unknown variant \(which)")
    }
}
