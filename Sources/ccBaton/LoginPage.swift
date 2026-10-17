/**
 * 添加账号页：内嵌终端，在独立配置目录里运行登录命令，登录成功后自动保存账号。
 */
import AppKit
import SwiftTerm
import SwiftUI

/** TerminalHost：把终端视图接入 SwiftUI */
struct TerminalHost: NSViewRepresentable {
    let environment: [String]

    func makeCoordinator() -> Coordinator { Coordinator() }

    /**
     * 创建终端
     *
     * 处理流程：
     * 1、设置字体和配色
     * 2、以登录 shell 启动，加载用户自己的环境
     * 3、让终端获得焦点
     */
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        // 1、设置字体和配色
        let v = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        v.processDelegate = context.coordinator
        v.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        v.nativeBackgroundColor = Theme.termBg
        v.nativeForegroundColor = Theme.termFg
        v.caretColor = NSColor(hex: 0xE08A68)

        // 2、以登录 shell 启动，加载用户自己的环境
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        v.startProcess(executable: shell, args: [], environment: environment,
                       execName: "-" + (shell as NSString).lastPathComponent,
                       currentDirectory: NSHomeDirectory())

        // 3、让终端获得焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            v.window?.makeFirstResponder(v)
        }
        context.coordinator.view = v
        return v
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.terminate()
    }

    /** Coordinator：接收终端进程事件 */
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        weak var view: LocalProcessTerminalView?
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}

/** LoginPage：添加账号的二级页，返回按钮 + 标题，下面是内嵌终端 */
struct LoginPage: View {
    @EnvironmentObject var store: AccountStore
    let onClose: () -> Void
    @State private var environment: [String]?
    @State private var waitingProfile = 0

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "添加 Claude Code 账号") {
                IconButton(icon: .arrowLeft, tip: "返回", size: 32, bordered: true) { close() }
            } extra: {
                EmptyView()
            } actions: {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("在下面的终端里登录，成功后会自动保存。终端用独立的配置目录，不影响当前登录。")
                    .font(.bodyText)
                    .foregroundStyle(Theme.text2)

                HStack(spacing: 8) {
                    Text("常用命令").font(.captionText).foregroundStyle(Theme.text3)
                    ForEach(["claude", "/login", "claude auth login"], id: \.self) { CopyChip(text: $0) }
                }

                Group {
                    if let environment {
                        TerminalHost(environment: environment)
                    } else {
                        Color(nsColor: Theme.termBg)
                    }
                }
                .padding(10)
                .background(Color(nsColor: Theme.termBg))
                .clipShape(RoundedRectangle(cornerRadius: Theme.rPanel, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("等待登录完成").font(.captionText).foregroundStyle(Theme.text3)
                Spacer()
                Button("取消") { close() }.buttonStyle(NeutralButton())
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
        .onAppear(perform: start)
        .onDisappear { store.resetLoginDir() }
        .onReceive(timer) { _ in poll() }
    }

    /**
     * 准备登录环境
     *
     * 处理流程：
     * 1、清空上次残留的登录目录
     * 2、让终端里的命令都使用这个独立目录，不影响当前登录
     */
    private func start() {
        // 1、清空上次残留的登录目录
        store.resetLoginDir()

        // 2、让终端里的命令都使用这个独立目录，不影响当前登录
        var env = ProcessInfo.processInfo.environment
        let dir = store.loginDir.path
        env["CLAUDE_CONFIG_DIR"] = dir
        env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = dir
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        environment = env.map { "\($0.key)=\($0.value)" }
    }

    /**
     * 检查是否登录成功
     *
     * 处理流程：
     * 1、读独立目录的凭据，没有就继续等
     * 2、账号信息稍晚写入，最多再等几轮
     * 3、保存账号并回到账号列表
     */
    private func poll() {
        // 1、读独立目录的凭据，没有就继续等
        guard environment != nil, let login = store.readLogin() else { return }

        // 2、账号信息稍晚写入，最多再等几轮
        if login.oauth == nil && waitingProfile < 4 {
            waitingProfile += 1
            return
        }

        // 3、保存账号并回到账号列表
        let known = store.profiles.map(\.accountUuid)
        if let p = store.upsert(credential: login.credential, oauth: login.oauth) {
            store.notice = known.contains(p.accountUuid) && !p.accountUuid.isEmpty
                ? "已更新 \(p.email)" : "已添加 \(p.email)"
        }
        close()
    }

    /** 回到账号列表并清理登录目录 */
    private func close() {
        environment = nil
        store.resetLoginDir()
        onClose()
    }
}

/** CopyChip：点一下复制命令 */
struct CopyChip: View {
    let text: String
    @State private var copied = false
    @State private var hover = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.15)) { copied = false }
            }
        } label: {
            HStack(spacing: 6) {
                Text(text).font(.mono)
                (copied ? Icon.check : Icon.copy).image(12)
                    .foregroundStyle(copied ? Theme.success : Theme.text3)
            }
            .foregroundStyle(Theme.text1)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)
                .fill(hover ? Theme.bgSubtle : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .onHover { hover = $0 }
        .hoverTip(copied ? "已复制" : "复制命令")
    }
}
