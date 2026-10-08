/**
 * 主窗口：顶部切换命令行和桌面端两个页面，各自管理账号的添加、切换、删除和保存。
 */
import AppKit
import SwiftUI

/** Panel：主窗口的页面 */
enum Panel: String, CaseIterable {
    case cli, desktop

    var title: String { self == .cli ? "命令行" : "桌面端" }
}

/** ContentView：主界面 */
struct ContentView: View {
    @AppStorage("panel") private var panel: Panel = .cli

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Panel.allCases, id: \.self) { p in
                    Button { withAnimation(.snappy) { panel = p } } label: {
                        Text(p.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(panel == p ? Theme.text : Theme.muted)
                            .padding(.horizontal, 16)
                            .frame(height: 26)
                            .background(Capsule().fill(panel == p ? Theme.card : Color.clear))
                            .overlay(Capsule().stroke(panel == p ? Theme.line : Color.clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Theme.line.opacity(0.5)))
            .padding(.top, 30)

            switch panel {
            case .cli: CLIPanel()
            case .desktop: DesktopPanel()
            }
        }
        .frame(minWidth: 580, minHeight: 540)
        .background(Theme.bg)
    }
}

/** NoticeBar：底部提示条 */
struct NoticeBar: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                .transition(.opacity)
        }
    }
}

/** CLIPanel：命令行账号页 */
struct CLIPanel: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var desktop: DesktopStore
    @State private var showLogin = false
    @State private var confirmImport = false
    @State private var pendingDelete: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 10) {
                    if !store.currentSaved, let email = store.currentEmail {
                        unsavedBanner(email)
                    }
                    if store.profiles.isEmpty && store.currentSaved {
                        emptyState
                    }
                    ForEach(store.profiles) { p in
                        ProfileRow(title: p.email.isEmpty ? "未知账号" : p.email,
                                   subtitle: subtitle(p),
                                   isCurrent: p.accountUuid == store.currentUuid,
                                   onSwitch: {
                                       withAnimation(.snappy) { store.switchTo(p) }
                                       desktop.refresh()
                                   },
                                   onDelete: { pendingDelete = p })
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            NoticeBar(text: store.notice)
        }
        .sheet(isPresented: $showLogin) { LoginSheet().environmentObject(store) }
        .alert("把命令行会话同步到桌面端？", isPresented: $confirmImport) {
            Button("同步") { Task { store.notice = await desktop.importCLISessions() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("命令行新建的会话会出现在所有桌面端账号的会话列表里，可以直接继续。桌面端的会话本来就能用 claude --resume 打开。同步时会短暂退出 Claude 桌面端，完成后自动重开。")
        }
        .alert("删除这个账号？", isPresented: Binding(get: { pendingDelete != nil },
                                                    set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { p in
            Button("删除", role: .destructive) { withAnimation(.snappy) { store.remove(p) } }
            Button("取消", role: .cancel) {}
        } message: { p in
            Text(p.accountUuid == store.currentUuid
                 ? "\(p.email) 正在使用，删除后命令行仍保持登录。"
                 : "删除 \(p.email) 保存的登录信息。")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Code 账号")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(store.profiles.isEmpty ? "还没有保存的账号" : "已保存 \(store.profiles.count) 个")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { confirmImport = true } label: {
                HStack(spacing: 5) {
                    Icon.swap.image(12)
                    Text("同步到桌面端")
                }
            }
            .buttonStyle(PillButton(filled: false))
            .disabled(desktop.busy || !desktop.installed)
            Button { showLogin = true } label: {
                HStack(spacing: 6) {
                    Icon.plus.image(14)
                    Text("添加账号").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
        }
    }

    private func subtitle(_ p: Profile) -> String {
        let plan = p.plan.isEmpty ? "" : p.plan.prefix(1).uppercased() + p.plan.dropFirst()
        return [p.orgName, plan].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func unsavedBanner(_ email: String) -> some View {
        HStack(spacing: 12) {
            Icon.download.image(16).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("当前登录的账号还没保存").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(email).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("保存") { withAnimation(.snappy) { store.importCurrent() } }
                .buttonStyle(PillButton(filled: true))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.accentSoft))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Icon.user.image(28).foregroundStyle(Theme.muted)
            Text("点右上角添加账号").font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

/** ProfileRow：一行账号卡片 */
struct ProfileRow: View {
    let title: String
    let subtitle: String
    let isCurrent: Bool
    var disabled = false
    let onSwitch: () -> Void
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            if isCurrent {
                HStack(spacing: 5) {
                    Icon.check.image(12)
                    Text("使用中").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Theme.accentSoft))
            } else {
                Button(action: onSwitch) {
                    HStack(spacing: 5) {
                        Icon.swap.image(12)
                        Text("切换")
                    }
                }
                .buttonStyle(PillButton(filled: false))
                .disabled(disabled)
            }

            Button(action: onDelete) {
                Icon.trash.image(14)
                    .foregroundStyle(hover ? Theme.danger : Theme.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .fill(hover ? Theme.cardHover : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .stroke(isCurrent ? Theme.accent.opacity(0.55) : Theme.line, lineWidth: 1))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }

    private var avatar: some View {
        let seed = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let color = Color(nsColor: NSColor(hex: Theme.avatarColors[abs(seed) % Theme.avatarColors.count]))
        return Text(title.first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(color))
    }
}

/** PillButton：胶囊按钮样式 */
struct PillButton: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(filled ? Color.white : Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(filled ? Theme.accent : Theme.bg))
            .overlay(Capsule().stroke(filled ? Color.clear : Theme.line))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
