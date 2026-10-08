/**
 * 桌面端会话同步：在各账号的会话目录之间复制会话索引，让切换账号后还能看到其他账号的会话。
 *
 * 桌面端把 Code 会话的索引存在 claude-code-sessions/<账号ID>/<组织ID>/ 下，对话记录本身在 ~/.claude/projects，本来就是共用的。
 * 桌面端写索引时不接受软链接目录（报 ENOTDIR），所以每个账号保留自己的真实目录，靠复制文件同步。
 * 索引文件是 local_<ID>.json，删除会话后留下 deleted_<ID> 标记；同步时删除标记优先，同名索引保留较新的一份。
 * 所有操作都要在桌面端没运行时进行，避免它写到一半的文件被覆盖。
 */
import Foundation

/** SessionSync：会话目录的同步、旧版软链接的修复和丢失会话的恢复 */
struct SessionSync {
    /** SessionAccount：一个账号下的所有会话目录 */
    struct SessionAccount: Identifiable {
        let uuid: String
        let slots: [URL]
        let count: Int

        var id: String { uuid }
    }

    /** claude-code-sessions 目录 */
    let root: URL
    /** 旧版共享目录，修复后移走 */
    let legacy: URL
    /** 旧版共享目录移到这里备份 */
    let backupDir: URL
    /** 命令行的对话记录目录，用来恢复丢失的会话和导入命令行会话 */
    let projectsDir: URL
    /** 已导入过的命令行会话 ID 列表 */
    let imported: URL
    /** 只处理这些账号；目录里还留着已经不用的旧账号，不能把它们当成账号同步 */
    var only: Set<String>? = nil

    private static let indexPrefix = "local_"
    private static let tombPrefix = "deleted_"

    // MARK: - 查询

    /** 返回只处理指定账号的副本 */
    func limited(to ids: Set<String>) -> SessionSync {
        var copy = self
        copy.only = ids
        return copy
    }

    /** 列出所有账号及其会话目录，按会话数从多到少排 */
    func accounts() -> [SessionAccount] {
        Self.children(root)
            .filter { !$0.lastPathComponent.hasPrefix(".") && Self.isDirectory($0) && !Self.isSymlink($0) }
            .filter { only?.contains($0.lastPathComponent) ?? true }
            .map { account in
                let slots = Self.children(account).filter { Self.isDirectory($0) }
                let ids = Set(slots.flatMap { Self.children($0).compactMap { Self.indexID($0.lastPathComponent) } })
                return SessionAccount(uuid: account.lastPathComponent, slots: slots, count: ids.count)
            }
            .sorted { $0.count > $1.count }
    }

    // MARK: - 同步

    /** 所有账号互相同步，返回改动的文件数 */
    @discardableResult
    func syncAll() -> Int {
        let slots = accounts().flatMap(\.slots)
        return merge(from: slots, to: slots)
    }

    /** 把一个账号的会话同步给指定的其他账号，返回改动的文件数 */
    @discardableResult
    func sync(from source: String, to targets: [String]) -> Int {
        let all = accounts()
        let src = all.filter { $0.uuid == source }.flatMap(\.slots)
        let dst = all.filter { targets.contains($0.uuid) && $0.uuid != source }.flatMap(\.slots)
        return merge(from: src, to: dst)
    }

