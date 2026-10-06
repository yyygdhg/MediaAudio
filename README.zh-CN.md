<p align="center"><img src="assets/hero.svg" alt="MediaAudio — 保留源音轨，验证每次输出" width="100%"></p>

<p align="center">
  <a href="https://github.com/yyygdhg/MediaAudio/releases/tag/v0.1.0"><img src="https://img.shields.io/badge/release-v0.1.0-38c9a4?style=flat-square" alt="v0.1.0"></a>
  <img src="https://img.shields.io/badge/platform-Windows%20x64-101c32?style=flat-square" alt="Windows x64">
  <img src="https://img.shields.io/badge/runtime-PowerShell%205.1-101c32?style=flat-square" alt="PowerShell 5.1">
  <a href="LICENSE"><img src="https://img.shields.io/badge/project%20license-MIT-101c32?style=flat-square" alt="项目代码 MIT"></a>
</p>

<p align="center"><a href="README.md">English</a> · <b>简体中文</b></p>
<p align="center"><a href="https://github.com/yyygdhg/MediaAudio/releases/tag/v0.1.0">下载首版</a> · <a href="docs/FAQ.zh-CN.md">常见问题与 Cookie 教程</a> · <a href="docs/VALIDATION.md">验证记录</a> · <a href="THIRD_PARTY_NOTICES.md">依赖与许可证</a></p>

# 保留源音轨，验证每次输出。

**MediaAudio 把一条视频链接，变成一个明确、可检查的音频保存流程。** 可以直接保留原始音轨，也可以生成适合 Apple 音乐库的 ALAC 文件。处理在本机完成，代码可读，输出通过验证后才算完成。

面向希望使用 **yt-dlp + FFmpeg**，又不想每次重新拼写命令的 Windows 用户。

## 它能做什么

| 能力 | 具体行为 |
| --- | --- |
| **保留原始音轨** | 按 yt-dlp 的 `bestaudio/best` 排序选择源音频，尽可能保留编码与容器；只有音视频合一时，才以 stream copy 分离。 |
| **输出 ALAC** | 将源音轨解码并编码为 ALAC `.m4a`，保持源采样率与声道数；不添加音量调整、EQ、降噪或音频滤镜。 |
| **验证再完成** | 用 ffprobe 检查编码、采样率、声道和时长，再用 FFmpeg 完整解码输出文件。 |
| **匿名优先** | 先不带 Cookie 访问；只有网站明确要求登录/验证、且你已指定 Cookie 来源时才重试。 |
| **便携与可维护** | BAT + 系统自带 PowerShell，无安装程序、管理员权限、PATH 修改或独立 Python 安装要求。 |
| **失败可恢复** | 转换失败保留已下载源文件/分片；同名输出加序号，不覆盖已有文件。 |
| **可恢复的更新** | yt-dlp 更新接口失败时改查官方发布文件，核对 SHA256 和版本；检查结果缓存，更新失败不阻止下载。 |

> **ALAC 是无损输出编码，不是音质修复。** YouTube 等网站常提供有损 Opus/AAC。转成 ALAC 无法恢复源文件已经丢失的信息；要保留网站实际提供的音轨，请使用 `original` 模式。

## 三步开始

