import SwiftUI

enum SettingsTabSection: String, CaseIterable, Identifiable {
    case app = "App"
    case features = "功能"
    case help = "帮助"

    var id: String { rawValue }
}

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case security
    case sync
    case connection
    case dashboard
    case terminal
    case sftp
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .security: return "安全性"
        case .sync: return "同步"
        case .connection: return "连接"
        case .dashboard: return "仪表板"
        case .terminal: return "终端"
        case .sftp: return "SFTP"
        case .diagnostics: return "诊断"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .security: return "lock.fill"
        case .sync: return "cloud.fill"
        case .connection: return "cable.connector"
        case .dashboard: return "gauge.with.needle.fill"
        case .terminal: return "terminal.fill"
        case .sftp: return "folder.fill"
        case .diagnostics: return "waveform.path.ecg"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(white: 0.45)
        case .security: return Color(red: 0.22, green: 0.48, blue: 0.98)
        case .sync: return Color(red: 0.22, green: 0.58, blue: 0.98)
        case .connection: return Color(red: 0.18, green: 0.72, blue: 0.42)
        case .dashboard: return Color(red: 0.98, green: 0.55, blue: 0.18)
        case .terminal: return Color(white: 0.35)
        case .sftp: return Color(red: 0.16, green: 0.66, blue: 0.62)
        case .diagnostics: return Color(red: 0.92, green: 0.28, blue: 0.32)
        }
    }

    var section: SettingsTabSection {
        switch self {
        case .general, .security, .sync: return .app
        case .connection, .dashboard, .terminal, .sftp: return .features
        case .diagnostics: return .help
        }
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return true }
        return title.localizedCaseInsensitiveContains(needle)
            || section.rawValue.localizedCaseInsensitiveContains(needle)
    }
}

enum SettingsChrome {
    static let sidebarWidth: CGFloat = 236
}

struct SettingsGroup<Content: View>: View {
    var title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            VStack(spacing: 0) {
                content()
            }
            .hostpaneGlassCard(cornerRadius: 12)
            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 4)
            }
        }
    }
}

struct SettingsHairline: View {
    var body: some View {
        Divider()
            .padding(.leading, 14)
    }
}

struct SettingsLabeledRow<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14))
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct SettingsToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsLabeledRow(title: title) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct SettingsChevronRow: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsLabeledRow(title: title) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SettingsActionRow: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(HostpaneTheme.accent)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
