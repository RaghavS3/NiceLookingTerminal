# NiceLookingTerminal

A native macOS terminal workspace for running shells and coding agents side by side, with optional Codex Desktop and phone Remote setup.

## Terminal behavior

- No application-level limit on terminal panes; large grids grow vertically with a readable minimum pane size.
- 100,000 lines of live scrollback per terminal.
- Incoming output does not move a viewport that the user has scrolled away from the bottom.
- Private disk-backed raw and searchable transcripts persist across app restarts.
- Transcript history can be opened, revealed, exported, or explicitly deleted.
- Closing a pane terminates its PTY process group, including descendant jobs.
- Local Codex uses `--no-alt-screen`; Full Agent Access adds the documented skip-permission option.

Cmd+A follows the focused macOS responder. In a terminal it selects retained terminal content; in a native text editor it selects that editor. Cmd+Backspace sends Ctrl+U only when a terminal is focused.

## Codex agents, Desktop, and phone Remote

The primary **Open Codex** action and Cmd+O create a new embedded agent in the selected workspace with `codex --yolo --no-alt-screen`. The no-alternate-screen flag keeps the agent usable inside the app's retained terminal viewport. This action grants the agent full access without approval prompts.

The separately labeled **Codex Desktop — phone-ready** and onboarding controls open the workspace in Codex Desktop for phone Remote setup.

First-run setup requires the Codex CLI, Git, a working login shell, workspace access, and network connectivity. Codex Desktop, AGY, and phone Remote confirmation are optional. **Set up Remote** opens the supported Codex Desktop connection settings directly. For Remote use, the host must remain awake, online, signed in, and running Codex Desktop.

Full Agent Access persists the user’s explicit choice and applies skip-permission flags to future embedded agent launches. macOS Full Disk Access remains a separate one-time System Settings approval that an app cannot grant itself.

## Build and test

```bash
swift build
swift test
```

The executable entry point is `Sources/MyTermExecutable/main.swift`. Testable application code is in the `MyTermApp` target under `Sources/MyTerm`; persistence and launch models are in `MyTermCore`, and terminal-specific behavior is in `MyTermTerminal`.

## Local package

```bash
./build_app.sh
```

This produces an explicitly local, ad-hoc-signed app and `NiceLookingTerminal-<version>-local.dmg`. Local packages are not suitable for public distribution and do not have a stable macOS privacy identity.

## Distribution package

A release requires an installed Developer ID Application certificate and a configured `notarytool` keychain profile:

```bash
BUILD_MODE=distribution \
CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
NOTARY_PROFILE="notary-profile" \
./build_app.sh
```

Distribution mode builds separate Apple Silicon and Intel release slices, verifies them while creating a universal executable, applies hardened Developer ID signing, and notarizes and staples the app. It then creates an Applications-linked DMG, notarizes and staples the DMG, runs Gatekeeper assessment, and writes a SHA-256 checksum. It fails instead of silently producing a distribution-ineligible artifact when credentials or verification are missing.

Keep the bundle identifier and Developer ID team stable across updates so macOS can retain privacy approval.

## Runtime data

Preferences, sessions, Planner content, copied attachments, and transcripts are stored with private permissions under:

```text
~/Library/Application Support/com.nicelookingterminal.app/
```

Setup shows transcript and attachment disk usage. Cleanup actions describe exactly which app-owned data they remove and never delete original source files.
