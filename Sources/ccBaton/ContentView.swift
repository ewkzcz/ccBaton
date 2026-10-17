/**
 * 主窗口：左侧导航栏切换命令行、桌面端和会话同步三个页面，右侧是当前页面；底部 Toast 报告操作结果。
 */
import AppKit
import SwiftUI

/** Panel：主窗口的页面 */
enum Panel: String, CaseIterable {
    case cli, desktop, sessions

    var title: String {
        switch self {
        case .cli: return "Claude Code"
        case .desktop: return "Claude 桌面端"
        case .sessions: return "会话同步"
        }
    }

    var icon: Icon {
        switch self {
        case .cli: return .terminal
        case .desktop: return .monitor
        case .sessions: return .history
        }
    }
}

/** ContentView：侧栏 + 内容区 */
struct ContentView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var desktop: DesktopStore
    @StateObject private var dialogs = Dialogs()
    @AppStorage("panel") private var panel: Panel = .cli
    @AppStorage("appearance") private var appearance: Appearance = .system
    @State private var toast: ToastItem?

    /** ToastItem：一条提示，id 用来区分内容相同的两次提示 */
    private struct ToastItem: Equatable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(panel: $panel)
                .zIndex(1)
            Group {
                switch panel {
                case .cli: CLIPanel()
                case .desktop: DesktopPanel()
                case .sessions: SessionsPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bgApp)
            .overlay(alignment: .bottom) { toastView }
        }
        .overlay { DialogHost() }
        .environmentObject(dialogs)
        .ignoresSafeArea()
        .frame(minWidth: 720, minHeight: 500)
        .background(Theme.bgApp)
        .onAppear { appearance.apply() }
        .onChange(of: appearance) { _, a in a.apply() }
        .onChange(of: store.notice) { _, text in show(text) { store.notice = nil } }
        .onChange(of: desktop.notice) { _, text in show(text) { desktop.notice = nil } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refresh()
            desktop.refresh()
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Toast(text: toast.text) { withAnimation(.easeOut(duration: 0.2)) { self.toast = nil } }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    // 进行中的提示等结果出来再换掉，其余按长短停留几秒
                    let seconds = toast.text.hasSuffix("…") ? 30 : (toast.text.count > 24 ? 4 : 2.5)
                    try? await Task.sleep(for: .seconds(seconds))
                    withAnimation(.easeOut(duration: 0.2)) { if self.toast?.id == toast.id { self.toast = nil } }
                }
        }
    }

    /** 把 Store 发来的提示换成 Toast，再清空原提示，下次同样的内容也能再弹 */
    private func show(_ text: String?, clear: @escaping () -> Void) {
        guard let text, !text.isEmpty else { return }
        withAnimation(.snappy(duration: 0.25)) { toast = ToastItem(text: text) }
        DispatchQueue.main.async(execute: clear)
    }
}

// MARK: - 侧栏

/** Sidebar：宽 200（收起 72），顶部品牌 → 账号页 → 分隔线 → 工具页 */
struct Sidebar: View {
    @Binding var panel: Panel
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var desktop: DesktopStore
    @AppStorage("sidebarCollapsed") private var collapsed = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            VStack(spacing: 2) {
                item(.cli, trailing: count(store.profiles.count), alert: store.currentEmail != nil && !store.currentSaved)
                item(.desktop, trailing: count(desktop.profiles.count), alert: desktop.currentUuid != nil && !desktop.currentSaved)
            }
            .padding(.top, 2)

            Rectangle().fill(Theme.border).frame(height: 1)
                .padding(.horizontal, collapsed ? 18 : 16)
                .padding(.vertical, 6)

