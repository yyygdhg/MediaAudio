# Contributing / 参与改进

Small, focused improvements are welcome. Preserve these workflow properties:

- Anonymous extraction first. Authentication only from an explicitly configured source and after a recognized authentication failure.
- No lossy re-encoding in either mode. Preserve the original stream, or encode ALAC without sample-rate/channel overrides or audio filters.
- Verify final audio parameters and fully decode before reporting success or cleaning the source.
- Keep failure media recoverable and existing outputs untouched.
- Keep scripts compatible with built-in Windows PowerShell 5.1 and preserve UTF-8 BOM in `.ps1` files.

Run the checks listed in README. Describe what changed, why, and which checks passed. Site extraction failures may belong to yt-dlp; first confirm the upstream version and whether direct yt-dlp reproduces the issue. Do not promise unsupported platforms without validation.

Never commit Cookie files, personal configurations, tokens, private logs, signed URLs, downloaded media or dependency EXEs. Review the complete diff and tracked-file list. AI-assisted contributions are welcome when reviewed, tested and accurately described.

欢迎针对具体问题的小改进。请保留匿名优先、源音频/ALAC 规则、完整验证、失败可恢复以及 PowerShell 5.1 兼容性。提交时写清用途与验证；不要附带 Cookie、账号资料、私密日志、媒体或第三方 EXE。AI 辅助开发可以参与，但仍需检查、测试并准确说明。
