# Lamba: development notes

Architecture, build steps and implementation details. For what Lamba does, see the [README](../README.md).

Menu bar app that turns the MagSafe 3 charging LED into a status light: manual colors, a Pomodoro timer, and notifications from Claude, scripts and builds.

Requires an Apple silicon Mac with a MagSafe 3 port, macOS 13+.

## Architecture

```
Sources/
  CSMC/          C wrapper for the AppleSMC user client — reads/writes only the LED key (ACLC)
  LambaCore/     UI-free shared code: LightState, LightPattern, PomodoroTimer, IPC, MCP server
  LambaHelper/   root launchd daemon; the only privileged part
  LambaApp/      menu bar app (AppKit status item + SwiftUI panel in UI/)
  LambaCLI/      `lamba` command line tool; `lamba mcp` is the MCP server
Tests/LambaCoreTests/
Support/         Info.plist, launchd plist, install/uninstall scripts
scripts/         build-app.sh, release.sh (signed + notarized DMG, Sparkle feed), strings.py
```

```
Claude / scripts ──► lamba (CLI, MCP) ──► Lamba.app ──► dev.hamur.lamba.helper (root) ──► SMC
                     ~/Library/Application Support/Lamba/lamba.sock   /var/run/dev.hamur.lamba.helper.sock
```

- **Helper** (`/Library/PrivilegedHelperTools/dev.hamur.lamba.helper`) accepts only `set <whitelisted state>` and `get`, only from root or the console user. It is not setuid, and it cannot run commands.
- **App** owns all logic (patterns, flash overlays, Pomodoro) and serves a user-only socket (0600, peer UID checked).
- **CLI** talks to the app. If the app is not running, `lamba set` falls back to the helper directly.

## Build

```sh
swift test
./scripts/build-app.sh                                   # ad-hoc signed, for local use
SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh   # release
open build/Lamba.app
```

On first launch a welcome window explains the one-time admin password prompt (Macs without a
MagSafe LED get an explanation instead, and Pomodoro/statistics keep working). It installs the helper, its launchd plist and `/usr/local/bin/lamba`.

## CLI

```sh
lamba set green|orange|off|system|orange-blink-slow|orange-blink-fast
lamba flash green --times 3
lamba alternate
lamba pomodoro start --work 50 --break 10
lamba pomodoro pause|resume|skip|stop
lamba status
lamba vibrate --times 3            # trackpad haptics, felt through the case (also with the lid closed)
lamba report --days 30            # focus statistics; add --csv for a daily table
```

## Claude

**Claude Code (MCP):** `claude mcp add lamba -- /usr/local/bin/lamba mcp`

**Claude Desktop:** add to `mcpServers` in `claude_desktop_config.json`:
```json
"lamba": { "command": "/usr/local/bin/lamba", "args": ["mcp"] }
```

MCP tools: `set_light`, `flash_light`, `pomodoro`, `vibrate`, `get_report`, `get_status`.

Haptics use the private MultitouchSupport `MTActuator` API (works without a finger on the trackpad and
with the lid closed) and fall back to the public `NSHapticFeedbackManager` if that API disappears.

## Statistics

The app keeps a local activity log (`~/Library/Application Support/Lamba/activity.jsonl`, 400-day retention):
Pomodoro focus time, light modes, charger state and notification flashes. Nothing leaves the Mac.
Settings › Statistics shows KPIs, a daily focus chart and usage breakdowns, with CSV export.
The aggregation lives in `LambaCore/Activity` and is unit-tested.

**Claude Code hooks** (`~/.claude/settings.json`): flash green when Claude finishes, orange when it needs you:
```json
{
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "/usr/local/bin/lamba flash green --times 3" }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "/usr/local/bin/lamba flash orange --times 5" }] }]
  }
}
```

## Dock

Settings → Dock turns on the Lamba Dock: a replacement for the macOS Dock with pinned apps
(imported from the macOS Dock), running apps, hover magnification, drag-and-drop onto apps and
the Trash, and a Lamba tile (LED + Pomodoro ring; click to start/pause, right-click for lights).
"Hide the macOS Dock" saves the system Dock's `autohide` / `autohide-delay`, sets a very long
reveal delay and restores the originals when turned off or when Lamba quits (also after a crash,
on next launch). Limitation: the Lamba Dock cannot reserve screen space, so maximized windows can
extend under it.

### Islands style (v3) and contexts

Settings → Dock → Style "Islands": separate floating islands — time/LED/battery, Claude (one icon),
live items (permission, meeting, music), the current context's apps (window-count bars, hover names,
window list via Accessibility), and shelf + quick toggles + Trash.