            item(.sessions, trailing: desktop.autoSync ? "自动" : nil, alert: false)
            Spacer()
            AppearancePicker(collapsed: collapsed)
                .padding(.bottom, 12)
        }
        .frame(width: collapsed ? Theme.sidebarCollapsed : Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.bgSidebar)
        .background(WindowDragArea())
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    /** 顶部：展开时红绿灯下面一行放图标、名字和收起按钮；收起时只留按钮 */
    @ViewBuilder
    private var topBar: some View {
        let toggle = IconButton(icon: collapsed ? .chevronsRight : .chevronsLeft,
                                tip: collapsed ? "展开侧栏" : "收起侧栏",
                                tipSide: .trailing) {
            withAnimation(.snappy(duration: 0.2)) { collapsed.toggle() }
        }
        Color.clear.frame(height: collapsed ? 28 : 26)
        if collapsed {
            toggle.frame(height: 32).padding(.bottom, 8)
        } else {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                Text("ccBaton").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text1)
                Spacer(minLength: 4)
                toggle
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 36)
            .padding(.bottom, 8)
        }
    }

    private func count(_ n: Int) -> String? { n > 0 ? "\(n)" : nil }

    private func item(_ p: Panel, trailing: String?, alert: Bool) -> some View {
        SidebarItem(panel: p, selected: panel == p, collapsed: collapsed, trailing: trailing, alert: alert) {
            panel = p
        }
    }
}

/** AppearancePicker：侧栏底部的外观切换；展开时是三段的分段控件，收起时是一个轮换按钮 */
private struct AppearancePicker: View {
    let collapsed: Bool
    @AppStorage("appearance") private var appearance: Appearance = .system
    @Namespace private var indicator

