import SwiftUI

enum StudioColor {
    static let paper = Color(red: 0.973, green: 0.965, blue: 0.941)
    static let sidebar = Color(red: 0.953, green: 0.941, blue: 0.906)
    static let card = Color(red: 0.997, green: 0.993, blue: 0.980)
    static let technique = Color(red: 0.988, green: 0.960, blue: 0.930)
    static let diagram = Color(red: 0.966, green: 0.909, blue: 0.858)
    static let ink = Color(red: 0.137, green: 0.153, blue: 0.137)
    static let muted = Color(red: 0.356, green: 0.369, blue: 0.333)
    static let line = Color(red: 0.873, green: 0.853, blue: 0.802)
    static let accent = Color(red: 0.682, green: 0.242, blue: 0.157)
    static let accentWash = Color(red: 0.954, green: 0.880, blue: 0.832)
    static let success = Color(red: 0.238, green: 0.379, blue: 0.289)
    static let successWash = Color(red: 0.902, green: 0.939, blue: 0.882)
}

struct StudioSurface: ViewModifier {
    var fill: Color = StudioColor.card
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(StudioColor.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct StudioButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primary ? .white : StudioColor.ink)
            .padding(.horizontal, 14)
            .frame(height: primary ? 45 : 34)
            .background(
                primary ? StudioColor.accent : StudioColor.card,
                in: .rect(cornerRadius: primary ? 9 : 8)
            )
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(StudioColor.line, lineWidth: 1)
                }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.50)
    }
}

struct WaveformMeter: View {
    let level: Double
    let active: Bool

    private let profile: [Double] = [
        0.14, 0.19, 0.15, 0.25, 0.35, 0.22, 0.41, 0.51, 0.28, 0.69,
        0.85, 0.49, 0.35, 0.71, 0.56, 0.28, 0.45, 0.73, 0.97, 0.68,
        0.42, 0.65, 0.83, 0.52, 0.38, 0.62, 0.39, 0.31, 0.45, 0.59,
        0.70, 0.33, 0.43, 0.56, 0.37, 0.24, 0.41, 0.30, 0.22, 0.17, 0.13
    ]

    var body: some View {
        Canvas { context, size in
            let step = size.width / CGFloat(profile.count)
            let barWidth = min(3, step * 0.55)
            for (index, magnitude) in profile.enumerated() {
                let amplitude = active ? (0.13 + level * 0.87) : 0.41
                let height = 3 + size.height * magnitude * amplitude
                let bounds = CGRect(
                    x: step * (CGFloat(index) + 0.5) - barWidth / 2,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let bar = Path(roundedRect: bounds, cornerRadius: barWidth / 2)
                let color = active ? StudioColor.accent.opacity(0.64 + magnitude * 0.32) : StudioColor.line
                context.fill(bar, with: .color(color))
            }
        }
        .frame(height: 31)
        .accessibilityHidden(true)
    }
}

struct MouthPositionDiagram: View {
    let drillID: String

    private struct Position {
        var tip: CGPoint
        var crest: CGPoint
        var marker: CGPoint
        var jaw: CGFloat = 0
    }

    private var position: Position {
        switch drillID {
        case "r":
            Position(tip: CGPoint(x: 121, y: 106), crest: CGPoint(x: 152, y: 103),
                     marker: CGPoint(x: 139, y: 106))
        case "v":
            Position(tip: CGPoint(x: 118, y: 126), crest: CGPoint(x: 159, y: 126),
                     marker: CGPoint(x: 101, y: 113), jaw: -3)
        case "short-i":
            Position(tip: CGPoint(x: 113, y: 128), crest: CGPoint(x: 141, y: 109),
                     marker: CGPoint(x: 140, y: 110), jaw: 2)
        case "short-a":
            Position(tip: CGPoint(x: 114, y: 138), crest: CGPoint(x: 148, y: 122),
                     marker: CGPoint(x: 143, y: 123), jaw: 6)
        case "long-a":
            Position(tip: CGPoint(x: 116, y: 141), crest: CGPoint(x: 167, y: 124),
                     marker: CGPoint(x: 165, y: 124), jaw: 8)
        case "sh":
            Position(tip: CGPoint(x: 117, y: 121), crest: CGPoint(x: 144, y: 103),
                     marker: CGPoint(x: 137, y: 105), jaw: -1)
        default:
            Position(tip: CGPoint(x: 98, y: 116), crest: CGPoint(x: 149, y: 123),
                     marker: CGPoint(x: 102, y: 115))
        }
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 264, size.height / 156)
            var drawing = context
            drawing.translateBy(x: (size.width - 264 * scale) / 2,
                                y: (size.height - 156 * scale) / 2)
            drawing.scaleBy(x: scale, y: scale)

            let outline = Color(red: 0.31, green: 0.22, blue: 0.17)
            let skin = Color(red: 0.99, green: 0.95, blue: 0.87)
            let mouth = Color(red: 0.46, green: 0.24, blue: 0.19)
            let tongue = Color(red: 0.87, green: 0.43, blue: 0.32)
            let p = position
            let lowerLip: CGFloat = drillID == "v" ? 114 : (drillID == "sh" ? 120 : 121) + p.jaw

            let cavity = Path { path in
                path.move(to: CGPoint(x: 102, y: 104))
                path.addQuadCurve(to: CGPoint(x: 151, y: 82), control: CGPoint(x: 126, y: 80))
                path.addCurve(to: CGPoint(x: 200, y: 100),
                              control1: CGPoint(x: 177, y: 83), control2: CGPoint(x: 183, y: 96))
                path.addQuadCurve(to: CGPoint(x: 203, y: 144), control: CGPoint(x: 210, y: 122))
                path.addQuadCurve(to: CGPoint(x: 108, y: 134 + p.jaw),
                                  control: CGPoint(x: 160, y: 148))
                path.closeSubpath()
            }
            drawing.fill(cavity, with: .color(mouth))

