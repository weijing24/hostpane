import SwiftUI
import HostpaneCore

struct RingMeter: View {
    var title: String
    var ratio: Double?
    var color: Color
    var size: CGFloat = 72
    var titleOnTop: Bool = false

    var body: some View {
        let ring = ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: max(5, size / 10))
            Circle()
                .trim(from: 0, to: min(max(ratio ?? 0, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: max(5, size / 10), lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(ratio.map(formatPercent) ?? "—")
                .font(size < 60 ? .caption2.monospacedDigit().weight(.semibold) : .caption.monospacedDigit().weight(.semibold))
        }
        .frame(width: size, height: size)
        let label = Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
        VStack(spacing: 4) {
            if titleOnTop {
                label
                ring
            } else {
                ring
                label
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct LoadChart: View {
    var points: [LoadPoint]

    var body: some View {
        Canvas { context, size in
            let peak = nicePeak(points.flatMap { [$0.one, $0.five, $0.fifteen] }.max() ?? 1)
            let plot = CGRect(x: 8, y: 4, width: max(size.width - 36, 8), height: max(size.height - 22, 8))
            drawGrid(context: context, plot: plot, peak: peak)
            guard points.count >= 2 else { return }
            stroke(context: context, plot: plot, peak: peak, color: HostpaneTheme.loadOne) { $0.one }
            stroke(context: context, plot: plot, peak: peak, color: HostpaneTheme.loadFive) { $0.five }
            stroke(context: context, plot: plot, peak: peak, color: HostpaneTheme.loadFifteen) { $0.fifteen }
            drawTimes(context: context, plot: plot)
        }
        .accessibilityLabel("CPU load history")
    }

    private func nicePeak(_ value: Double) -> Double {
        let floorValue = max(value, 1)
        if floorValue <= 1 { return 1 }
        if floorValue <= 2 { return 2 }
        let step: Double = floorValue <= 4 ? 1 : (floorValue <= 8 ? 2 : (floorValue <= 16 ? 4 : 8))
        return (floorValue / step).rounded(.up) * step
    }

    private func drawGrid(context: GraphicsContext, plot: CGRect, peak: Double) {
        for step in 0...4 {
            let y = plot.maxY - plot.height * CGFloat(step) / 4
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: y))
            line.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(line, with: .color(.secondary.opacity(step == 0 ? 0.35 : 0.12)), lineWidth: 1)
            let label = peak >= 10
                ? String(format: "%.0f", peak * Double(step) / 4)
                : String(format: "%g", peak * Double(step) / 4)
            context.draw(
                Text(label).font(.caption2).foregroundColor(.secondary),
                at: CGPoint(x: plot.maxX + 6, y: y),
                anchor: .leading
            )
        }
    }

    private func drawTimes(context: GraphicsContext, plot: CGRect) {
        guard points.count >= 2 else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let first = points[points.count / 3]
        let last = points[(points.count * 2) / 3]
        for point in [first, last] {
            let index = points.firstIndex(of: point) ?? 0
            let x = plot.minX + CGFloat(index) / CGFloat(points.count - 1) * plot.width
            var line = Path()
            line.move(to: CGPoint(x: x, y: plot.minY))
            line.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(
                line,
                with: .color(.secondary.opacity(0.22)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            context.draw(
                Text(formatter.string(from: point.at)).font(.caption2).foregroundColor(.secondary),
                at: CGPoint(x: x, y: plot.maxY + 10),
                anchor: .center
            )
        }
    }

    private func stroke(
        context: GraphicsContext,
        plot: CGRect,
        peak: Double,
        color: Color,
        value: (LoadPoint) -> Double
    ) {
        var path = Path()
        for (index, point) in points.enumerated() {
            let x = plot.minX + CGFloat(index) / CGFloat(max(points.count - 1, 1)) * plot.width
            let y = plot.maxY - CGFloat(min(max(value(point) / peak, 0), 1)) * plot.height
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.7)
    }
}

struct SplitTrafficDonut: View {
    var upBytes: UInt64
    var downBytes: UInt64
    var size: CGFloat = 72

    var body: some View {
        let total = max(Double(upBytes &+ downBytes), 1)
        let upShare = Double(upBytes) / total
        ZStack {
            Circle()
                .trim(from: 0.02, to: max(upShare - 0.02, 0.02))
                .stroke(HostpaneTheme.netUp, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: upShare + 0.02, to: 0.98)
                .stroke(HostpaneTheme.netDown, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

struct StorageBar: View {
    var ratio: Double
    var color: Color = HostpaneTheme.online

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.14))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: 14)
    }
}

struct DockerWhaleIcon: View {
    var size: CGFloat = 18
    var color: Color = HostpaneTheme.docker

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x / 24 * s, y: y / 24 * s)
            }
            var bodyPath = Path()
            bodyPath.move(to: p(7.2, 14))
            bodyPath.addCurve(to: p(19.2, 12.8), control1: p(10.5, 7.6), control2: p(16.2, 7.8))
            bodyPath.addCurve(to: p(21, 16.2), control1: p(21.6, 14), control2: p(21.4, 15.4))
            bodyPath.addCurve(to: p(13.2, 19.2), control1: p(20.2, 18.6), control2: p(16.4, 19.8))
            bodyPath.addCurve(to: p(7.2, 14), control1: p(9.6, 18.6), control2: p(7.4, 16.4))
            context.fill(bodyPath, with: .color(color))

            var tail = Path()
            tail.move(to: p(7.4, 13.4))
            tail.addCurve(to: p(1.8, 7.2), control1: p(5.4, 11), control2: p(3.0, 8.2))
            tail.addCurve(to: p(6.4, 11.8), control1: p(3.8, 9.4), control2: p(5.6, 11))
            tail.addCurve(to: p(1.6, 18.8), control1: p(4.2, 13.6), control2: p(2.2, 16.8))
            tail.addCurve(to: p(7.4, 15.2), control1: p(3.6, 17.4), control2: p(5.8, 16))
            tail.closeSubpath()
            context.fill(tail, with: .color(color))

            let eye = CGRect(
                x: 16.6 / 24 * s,
                y: 12.0 / 24 * s,
                width: 1.8 / 24 * s,
                height: 1.8 / 24 * s
            )
            context.fill(Path(ellipseIn: eye), with: .color(.white))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Docker")
    }
}

enum MemorySliceKind: Hashable {
    case used
    case cached
    case free

    var title: String {
        switch self {
        case .used: return "Used"
        case .cached: return "Cached"
        case .free: return "Free"
        }
    }

    var color: Color {
        switch self {
        case .used: return HostpaneTheme.memUsed
        case .cached: return HostpaneTheme.memCached
        case .free: return HostpaneTheme.memFree
        }
    }
}

struct MemoryDonut: View {
    var metrics: HostMetrics
    var size: CGFloat = 148
    @Binding var hovered: MemorySliceKind?

    var body: some View {
        let slices = Self.slices(from: metrics)
        ZStack {
            ForEach(slices) { slice in
                let expanded = hovered == slice.kind
                DonutSliceShape(
                    startFraction: slice.start,
                    endFraction: slice.end,
                    innerRatio: expanded ? 0.54 : 0.60,
                    outerRatio: expanded ? 1.0 : 0.92
                )
                .fill(slice.kind.color)
                .shadow(color: slice.kind.color.opacity(expanded ? 0.35 : 0), radius: expanded ? 8 : 0)
                .contentShape(
                    DonutSliceShape(
                        startFraction: slice.start,
                        endFraction: slice.end,
                        innerRatio: 0.52,
                        outerRatio: 1.0
                    )
                )
                .onHover { inside in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        if inside {
                            hovered = slice.kind
                        } else if hovered == slice.kind {
                            hovered = nil
                        }
                    }
                }
                .zIndex(expanded ? 1 : 0)
            }
            centerLabel
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: hovered)
        }
        .frame(width: size, height: size)
        .padding(6)
    }

