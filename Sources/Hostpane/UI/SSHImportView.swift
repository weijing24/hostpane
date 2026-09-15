import SwiftUI
import HostpaneCore

struct SSHImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let draft = model.importDraft {
                list(draft)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    @ViewBuilder
    private func list(_ draft: SSHImportDraft) -> some View {
        List {
            ForEach(draft.candidates) { row in
                Button {
                    model.toggleImportRow(row.id)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: row.alreadyImported
                              ? "checkmark.circle"
                              : (row.selected ? "checkmark.circle.fill" : "circle"))
                            .foregroundStyle(row.alreadyImported ? Color.secondary : HostpaneTheme.accent)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.host.displayName)
                                .foregroundStyle(.primary)
                            Text("\(row.host.username)@\(row.host.hostname):\(row.host.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.alreadyImported {
                            Text("已在主机簿")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(row.alreadyImported)
            }
        }
        .navigationTitle("导入 SSH Config")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    model.importDraft = nil
                    dismiss()
                }
            }
            ToolbarItem(placement: .automatic) {
                Button("全选新机器") { model.setImportSelection(allNew: true) }
            }
            ToolbarItem(placement: .automatic) {
                Button("全不选") { model.setImportSelection(allNew: false) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("导入 \(draft.selectedNewCount) 台") {
                    model.confirmImportSSHConfig()
                    dismiss()
                }
                .disabled(draft.selectedNewCount == 0)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("只写入 Hostpane 主机簿，不会改 ~/.ssh/config。已存在的条目不能重复勾选。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
    }
}
