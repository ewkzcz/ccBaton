/**
 * 桌面端账号存储：给 Claude 桌面端的登录状态做快照，按账号保存、切换、删除。
 *
 * 桌面端的登录状态分散在 cookie、网页存储和 config.json 的 oauth 字段里，都用本机同一把密钥加密，
 * 所以整份复制即可切换，不需要解密。读写这些文件前必须先退出桌面端，否则它会把旧状态写回去。
 */
import AppKit
import Foundation

/** DesktopProfile：一个已保存的桌面端账号 */
struct DesktopProfile: Codable, Identifiable, Equatable {
    var id: String
    var accountUuid: String
    var name: String
    var addedAt: Date
}

/** DesktopStore：桌面端账号列表与切换逻辑 */
@MainActor
final class DesktopStore: ObservableObject {
    @Published private(set) var profiles: [DesktopProfile] = []
    @Published private(set) var currentUuid: String?
    @Published private(set) var running = false
    @Published private(set) var busy = false
    @Published var notice: String?
    /** 切换、保存、登录账号时，以及桌面端没运行时，导入命令行会话并让所有账号的会话互相同步 */
    @Published var autoSync: Bool {
        didSet { UserDefaults.standard.set(autoSync, forKey: Self.autoSyncKey) }
    }

    static let bundleID = "com.anthropic.claudefordesktop"

    /** 随账号走的文件和目录 */
    private static let items = ["Cookies", "Cookies-journal", "Local Storage", "Session Storage", "IndexedDB", "WebStorage"]
    /** config.json 里随账号走的字段：oauth: 开头的令牌缓存，加上最后登录的账号 */
    private static let accountKey = "lastKnownAccountUuid"
    private static func isAuthKey(_ k: String) -> Bool { k.hasPrefix("oauth:") || k == accountKey }
    private static let autoSyncKey = "desktop.autoSyncSessions"

    private let dataDir: URL
    private let configURL: URL
    private let rootDir: URL
    private let listURL: URL
    private let sessions: SessionSync

    /** 当前登录的账号是否已保存 */
    var currentSaved: Bool {
        guard let currentUuid else { return true }
        return profiles.contains { $0.accountUuid == currentUuid }
    }

    /** 桌面端是否安装过（数据目录存在） */
    var installed: Bool { FileManager.default.fileExists(atPath: dataDir.path) }

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dataDir = support.appendingPathComponent("Claude", isDirectory: true)
        configURL = dataDir.appendingPathComponent("config.json")
        rootDir = support.appendingPathComponent("ccBaton/desktop", isDirectory: true)
        listURL = rootDir.appendingPathComponent("profiles.json")
        let sessionsDir = dataDir.appendingPathComponent("claude-code-sessions", isDirectory: true)
        sessions = SessionSync(root: sessionsDir,
                               legacy: sessionsDir.appendingPathComponent(".ccbaton-shared", isDirectory: true),
                               backupDir: rootDir.appendingPathComponent("sessions-backup", isDirectory: true),
                               projectsDir: fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"),
                               imported: rootDir.appendingPathComponent("cli-imported.json"))
        autoSync = UserDefaults.standard.object(forKey: Self.autoSyncKey) as? Bool ?? true
        try? fm.createDirectory(at: rootDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        load()
        refresh()
    }

    // MARK: - 状态

    /** 刷新当前账号和运行状态：有令牌缓存才算已登录 */
    func refresh() {
        running = Self.runningApp() != nil
        if !running {
            let repaired = syncSessions()
            if !repaired.isEmpty { notice = String(repaired.dropFirst()) }
        }
        let config = readConfig()
        let loggedIn = config?.keys.contains { $0.hasPrefix("oauth:") } ?? false
        currentUuid = loggedIn ? config?[Self.accountKey] as? String : nil
    }

    // MARK: - 操作

    /**
     * 保存当前登录的账号
     *
     * 处理流程：
     * 1、退出桌面端，保证文件不再被写
     * 2、按账号 ID 查找已有记录，没有就新建
     * 3、同步会话，拍快照并落盘，再按原样重新打开桌面端
     */
    func importCurrent(name: String) async {
        guard let uuid = currentUuid else {
            notice = "桌面端当前没有登录"
            return
        }
        await perform {
            // 1、退出桌面端，保证文件不再被写
            guard let wasRunning = await quitClaude() else { return }

            // 2、按账号 ID 查找已有记录，没有就新建
            var p = profiles.first { $0.accountUuid == uuid }
                ?? DesktopProfile(id: UUID().uuidString.lowercased(), accountUuid: uuid, name: "", addedAt: Date())
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { p.name = trimmed }

            // 3、同步会话，拍快照并落盘，再按原样重新打开桌面端
            let repaired = syncSessions()
            if snapshot(to: dir(p)) {
                if let i = profiles.firstIndex(where: { $0.id == p.id }) { profiles[i] = p } else { profiles.append(p) }
                save()
                notice = "已保存 \(p.name)" + repaired
            } else {
                notice = "保存失败，桌面端的数据没有读全"
            }
            if wasRunning { launchClaude() }
        }
    }