    @ViewBuilder
    private var centerLabel: some View {
        let kind = hovered
        let bytes = kind.map { Self.bytes(kind: $0, metrics: metrics) } ?? metrics.memoryTotalBytes
        VStack(spacing: 2) {
            Text(kind?.title ?? "Total")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatInspectBytes(bytes))
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
        }
        .id(kind)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    private struct Slice: Identifiable {
        var kind: MemorySliceKind
        var start: CGFloat
        var end: CGFloat
        var id: MemorySliceKind { kind }
    }

    private static func bytes(kind: MemorySliceKind, metrics: HostMetrics) -> UInt64 {
        switch kind {
        case .used: return metrics.memoryBreakdownUsedBytes
        case .cached: return metrics.memoryCachedBytes
        case .free: return metrics.memoryFreeBytes
        }
    }

    private static func slices(from metrics: HostMetrics) -> [Slice] {
        let parts: [(MemorySliceKind, UInt64)] = [
            (.used, metrics.memoryBreakdownUsedBytes),
            (.cached, metrics.memoryCachedBytes),
            (.free, metrics.memoryFreeBytes)
        ]
        let total = max(
            Double(metrics.memoryTotalBytes),
            Double(parts.reduce(UInt64(0)) { $0 &+ $1.1 })
        )
        guard total > 0 else { return [] }
        let gap: CGFloat = 0.02
        var cursor: CGFloat = 0
        var result: [Slice] = []
        for (kind, bytes) in parts {
            let share = CGFloat(Double(bytes) / total)
            guard share > 0.002 else {
                cursor += share
                continue
            }
            let inset = min(gap / 2, share / 4)
            result.append(Slice(kind: kind, start: cursor + inset, end: cursor + share - inset))
            cursor += share
        }
        return result
    }
}

