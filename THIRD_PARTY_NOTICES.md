# Third-party dependencies / 第三方依赖

MediaAudio's original scripts, documentation and artwork use [MIT](LICENSE). This license does **not** replace the licenses of external programs. MediaAudio invokes those programs as separate command-line executables; it does not include their source code in its own scripts.

The v0.1.0 repository and release ZIP contain **no third-party executable binaries**. First-time setup downloads unmodified programs directly to the user's machine from the upstream providers below. `dependencies.lock.json` pins initial versions, URLs, archive SHA256 values and selected archive paths. The local dependencies and their downloaded license notices are excluded from Git and release packaging.

| Dependency | Initial version | Role | Licensing and upstream |
| --- | --- | --- | --- |
| yt-dlp | 2026.08.19 | Site extraction and downloads | Source project: Unlicense. PyInstaller Windows executables contain GPLv3+ components; bundled components have additional notices. [License explanation](https://github.com/yt-dlp/yt-dlp#licensing), [third-party notices](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/THIRD_PARTY_LICENSES.txt). |
| FFmpeg / ffprobe | 9.0.2, Gyan essentials build | Processing, full decode, parameter inspection | This selected static Windows build is GPLv3. [FFmpeg legal information](https://ffmpeg.org/legal.html), [build provider](https://www.gyan.dev/ffmpeg/builds/), [fixed release](https://github.com/GyanD/codexffmpeg/releases/tag/9.0.2). |
| Node.js | 24.19.0 | yt-dlp JavaScript runtime | Node.js is MIT; its LICENSE includes notices for bundled components. Only `node.exe` and the LICENSE are extracted, not npm. [Version license](https://github.com/nodejs/node/blob/v24.19.0/LICENSE), [official downloads](https://nodejs.org/dist/v24.19.0/). |

yt-dlp is based on earlier youtube-dl/youtube-dlc work. Credit and responsibility for its extraction engines remain with their contributors. FFmpeg codecs and media processing remain the work of FFmpeg and its dependencies. Node.js remains the work of its contributors. The providers listed above are not sponsors or endorsers of MediaAudio.

## If you redistribute an all-in-one bundle

You become a distributor of any included third-party binaries. Preserve relevant copyright/license notices and meet each applicable license, including GPL corresponding-source requirements for covered binaries. Corresponding source must match the distributed binaries and include required build/dependency material; a generic project-homepage link or a thank-you line is not a substitute. Do not assume MediaAudio's MIT license licenses the whole bundle as MIT.

The initial publication intentionally avoids this binary redistribution. Runtime downloads are made directly by the user-facing setup script from upstream. The existing developer's local all-in-one package is **not** the public v0.1.0 release asset.

## 中文说明

我们的脚本许可证与上游工具许可证分别适用。首版公开仓库和下载包不包含第三方 EXE；首次准备由本机脚本直接向上游下载，核对固定 SHA256，保留许可文件。准备后的 `bin/` 不进入 Git 或发行包。

如果你自行打包并再分发完整依赖，就需要履行这些组件各自的版权、许可证和对应源码提供义务。不能只写一行致谢，也不能用本项目 MIT 许可证覆盖第三方程序。上游源码与构建说明需要匹配实际分发版本，不能只给一个泛泛的首页链接。

Cookie、个人配置、日志和下载的媒体不属于发行内容。程序许可证不授予你对媒体内容本身的下载、再分发或其他权利。
