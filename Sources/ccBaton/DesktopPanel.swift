/**
 * 桌面端页面：管理 Claude 桌面端的账号，切换时自动退出并重开桌面端。
 */
import AppKit
import SwiftUI

/** DesktopPanel：桌面端账号页 */
struct DesktopPanel: View {
    @EnvironmentObject var desktop: DesktopStore
    @EnvironmentObject var cli: AccountStore
    @State private var confirmLogin = false
    @State private var naming: NameRequest?
    @State private var nameInput = ""
    @State private var pendingDelete: DesktopProfile?

    /** NameRequest：保存或改名时要填的名字 */
    private struct NameRequest: Identifiable {
        let id = UUID()
        let profile: DesktopProfile?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 10) {
                    if !desktop.installed {
                        hint("没有找到 Claude 桌面端的数据，请先安装并打开一次")
                    }
                    if !desktop.currentSaved, let uuid = desktop.currentUuid {
                        unsavedBanner(uuid)
                    }
                    if desktop.profiles.isEmpty && desktop.currentSaved {
                        emptyState
                    }
                    ForEach(desktop.profiles) { p in
                        ProfileRow(title: displayName(p),
                                   subtitle: "添加于 " + p.addedAt.formatted(date: .abbreviated, time: .omitted),
                                   isCurrent: p.accountUuid == desktop.currentUuid,
                                   disabled: desktop.busy,
                                   onSwitch: { Task { await desktop.switchTo(p) } },
                                   onDelete: { pendingDelete = p })
                        .contextMenu {
                            Button("改名") { ask(p) }
                        }
                    }
                    if !desktop.profiles.isEmpty {
                        hint("切换时会自动退出并重新打开 Claude 桌面端；右键账号可以改名")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            NoticeBar(text: desktop.notice)
        }
        .alert("登录新的桌面端账号？", isPresented: $confirmLogin) {
            Button("继续") { Task { await desktop.startNewLogin() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(desktop.currentSaved
                 ? "会退出 Claude 桌面端并清空登录状态，然后重新打开让你登录。当前账号已保存，随时可以切回来。"
                 : "当前账号还没保存，会先备份一份，但建议先点“保存”。之后退出桌面端并清空登录状态，重新打开让你登录。")
        }
        .alert(naming?.profile == nil ? "保存当前桌面端账号" : "改名",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } }),
               presenting: naming) { req in
            TextField("名字，比如邮箱", text: $nameInput)
            Button("确定") {
                if let p = req.profile {
                    desktop.rename(p, to: nameInput)
                } else {
                    let name = nameInput
                    Task { await desktop.importCurrent(name: name) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: { req in
            Text(req.profile == nil ? "保存时会短暂退出 Claude 桌面端，完成后自动重开。" : "")
        }
        .alert("删除这个账号？", isPresented: Binding(get: { pendingDelete != nil },
                                                    set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { p in
            Button("删除", role: .destructive) { withAnimation(.snappy) { desktop.remove(p) } }
            Button("取消", role: .cancel) {}
        } message: { p in
            Text(p.accountUuid == desktop.currentUuid
                 ? "\(displayName(p)) 正在使用，删除后桌面端仍保持登录。"
                 : "删除 \(displayName(p)) 保存的登录信息。")
        }
        .onAppear { desktop.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            desktop.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude 桌面端账号")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { confirmLogin = true } label: {
                HStack(spacing: 6) {
                    if desktop.busy { ProgressView().controlSize(.small).tint(.white) } else { Icon.plus.image(14) }
                    Text("添加账号").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(desktop.busy || !desktop.installed)
        }
    }

    private var status: String {
        let count = desktop.profiles.isEmpty ? "还没有保存的账号" : "已保存 \(desktop.profiles.count) 个"
        return count + (desktop.running ? " · 桌面端运行中" : " · 桌面端未运行")
    }

    /** 显示名：自己起的名字，其次是命令行里同一账号的邮箱，最后用账号 ID 前缀 */
    private func displayName(_ p: DesktopProfile) -> String {
        if !p.name.isEmpty { return p.name }
        return cliEmail(p.accountUuid) ?? "桌面账号 \(p.accountUuid.prefix(8))"
    }

    private func cliEmail(_ uuid: String) -> String? {
        cli.profiles.first { $0.accountUuid == uuid && !$0.email.isEmpty }?.email
            ?? (cli.currentUuid == uuid ? cli.currentEmail : nil)
    }

    private func ask(_ p: DesktopProfile?) {
        nameInput = p.map(displayName) ?? desktop.currentUuid.flatMap(cliEmail) ?? ""
        naming = NameRequest(profile: p)
    }

    private func unsavedBanner(_ uuid: String) -> some View {
        HStack(spacing: 12) {
            Icon.download.image(16).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("桌面端当前登录的账号还没保存").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(cliEmail(uuid) ?? "账号 \(uuid.prefix(8))").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("保存") { ask(nil) }
                .buttonStyle(PillButton(filled: true))
                .disabled(desktop.busy)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.accentSoft))
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Icon.user.image(28).foregroundStyle(Theme.muted)
            Text("先在桌面端登录，回到这里保存；或点右上角添加账号").font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