struct DonutSliceShape: Shape {
    var startFraction: CGFloat
    var endFraction: CGFloat
    var innerRatio: CGFloat
    var outerRatio: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(innerRatio, outerRatio) }
        set {
            innerRatio = newValue.first
            outerRatio = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = Angle.degrees(-90 + Double(startFraction) * 360)
        let end = Angle.degrees(-90 + Double(endFraction) * 360)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius * outerRatio,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: radius * innerRatio,
            startAngle: end,
            endAngle: start,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

struct DistroBadge: View {
    var osID: String
    var size: CGFloat = 64

    private var identity: String {
        osID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(background)
            mark
        }
        .frame(width: size, height: size)
        .accessibilityLabel(identity.isEmpty ? "Linux" : identity)
    }

    private var background: Color {
        switch identity {
        case "ubuntu", "pop", "popos":
            return Color(red: 0.91, green: 0.33, blue: 0.13)
        case "debian", "raspbian":
            return Color(red: 0.66, green: 0.09, blue: 0.29)
        case "synology", "dsm":
            return Color(red: 0.13, green: 0.45, blue: 0.89)
        case "fedora":
            return Color(red: 0.03, green: 0.22, blue: 0.42)
        case "centos", "rhel", "rocky", "almalinux", "ol":
            return Color(red: 0.74, green: 0.14, blue: 0.16)
        case "arch", "manjaro":
            return Color(red: 0.09, green: 0.52, blue: 0.82)
        case "alpine":
            return Color(red: 0.07, green: 0.34, blue: 0.58)
        case "opensuse", "sles":
            return Color(red: 0.45, green: 0.76, blue: 0.10)
        default:
            return HostpaneTheme.accent
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch identity {
        case "ubuntu", "pop", "popos":
            UbuntuMark()
                .padding(size * 0.16)
        case "synology", "dsm":
            Image(systemName: "internaldrive.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        default:
            Image(systemName: "server.rack")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct UbuntuMark: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width * 0.30
            let ring = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.stroke(ring, with: .color(.white), lineWidth: size.width * 0.10)
            let dotRadius = size.width * 0.10
            for degrees in [90.0, 210.0, 330.0] {
                let radians = degrees * .pi / 180
                let point = CGPoint(
                    x: center.x + cos(radians) * radius,
                    y: center.y + sin(radians) * radius
                )
                let dot = Path(ellipseIn: CGRect(
                    x: point.x - dotRadius,
                    y: point.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                ))
                context.fill(dot, with: .color(.white))
            }
        }
    }
}

struct InspectCard<Content: View>: View {
    var expandsVertically: Bool
    var content: Content

    init(expandsVertically: Bool = false, @ViewBuilder content: () -> Content) {
        self.expandsVertically = expandsVertically
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(
                maxWidth: .infinity,
                maxHeight: expandsVertically ? .infinity : nil,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
    }
}
