# Local dependencies

On first launch, MediaAudio prepares `yt-dlp.exe`, `ffmpeg.exe`, `ffprobe.exe` and `node.exe` here using `dependencies.lock.json` and upstream downloads. License notices are saved under `licenses/`.

This directory's executable contents are local runtime data, not repository or release content. If all four executables are already present, setup does not overwrite them. Keep them here when moving a prepared portable folder.

首次启动自动下载、校验并准备依赖。依赖不进入公开仓库或首版发行包；移动已经准备好的便携工具时，应保留本目录。
