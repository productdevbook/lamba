# Lamba

macOS menu bar app (Swift Package, macOS 13+): MagSafe LED status light, Pomodoro, an optional Dock,
Claude Code sessions. Bundle id `dev.hamur.lamba`, root helper `dev.hamur.lamba.helper`.
Architecture and release details: `docs/DEVELOPMENT.md`.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org) for every commit:

```
<type>(<optional scope>): <short summary in the imperative>
```

- Types: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`, `ci`, `chore`, `style`.
- Scopes when they help: `core`, `app`, `dock`, `panel`, `settings`, `helper`, `cli`, `release`.
- Examples: `feat(dock): show the window list on hover`, `fix(core): keep Pomodoro running on light changes`,
  `ci: split the release workflow`, `docs: explain Homebrew install`.
- A breaking change gets `!` after the type (`feat(helper)!: …`) and a `BREAKING CHANGE:` footer.
- One logical change per commit. The body says why, not what.

## Working on it

```sh
swift build && swift test                          # 51+ tests in Tests/LambaCoreTests
./scripts/build-app.sh                             # build/Lamba.app, ad-hoc signed
osascript -e 'quit app "Lamba"'; sleep 3; open build/Lamba.app
.build/debug/LambaApp --snapshot <dir>             # renders panel and settings to PNGs
```

- User-facing strings: add them to `scripts/strings.d/<area>.py` (English, Turkish, German) and an
  accessor in Swift; `scripts/strings.py` generates the `.lproj` files.
- Changing the app <-> helper protocol (`HelperRequest`): bump `LambaVersion.helperProtocol` so the
  app reinstalls the helper.
- The Dock is a non-activating panel: SwiftUI hover and popovers don't work there; use
  `layout.pointerX` and `DockPopover`.
- Keep long SwiftUI `body` expressions split into small properties; CI's compiler times out on them.

## Releasing

Push a `v1.2.3` tag. The Release workflow signs, notarizes, publishes the DMG and Sparkle feed as a
GitHub release and updates `Casks/lamba.rb` in `productdevbook/homebrew-tap`. Locally:
`./scripts/release.sh 1.2.3` (see the script header for the environment variables).
