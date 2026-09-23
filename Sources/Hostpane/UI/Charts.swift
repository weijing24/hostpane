import SwiftUI
import HostpaneCore

struct RingMeter: View {
    var title: String
    var ratio: Double?
    var color: Color
    var size: CGFloat = 72
    var titleOnTop: Bool = false
    @Environment(\.reduceStatusMotion) private var reduceStatusMotion

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
        .animation(reduceStatusMotion ? nil : .easeInOut(duration: 0.35), value: ratio)
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
        DockerLogoShape()
            .fill(color, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
            .accessibilityLabel("Docker")
    }
}

/// Official Moby Dock mark from https://uxwing.com/docker-icon/ (viewBox 122.88×88.17).
private struct DockerLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let view = CGSize(width: 122.88, height: 88.17)
        let scale = min(rect.width / view.width, rect.height / view.height)
        let origin = CGPoint(
            x: rect.midX - view.width * scale / 2,
            y: rect.midY - view.height * scale / 2
        )
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: origin.x, ty: origin.y)
        return svgPath.applying(transform)
    }

    private var svgPath: Path {
        Self.parse(
            """
            M121.68,33.34c-0.34-0.28-3.42-2.62-10.03-2.62c-1.71,0-3.48,0.17-5.19,0.46c-1.25-8.72-8.49-12.94-8.78-13.16 \
            l-1.77-1.03l-1.14,1.65c-1.42,2.22-2.51,4.73-3.13,7.29c-1.2,4.96-0.46,9.63,2.05,13.62c-3.02,1.71-7.92,2.11-8.95,2.17l-80.93,0 \
            c-2.11,0-3.82,1.71-3.82,3.82c-0.11,7.07,1.08,14.13,3.53,20.8c2.79,7.29,6.95,12.71,12.31,16.01c6.04,3.7,15.9,5.81,27.01,5.81 \
            c5.01,0,10.03-0.46,14.99-1.37c6.9-1.25,13.51-3.65,19.6-7.12c5.02-2.91,9.52-6.61,13.34-10.94c6.44-7.24,10.26-15.33,13.05-22.51 \
            c0.4,0,0.74,0,1.14,0c7.01,0,11.34-2.79,13.73-5.19c1.6-1.48,2.79-3.31,3.65-5.36l0.51-1.48L121.68,33.34z \
            M71.59,39.38h10.83c0.51,0,0.97-0.4,0.97-0.97v-9.69c0-0.51-0.4-0.97-0.97-0.97h-10.83c-0.51,0-0.97,0.4-0.97,0.97v9.69 \
            C70.68,38.98,71.08,39.38,71.59,39.38z \
            M56.49,11.63h10.83c0.51,0,0.97-0.4,0.97-0.97V0.97c0-0.51-0.46-0.97-0.97-0.97H56.49c-0.51,0-0.97,0.4-0.97,0.97v9.69 \
            C55.52,11.17,55.97,11.63,56.49,11.63z \
            M56.49,25.53h10.83c0.51,0,0.97-0.46,0.97-0.97v-9.69c0-0.51-0.46-0.97-0.97-0.97H56.49c-0.51,0-0.97,0.4-0.97,0.97v9.69 \
            C55.52,25.08,55.97,25.53,56.49,25.53z \
            M41.5,25.53h10.83c0.51,0,0.97-0.46,0.97-0.97v-9.69c0-0.51-0.4-0.97-0.97-0.97H41.5c-0.51,0-0.97,0.4-0.97,0.97v9.69 \
            C40.53,25.08,40.93,25.53,41.5,25.53z \
            M26.28,25.53h10.83c0.51,0,0.97-0.46,0.97-0.97v-9.69c0-0.51-0.4-0.97-0.97-0.97H26.28c-0.51,0-0.97,0.4-0.97,0.97v9.69 \
            C25.37,25.08,25.77,25.53,26.28,25.53z \
            M56.49,39.38h10.83c0.51,0,0.97-0.4,0.97-0.97v-9.69c0-0.51-0.4-0.97-0.97-0.97h-10.83c-0.51,0-0.97,0.4-0.97,0.97v9.69 \
            C55.52,38.98,55.97,39.38,56.49,39.38z \
            M41.5,39.38h10.83c0.51,0,0.97-0.4,0.97-0.97v-9.69c0-0.51-0.4-0.97-0.97-0.97h-10.83c-0.51,0-0.97,0.4-0.97,0.97v9.69 \
            C40.53,38.98,40.93,39.38,41.5,39.38z \
            M26.28,39.38h10.83c0.51,0,0.97-0.4,0.97-0.97v-9.69c0-0.51-0.4-0.97-0.97-0.97h-10.83c-0.51,0-0.97,0.4-0.97,0.97v9.69 \
            C25.37,38.98,25.77,39.38,26.28,39.38z \
            M11.35,39.38h10.83c0.51,0,0.97-0.4,0.97-0.97v-9.69c0-0.51-0.4-0.97-0.97-0.97h-10.83c-0.51,0-0.97,0.4-0.97,0.97v9.69 \
            C10.44,38.98,10.84,39.38,11.35,39.38z
            """
        )
    }

    private static func parse(_ d: String) -> Path {
        let tokens = tokenize(d)
        var path = Path()
        var i = 0
        var command: Character = "M"
        var x: CGFloat = 0
        var y: CGFloat = 0
        var start = CGPoint.zero

        func number() -> CGFloat {
            guard i < tokens.count, let value = Double(tokens[i]) else { return 0 }
            i += 1
            return CGFloat(value)
        }

        while i < tokens.count {
            let token = tokens[i]
            if let first = token.first, first.isLetter {
                command = first
                i += 1
                if command == "Z" || command == "z" {
                    path.closeSubpath()
                    x = start.x
                    y = start.y
                    continue
                }
            }
            switch command {
            case "M":
                x = number(); y = number()
                path.move(to: CGPoint(x: x, y: y))
                start = CGPoint(x: x, y: y)
                command = "L"
            case "m":
                x += number(); y += number()
                path.move(to: CGPoint(x: x, y: y))
                start = CGPoint(x: x, y: y)
                command = "l"
            case "L":
                x = number(); y = number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "l":
                x += number(); y += number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "H":
                x = number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "h":
                x += number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "V":
                y = number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "v":
                y += number()
                path.addLine(to: CGPoint(x: x, y: y))
            case "C":
                let x1 = number(), y1 = number(), x2 = number(), y2 = number()
                x = number(); y = number()
                path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case "c":
                let x1 = x + number(), y1 = y + number()
                let x2 = x + number(), y2 = y + number()
                let nx = x + number(), ny = y + number()
                path.addCurve(to: CGPoint(x: nx, y: ny), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
                x = nx; y = ny
            default:
                i += 1
            }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        for character in d {
            if character.isLetter {
                flush()
                tokens.append(String(character))
            } else if character == "," || character.isWhitespace {
                flush()
            } else if character == "-", !current.isEmpty, current.last != "e", current.last != "E" {
                flush()
                current = "-"
            } else if character == ".", current.contains(".") {
                flush()
                current = "."
            } else {
                current.append(character)
            }
        }
        flush()
        return tokens
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
    @Environment(\.reduceStatusMotion) private var reduceStatusMotion

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
                    let update = {
                        if inside {
                            hovered = slice.kind
                        } else if hovered == slice.kind {
                            hovered = nil
                        }
                    }
                    if reduceStatusMotion {
                        update()
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            update()
                        }
                    }
                }
                .zIndex(expanded ? 1 : 0)
            }
            centerLabel
                .animation(reduceStatusMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: hovered)
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
