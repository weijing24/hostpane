import SwiftUI
import HostpaneCore

struct DashboardSettingsView: View {
    @Environment(AppModel.self) private var model
    var openPage: (SettingsPage) -> Void

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                settingsLink("仪表板背景", systemImage: "photo") {
                    openPage(.dashboardBackground)
                }
            } header: {
                Text("外观")
            }

            Section {
                settingsLink("状态详情布局", systemImage: "rectangle.split.2x2") {
                    openPage(.statusLayout)
                }
            } header: {
                Text("状态详情")
            }

            Section {
                Picker("刷新间隔", selection: $model.settings.statusRefreshSeconds) {
                    ForEach(AppSettings.statusRefreshChoices, id: \.self) { seconds in
                        Text("\(seconds) 秒").tag(seconds)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("状态刷新")
            } footer: {
                Text("上一次采集返回之后，再等待这段时间，才发送下一次机器状态请求。")
            }

            Section {
                Toggle("显示标签筛选", isOn: $model.settings.showTagFilter)
                    .onChange(of: model.settings.showTagFilter) { _, shown in
                        if !shown {
                            model.dashboardFilter = .all
                            model.machineFilter = .all
                        }
                    }
                Toggle("服务器列表显示标签", isOn: $model.settings.showTagsOnMachines)
            } header: {
                Text("标签")
            } footer: {
                Text("标签筛选会显示在机器列表和仪表板上。服务器列表标签只控制机器卡片上的标签。")
            }

            Section {
                Toggle("显示延迟", isOn: $model.settings.showLatency)
                Toggle("延迟显示颜色", isOn: $model.settings.latencyUsesColor)
                Stepper(value: $model.settings.latencyRefreshSeconds, in: 5...120) {
                    Text("每 \(model.settings.latencyRefreshSeconds) 秒刷新一次")
                }
            } header: {
                Text("延迟显示")
            } footer: {
                Text("这台 Mac 到服务器的近似 SSH 往返时间。延迟探测和状态采集分开计时。")
            }

            Section {
                Toggle("减少实时状态动画", isOn: $model.settings.reduceStatusMotion)
            } header: {
                Text("动态效果")
            } footer: {
                Text("打开后，仪表板和状态详情不再播放环形图和悬停过渡。")
            }
        }
        .formStyle(.grouped)
    }

    private func settingsLink(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum BackgroundPalette: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
    var title: String { self == .light ? "亮色" : "暗色" }
    var isDark: Bool { self == .dark }
}

