# MediaAudio v0.1.0 — First public release / 首个公开版本

A small, local Windows audio workflow built around yt-dlp and FFmpeg. Save the original source stream, or create ALAC output with parameter checks and full decoding before completion.

## Download and start

Download **MediaAudio-v0.1.0-Windows-x64.zip**, verify it with **SHA256SUMS.txt** if desired, extract the whole folder and double-click `MediaAudio.bat`.

**First launch needs internet access:** this release contains project scripts and documentation, not third-party EXEs. It downloads pinned dependencies directly from their upstream providers, verifies SHA256 and keeps them in local `bin/`. No administrator rights, PATH edits or separate Python installation are needed. After preparation, the folder is portable.

## Included

- Original audio preservation or ALAC `.m4a`, with the source sample rate and channels.
- ffprobe parameter/duration validation and full FFmpeg decode.
- Anonymous-first extraction, optional explicitly configured cookies and source retention on processing failure.
- Unicode-safe titles, output collision handling and official yt-dlp update recovery.
- English / 简体中文 READMEs, illustrated introduction, FAQ/cookie export tutorial and dependency/license notices.
- 29 passing local checks; real anonymous YouTube/Bilibili metadata checks on 2026-10-06.

## Scope

Windows x64 with PowerShell 5.1. YouTube/Bilibili examples have validation records; other sites are inherited from yt-dlp and not individually tested. Website verification and account/region restrictions can still cause failures. ALAC cannot restore quality already lost in a lossy source.

Project scripts/docs/artwork: MIT. Upstream dependencies keep their own licenses. No cookies, private configuration, logs, media or third-party binaries are included in the release.

## 中文

首个公开版本：基于 yt-dlp 与 FFmpeg 的 Windows 本机音频工作流。可以保留原始音轨或输出 ALAC，检查源采样率和声道，最终文件通过 ffprobe 与完整解码后才报告完成。

下载 **MediaAudio-v0.1.0-Windows-x64.zip**，完整解压，双击 `MediaAudio.bat`。**首次启动需要联网**，从上游下载固定版本依赖并校验 SHA256；本包不捆绑第三方 EXE。无需管理员权限、修改 PATH 或另装 Python，准备后整个文件夹可移动。

默认在桌面输出 ALAC；改 `output_mode=original` 可保留源音轨。默认匿名访问，只有网站要求认证、且你已配置来源时才使用 Cookie。中英文 README 与 FAQ 包含 Cookie 获取/更新教程及已知限制。

29 项本地检查全部通过，发布当天 YouTube 与 Bilibili 匿名格式检查通过。其他网站尚未逐一验证，无法保证所有链接都可访问。源音轨有损时，转 ALAC 不会恢复丢失信息。

项目自有代码、文档和原创图像为 MIT；上游依赖各自适用其许可证。发行包不含 Cookie、个人配置、日志、媒体或第三方二进制。