    var body: some View {
        if collapsed {
            IconButton(icon: appearance.icon, tip: "外观：\(appearance.title)", tipSide: .trailing) {
                let all = Appearance.allCases
                appearance = all[(all.firstIndex(of: appearance)! + 1) % all.count]
            }
        } else {
            HStack(spacing: 0) {
                ForEach(Appearance.allCases, id: \.self) { a in
                    Button { withAnimation(.snappy(duration: 0.2)) { appearance = a } } label: {
                        a.icon.image(14)
                            .foregroundStyle(appearance == a ? Theme.text1 : Theme.text3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .background {
                                if appearance == a {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Theme.card)
                                        .shadow(color: Theme.shadowSm, radius: 1, y: 1)
                                        .matchedGeometryEffect(id: "selected", in: indicator)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverTip(a.title, side: .top)
                    .accessibilityLabel(a.title)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.bgSubtle))
            .padding(.horizontal, 16)
        }
    }
}

/** SidebarItem：侧栏一行，高 28、圆角 6，当前项 bg-selected；收起时只剩图标，名字由 HoverTip 报 */
private struct SidebarItem: View {
    let panel: Panel
    let selected: Bool
    let collapsed: Bool
    let trailing: String?
    let alert: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Group {
                if collapsed {
                    glyph(size: 20)
                        .overlay(alignment: .topTrailing) {
                            if alert {
                                Circle().fill(Theme.danger).frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(selected ? Theme.bgSelected : Theme.bgSidebar, lineWidth: 2))
                                    .offset(x: 4, y: -3)
                            }
                        }
                        .frame(width: 48, height: 32)
                } else {
                    HStack(spacing: 8) {
                        glyph(size: 16)
                        Text(panel.title)
                            .font(.system(size: 13, weight: selected ? .medium : .regular))
                            .foregroundStyle(Theme.text1)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if alert {
                            Circle().fill(Theme.danger).frame(width: 6, height: 6)
                        } else if let trailing {
                            Text(trailing).font(.captionText).monospacedDigit().foregroundStyle(Theme.text3)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)
                .fill(selected ? Theme.bgSelected : (hover ? Theme.bgSubtle : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, collapsed ? 12 : 8)
        .onHover { hover = $0 }
        .hoverTip(collapsed ? tip : "", side: .trailing)
        .accessibilityLabel(tip)
    }

    private var tip: String {
        alert ? "\(panel.title) · 当前账号还没保存" : panel.title
    }

    /** 应用页用彩色小方块，工具页用线条图标 */
    @ViewBuilder
    private func glyph(size: CGFloat) -> some View {
        switch panel {
        case .cli, .desktop:
            panel.icon.image(size * 0.62)
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(Color(nsColor: NSColor(hex: panel == .cli ? 0xD97757 : 0x3F3F46))))
        case .sessions:
            panel.icon.image(size).foregroundStyle(selected ? Theme.text1 : Theme.text2)
        }
    }
}

// MARK: - 命令行页

/** CLIPanel：命令行账号页 */
struct CLIPanel: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var dialogs: Dialogs
    @State private var adding = false

    var body: some View {
        if adding {
            LoginPage { adding = false }
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            PageHeader(icon: nil, title: "Claude Code", subtitle: "账号") {
                EmptyView()
            } actions: {
                Button { adding = true } label: {
                    HStack(spacing: 6) {
                        Icon.plus.image(14)
                        Text("添加账号")
                    }
                }
                .buttonStyle(SolidButton())
            }

            ScrollView {
                VStack(spacing: 8) {
                    if !store.currentSaved, let email = store.currentEmail {
                        Notice(tone: .warning, title: "当前登录的账号还没保存", detail: email) {
                            Button("保存") { withAnimation(.snappy) { store.importCurrent() } }
                                .buttonStyle(NeutralButton(compact: true))
                        }
                        .padding(.bottom, 4)
                    }
                    if store.profiles.isEmpty && store.currentSaved {
                        EmptyState(icon: .user, title: "还没有保存的账号",
                                   detail: "点右上角“添加账号”，在内嵌终端里登录")
                    }
                    ForEach(store.profiles) { p in
                        AccountCard(title: p.email.isEmpty ? "未知账号" : p.email,
                                    subtitle: p.orgName,
                                    badge: plan(p),
                                    isCurrent: p.accountUuid == store.currentUuid,
                                    onSwitch: { withAnimation(.snappy) { store.switchTo(p) } },
                                    onDelete: { confirmDelete(p) })
                    }
                    if !store.profiles.isEmpty {
                        Text("切换后，已经打开的 Claude Code 需要重开才会用新账号；用 claude --resume 可以接着之前的会话")
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
    }

    private func plan(_ p: Profile) -> String? {
        p.plan.isEmpty ? nil : p.plan.prefix(1).uppercased() + p.plan.dropFirst()
    }

    private func confirmDelete(_ p: Profile) {
        dialogs.present(DialogSpec(
            title: "删除「\(p.email)」？",
            message: p.accountUuid == store.currentUuid
                ? "这个账号正在使用，删除后命令行仍保持登录，只删除本应用保存的登录信息。"
                : "删除本应用保存的登录信息，之后要用这个账号需要重新添加。",
            confirm: "删除", destructive: true) { _ in
                withAnimation(.snappy) { store.remove(p) }
            })
    }
}

// MARK: - 账号卡片

/** AccountCard：一张账号卡片，最小高 58、圆角 10；右侧操作只在悬停时出现，当前账号用直连色 soft 底 + 描边 */
struct AccountCard: View {
    let title: String
    let subtitle: String
    var badge: String?
    let isCurrent: Bool
    var disabled = false
    let onSwitch: () -> Void
    var onRename: (() -> Void)?
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.strong)
                        .foregroundStyle(Theme.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let badge { Badge(text: badge) }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.captionText)
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)

            HStack(spacing: 2) {
                if !isCurrent {
                    IconButton(icon: .swap, tip: "切换到这个账号", action: onSwitch).disabled(disabled)
                }
                if let onRename {
                    IconButton(icon: .pencil, tip: "改名", action: onRename).disabled(disabled)
                }
                IconButton(icon: .trash, tip: "删除", danger: true, action: onDelete)
            }
            .opacity(hover ? 1 : 0)

            if isCurrent {
                HStack(spacing: 6) {
                    Circle().fill(Theme.directFill).frame(width: 6, height: 6)
                    Text("使用中").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.directText)
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .background(RoundedRectangle(cornerRadius: Theme.rPanel, style: .continuous)
            .fill(isCurrent ? Theme.directSoft : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.rPanel, style: .continuous)
            .strokeBorder(isCurrent ? Theme.directBorder : (hover ? Theme.borderStrong : Theme.border)))
        .shadow(color: hover && !isCurrent ? Theme.shadowSm : .clear, radius: 2, y: 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .zIndex(hover ? 1 : 0)
    }

    /** 图标框固定白底深色字，深色主题里也不反色 */
    private var avatar: some View {
        Text(title.first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(nsColor: NSColor(hex: 0x18181B)))
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
    }
}
