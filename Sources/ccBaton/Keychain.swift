/**
 * 钥匙串读写：通过系统 security 命令存取登录凭据，与 Claude Code 自身的写法一致，读写时不弹授权框。
 */
import Foundation

/** Shell：同步执行一个命令并取回标准输出 */
enum Shell {
    /**
     * 执行命令
     *
     * 处理流程：
     * 1、配置可执行文件、参数和管道
     * 2、启动后按需写入标准输入
     * 3、读完输出并等待退出
     */
    @discardableResult
    static func run(_ path: String, _ args: [String], input: String? = nil) -> (status: Int32, out: String) {
        // 1、配置可执行文件、参数和管道
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        let inPipe = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        if input != nil { p.standardInput = inPipe }

        // 2、启动后按需写入标准输入
        do { try p.run() } catch { return (-1, "") }
        if let input {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inPipe.fileHandleForWriting.close()
        }

        // 3、读完输出并等待退出
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/** Keychain：按服务名存取通用密码条目 */
enum Keychain {
    private static let tool = "/usr/bin/security"
    private static let stdinLimit = 4000

    /** 条目的账户名：与 Claude Code 取值规则相同 */
    static let account: String = {
        let name = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        return name.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) != nil ? name : "claude-code-user"
    }()

    /** 读取条目内容，不存在时返回 nil */
    static func read(_ service: String) -> String? {
        let r = Shell.run(tool, ["find-generic-password", "-a", account, "-s", service, "-w"])
        guard r.status == 0 else { return nil }
        let s = r.out.trimmingCharacters(in: .newlines)
        return s.isEmpty ? nil : s
    }

    /**
     * 写入或覆盖条目
     *
     * 处理流程：
     * 1、内容转十六进制，避免引号和换行问题
     * 2、短内容走标准输入，不在进程参数里暴露；过长时改走参数
     * 3、读回比对，确认写入成功
     */
    @discardableResult
    static func write(_ service: String, _ value: String) -> Bool {
        // 1、内容转十六进制，避免引号和换行问题
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()

        // 2、短内容走标准输入，不在进程参数里暴露；过长时改走参数
        let line = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \"\(hex)\"\n"
        if line.utf8.count <= stdinLimit {
            Shell.run(tool, ["-i"], input: line)
        } else {
            Shell.run(tool, ["add-generic-password", "-U", "-a", account, "-s", service, "-X", hex])
        }

        // 3、读回比对，确认写入成功
        return read(service) == value
    }

    /** 删除条目 */
    static func delete(_ service: String) {
        Shell.run(tool, ["delete-generic-password", "-a", account, "-s", service])
    }
}
