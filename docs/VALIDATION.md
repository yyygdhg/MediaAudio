# Validation / 验证记录

## v0.1.0 publication checks — 2026-10-06

Executed in **Windows x64 using built-in Windows PowerShell 5.1**. This is a record of tested examples and local invariants, not a guarantee that every URL or platform works.

| Suite | Passed | Scope |
| --- | ---: | --- |
| `tests/Test-Dependencies.ps1` | 6/6 | Pinned upstream lock, HTTPS/host constraints, path containment, corrupt-download refusal, exact ZIP extraction and prepared-folder setup skip. |
| `scripts/Test-MediaAudio.ps1` | 14/14 | Dependency execution, config recovery, invalid config handling, privacy, Unicode/argument quoting, synthetic 48 kHz stereo and 44.1 kHz mono fixtures, original/ALAC modes, collisions, stream-copy fallback, failure source retention and corrupt-output refusal. |
| `scripts/Test-Repair.ps1` | 9/9 | Actionable/redacted diagnostics, checksum parsing, wrong-hash rejection, update caching, cookie opt-in/file handling, anonymous independence and selective authentication retry. |
| First-time dependency setup | Passed | Started with no dependency EXEs; downloaded pinned upstream assets, verified SHA256, extracted exact files and executed all four version checks. |

**29 local checks passed, 0 failed.** Source tests generate synthetic audio and do not rely on a user account or commit media fixtures.

Initial dependencies: yt-dlp `2026.08.19`; FFmpeg/ffprobe `9.0.2` Gyan essentials; Node `24.19.0`. Node's official archive and license are fetched from Node.js, not copied from a development runtime.

## Live-site checks

| Date | Site | Result | Authentication | Exact scope |
| --- | --- | --- | --- | --- |
| 2026-10-06 | YouTube | Passed; format `251`, Opus | No cookies | Public-link metadata/format extraction through the clean public source. |
| 2026-10-06 | Bilibili | Passed; format `30232`, AAC | No cookies | Public BV metadata/format extraction through the clean public source. |
| 2026-10-05 | YouTube | Passed | Anonymous and explicitly provided local cookies tested separately | Earlier workflow completed an actual original Opus download and full decode; ALAC output was verified at 48 kHz, stereo, roughly 669.5 seconds. |
| 2026-10-05 | Bilibili | Passed | No Bilibili cookies | Earlier workflow completed an actual AAC-source-to-ALAC download/conversion and full decode at 44.1 kHz, stereo. |

Live results are time-specific. The same YouTube link initially returned a bot/login requirement, worked with an explicitly exported local session, and later worked anonymously. No permanent explanation for that change is asserted.

The v0.1.0 publication changes dependency provisioning and documentation; the media workflow retains the tested original/ALAC behavior. Live checks on the publication date were metadata checks, **not a new full download on every site**. Other yt-dlp-supported sites are not individually validated by this project.

## What is not established

- Universal support for every site/video, perpetual anonymous access, or permanent authentication compatibility.
- Windows ARM64, macOS or Linux compatibility; a complete Windows 10 versus 11 test matrix.
- Subjective audio superiority of one codec based solely on its bitrate.
- DPAPI repair, automatic account login, challenge solving or rights to restricted media.

## 中文说明

首版在 Windows x64、系统 PowerShell 5.1 下完成 **29 项本地检查，全部通过**，并验证了空依赖目录的首次下载、校验与准备。2026-10-06 的公开版 YouTube 与 Bilibili 检查均为**匿名元数据/格式检查**。前一天的原工作流有真实音频下载、ALAC 转换和完整解码记录。

这些记录用于说明验证范围，不表示每个链接、每个平台或以后每次运行都保证成功。其他网站、系统和具体权限情形需要逐项验证。
