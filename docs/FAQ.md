# FAQ · Troubleshooting & cookies

[简体中文](FAQ.zh-CN.md) · [Back to README](../README.md)

## Do I normally need cookies?

**No.** MediaAudio starts with no cookies. If anonymous extraction succeeds, the download also uses no cookies. It retries a configured cookie source only after a recognized authentication error. A missing cookie file does not block anonymous public content.

This is site- and session-dependent. A link can require verification at one time and work anonymously later. YouTube verification is not a universal requirement for Bilibili or other sites. See the [upstream explanation](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp).

## YouTube says “Sign in to confirm you're not a bot”

1. Open the exact video in your own browser and confirm that it plays. Complete any login or verification requested by the site yourself.
2. Double-click `UpdateYtDlp.bat` to check for parser updates. Updates cannot guarantee removal of a site authentication requirement.
3. Retry normally. If the error persists and you choose to provide a session, follow one of the optional methods below.

Private/age-restricted/members-only content can require an account with the necessary access. Cookies do not grant permissions your account does not have.

## Option A: use your own browser's cookies

In the tool's `config.ini`, set:

```ini
cookies_from_browser=chrome
cookies_file=
```

`edge` is another yt-dlp-supported selector. Only choose a browser you own and intend to use. MediaAudio does not sign in, solve challenges or silently discover browsers. If the browser reader fails, use Option B rather than disabling browser encryption.

## Option B: export a local YouTube-only Netscape file

Use this when you prefer a local file or receive `Failed to decrypt with DPAPI`.

1. Read yt-dlp's [official export instructions](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#exporting-youtube-cookies). Its FAQ links to the Chrome extension **[Get cookies.txt LOCALLY](https://chromewebstore.google.com/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc)**. This is distinct from the old “Get cookies.txt” extension.
2. For the upstream-recommended export flow, use a new private/incognito window, sign in to YouTube yourself, and confirm access to the video. The extension may need your manual permission to operate in that window.
3. In that same window and tab, navigate to `https://www.youtube.com/robots.txt`. Export **only `youtube.com` cookies** in **Netscape** format; do not use an “export all sites” option. Close the private window after exporting. See the upstream page for details and account-session considerations.
4. Create a `cookies` folder inside your extracted MediaAudio folder. Save the file locally as `cookies\youtube.txt`.
5. Configure:

   ```ini
   cookies_file=cookies\youtube.txt
   cookies_from_browser=
   ```

6. Run `MediaAudio.bat` again. Anonymous access is still tried first; the file is read only if the site asks for authentication.

The file must start with `# Netscape HTTP Cookie File` or `# HTTP Cookie File`. JSON is not accepted. Relative paths are based on the tool's folder; absolute paths and environment variables are supported. When both cookie settings are non-empty, `cookies_file` takes priority.

**Cookie files contain account sessions. Keep them on your machine. Never paste their contents into an issue, chat, screenshot or public repository.** The repository ignores local cookies and personal `config.ini`, but that does not protect an unrelated manual upload.

## The cookie file worked before, but no longer works

Sessions can expire, rotate or be revoked. First confirm that the account can still play the video in the browser; if authentication is required, export a fresh YouTube-only file and replace your local file. Do not share the old file. An authenticated account can still be blocked by site validation, rate limits or content restrictions.

To stop using cookies completely, clear both settings. MediaAudio will remain anonymous and report any required login.

## DPAPI fails even though Chrome can play the video

Browser playback and an external program decrypting its cookie database are different operations. The original environment produced the same DPAPI failure with stable/nightly yt-dlp and in a normal desktop session. A local browser export solved the workflow without changing Chrome security. This does **not** claim to repair DPAPI itself. See [upstream issue #10927](https://github.com/yt-dlp/yt-dlp/issues/10927).

## GitHub update check returns HTTP 403 / rate limit exceeded

MediaAudio falls back from yt-dlp's update API to official release assets, checks SHA256 and the executable version, and keeps a backup on replacement. Successful checks are cached for 24 hours; failed checks for one hour. `UpdateYtDlp.bat` forces a new check. If all update paths fail, the installed version is kept and downloads can continue.

## First-time setup cannot download a dependency

Check connectivity to GitHub, `raw.githubusercontent.com` and `nodejs.org`, then run `SetupDependencies.bat` again. A checksum failure stops installation; do not bypass it. The lock file pins release assets, so a removed or replaced upstream asset requires a reviewed lock-file update.

You may prepare the four executables yourself under `bin/` from their upstream providers. If all four exist, automatic setup is skipped. MediaAudio does not alter system PATH or install global runtimes. See [dependencies](../THIRD_PARTY_NOTICES.md).

## Where are the files and logs?

- Final output: `output_directory` (your Desktop by default).
- Recent run log: `logs\latest.log`.
- Failed source/partial files: `.MediaAudio-work\job-...` inside the output directory; the console prints the path.
- Private request metadata is removed after processing, including on a per-item failure. Downloaded source/partial media is retained on failure.

Successful source cleanup happens only after codec/parameter checks and a full decode of the final output. Completed output files are never overwritten.

## Can ALAC improve a lossy source?

No. ALAC avoids another lossy encode; it cannot recover discarded information. `original` keeps the source stream. Comparing raw bitrates across AAC and Opus does not by itself establish which sounds better. MediaAudio uses yt-dlp's format ranking rather than extension preference.

## Is this more powerful than yt-dlp?

It is a narrower workflow on top of yt-dlp. It makes repeated audio extraction, ALAC conversion, recovery and validation easier for its intended Windows audience. Experts can get more flexibility from the upstream tools directly. MediaAudio does not replace their extraction or codec engines.

## How do I report a problem?

Include the MediaAudio version, Windows version, output mode, dependency versions and a sanitized error. Include a public URL only if it is safe to share. Do not include cookie files, signed download URLs, private playlist information or unreviewed logs. See [CONTRIBUTING.md](../CONTRIBUTING.md).
