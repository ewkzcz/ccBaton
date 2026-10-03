# ccBaton

由于目前版本的 cc-switch 无法实现多个 Claude 账户之间的切换，当前项目实现了一个极简的 Claude 账号管理器，实现在一台 Mac 上保存多个 Claude Code 账号，点一下就切换，不用反复退出再登录。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
  <img src="docs/screenshot-light.png" alt="ccBaton 主界面" width="580">
</picture>



## 一、工作原理

Claude Code 把登录凭据存在钥匙串的 `Claude Code-credentials` 条目里，账号信息存在 `~/.claude.json` 的 `oauthAccount` 字段里。ccBaton 为每个账号单独存一份凭据，切换时把目标账号的凭据和账号信息写回这两处。

- **添加账号**：弹窗里内嵌一个终端，用独立的配置目录运行登录命令，不影响当前登录；登录成功后自动保存。
- **切换账号**：先把当前账号的最新凭据回存，再写入目标账号；写之前备份 `~/.claude.json`。
- **自动回存**：每次回到窗口都会检查当前账号，令牌刷新过就更新存档，避免存档过期。

切换只换登录凭据和账号信息，`~/.claude/` 下的**会话记录、设置、MCP 和 CLAUDE.md 都不动，所有账号共用同一份**。一个账号额度用完，切换后用 `claude --resume` 就能接着之前的会话继续。

切换后，已经打开的 Claude Code 需要重开才会用新账号。



## 二、功能说明

| 功能 | 说明 |
|---|---|
| 添加账号 | 在内嵌终端里运行 `claude` 后输入 `/login`，或直接运行 `claude auth login` |
| 保存当前账号 | 命令行已登录但没保存过的账号，会在列表顶部提示保存 |
| 切换 | 点账号即切换，当前在用的账号会标出来 |
| 删除 | 只删本应用存的凭据，不会让命令行退出登录 |
| 会话共享 | 各账号共用会话记录和配置，切换后可以继续之前的会话 |

数据存放位置：

| 位置 | 内容 |
|---|---|
| 钥匙串 `ccBaton-<id>` | 每个账号的登录凭据 |
| `~/Library/Application Support/ccBaton/profiles.json` | 账号列表 |
| `~/Library/Application Support/ccBaton/claude.json.bak` | 最近一次切换前的 `~/.claude.json` 备份 |



## 三、安装和使用

需要 macOS 14 以上、Apple 芯片，以及 Swift 5.9 以上。

```bash
swift run                   # 本地运行
./scripts/build-app.sh      # 打包成 dist/ccBaton.app 并本机签名
```

打包后把 `dist/ccBaton.app` 拖进“应用程序”即可。**安装后占用约 3.7 MB，压缩包约 1.4 MB**。



## 四、社区友链

[LINUX DO](https://linux.do/)：一个关注开发者、开源项目与 AI 工具交流的社区。感谢社区佬友对开源工具和 Agent 工作流的讨论与反馈。
