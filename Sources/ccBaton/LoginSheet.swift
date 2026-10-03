/**
 * 登录弹窗：内嵌终端，在独立配置目录里运行登录命令，登录成功后自动保存账号。
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

/** LoginSheet：添加账号的弹窗 */
struct LoginSheet: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var environment: [String]?
    @State private var waitingProfile = 0

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Icon.terminal.image(18).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("登录新账号").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("在下面完成登录，成功后会自动保存").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { close() } label: {
                    Icon.close.image(14)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.card))
                        .overlay(Circle().stroke(Theme.line))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
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
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("等待登录完成").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .padding(20)
        .frame(width: 580, height: 500)
        .background(Theme.bg)
        .onAppear(perform: start)
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
     * 3、保存账号并关闭弹窗
     */
    private func poll() {
        // 1、读独立目录的凭据，没有就继续等
        guard environment != nil, let login = store.readLogin() else { return }

        // 2、账号信息稍晚写入，最多再等几轮
        if login.oauth == nil && waitingProfile < 4 {
            waitingProfile += 1
            return
        }

        // 3、保存账号并关闭弹窗
        let known = store.profiles.map(\.accountUuid)
        if let p = store.upsert(credential: login.credential, oauth: login.oauth) {
            store.notice = known.contains(p.accountUuid) && !p.accountUuid.isEmpty
                ? "已更新 \(p.email)" : "已添加 \(p.email)"
        }
        close()
    }

    /** 关闭弹窗并清理登录目录 */
    private func close() {
        environment = nil
        store.resetLoginDir()
        dismiss()
    }
}

/** CopyChip：点一下复制命令 */
struct CopyChip: View {
    let text: String
    @State private var copied = false

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
                Text(text).font(.system(size: 12, design: .monospaced))
                (copied ? Icon.check : Icon.copy).image(12)
                    .foregroundStyle(copied ? Theme.accent : Theme.muted)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(copied ? Theme.accent.opacity(0.6) : Theme.line))
        }
        .buttonStyle(.plain)
        .help("复制")
    }
}
