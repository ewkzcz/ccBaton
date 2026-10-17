/**
 * 会话同步页：开关自动同步、把命令行会话导入桌面端，以及选一个来源账号和若干目标账号手动同步桌面端会话。
 */
import SwiftUI

/** SessionsPanel：会话同步页 */
struct SessionsPanel: View {
    @EnvironmentObject var desktop: DesktopStore
    @EnvironmentObject var cli: AccountStore
    @EnvironmentObject var dialogs: Dialogs
    @State private var accounts: [SessionSync.SessionAccount] = []
    @State private var source: String?
    @State private var targets: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(icon: .history, title: "会话同步") {
                EmptyView()
            } actions: {
                EmptyView()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !desktop.installed {
                        Notice(tone: .warning, title: "没有找到 Claude 桌面端的数据",
                               detail: "会话同步只对 Claude 桌面端生效，请先安装并打开一次")
                            .padding(.bottom, 8)
                    }

                    Toggle(isOn: $desktop.autoSync) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("所有账号自动同步").font(.strong).foregroundStyle(Theme.text1)
                            Text("每次切换、保存、添加账号时，所有账号的会话互相同步，非 Pro 账号也包括在内；顺带导入命令行新建的会话")
                                .font(.captionText).foregroundStyle(Theme.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(SwitchStyle())
                    .modifier(PanelCard())

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("命令行会话").font(.strong).foregroundStyle(Theme.text1)
                            Text("命令行新建的会话没有桌面端索引，导入后会出现在所有桌面端账号的会话列表里")
                                .font(.captionText).foregroundStyle(Theme.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button("同步到桌面端") { confirmImport() }
                            .buttonStyle(NeutralButton(compact: true))
                            .disabled(desktop.busy || !desktop.installed)
                    }
                    .modifier(PanelCard())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("手动同步").font(.section).foregroundStyle(Theme.text1)
                        Text("把一个账号的会话复制给其他账号，同一个会话保留较新的一份；非 Pro 账号显示为“第三方会话”，也能同步和迁移")
                            .font(.captionText).foregroundStyle(Theme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 4)

                    if accounts.count < 2 {
                        Notice(title: "至少要有两个账号在桌面端用过，才能互相同步",
                               detail: "Pro 账号或非 Pro 账号都算")
                    } else {
                        label("从这个账号")
                        ForEach(accounts) { a in
                            row(a, selected: source == a.uuid, radio: true) {
                                source = a.uuid
                                targets = Set(accounts.map(\.uuid)).subtracting([a.uuid])
                            }
                        }
                        label("同步到").padding(.top, 10)
                        ForEach(accounts.filter { $0.uuid != source }) { a in
                            row(a, selected: targets.contains(a.uuid), radio: false) {
                                if targets.contains(a.uuid) { targets.remove(a.uuid) } else { targets.insert(a.uuid) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 72)
            }

            footer
        }
        .onAppear(perform: reload)
        .onChange(of: desktop.busy) { _, busy in if !busy { reload() } }
    }

    /** 底栏：说明 + 唯一的实心按钮 */
    private var footer: some View {
        HStack(spacing: 12) {
            Text("同步时会短暂退出 Claude 桌面端，完成后自动重开")
                .font(.captionText)
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                guard let source else { return }
                let to = Array(targets)
                Task { await desktop.syncSessions(from: source, to: to) }
            } label: {
                HStack(spacing: 6) {
                    if desktop.busy {
                        ProgressView().controlSize(.mini).tint(.white).frame(width: 14, height: 14)
                    } else {
                        Icon.swap.image(14)
                    }
                    Text(targets.isEmpty ? "同步" : "同步到 \(targets.count) 个账号")
                }
            }
            .buttonStyle(SolidButton())
            .disabled(source == nil || targets.isEmpty || desktop.busy || accounts.count < 2)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    /**
     * 重新读取有会话的账号
     *
     * 处理流程：
     * 1、只列出有会话目录的账号
     * 2、来源默认选当前账号，目标默认选其余全部；保留还有效的选择
     */
    private func reload() {
        // 1、只列出有会话目录的账号
        accounts = desktop.sessionAccounts().filter { !$0.slots.isEmpty }

        // 2、来源默认选当前账号，目标默认选其余全部；保留还有效的选择
        let ids = Set(accounts.map(\.uuid))
        if source == nil || !ids.contains(source!) {
            source = desktop.currentUuid.flatMap { ids.contains($0) ? $0 : nil } ?? accounts.first?.uuid
            targets = ids.subtracting([source].compactMap { $0 })
        } else {
            targets = targets.intersection(ids)
        }
    }

    private func confirmImport() {
        dialogs.present(DialogSpec(
            title: "把命令行会话同步到桌面端？",
            message: "命令行新建的会话会出现在所有桌面端账号的会话列表里，可以直接继续。桌面端的会话本来就能用 claude --resume 打开。同步时会短暂退出 Claude 桌面端，完成后自动重开。",
            confirm: "同步") { _ in
                Task { _ = await desktop.importCLISessions() }
            })
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text3)
    }

    private func row(_ a: SessionSync.SessionAccount, selected: Bool, radio: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CheckMark(on: selected, radio: radio)
                Text(desktop.accountName(a.uuid, cli: cli))
                    .font(.bodyText)
                    .foregroundStyle(Theme.text1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if a.uuid == desktop.currentUuid { Badge(text: "使用中", tone: .direct) }
                Spacer()
                Text("\(a.count) 个会话").font(.captionText).monospacedDigit().foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: Theme.rPanel, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.rPanel, style: .continuous)
                .strokeBorder(selected ? Theme.borderStrong : Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/** PanelCard：白底细描边的卡片容器 */
private struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.rPanel, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.rPanel, style: .continuous).strokeBorder(Theme.border))
    }
}