    /**
     * 切换到指定账号
     *
     * 处理流程：
     * 1、退出桌面端
     * 2、回存当前账号；没保存过的账号也留一份备份，防止丢失
     * 3、同步各账号的会话，写入目标账号的快照，再打开桌面端
     */
    func switchTo(_ p: DesktopProfile) async {
        await perform {
            // 1、退出桌面端
            guard await quitClaude() != nil else { return }

            // 2、回存当前账号；没保存过的账号也留一份备份，防止丢失
            backupCurrent()

            // 3、同步各账号的会话，写入目标账号的快照，再打开桌面端
            let repaired = syncSessions()
            guard restore(from: dir(p)) else {
                notice = "找不到 \(p.name) 的登录信息，请重新添加"
                return
            }
            launchClaude()
            notice = "已切换到 \(p.name)" + repaired
        }
    }

    /**
     * 登录新账号：保存好当前账号后清空登录状态，打开桌面端让用户登录
     *
     * 处理流程：
     * 1、退出桌面端，回存当前账号，同步会话
     * 2、清掉登录相关的文件和字段
     * 3、打开桌面端，登录后回到本窗口保存
     */
    func startNewLogin() async {
        await perform {
            // 1、退出桌面端，回存当前账号，同步会话
            guard await quitClaude() != nil else { return }
            backupCurrent()
            let repaired = syncSessions()

            // 2、清掉登录相关的文件和字段
            clearAuth()

            // 3、打开桌面端，登录后回到本窗口保存
            launchClaude()
            notice = "请在桌面端登录新账号，完成后回到这里保存" + repaired
        }
    }

    /** 删除账号：只删本应用保存的快照，不影响桌面端当前登录 */
    func remove(_ p: DesktopProfile) {
        try? FileManager.default.removeItem(at: dir(p))
        profiles.removeAll { $0.id == p.id }
        save()
        notice = "已删除 \(p.name)"
    }

    /** 改名 */
    func rename(_ p: DesktopProfile, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let i = profiles.firstIndex(where: { $0.id == p.id }) else { return }
        profiles[i].name = trimmed
        save()
    }

    // MARK: - 流程

    /** 串行执行一项操作，期间标记忙碌 */
    private func perform(_ work: () async -> Void) async {
        guard !busy else { return }
        busy = true
        await work()
        busy = false
        refresh()
    }

    /** 回存当前账号到它的快照；当前账号没保存过时存到 last-backup */
    private func backupCurrent() {
        refresh()
        guard let uuid = currentUuid else { return }
        if let p = profiles.first(where: { $0.accountUuid == uuid }) {
            snapshot(to: dir(p))
        } else {
            snapshot(to: rootDir.appendingPathComponent("last-backup", isDirectory: true))
        }
    }

    // MARK: - 会话同步

    /** 列出有会话目录的账号，给手动同步选择 */
    func sessionAccounts() -> [SessionSync.SessionAccount] { sessions.accounts() }

    /**
     * 把指定账号的会话同步给其他指定账号
     *
     * 处理流程：
     * 1、退出桌面端，保证会话文件不再被写
     * 2、修复旧版软链接，再按选择同步
     * 3、按原样重新打开桌面端
     */
    func syncSessions(from source: String, to targets: [String]) async {
        await perform {
            // 1、退出桌面端，保证会话文件不再被写
            guard let wasRunning = await quitClaude() else { return }

            // 2、修复旧版软链接，再按选择同步
            let recovered = sessions.repairLegacyLinks()
            let changed = sessions.sync(from: source, to: targets)
            notice = "会话已同步到 \(targets.count) 个账号，更新了 \(changed) 个文件" + recoveredText(recovered)

            // 3、按原样重新打开桌面端
            if wasRunning { launchClaude() }
        }
    }

    /**
     * 把命令行新建的会话导入桌面端
     *
     * 处理流程：
     * 1、退出桌面端，保证会话文件不再被写
     * 2、修复旧版软链接，导入命令行会话；开着自动同步时再让所有账号互相同步
     * 3、按原样重新打开桌面端
     *
     * 返回值：给用户看的结果说明
     */
    func importCLISessions() async -> String {
        var result = ""
        await perform {
            // 1、退出桌面端，保证会话文件不再被写
            guard let wasRunning = await quitClaude() else {
                result = notice ?? ""
                return
            }

            // 2、修复旧版软链接，导入命令行会话；开着自动同步时再让所有账号互相同步
            let recovered = sessions.repairLegacyLinks()
            let count = sessions.importCLI()
            if autoSync { sessions.syncAll() }
            result = (count > 0 ? "已把 \(count) 个命令行会话导入桌面端" : "没有新的命令行会话需要导入")
                + recoveredText(recovered)
            notice = result

            // 3、按原样重新打开桌面端
            if wasRunning { launchClaude() }
        }
        return result
    }