**Contexts** (Settings → Contexts; `LambaCore/DockContexts.swift`, `LambaApp/Contexts/`): each has its
apps, rules (time range, display, Wi-Fi, front app, mirroring; first match wins, a hand pick lasts
until the rules' answer changes) and a look applied on switch: wallpaper (built-in or file),
light/dark (Apple Events), Dock tint, LED flash, a Shortcuts shortcut (e.g. Focus), apps to
open/hide. Lamba saves the user's own wallpaper/appearance before first changing them and restores
them when a context leaves the field unset. Wi-Fi rules ask for Location access (macOS 14+ needs it
to read the network name). Quick toggles: Do Not Disturb (via chosen shortcuts — no public Focus
API), keep awake, dark mode, microphone. The shelf keeps dropped files for drag-out, AirDrop, copy.

### Live capsules (strip style)

Appear only while something is happening:

- **Claude** — `lamba agent working|waiting|done [--hook]`, sent by Claude Code hooks
  (Settings → Integrations → Install adds them to `~/.claude/settings.json`, keeping a backup).
  "Waiting" flashes orange, "done" flashes green; stale sessions expire after 30 minutes.
  `PreToolUse` → `lamba agent tool --hook` shows what Claude is doing ("Editing · Dock.swift").
  `PermissionRequest` → `lamba agent permission --hook` puts **Allow / Deny** in the Dock; the CLI
  waits (up to ~10 min) and prints Claude Code's decision JSON. Right-click → "Ask in terminal",
  a timeout, or Lamba not running all fall back to the normal terminal prompt.
- **Meeting** — the next calendar event within 10 minutes (EventKit, asks for Calendar access);
  click joins the Zoom/Meet/Teams link. A minute before the start the LED flashes and the trackpad vibrates.
- **Music** — Spotify or Music, from the notifications they broadcast (no permission needed to read);
  click plays/pauses, right-click skips. Controls use Apple Events (macOS asks once per app).

**Claude is a single icon** (no text): spinning while working, a pulsing hand when it needs you,
a check right after a turn ends. Click it for every machine (this Mac and each SSH host, with its
connection state) and its sessions — running first, finished (last 30 min) dimmed. Click a session
to open its Terminal/iTerm2 tab (selected by tty via Apple Events).

**Other machines over SSH:** `lamba ssh-setup <host>` copies `Support/lamba-hook` (Python 3, no
dependencies) to `~/.lamba/` on the host, adds it to the host's Claude Code hooks, and registers the
host with a `# Lamba: <host> /tmp/lamba-<user>.sock` line in `~/.ssh/config`. Lamba keeps a
background `ssh -N -R <remote socket>:<Lamba socket> <host>` per registered host (with backoff), so
sessions in Warp's SSH, tmux or Zellij all reach it; interactive `ssh` sessions don't forward and
can't take the socket over. Clicking a remote session finds your interactive `ssh <host>` (via
`ps`) and opens its app/tab. The host's sshd needs `StreamLocalBindUnlink yes` so reconnects can
replace a stale socket. Claude Code reads hooks at startup: running sessions need a restart (or /hooks).

Signed builds get `Support/Lamba.entitlements` (Apple Events, Calendars) for the hardened runtime.

## Languages

English, Turkish and German. Translations live in `scripts/strings.py`, which `build-app.sh` turns into
`Support/Localization/*.lproj/Localizable.strings`. Users can override the language in Settings › General.

## Uninstall

```sh
sudo /path/to/Lamba.app/Contents/Resources/uninstall.sh && rm -rf /path/to/Lamba.app
```

## Releasing

Updates use [Sparkle](https://sparkle-project.org). Downloads and the feed are GitHub releases of
this repo. Installed copies read `releases/latest/download/appcast.xml` once a day; every update is verified with the
EdDSA public key in `Support/Info.plist` (`SUPublicEDKey`). The private key is in the maintainer's
login keychain under the account `lamba`. Back it up, without it no update can ever be shipped:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account lamba -x lamba-sparkle.key
```

**From this Mac:**

```sh
xcrun notarytool store-credentials lamba     # once: saves the notary credentials as a profile
APPLE_TEAM_ID=QPH96J479A NOTARY_PROFILE=lamba PUBLISH=1 ./scripts/release.sh 1.0.0
git commit -am "Release 1.0.0" && git tag v1.0.0 && git push --follow-tags
```

`release.sh` sets the version (Info.plist and `LambaVersion.current`), runs the tests, builds and
signs everything inside out (Sparkle, helper, CLI, app) with the hardened runtime, notarizes and
staples the app, builds a DMG (create-dmg when installed), notarizes it, adds it to the published
appcast and signs the feed. With `PUBLISH=1` it creates GitHub release `v<version>` with
`Lamba-<version>.dmg`, `Lamba.dmg` (the download link always points at the latest one) and
`appcast.xml`. `--no-notarize` stops after a signed DMG.
Release notes in `release-notes/<version>.html` are shown in the update window.

**From GitHub Actions:** push a `v*` tag (or run *Release* by hand). Repository secrets:

| Secret | What |
|---|---|
| `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PASSWORD` | Developer ID Application certificate as base64 `.p12`, and its password |
| `KEYCHAIN_PASSWORD` | any string, for the temporary keychain |
| `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID` | notarization |
| `SPARKLE_PRIVATE_KEY` | contents of the exported `lamba-sparkle.key` |
| `HOMEBREW_TAP_DEPLOY_KEY` | write-enabled deploy key of `productdevbook/homebrew-tap` (the one PortKiller uses); the release updates `Casks/lamba.rb` |

The helper lives outside the app (`/Library/PrivilegedHelperTools`), so an update that changes the
app <-> helper protocol must bump `LambaVersion.helperProtocol`; the updated app then reinstalls the
helper with one password prompt. The `lamba` command is a symlink into the app and follows updates.

## Before selling

- [x] Bundle id `dev.hamur.lamba` (helper `dev.hamur.lamba.helper`); never use "MagSafe" in the name
- [x] Developer ID signing, notarization and automatic updates (`scripts/release.sh`, Sparkle)
- [ ] Move helper install to `SMAppService.daemon`
- [ ] Verify the caller's code signature in the helper, not only its UID
- [ ] Licensing (see ova's `License/` for a license key + trial setup)
- [ ] Test on each MagSafe 3 model and after macOS updates (`ACLC` is undocumented)
