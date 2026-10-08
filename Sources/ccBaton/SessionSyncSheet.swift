/**
 * 会话同步弹窗：选一个来源账号和若干目标账号，把来源账号的桌面端会话同步过去；也可以开关自动同步。
 */
import SwiftUI

/** SessionSyncSheet：手动同步会话的弹窗 */
struct SessionSyncSheet: View {
    @EnvironmentObject var desktop: DesktopStore
    @Environment(\.dismiss) private var dismiss
    /** 账号 ID 转成显示名 */
    let name: (String) -> String
    @State private var accounts: [SessionSync.SessionAccount] = []
    @State private var source: String?
    @State private var targets: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Icon.swap.image(18).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("同步会话").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("把一个账号的会话复制给其他账号，同一个会话保留较新的一份").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Icon.close.image(14)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.card))
                        .overlay(Circle().stroke(Theme.line))
                }
                .buttonStyle(.plain)
            }

            Toggle(isOn: $desktop.autoSync) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("所有账号自动同步").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Text("每次切换、保存、添加账号时，所有账号的会话互相同步").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.line))

            if accounts.count < 2 {
                Text("至少要有两个账号在桌面端登录过，才能互相同步")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        section("从这个账号")
                        ForEach(accounts) { a in
                            row(a, selected: source == a.uuid, radio: true) {
                                source = a.uuid
                                targets = Set(accounts.map(\.uuid)).subtracting([a.uuid])
                            }
                        }
                        section("同步到").padding(.top, 8)
                        ForEach(accounts.filter { $0.uuid != source }) { a in
                            row(a, selected: targets.contains(a.uuid), radio: false) {
                                if targets.contains(a.uuid) { targets.remove(a.uuid) } else { targets.insert(a.uuid) }
                            }
                        }
                    }
                }
            }

            HStack {
                Text("同步时会短暂退出 Claude 桌面端，完成后自动重开")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(PillButton(filled: false))
                Button("同步") {
                    guard let source else { return }
                    let to = Array(targets)
                    dismiss()
                    Task { await desktop.syncSessions(from: source, to: to) }
                }
                .buttonStyle(PillButton(filled: true))
                .disabled(source == nil || targets.isEmpty || desktop.busy)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .background(Theme.bg)
        .onAppear {
            accounts = desktop.sessionAccounts().filter { !$0.slots.isEmpty }
            source = desktop.currentUuid.flatMap { uuid in accounts.first { $0.uuid == uuid }?.uuid }
                ?? accounts.first?.uuid
            targets = Set(accounts.map(\.uuid)).subtracting([source].compactMap { $0 })
        }
    }

    private func section(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
    }

    private func row(_ a: SessionSync.SessionAccount, selected: Bool, radio: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: radio ? (selected ? "largecircle.fill.circle" : "circle")
                                        : (selected ? "checkmark.square.fill" : "square"))
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
                Text(name(a.uuid)).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(1)
                if a.uuid == desktop.currentUuid {
                    Text("使用中").font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
                Spacer()
                Text("\(a.count) 个会话").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? Theme.accent.opacity(0.55) : Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