    /**
     * 把 sources 里的会话索引合并进 targets
     *
     * 处理流程：
     * 1、收集来源里的删除标记，以及每个索引文件最新的一份
     * 2、删除标记复制到目标，并删掉目标里对应的索引
     * 3、目标没删过的会话，缺的补上，旧的换成新的
     */
    private func merge(from sources: [URL], to targets: [URL]) -> Int {
        // 1、收集来源里的删除标记，以及每个索引文件最新的一份
        var tombs: [String: URL] = [:]
        var latest: [String: URL] = [:]
        for file in sources.flatMap(Self.children) {
            let name = file.lastPathComponent
            if let id = Self.tombID(name) {
                tombs[id] = file
            } else if Self.indexID(name) != nil, latest[name].map({ Self.mtime(file) > Self.mtime($0) }) ?? true {
                latest[name] = file
            }
        }

        var changed = 0
        for target in targets {
            // 2、删除标记复制到目标，并删掉目标里对应的索引
            for (id, tomb) in tombs {
                let dest = target.appendingPathComponent(tomb.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path), Self.copy(tomb, to: dest) { changed += 1 }
                let index = target.appendingPathComponent("\(Self.indexPrefix)\(id).json")
                if (try? FileManager.default.removeItem(at: index)) != nil { changed += 1 }
            }

            // 3、目标没删过的会话，缺的补上，旧的换成新的
            let deleted = Set(Self.children(target).compactMap { Self.tombID($0.lastPathComponent) })
            for (name, file) in latest {
                guard let id = Self.indexID(name), !deleted.contains(id) else { continue }
                let dest = target.appendingPathComponent(name)
                guard dest.standardizedFileURL != file.standardizedFileURL else { continue }
                if !FileManager.default.fileExists(atPath: dest.path) || Self.mtime(file) > Self.mtime(dest) {
                    if Self.copy(file, to: dest) { changed += 1 }
                }
            }
        }
        return changed
    }

    // MARK: - 修复旧版软链接

    /**
     * 把旧版留下的软链接换回真实目录，并恢复软链接期间没存下来的会话
     *
     * 旧版把每个 <账号ID>/<组织ID> 换成了指向共享目录的软链接，桌面端读得到但写不进去，
     * 这段时间新建的会话只有对话记录，没有索引，桌面端重启后就看不到了。
     *
     * 处理流程：
     * 1、找出所有软链接，最早的创建时间就是会话开始丢失的时间
     * 2、每个软链接换成真实目录，内容从链接指向的目录复制
     * 3、全部换好后，把旧共享目录移到备份目录
     * 4、从对话记录里恢复丢失的会话
     *
     * 返回值：恢复的会话数；没有软链接时返回 nil
     */
    func repairLegacyLinks() -> Int? {
        // 1、找出所有软链接，最早的创建时间就是会话开始丢失的时间
        let fm = FileManager.default
        let links = Self.children(root)
            .filter { !$0.lastPathComponent.hasPrefix(".") && !Self.isSymlink($0) }
            .flatMap(Self.children)
            .filter(Self.isSymlink)
        guard !links.isEmpty else { return nil }
        let since = links.compactMap { (try? fm.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date }.min()
            ?? Date()

        // 2、每个软链接换成真实目录，内容从链接指向的目录复制
        var allFixed = true
        for link in links {
            let target = link.resolvingSymlinksInPath()
            let tmp = link.deletingLastPathComponent().appendingPathComponent(".ccbaton-tmp-\(UUID().uuidString)")
            do {
                try fm.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                for item in Self.children(target) {
                    try fm.copyItem(at: item, to: tmp.appendingPathComponent(item.lastPathComponent))
                }
                try fm.removeItem(at: link)
                try fm.moveItem(at: tmp, to: link)
            } catch {
                try? fm.removeItem(at: tmp)
                allFixed = false
            }
        }

        // 3、全部换好后，把旧共享目录移到备份目录
        if allFixed, fm.fileExists(atPath: legacy.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? fm.moveItem(at: legacy, to: backupDir.appendingPathComponent("shared-\(stamp)"))
        }

        // 4、从对话记录里恢复丢失的会话
        return recover(since: since)
    }

    // MARK: - 恢复丢失的会话

    /** 为 since 之后在桌面端新建、但没有索引的会话补写索引，返回恢复的会话数 */
    func recover(since: Date) -> Int {
        addIndexes(modifiedSince: since) { info in
            info.fromDesktop && (info.createdAt.map { $0 >= since } ?? false)
        }.count
    }

    // MARK: - 导入命令行会话

    /**
     * 把命令行新建的会话导入桌面端，所有账号都能在会话列表里看到并继续
     *
     * 导入过的会话记在 imported 文件里，之后在桌面端删掉也不会再被导回来。
     * SDK 和自动化脚本跑出来的会话不导入。
     *
     * 返回值：导入的会话数
     */
    @discardableResult
    func importCLI() -> Int {
        let handled = Set((try? Data(contentsOf: imported))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String] ?? [])
        let added = addIndexes(skipping: handled) { $0.entrypoint == "cli" }
        guard !added.isEmpty else { return 0 }
        if let data = try? JSONSerialization.data(withJSONObject: handled.union(added).sorted(),
                                                  options: [.prettyPrinted]) {
            try? data.write(to: imported, options: .atomic)
        }
        return added.count
    }