    /**
     * 自动同步：修复旧版软链接，开着自动同步时导入命令行会话并让所有账号互相同步
     *
     * 只在桌面端没运行时调用，避免它写到一半的文件被覆盖。
     *
     * 返回值：修复了旧版软链接时返回给用户的说明，否则为空
     */
    @discardableResult
    private func syncSessions() -> String {
        let recovered = sessions.repairLegacyLinks()
        if autoSync {
            sessions.importCLI()
            sessions.syncAll()
        }
        return recovered == nil ? "" : "；已修复会话目录" + recoveredText(recovered)
    }

    private func recoveredText(_ recovered: Int?) -> String {
        guard let recovered, recovered > 0 else { return "" }
        return "，找回了 \(recovered) 个之前没保存下来的会话"
    }

    // MARK: - 桌面端进程

    private static func runningApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /**
     * 退出桌面端并等它完全退出
     *
     * 返回值：原本在运行返回 true，原本没运行返回 false，退出超时返回 nil
     */
    private func quitClaude() async -> Bool? {
        guard let app = Self.runningApp() else { return false }
        notice = "正在退出 Claude 桌面端…"
        app.terminate()
        for _ in 0..<100 {
            if app.isTerminated { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard app.isTerminated else {
            notice = "Claude 桌面端没有退出，请手动退出后再试"
            return nil
        }
        // 留一点时间让它把文件句柄释放干净
        try? await Task.sleep(nanoseconds: 500_000_000)
        return true
    }

    private func launchClaude() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - 快照

    private func dir(_ p: DesktopProfile) -> URL {
        rootDir.appendingPathComponent(p.id, isDirectory: true)
    }

    /**
     * 把当前登录状态复制到快照目录
     *
     * 处理流程：
     * 1、在临时目录里复制文件和目录
     * 2、取出 config.json 里的登录字段单独存放
     * 3、全部成功后替换旧快照
     */
    @discardableResult
    private func snapshot(to dest: URL) -> Bool {
        let fm = FileManager.default
        guard let config = readConfig() else { return false }

        // 1、在临时目录里复制文件和目录
        let tmp = rootDir.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        do {
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for name in Self.items {
                let src = dataDir.appendingPathComponent(name)
                if fm.fileExists(atPath: src.path) { try fm.copyItem(at: src, to: tmp.appendingPathComponent(name)) }
            }

            // 2、取出 config.json 里的登录字段单独存放
            let auth = config.filter { Self.isAuthKey($0.key) }
            let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted])
            try data.write(to: tmp.appendingPathComponent("auth.json"), options: .atomic)

            // 3、全部成功后替换旧快照
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: tmp, to: dest)
            return true
        } catch {
            return false
        }
    }

    /**
     * 用快照覆盖桌面端的登录状态
     *
     * 处理流程：
     * 1、检查快照完整
     * 2、清掉现有登录状态，复制快照里的文件和目录
     * 3、把登录字段写回 config.json
     */
    private func restore(from src: URL) -> Bool {
        // 1、检查快照完整
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: src.appendingPathComponent("auth.json")),
              let auth = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }

        // 2、清掉现有登录状态，复制快照里的文件和目录
        clearAuth()
        for name in Self.items {
            let from = src.appendingPathComponent(name)
            if fm.fileExists(atPath: from.path) { try? fm.copyItem(at: from, to: dataDir.appendingPathComponent(name)) }
        }

        // 3、把登录字段写回 config.json
        var config = readConfig() ?? [:]
        config.merge(auth) { _, new in new }
        writeConfig(config)
        return true
    }

    /** 清掉桌面端的登录文件和 config.json 里的登录字段 */
    private func clearAuth() {
        let fm = FileManager.default
        for name in Self.items { try? fm.removeItem(at: dataDir.appendingPathComponent(name)) }
        if var config = readConfig() {
            for k in config.keys where Self.isAuthKey(k) { config.removeValue(forKey: k) }
            writeConfig(config)
        }
    }

    // MARK: - 文件

    private func load() {
        guard let data = try? Data(contentsOf: listURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        profiles = (try? dec.decode([DesktopProfile].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(profiles) else { return }
        try? data.write(to: listURL, options: .atomic)
    }

    private func readConfig() -> [String: Any]? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func writeConfig(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj,
                                                     options: [.prettyPrinted, .withoutEscapingSlashes]) else { return }
        try? data.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }
}
