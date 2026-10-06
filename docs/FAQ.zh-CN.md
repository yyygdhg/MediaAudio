# 常见问题 · 故障排查与 Cookie 教程

[English](FAQ.md) · [返回 README](../README.zh-CN.md)

## 平时需要 Cookie 吗？

**不需要把它当作固定步骤。** 工具先匿名访问，成功后下载也不带 Cookie。只有网站明确要求登录/验证、且你已指定 Cookie 来源时，才读取该来源并重试一次。Cookie 文件不存在也不影响匿名成功的公开视频。

要求取决于网站、内容与当时会话。同一 YouTube 链接可能暂时要求验证，之后又恢复匿名可用；不能由此推断 B 站或所有平台都需要 Cookie。[上游说明](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp)

## YouTube 提示“Sign in to confirm you're not a bot”怎么办？

1. 在自己的浏览器打开同一视频，确认能播放；网站要求的登录或验证由你本人完成。
2. 双击 `UpdateYtDlp.bat` 检查解析器更新。更新可以处理兼容问题，但不保证解除网站的认证要求。
3. 正常重试。仍然失败、且你愿意提供自己的登录会话时，再选择下面的一种可选方式。

私有、年龄限制、会员内容可能需要有访问权限的账号。Cookie 不会赋予账号原本没有的权限。

## 方式 A：读取自己的浏览器 Cookie

在工具目录的 `config.ini` 设置：

```ini
cookies_from_browser=chrome
cookies_file=
```

yt-dlp 也支持 `edge` 等浏览器名称。只指定你本人拥有并打算使用的浏览器。工具不会替你登录、处理挑战或自动扫描浏览器。解密失败时使用方式 B，不要为此关闭浏览器加密保护。

## 方式 B：导出本地 YouTube Netscape Cookie 文件

适用于想明确使用本地文件，或者遇到 `Failed to decrypt with DPAPI` 的情况。

1. 阅读 yt-dlp 的[官方导出说明](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#exporting-youtube-cookies)。官方 FAQ 推荐的 Chrome 扩展是 **[Get cookies.txt LOCALLY](https://chromewebstore.google.com/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc)**，与旧版“Get cookies.txt”不同。
2. 按上游推荐流程，新建一个无痕窗口，自己登录 YouTube，并确认能访问目标视频。扩展可能需要你手动允许在该无痕窗口中使用。
3. 在同一个窗口、同一个标签页进入 `https://www.youtube.com/robots.txt`。用扩展导出**仅 `youtube.com` 范围**的 Cookie，格式选 **Netscape**；不要选择“导出全部网站”。导出后关闭该无痕窗口。完整步骤及账号会话注意事项以上游说明为准。
4. 在解压后的 MediaAudio 文件夹里创建 `cookies` 文件夹，把文件保存为 `cookies\youtube.txt`。
5. 修改配置：

   ```ini
   cookies_file=cookies\youtube.txt
   cookies_from_browser=
   ```

6. 再次运行 `MediaAudio.bat`。仍然先匿名尝试，网站要求认证时才读取这个文件。

文件第一行必须是 `# Netscape HTTP Cookie File` 或 `# HTTP Cookie File`，不接受 JSON。相对路径以工具目录为基准，也支持绝对路径和环境变量。两个 Cookie 配置都填写时，`cookies_file` 优先。

**Cookie 文件含账号会话，只保留在本机。不要把内容粘贴到问题帖、聊天、截图或公开仓库。** 仓库忽略本地 Cookie 和个人 `config.ini`，但不会阻止你通过其他方式手动上传它们。

## Cookie 以前能用，现在失效了怎么办？

会话可能过期、轮换或被撤销。先确认账号在浏览器仍能播放该视频；如果网站确实要求认证，重新导出 YouTube 范围的 Cookie，替换本地文件即可。不要分享旧文件。即使登录成功，网站验证、限流或视频权限仍可能导致失败。

如果完全不想使用 Cookie，把两个配置项都清空；工具会保持匿名，遇到必须登录的内容就明确报告原因。

## Chrome 能播放，为什么 DPAPI 解密仍失败？

浏览器内部播放和外部程序解密 Cookie 数据库是两件事。原开发环境在稳定版、测试版 yt-dlp 以及正常桌面会话中均遇到相同 DPAPI 错误；浏览器正常导出的本地文件解决了使用流程，无需改 Chrome 安全设置。这里并不声称修复了 DPAPI 本身。[上游问题 #10927](https://github.com/yt-dlp/yt-dlp/issues/10927)

## 更新检查返回 GitHub 403 / rate limit exceeded

工具会从 yt-dlp 更新接口切换到官方发行文件，核对 SHA256 与版本，替换时保留旧程序备份。成功检查缓存 24 小时，失败检查缓存 1 小时；`UpdateYtDlp.bat` 强制检查。所有更新途径都失败时保留当前程序，下载仍可继续尝试。

## 首次准备下载依赖失败

确认能访问 GitHub、`raw.githubusercontent.com` 和 `nodejs.org`，再运行 `SetupDependencies.bat`。校验不一致会停止安装，不要跳过校验。锁文件使用固定发布文件；上游删改资产时，需要审查并更新锁文件。

也可以自行从上游准备四个 EXE 到 `bin/`。四个都存在时自动准备跳过。工具不改系统 PATH，也不安装全局运行时。详见[依赖说明](../THIRD_PARTY_NOTICES.md)。

## 文件与日志在哪里？

- 最终输出：`output_directory`，默认桌面。
- 最近运行日志：`logs\latest.log`。
- 失败时源文件/分片：输出目录内 `.MediaAudio-work\job-...`，控制台会显示路径。
- 请求元数据可能含私密请求头，每项处理后会移除，包括失败时；失败的源音频/分片仍保留。

成功清理源文件前，必须通过编码/参数检查及最终文件完整解码。最终输出不会覆盖已有同名文件。

## 转 ALAC 会提高音质吗？

不会恢复源音轨已经丢失的信息。ALAC 用于避免再进行有损编码；`original` 保留源流。AAC、Opus 等不同编码的码率不能单独作为主观音质排名，本工具采用 yt-dlp 的格式质量排序，不按扩展名盲选。

## 它比直接使用 yt-dlp 更强吗？

这是基于 yt-dlp 的专用工作流，面向希望重复进行音频提取、ALAC 输出、恢复和验证的 Windows 用户。它减少重复配置和命令步骤；专业用户直接使用上游工具会有更多自由度。它不替代网站解析引擎和编解码引擎。

## 怎样提交问题？

提供工具版本、Windows 版本、输出模式、依赖版本及脱敏错误。可安全分享时才附公开链接。不要附 Cookie、带签名下载地址、私有列表或未经检查的日志。详见 [CONTRIBUTING.md](../CONTRIBUTING.md)。