    // MARK: - 补写索引

    /**
     * 为没有索引的对话记录补写索引
     *
     * 处理流程：
     * 1、收集已有索引引用的对话记录，取最新的一份索引做模板
     * 2、遍历对话记录，跳过已有索引、已处理过、时间太早的
     * 3、先读开头判断来源（开头读不到来源就读全文），符合条件的再读全文取标题、目录、时间等信息
     * 4、生成索引写进每个会话目录
     *
     * 参数：modifiedSince 只看这之后改动过的对话记录；skipping 跳过的会话 ID；accept 决定要不要补写
     * 返回值：补写了索引的会话 ID
     */
    private func addIndexes(modifiedSince: Date = .distantPast, skipping: Set<String> = [],
                            accept: (Transcript) -> Bool) -> [String] {
        // 1、收集已有索引引用的对话记录，取最新的一份索引做模板
        let slots = accounts().flatMap(\.slots)
        guard !slots.isEmpty else { return [] }
        let indexes = slots.flatMap(Self.children).filter { Self.indexID($0.lastPathComponent) != nil }
        var known = skipping
        for file in indexes {
            guard let obj = Self.readJSON(file) else { continue }
            if let id = obj["cliSessionId"] as? String { known.insert(id) }
            known.formUnion(obj["priorCliSessionIds"] as? [String] ?? [])
        }
        let template = indexes.max { Self.mtime($0) < Self.mtime($1) }.flatMap(Self.readJSON) ?? [:]

        // 2、遍历对话记录，跳过已有索引、已处理过、时间太早的
        var added: [String] = []
        for project in Self.children(projectsDir) where Self.isDirectory(project) {
            for file in Self.children(project) where file.pathExtension == "jsonl" {
                let cliID = file.deletingPathExtension().lastPathComponent
                guard !known.contains(cliID), Self.mtime(file) >= modifiedSince else { continue }

                // 3、先读开头判断来源（开头读不到来源就读全文），符合条件的再读全文取标题、目录、时间等信息
                guard let head = Transcript(file, headOnly: true),
                      head.entrypoint == nil || accept(head),
                      let info = Transcript(file), info.hasPrompt, let cwd = info.cwd, accept(info) else { continue }

                // 4、生成索引写进每个会话目录
                let index = Self.makeIndex(cliID: cliID, cwd: cwd, info: info, template: template)
                guard let data = try? JSONSerialization.data(withJSONObject: index, options: [.withoutEscapingSlashes]),
                      let sessionID = index["sessionId"] as? String else { continue }
                let modified = info.lastActivityAt ?? info.createdAt ?? Date()
                for slot in slots {
                    let dest = slot.appendingPathComponent("\(sessionID).json")
                    guard (try? data.write(to: dest, options: .atomic)) != nil else { continue }
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600, .modificationDate: modified],
                                                           ofItemAtPath: dest.path)
                }
                known.insert(cliID)
                added.append(cliID)
            }
        }
        return added
    }

    /** 按桌面端的格式生成一份索引；提示词快照、MCP 配置这类环境字段沿用模板 */
    private static func makeIndex(cliID: String, cwd: String, info: Transcript,
                                  template: [String: Any]) -> [String: Any] {
        let ms = { (d: Date?) in Int64(((d ?? Date()).timeIntervalSince1970 * 1000).rounded()) }
        var index: [String: Any] = [
            "sessionId": "\(indexPrefix)\(UUID().uuidString.lowercased())",
            "cliSessionId": cliID,
            "cwd": cwd,
            "originCwd": cwd,
            "createdAt": ms(info.createdAt),
            "lastActivityAt": ms(info.lastActivityAt),
            "lastFocusedAt": ms(info.lastActivityAt),
            // 命令行可能接了第三方模型，桌面端不认识，只沿用 Claude 模型
            "model": info.model.flatMap { $0.hasPrefix("claude-") ? $0 : nil }
                ?? template["model"] as? String ?? "default",
            "effort": template["effort"] as? String ?? "medium",
            "isArchived": false,
            "title": info.title,
            "titleSource": "auto",
            "permissionMode": info.permissionMode ?? "default",
            "remoteMcpServersConfig": template["remoteMcpServersConfig"] ?? [],
            "lastSpawnRootDetected": false,
            "remoteControlAutoEligible": false,
            "alwaysAllowedReasons": [],
            "sessionPermissionUpdates": [],
            "classifierSummaryEnabled": true,
            "reportFindingsCard": true,
            "spawnSeed": [:],
        ]
        for key in ["promptAppendSnapshot", "chromePermissionMode"] { index[key] = template[key] }
        return index
    }

    // MARK: - 工具

    private static func indexID(_ name: String) -> String? {
        guard name.hasPrefix(indexPrefix), name.hasSuffix(".json") else { return nil }
        return String(name.dropFirst(indexPrefix.count).dropLast(5))
    }

    private static func tombID(_ name: String) -> String? {
        name.hasPrefix(tombPrefix) ? String(name.dropFirst(tombPrefix.count)) : nil
    }

    /** 先复制到临时文件再换上，保留原文件的修改时间 */
    private static func copy(_ src: URL, to dest: URL) -> Bool {
        let fm = FileManager.default
        let tmp = dest.deletingLastPathComponent().appendingPathComponent(".ccbaton-\(UUID().uuidString)")
        do {
            try fm.copyItem(at: src, to: tmp)
            try fm.setAttributes([.modificationDate: mtime(src)], ofItemAtPath: tmp.path)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: tmp, to: dest)
            return true
        } catch {
            try? fm.removeItem(at: tmp)
            return false
        }
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    }

    static func children(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
    }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    static func mtime(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}

