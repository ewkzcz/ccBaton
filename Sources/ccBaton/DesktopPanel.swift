/**
 * 桌面端页面：管理 Claude 桌面端的账号，切换时自动退出并重开桌面端。
 */
import AppKit
import SwiftUI

/** DesktopPanel：桌面端账号页 */
struct DesktopPanel: View {
    @EnvironmentObject var desktop: DesktopStore
    @EnvironmentObject var cli: AccountStore
    @EnvironmentObject var dialogs: Dialogs

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(icon: nil, title: "Claude 桌面端", subtitle: "账号") {
                if desktop.installed {
                    Badge(text: desktop.running ? "运行中" : "未运行", tone: desktop.running ? .success : .neutral)
                }
            } actions: {
                Button { confirmLogin() } label: {
                    HStack(spacing: 6) {
                        if desktop.busy {
                            ProgressView().controlSize(.mini).tint(.white).frame(width: 14, height: 14)
                        } else {
                            Icon.plus.image(14)
                        }
                        Text("添加账号")
                    }
                }
                .buttonStyle(SolidButton())
                .disabled(desktop.busy || !desktop.installed)
            }

            ScrollView {
                VStack(spacing: 8) {
                    if !desktop.installed {
                        Notice(tone: .warning, title: "没有找到 Claude 桌面端的数据",
                               detail: "请先安装 Claude 桌面端并打开一次")
                            .padding(.bottom, 4)
                    }
                    if !desktop.currentSaved, let uuid = desktop.currentUuid {
                        Notice(tone: .warning, title: "桌面端当前登录的账号还没保存",
                               detail: desktop.cliEmail(uuid, cli: cli) ?? "账号 \(uuid.prefix(8))") {
                            Button("保存") { ask(nil) }
                                .buttonStyle(NeutralButton(compact: true))
                                .disabled(desktop.busy)
                        }
                        .padding(.bottom, 4)
                    }
                    if desktop.profiles.isEmpty && desktop.currentSaved && desktop.installed {
                        EmptyState(icon: .monitor, title: "还没有保存的桌面端账号",
                                   detail: "先在桌面端登录，回到这里保存；或点右上角“添加账号”")
                    }
                    ForEach(desktop.profiles) { p in
                        AccountCard(title: desktop.displayName(p, cli: cli),
                                    subtitle: "添加于 " + p.addedAt.formatted(date: .abbreviated, time: .omitted),
                                    isCurrent: p.accountUuid == desktop.currentUuid,
                                    disabled: desktop.busy,
                                    onSwitch: { Task { await desktop.switchTo(p) } },
                                    onRename: { ask(p) },
                                    onDelete: { confirmDelete(p) })
                        .contextMenu {
                            Button("改名") { ask(p) }
                        }
                    }
                    if !desktop.profiles.isEmpty {
                        Text("切换时会自动退出并重新打开 Claude 桌面端")
                            .font(.captionText)
                            .foregroundStyle(Theme.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 72)
            }
        }
        .onAppear { desktop.refresh() }
    }

    private func confirmLogin() {
        dialogs.present(DialogSpec(
            title: "登录新的桌面端账号？",
            message: desktop.currentSaved
                ? "会退出 Claude 桌面端并清空登录状态，然后重新打开让你登录。当前账号已保存，随时可以切回来。"
                : "当前账号还没保存，会先备份一份，但建议先点“保存”。之后退出桌面端并清空登录状态，重新打开让你登录。",
            confirm: "退出并登录") { _ in
                Task { await desktop.startNewLogin() }
            })
    }

    /** 保存当前账号（p 为空）或给已保存的账号改名 */
    private func ask(_ p: DesktopProfile?) {
        let initial = p.map { desktop.displayName($0, cli: cli) }
            ?? desktop.currentUuid.flatMap { desktop.cliEmail($0, cli: cli) } ?? ""
        dialogs.present(DialogSpec(
            title: p == nil ? "保存当前桌面端账号" : "改名",
            message: p == nil ? "保存时会短暂退出 Claude 桌面端，完成后自动重开。" : "",
            confirm: p == nil ? "保存" : "改名",
            input: initial,
            placeholder: "名字，比如邮箱") { name in
                if let p {
                    desktop.rename(p, to: name)
                } else {
                    Task { await desktop.importCurrent(name: name) }
                }
            })
    }

    private func confirmDelete(_ p: DesktopProfile) {
        let name = desktop.displayName(p, cli: cli)
        dialogs.present(DialogSpec(
            title: "删除「\(name)」？",
            message: p.accountUuid == desktop.currentUuid
                ? "这个账号正在使用，删除后桌面端仍保持登录，只删除本应用保存的登录信息。"
                : "删除本应用保存的登录信息，之后要用这个账号需要重新添加。",
            confirm: "删除", destructive: true) { _ in
                withAnimation(.snappy) { desktop.remove(p) }
            })
    }
}

/** 账号显示名：桌面端页和会话同步页共用 */
extension DesktopStore {
    /** 显示名：自己起的名字，其次是命令行里同一账号的邮箱，最后用账号 ID 前缀 */
    func displayName(_ p: DesktopProfile, cli: AccountStore) -> String {
        if !p.name.isEmpty { return p.name }
        return cliEmail(p.accountUuid, cli: cli) ?? "桌面账号 \(p.accountUuid.prefix(8))"
    }

    /** 按账号 ID 取显示名：保存过的用它的名字，否则用命令行里的邮箱或账号 ID 前缀 */
    func accountName(_ uuid: String, cli: AccountStore) -> String {
        if uuid == thirdPartyUuid { return "第三方会话" }
        if let p = profiles.first(where: { $0.accountUuid == uuid }) { return displayName(p, cli: cli) }
        return cliEmail(uuid, cli: cli) ?? "账号 \(uuid.prefix(8))"
    }

    func cliEmail(_ uuid: String, cli: AccountStore) -> String? {
        cli.profiles.first { $0.accountUuid == uuid && !$0.email.isEmpty }?.email
            ?? (cli.currentUuid == uuid ? cli.currentEmail : nil)
    }
}
