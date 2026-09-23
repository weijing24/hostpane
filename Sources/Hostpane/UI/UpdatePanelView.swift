import SwiftUI

enum UpdatePhase: Equatable {
    case checking
    case upToDate(current: String, latest: String)
    case available(version: String, notes: String)
    case downloading(version: String)
    case installing(version: String)
    case failed(String)
}

struct UpdatePanelView: View {
    var phase: UpdatePhase
    var onInstall: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            Spacer(minLength: 0)
            buttons
        }
        .padding(20)
        .frame(width: 460, height: 420)
        .background(HostpaneTheme.page)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("软件更新")
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var subtitle: String {
        switch phase {
        case .checking:
            return "正在检查 GitHub Releases…"
        case .upToDate(let current, let latest):
            if current == latest {
                return "Hostpane \(current) 已是最新版本"
            }
            return "当前 \(current) 比已发布的 \(latest) 新"
        case .available(let version, _):
            return "可以安装 Hostpane \(version)"
        case .downloading(let version):
            return "正在下载 Hostpane \(version)…"
        case .installing(let version):
            return "正在安装 Hostpane \(version)…"
        case .failed:
            return "没有完成更新"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .checking, .downloading, .installing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(progressText)
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            Text("发布页上没有更新的版本。")
                .foregroundStyle(.secondary)
        case .available(_, let notes):
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    Text(notes.isEmpty ? "这个版本没有更新说明。" : notes)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(height: 220)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                Text("安装会替换 /Applications/Hostpane.app，然后重新打开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var progressText: String {
        switch phase {
        case .checking: return "正在获取最新版本"
        case .downloading: return "正在下载磁盘映像"
        case .installing: return "即将退出并重新打开"
        default: return ""
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            Spacer()
            switch phase {
            case .available:
                Button("稍后", action: onClose)
                Button("安装并重新打开", action: onInstall)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            case .downloading:
                Button("取消", action: onClose)
            case .installing:
                EmptyView()
            default:
                Button("好", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