/** Transcript：从一份对话记录里读出恢复索引需要的信息 */
private struct Transcript {
    /** 第一条记录的来源：cli、sdk-cli、claude-desktop */
    var entrypoint: String?
    var fromDesktop = false
    var hasPrompt = false
    var cwd: String?
    var createdAt: Date?
    var lastActivityAt: Date?
    var model: String?
    var permissionMode: String?
    var customTitle: String?
    var aiTitle: String?
    var firstPrompt: String?

    /** 标题：自己起的名字，其次是自动生成的标题，最后用第一句话 */
    var title: String {
        let raw = customTitle ?? aiTitle ?? firstPrompt ?? "恢复的会话"
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }

    /** 读对话记录；headOnly 只读开头 64KB，用来快速判断来源 */
    init?(_ url: URL, headOnly: Bool = false) {
        let handle = try? FileHandle(forReadingFrom: url)
        defer { try? handle?.close() }
        guard let data = headOnly ? try? handle?.read(upToCount: 65536) : try? handle?.readToEnd() else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
            if let ep = obj["entrypoint"] as? String {
                if entrypoint == nil { entrypoint = ep }
                if ep == "claude-desktop" { fromDesktop = true }
            }
            if cwd == nil { cwd = obj["cwd"] as? String }
            if let ts = (obj["timestamp"] as? String).flatMap(iso.date(from:)) {
                if createdAt == nil { createdAt = ts }
                lastActivityAt = ts
            }
            switch obj["type"] as? String {
            case "custom-title": customTitle = obj["customTitle"] as? String ?? customTitle
            case "ai-title": aiTitle = obj["aiTitle"] as? String ?? aiTitle
            case "permission-mode": permissionMode = obj["permissionMode"] as? String ?? permissionMode
            case "assistant":
                if let m = (obj["message"] as? [String: Any])?["model"] as? String, !m.hasPrefix("<") { model = m }
            case "user":
                guard obj["isSidechain"] as? Bool != true, obj["isMeta"] as? Bool != true else { break }
                if permissionMode == nil { permissionMode = obj["permissionMode"] as? String }
                if firstPrompt == nil, let text = Self.text((obj["message"] as? [String: Any])?["content"]) {
                    firstPrompt = text
                    hasPrompt = true
                }
            default: break
            }
        }
    }

    /** 取用户消息里的文字，工具结果之类的不算 */
    private static func text(_ content: Any?) -> String? {
        if let s = content as? String { return s.isEmpty || s.hasPrefix("<") ? nil : s }
        let parts = (content as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .filter { !$0.hasPrefix("<") }
        return parts.first
    }
}
