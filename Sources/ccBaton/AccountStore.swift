/**
 * 账号存储：保存多个账号的登录凭据，负责导入、切换、删除，以及登录用的独立配置目录。
 */
import CryptoKit
import Foundation

/** Profile：一个已保存的账号 */
struct Profile: Codable, Identifiable, Equatable {
    var id: String
    var email: String
    var orgName: String
    var plan: String
    var accountUuid: String
    var oauthAccount: String?
    var addedAt: Date

    /** 凭据在钥匙串里的服务名 */
    var service: String { "ccBaton-\(id)" }
}

/** AccountStore：账号列表与切换逻辑 */
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var currentUuid: String?
    @Published private(set) var currentEmail: String?
    @Published var notice: String?

    static let defaultService = "Claude Code-credentials"

    let supportDir: URL
    let loginDir: URL
    private let listURL: URL
    private let claudeJSON: URL

    /** 登录目录对应的钥匙串服务名：前缀加目录路径哈希的前 8 位 */
    var loginService: String {
        let path = loginDir.path.precomposedStringWithCanonicalMapping
        let hash = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(Self.defaultService)-\(hash.prefix(8))"
    }

    /** 当前登录的账号是否已保存 */
    var currentSaved: Bool {
        guard let currentUuid else { return true }
        return profiles.contains { $0.accountUuid == currentUuid }
    }

    init() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ccBaton", isDirectory: true)
        loginDir = supportDir.appendingPathComponent("login", isDirectory: true)
        listURL = supportDir.appendingPathComponent("profiles.json")
        claudeJSON = home.appendingPathComponent(".claude.json")
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        load()
        refresh()
    }

    // MARK: - 状态

    /**
     * 刷新当前账号
     *
     * 处理流程：
     * 1、读 ~/.claude.json 里的账号信息
     * 2、把当前账号的最新凭据回存，避免令牌刷新后存档过期
     */
    func refresh() {
        // 1、读 ~/.claude.json 里的账号信息
        let oauth = readClaudeJSON()?["oauthAccount"] as? [String: Any]
        currentUuid = oauth?["accountUuid"] as? String
        currentEmail = oauth?["emailAddress"] as? String

        // 2、把当前账号的最新凭据回存，避免令牌刷新后存档过期
        syncActive()
    }

    /**
     * 回存当前账号凭据
     *
     * 处理流程：
     * 1、找到与当前登录对应的已存账号
     * 2、凭据有变化时写回该账号的条目
     * 3、同步账号信息和套餐
     */
    private func syncActive() {
        // 1、找到与当前登录对应的已存账号
        guard let uuid = currentUuid,
              let idx = profiles.firstIndex(where: { $0.accountUuid == uuid }),
              let cred = Keychain.read(Self.defaultService),
              Self.parseCredential(cred) != nil else { return }

        // 2、凭据有变化时写回该账号的条目
        let p = profiles[idx]
        if Keychain.read(p.service) != cred { Keychain.write(p.service, cred) }

        // 3、同步账号信息和套餐
        if let oauth = readClaudeJSON()?["oauthAccount"] as? [String: Any] {
            profiles[idx] = Self.fill(p, credential: cred, oauth: oauth)
            save()
        }
    }

    // MARK: - 操作

    /** 保存当前登录的账号 */
    func importCurrent() {
        guard let cred = Keychain.read(Self.defaultService), Self.parseCredential(cred) != nil else {
            notice = "没有读到当前的登录信息"
            return
        }
        let oauth = readClaudeJSON()?["oauthAccount"] as? [String: Any]
        if let p = upsert(credential: cred, oauth: oauth) { notice = "已保存 \(p.email)" }
    }

    /**
     * 新增或更新账号
     *
     * 处理流程：
     * 1、按账号 ID 查找已有记录，没有就新建
     * 2、凭据写入钥匙串
     * 3、更新列表并落盘
     */
    @discardableResult
    func upsert(credential: String, oauth: [String: Any]?) -> Profile? {
        // 1、按账号 ID 查找已有记录，没有就新建
        let uuid = oauth?["accountUuid"] as? String ?? ""
        let existing = uuid.isEmpty ? nil : profiles.first { $0.accountUuid == uuid }
        var p = existing ?? Profile(id: UUID().uuidString.lowercased(), email: "", orgName: "", plan: "",
                                    accountUuid: uuid, oauthAccount: nil, addedAt: Date())
        p = Self.fill(p, credential: credential, oauth: oauth)

        // 2、凭据写入钥匙串
        guard Keychain.write(p.service, credential) else {
            notice = "保存登录信息失败"
            return nil
        }

        // 3、更新列表并落盘
        if let i = profiles.firstIndex(where: { $0.id == p.id }) { profiles[i] = p } else { profiles.append(p) }
        save()
        return p
    }

    /**
     * 切换到指定账号
     *
     * 处理流程：
     * 1、先回存当前账号的最新凭据
     * 2、取目标账号凭据，备份 ~/.claude.json
     * 3、写入 Claude Code 默认的凭据条目
     * 4、改写 ~/.claude.json 里的账号信息
     */
    func switchTo(_ p: Profile) {
        // 1、先回存当前账号的最新凭据
        refresh()

        // 2、取目标账号凭据，备份 ~/.claude.json
        guard let cred = Keychain.read(p.service) else {
            notice = "找不到这个账号的登录信息，请重新添加"
            return
        }
        guard var config = readClaudeJSON() ?? (FileManager.default.fileExists(atPath: claudeJSON.path) ? nil : [:]) else {
            notice = "~/.claude.json 读取失败，稍后再试"
            return
        }
        let backup = supportDir.appendingPathComponent("claude.json.bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: claudeJSON, to: backup)

        // 3、写入 Claude Code 默认的凭据条目
        guard Keychain.write(Self.defaultService, cred) else {
            notice = "写入登录信息失败"
            return
        }

        // 4、改写 ~/.claude.json 里的账号信息
        if let raw = p.oauthAccount, let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) {
            config["oauthAccount"] = obj
        } else {
            config.removeValue(forKey: "oauthAccount")
        }
        writeClaudeJSON(config)
        refresh()
        notice = "已切换到 \(p.email)，已打开的 Claude Code 需要重开"
    }

    /** 删除账号：只删本应用保存的凭据，不影响当前登录 */
    func remove(_ p: Profile) {
        Keychain.delete(p.service)
        profiles.removeAll { $0.id == p.id }
        save()
        notice = "已删除 \(p.email)"
    }

    // MARK: - 登录目录

    /** 清空登录目录和对应的钥匙串条目 */
    func resetLoginDir() {
        Keychain.delete(loginService)
        try? FileManager.default.removeItem(at: loginDir)
        try? FileManager.default.createDirectory(at: loginDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    /** 读登录目录里新登录的凭据和账号信息 */
    func readLogin() -> (credential: String, oauth: [String: Any]?)? {
        guard let cred = Keychain.read(loginService), Self.parseCredential(cred) != nil else { return nil }
        let url = loginDir.appendingPathComponent(".claude.json")
        let obj = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        return (cred, obj?["oauthAccount"] as? [String: Any])
    }

    // MARK: - 文件

    private func load() {
        guard let data = try? Data(contentsOf: listURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        profiles = (try? dec.decode([Profile].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(profiles) else { return }
        try? data.write(to: listURL, options: .atomic)
    }

    /** 读 ~/.claude.json，文件不存在或解析失败返回 nil */
    private func readClaudeJSON() -> [String: Any]? {
        guard let data = try? Data(contentsOf: claudeJSON) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /** 写 ~/.claude.json，保持仅本人可读写 */
    private func writeClaudeJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj,
                                                     options: [.prettyPrinted, .withoutEscapingSlashes]) else { return }
        try? data.write(to: claudeJSON, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claudeJSON.path)
    }

    // MARK: - 解析

    /** 取凭据里的 claudeAiOauth 段，格式不对返回 nil */
    static func parseCredential(_ s: String) -> [String: Any]? {
        let obj = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
        return obj?["claudeAiOauth"] as? [String: Any]
    }

    /** 用凭据和账号信息填充记录 */
    private static func fill(_ p: Profile, credential: String, oauth: [String: Any]?) -> Profile {
        var p = p
        if let plan = parseCredential(credential)?["subscriptionType"] as? String { p.plan = plan }
        guard let oauth else { return p }
        p.email = oauth["emailAddress"] as? String ?? p.email
        p.orgName = oauth["organizationName"] as? String ?? p.orgName
        p.accountUuid = oauth["accountUuid"] as? String ?? p.accountUuid
        if let data = try? JSONSerialization.data(withJSONObject: oauth) {
            p.oauthAccount = String(decoding: data, as: UTF8.self)
        }
        return p
    }
}