1. 下载 **[MediaAudio-v0.1.0-Windows-x64.zip](https://github.com/yyygdhg/MediaAudio/releases/download/v0.1.0/MediaAudio-v0.1.0-Windows-x64.zip)**，将整个文件夹解压到可写的位置。
2. 双击 **`MediaAudio.bat`**。首次启动会从上游提供方下载固定版本依赖，并核对 SHA256。请预留几分钟、联网环境及建议约 1 GB 的初次准备空间。
3. 粘贴支持的视频链接。验证后的音频默认保存到 **`%USERPROFILE%\Desktop`**。

首版 ZIP 包含项目脚本和文档，**不包含预打包的第三方 EXE**。准备完成后依赖保存在 `bin/`；四个必需程序都存在时不会再次执行初次准备。也可以提前双击 `SetupDependencies.bat`。

### 选择输出方式

配置保存在 `config.ini`；缺失时首次运行会创建默认配置。用记事本或 VS Code 打开：

```ini
[General]
output_directory=%USERPROFILE%\Desktop
auto_update_ytdlp=true
download_playlist=false
cookies_from_browser=
cookies_file=
open_folder_when_finished=false
pause_after_finished=true
write_log=true

[Output]
output_mode=alac
```

| 配置 | 用途 |
| --- | --- |
| `output_mode=alac` | 默认 ALAC `.m4a`；保留源采样率和声道数。 |
| `output_mode=original` | 保留最佳可用的原始音轨。 |
| `output_directory=D:\Music` | 自定义保存目录；相对路径以工具文件夹为基准。 |
| `download_playlist=true` | 明确开启整个播放列表/多分 P；默认只处理一个。 |
| `cookies_file=` / `cookies_from_browser=` | 默认均为空。需要登录时再看 [FAQ](docs/FAQ.zh-CN.md)。 |

文件名保留视频标题，清理 Windows 非法字符；同名文件加序号，不猜测歌手、歌名和年份。

### 可选命令行

```powershell
.\MediaAudio.bat -Url "https://www.youtube.com/watch?v=VIDEO_ID" -NoPause
.\UpdateYtDlp.bat -NoPause
```

## 范围与限制

- **Windows 10/11 x64、PowerShell 5.1。** 尚未验证其他系统或 Windows ARM64。
- **YouTube 和 Bilibili** 有实际解析检查，原工作流也完成过真实下载和 ALAC 验证；其他平台依赖 yt-dlp，尚未被本项目逐一验证。详见 [验证范围](docs/VALIDATION.md)。
- 网站策略、会话过期、地区/账号权限与网络问题仍可能阻止下载；更新或 Cookie 不保证所有视频可用。
- 这是**本机运行的控制台工具**。没有网页提取服务、GUI、账号系统或遥测上传。
- 日志可能含标题、视频 ID 和本地路径。敏感请求头值、带签名的查询参数会脱敏；分享前仍应检查日志。

## 工作流

```mermaid
flowchart LR
    A[视频链接] --> B[匿名解析]
    B -->|公开访问成功| C[选择源音轨]
    B -->|要求登录且已配置来源| D[可选本地 Cookie]
    D --> C
    C --> E[下载]
    E --> F[保留原始 / ALAC]
    F --> G[ffprobe + 完整解码]
    G --> H[验证后的文件]
```

**本项目负责流程，上游项目提供媒体引擎。** yt-dlp 负责解析/下载，FFmpeg 负责处理和解码，ffprobe 读取参数，Node 执行 yt-dlp 的 JavaScript 解析任务。

## 开发与维护

先运行 `SetupDependencies.bat`，再在 Windows PowerShell 执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Dependencies.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-MediaAudio.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Repair.ps1
```

本地测试生成合成音频，不把下载的音乐提交到仓库。在线平台测试单独记录，因为结果会变化。提交问题前请看 [CONTRIBUTING.md](CONTRIBUTING.md)，尤其不要附带 Cookie 内容。

## 项目与致谢

由 **[Liminal / yyygdhg](https://github.com/yyygdhg)** 主导并维护，使用 AI 辅助开发。需求取舍、输出检查和兼容性限制均保留说明，方便检查与继续改进。

项目脚本、文档及原创图像使用 **[MIT](LICENSE)**。第三方工具保留各自许可证；Windows yt-dlp EXE 和所选 FFmpeg 构建涉及 GPL 要求。v0.1.0 的公开包不再分发它们的二进制文件。自行制作完整捆绑包前请阅读 **[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)**。

仅用于你有权保存的媒体，并遵守适用法律和来源网站条款。

<p align="center">一个小工具，把使用流程和验证结果说明白。</p>