struct DashboardBackgroundSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var palette = BackgroundPalette.light

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(BackgroundPalette.allCases) { mode in
                            Button {
                                palette = mode
                            } label: {
                                Text(mode.title)
                                    .font(.callout.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(palette == mode ? Color.white : Color.primary)
                                    .background(
                                        Capsule().fill(palette == mode ? HostpaneTheme.accent : Color.secondary.opacity(0.15))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 220)
                    DashboardBackgroundPreview(background: selection, dark: palette.isDark)
                }
                .padding(.vertical, 4)
            } header: {
                Text("预览")
            }

            Section {
                ForEach(DashboardBackground.allCases) { background in
                    Button {
                        setBackground(background)
                    } label: {
                        HStack(spacing: 12) {
                            Text(background.title)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 12)
                            DashboardBackgroundSwatch(background: background, dark: palette.isDark)
                            Image(systemName: selection == background ? "circle.inset.filled" : "circle")
                                .foregroundStyle(selection == background ? HostpaneTheme.accent : Color.secondary.opacity(0.45))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(palette.isDark ? "深色模式背景" : "浅色模式背景")
            } footer: {
                Text("适用于仪表板和状态详情。暗色列表只在深色外观下使用。")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if model.isDarkAppearance {
                palette = .dark
            }
        }
    }

    private var selection: DashboardBackground {
        palette.isDark ? model.settings.dashboardBackgroundDark : model.settings.dashboardBackgroundLight
    }

    private func setBackground(_ background: DashboardBackground) {
        if palette.isDark {
            model.settings.dashboardBackgroundDark = background
        } else {
            model.settings.dashboardBackgroundLight = background
        }
    }
}

struct StatusLayoutEditorView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: StatusCardKind?

    var body: some View {
        let layout = model.settings.statusLayout
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("列数")
                        .font(.headline)
                    Spacer()
                    Picker("列数", selection: columnsBinding) {
                        ForEach(1...4, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("组件")
                        .font(.headline)
                    if layout.missingKinds.isEmpty {
                        Text("所有组件都已在画布上。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(layout.missingKinds) { kind in
                            Button {
                                add(kind)
                            } label: {
                                Label("添加\(kind.title)", systemImage: "plus")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("布局")
                        .font(.headline)
                    StatusLayoutCanvas(layout: layout, selected: selected) { kind in
                        selected = kind
                    }
                }

                if let selected, let placement = layout.cards.first(where: { $0.kind == selected }) {
                    placementControls(placement, columns: layout.columns)
                }

                Text("选择一张卡片，编辑它所在的列、宽度和高度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HostpaneTheme.page)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    guard let selected else { return }
                    var layout = model.settings.statusLayout
                    layout.remove(selected)
                    model.settings.statusLayout = layout
                    self.selected = nil
                } label: {
                    Image(systemName: "trash")
                }
                .help("从画布移除")
                .disabled(selected == nil)
                Button {
                    model.settings.statusLayout = .default
                    selected = nil
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("恢复默认布局")
            }
        }
    }

    private var columnsBinding: Binding<Int> {
        Binding(
            get: { model.settings.statusLayout.columns },
            set: { newValue in
                var layout = model.settings.statusLayout
                layout.columns = newValue
                model.settings.statusLayout = layout.normalized()
            }
        )
    }

    private func add(_ kind: StatusCardKind) {
        var layout = model.settings.statusLayout
        layout.add(kind)
        model.settings.statusLayout = layout
        selected = kind
    }

    @ViewBuilder
    private func placementControls(_ placement: StatusCardPlacement, columns: Int) -> some View {
        let columnLimit = max(columns - placement.width, 0)
        let widthLimit = max(columns - placement.column, 1)
        VStack(alignment: .leading, spacing: 8) {
            Text(placement.kind.title)
                .font(.headline)
            Stepper(value: placementBinding(\.column), in: 0...columnLimit) {
                Text("列：\(placement.column + 1)")
            }
            Stepper(value: placementBinding(\.width), in: 1...widthLimit) {
                Text("宽度：\(placement.width)")
            }
            Stepper(value: placementBinding(\.height), in: 1...StatusCardPlacement.maxHeight) {
                Text("高度：\(placement.height)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func placementBinding(_ keyPath: WritableKeyPath<StatusCardPlacement, Int>) -> Binding<Int> {
        Binding(
            get: {
                guard let selected,
                      let placement = model.settings.statusLayout.cards.first(where: { $0.kind == selected })
                else { return 1 }
                return placement[keyPath: keyPath]
            },
            set: { newValue in
                guard let selected else { return }
                var layout = model.settings.statusLayout
                guard let index = layout.cards.firstIndex(where: { $0.kind == selected }) else { return }
                layout.cards[index][keyPath: keyPath] = newValue
                model.settings.statusLayout = layout.normalized()
            }
        )
    }
}

struct DashboardPageBackground: View {
    var light: DashboardBackground
    var dark: DashboardBackground
    var isDark: Bool

    var body: some View {
        let choice = isDark ? dark : light
        if let gradient = choice.linearGradient(dark: isDark) {
            gradient
        } else if isDark {
            Color(red: 0.11, green: 0.11, blue: 0.12)
        } else {
            HostpaneTheme.page
        }
    }
}

struct DashboardScrollBackdrop<Content: View>: View {
    var light: DashboardBackground
    var dark: DashboardBackground
    var isDark: Bool
    var inset: CGFloat = 24
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .padding(inset)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    .background {
                        DashboardPageBackground(light: light, dark: dark, isDark: isDark)
                    }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct DashboardBackgroundPreview: View {
    var background: DashboardBackground
    var dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                previewStat("总计", 6, HostpaneTheme.total)
                previewStat("在线", 5, HostpaneTheme.online)
                previewStat("离线", 1, HostpaneTheme.offline)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preview Server")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(HostpaneTheme.online).frame(width: 8, height: 8)
                        Text("24 ms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(HostpaneTheme.online)
                    }
                }
                HStack(spacing: 12) {
                    meta("cpu", "12 Cores")
                    meta("memorychip", "16.0 G")
                    meta("internaldrive", "128 G")
                    meta("clock", "10 h")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    RingMeter(title: "CPU", ratio: 0.18, color: HostpaneTheme.cpuRing, size: 48, titleOnTop: true)
                    RingMeter(title: "RAM", ratio: 0.40, color: HostpaneTheme.memoryRing, size: 48, titleOnTop: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            DashboardPageBackground(light: background, dark: background, isDark: dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func previewStat(_ title: String, _ value: Int, _ dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text("\(value)")
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func meta(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text).monospacedDigit()
        }
    }
}

private struct DashboardBackgroundSwatch: View {
    var background: DashboardBackground
    var dark: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(background.linearGradient(dark: dark) ?? LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .windowBackgroundColor)],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .frame(width: 92, height: 22)
    }
}

private struct StatusLayoutCanvas: View {
    var layout: StatusDetailLayout
    var selected: StatusCardKind?
    var onSelect: (StatusCardKind) -> Void

    var body: some View {
        let normalized = layout.normalized()
        let slots = StatusLayoutGrid.slots(for: normalized)
        let rowCount = max(slots.map { $0.row + $0.height }.max() ?? 1, 1)
        let rowHeight = CGFloat(128)
        let gap = CGFloat(10)
        GeometryReader { geo in
            let columnWidth = geo.size.width / CGFloat(max(normalized.columns, 1))
            ZStack(alignment: .topLeading) {
                ForEach(slots) { slot in
                    StatusLayoutSlotButton(
                        slot: slot,
                        selected: selected == slot.kind,
                        columnWidth: columnWidth,
                        rowHeight: rowHeight,
                        gap: gap,
                        onSelect: onSelect
                    )
                }
            }
        }
        .frame(height: rowHeight * CGFloat(rowCount))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

private struct StatusLayoutSlotButton: View {
    var slot: StatusGridSlot
    var selected: Bool
    var columnWidth: CGFloat
    var rowHeight: CGFloat
    var gap: CGFloat
    var onSelect: (StatusCardKind) -> Void

    var body: some View {
        Button {
            onSelect(slot.kind)
        } label: {
            StatusLayoutPreviewCard(kind: slot.kind, selected: selected)
        }
        .buttonStyle(.plain)
        .frame(width: tileWidth, height: tileHeight)
        .offset(x: originX, y: originY)
    }

    private var tileWidth: CGFloat {
        max(columnWidth * CGFloat(slot.width) - gap, 40)
    }

    private var tileHeight: CGFloat {
        max(rowHeight * CGFloat(slot.height) - gap, 40)
    }

    private var originX: CGFloat {
        columnWidth * CGFloat(slot.column) + gap / 2
    }

    private var originY: CGFloat {
        rowHeight * CGFloat(slot.row) + gap / 2
    }
}

private struct StatusLayoutPreviewCard: View {
    var kind: StatusCardKind
    var selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(kind.title, systemImage: kind.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(kind.tint)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(kind.previewLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? HostpaneTheme.accent : Color.secondary.opacity(0.16), lineWidth: selected ? 2 : 1)
        )
    }
}

extension DashboardBackground {
    func linearGradient(dark: Bool) -> LinearGradient? {
        guard let stops = colorStops(dark: dark) else { return nil }
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func colorStops(dark: Bool) -> [Color]? {
        guard let light = lightStops else { return nil }
        let rgb = dark ? light.map(Self.darken) : light
        return rgb.map { Color(red: $0.0, green: $0.1, blue: $0.2) }
    }

    private var lightStops: [(Double, Double, Double)]? {
        switch self {
        case .plain:
            return nil
        case .sunrise:
            return [(1.00, 0.70, 0.78), (1.00, 0.82, 0.66), (1.00, 0.89, 0.60)]
        case .sunset:
            return [(1.00, 0.70, 0.28), (1.00, 0.42, 0.24), (0.89, 0.23, 0.29)]
        case .love:
            return [(1.00, 0.35, 0.42), (1.00, 0.54, 0.63), (1.00, 0.70, 0.78)]
        case .ocean:
            return [(0.49, 0.88, 0.82), (0.37, 0.78, 0.90), (0.56, 0.83, 1.00)]
        case .barbie:
            return [(1.00, 0.31, 0.64), (1.00, 0.48, 0.82), (1.00, 0.65, 0.88)]
        case .starry:
            return [(0.95, 0.91, 0.69), (0.56, 0.60, 0.83), (0.16, 0.16, 0.42)]
        case .jelly:
            return [(0.24, 0.75, 0.71), (0.42, 0.49, 1.00), (0.75, 0.52, 0.99)]
        case .lavandula:
            return [(0.78, 0.71, 1.00), (0.65, 0.55, 0.98), (0.49, 0.42, 0.90)]
        case .watermelon:
            return [(1.00, 0.30, 0.30), (1.00, 0.54, 0.24), (0.78, 0.88, 0.35)]
        case .dandelion:
            return [(0.96, 0.91, 0.76), (0.91, 0.95, 0.83), (0.72, 0.89, 0.82)]
        case .lemon:
            return [(0.96, 0.91, 0.54), (0.83, 0.94, 0.63), (0.66, 0.85, 0.94)]
        case .spring:
            return [(1.00, 0.70, 0.85), (0.91, 0.78, 1.00), (0.72, 0.85, 1.00)]
        case .summer:
            return [(0.12, 0.42, 0.23), (0.49, 0.70, 0.26), (0.83, 0.88, 0.34)]
        case .autumn:
            return [(1.00, 0.70, 0.28), (1.00, 0.48, 0.24), (0.90, 0.22, 0.21)]
        case .winter:
            return [(0.84, 0.89, 1.00), (0.89, 0.85, 1.00), (0.96, 0.94, 1.00)]
        case .neon:
            return [(0.75, 0.15, 0.83), (0.49, 0.23, 0.93), (0.13, 0.83, 0.93)]
        case .aurora:
            return [(0.18, 0.83, 0.75), (0.05, 0.45, 0.56), (0.06, 0.15, 0.27)]
        case .ai:
            return [(1.00, 0.48, 0.24), (1.00, 0.31, 0.64), (0.49, 0.42, 1.00)]
        case .colorful:
            return [(0.98, 0.66, 0.83), (0.77, 0.71, 0.99), (0.65, 0.95, 0.99)]
        }
    }

    /// Dark mode keeps the same hue, dark enough for the page but still obviously colored.
    private static func darken(_ color: (Double, Double, Double)) -> (Double, Double, Double) {
        (
            min(color.0 * 0.55 + 0.12, 0.75),
            min(color.1 * 0.55 + 0.12, 0.75),
            min(color.2 * 0.55 + 0.12, 0.75)
        )
    }
}

extension StatusCardKind {
    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .load: return "waveform.path.ecg"
        case .processes: return "list.bullet.rectangle"
        case .memory: return "memorychip"
        case .network: return "network"
        case .storage: return "internaldrive"
        case .docker: return "shippingbox"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: return HostpaneTheme.cpuUser
        case .load: return HostpaneTheme.loadFifteen
        case .processes: return HostpaneTheme.loadOne
        case .memory: return HostpaneTheme.memUsed
        case .network: return HostpaneTheme.netUp
        case .storage: return HostpaneTheme.online
        case .docker: return HostpaneTheme.docker
        }
    }

    var previewLine: String {
        switch self {
        case .cpu: return "18%"
        case .load: return "0.00 / 0.00 / 0.00"
        case .processes: return "Pid · Process · CPU"
        case .memory: return "6.43 G · 40% Used"
        case .network: return "128 K/s"
        case .storage: return "48.0 G / 128 G"
        case .docker: return "正在运行的容器  0"
        }
    }
}