            let tongueShape = Path { path in
                path.move(to: p.tip)
                path.addCurve(to: p.crest,
                              control1: CGPoint(x: p.tip.x + 12, y: p.tip.y + 2),
                              control2: CGPoint(x: p.crest.x - 14, y: p.crest.y - 1))
                path.addCurve(to: CGPoint(x: 204, y: 136),
                              control1: CGPoint(x: 175, y: p.crest.y + 1),
                              control2: CGPoint(x: 196, y: 123))
                path.addQuadCurve(to: CGPoint(x: 127, y: 140 + p.jaw),
                                  control: CGPoint(x: 168, y: 153))
                path.addQuadCurve(to: p.tip, control: CGPoint(x: p.tip.x + 5, y: 134 + p.jaw))
                path.closeSubpath()
            }
            drawing.fill(tongueShape, with: .color(tongue))
            drawing.stroke(tongueShape, with: .color(outline), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

            let upperProfile = Path { path in
                path.move(to: CGPoint(x: 121, y: 15))
                path.addQuadCurve(to: CGPoint(x: 105, y: 53), control: CGPoint(x: 107, y: 27))
                path.addQuadCurve(to: CGPoint(x: 84, y: 78), control: CGPoint(x: 98, y: 67))
                path.addQuadCurve(to: CGPoint(x: 91, y: 87), control: CGPoint(x: 78, y: 85))
                path.addQuadCurve(to: CGPoint(x: 98, y: 90), control: CGPoint(x: 97, y: 86))
                path.addQuadCurve(to: CGPoint(x: 93, y: 101), control: CGPoint(x: 98, y: 96))
                path.addQuadCurve(to: CGPoint(x: 104, y: 107), control: CGPoint(x: 90, y: 109))
                path.addQuadCurve(to: CGPoint(x: 127, y: 93), control: CGPoint(x: 115, y: 102))
                path.addCurve(to: CGPoint(x: 177, y: 90),
                              control1: CGPoint(x: 146, y: 79), control2: CGPoint(x: 158, y: 82))
                path.addQuadCurve(to: CGPoint(x: 202, y: 103), control: CGPoint(x: 192, y: 98))
            }
            drawing.stroke(upperProfile, with: .color(outline), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            let teeth = Path { path in
                path.move(to: CGPoint(x: 103, y: 106))
                path.addQuadCurve(to: CGPoint(x: 114, y: 102), control: CGPoint(x: 108, y: 105))
                path.addLine(to: CGPoint(x: 114, y: 111))
                path.addQuadCurve(to: CGPoint(x: 104, y: 114), control: CGPoint(x: 108, y: 115))
                path.closeSubpath()
            }
            drawing.fill(teeth, with: .color(skin))
            drawing.stroke(teeth, with: .color(outline), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

            let lowerProfile = Path { path in
                path.move(to: CGPoint(x: 106, y: lowerLip + 1))
                path.addQuadCurve(to: CGPoint(x: 95, y: lowerLip), control: CGPoint(x: 101, y: lowerLip - 3))
                path.addQuadCurve(to: CGPoint(x: 93, y: lowerLip + 8), control: CGPoint(x: 90, y: lowerLip + 3))
                path.addQuadCurve(to: CGPoint(x: 99, y: lowerLip + 18), control: CGPoint(x: 100, y: lowerLip + 10))
                path.addQuadCurve(to: CGPoint(x: 113, y: 147 + p.jaw / 2), control: CGPoint(x: 99, y: 149))
                path.addQuadCurve(to: CGPoint(x: 147, y: 144 + p.jaw / 2), control: CGPoint(x: 126, y: 149))
                path.addQuadCurve(to: CGPoint(x: 203, y: 144), control: CGPoint(x: 177, y: 147))
                path.move(to: CGPoint(x: 106, y: lowerLip + 1))
                path.addQuadCurve(to: CGPoint(x: 117, y: 132 + p.jaw), control: CGPoint(x: 113, y: lowerLip + 5))
            }
            drawing.stroke(lowerProfile, with: .color(outline), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            if drillID == "th" || drillID == "sh" {
                for offset in [-4.0, 4.0] {
                    let air = Path { path in
                        path.move(to: CGPoint(x: 88, y: 114 + offset))
                        path.addQuadCurve(to: CGPoint(x: 66, y: 116 + offset),
                                          control: CGPoint(x: 77, y: 112 + offset))
                    }
                    drawing.stroke(air, with: .color(StudioColor.accent.opacity(0.70)),
                                   style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [2, 3]))
                }
            }

            let line = Path { path in
                path.move(to: p.marker)
                path.addLine(to: CGPoint(x: p.marker.x + 34, y: 51))
                path.addLine(to: CGPoint(x: 217, y: 51))
            }
            drawing.stroke(line, with: .color(StudioColor.accent.opacity(0.75)),
                           style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [3, 3]))
            let spot = Path(ellipseIn: CGRect(x: p.marker.x - 4, y: p.marker.y - 4, width: 8, height: 8))
            drawing.fill(spot, with: .color(StudioColor.accent))
            drawing.stroke(spot, with: .color(skin), lineWidth: 1.35)
            let endpoint = Path(ellipseIn: CGRect(x: 215, y: 49, width: 4, height: 4))
            drawing.fill(endpoint, with: .color(StudioColor.accent))
        }
        .frame(height: 148)
        .background(StudioColor.diagram, in: .rect(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}
