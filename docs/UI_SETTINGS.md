# UI & Settings

Termode v0.39 polishes the settings, theme, terminal layout, and status
readouts. This page explains the user-facing options and how to keep the
terminal readable.

Settings live in two places that stay in sync:

- the **Settings screen** (gear icon in the app bar)
- command-based settings: `settings-summary`, `settings-doctor`,
  `terminal-settings`, `keyboard-settings`, `theme-test`, `status`

## Theme

- Color schemes: `Green` (default), `Amber`, `White`.
- Each scheme sets a readable text color on a dark background.
- ANSI colors stay visible on the dark background.
- Run `theme-test` to preview normal, dim, bold, ANSI foreground/background
  colors, and the status badge sample.

## Font Size

- Default is `14`.
- Range is `10`–`24` in the Settings screen slider.
- The terminal honors the font size setting for both output and the input line.
- Avoid very small fonts on small screens; `12`–`16` is comfortable for most
  devices.

## Line Height

- Default is `1.30`.
- Range is `1.0`–`2.0`.
- A slightly larger line height improves readability for dense output.

## Cursor Style

- Styles: `block` (default), `bar`, `underline`.
- Blinking can be toggled on or off.

## Scrollback

- Allowed values: `500`, `1000`, `2000` (default), `5000`, `10000` lines.
- Larger scrollback keeps more history but uses more memory.

## Paste Safety

- `Paste warning` (default `1000` chars): large pastes prompt before sending.
- `Paste hard limit` (default `10000` chars): pastes above this are blocked.
- Use `paste-force` to send a blocked-but-allowed large paste once.

## Keep Screen On

- A preference that signals you do not want the terminal to sleep quickly.
- Stored with your other settings and shown in `settings-summary`.

## Welcome Banner

- Controls whether the short welcome banner shows on new session tabs.
- A larger ASCII banner can be enabled separately.

## Safe Settings Reset

`settings-reset-safe --confirm` (or the **Safe Reset (Visual Only)** button in
the Settings screen) restores visual and terminal-rendering settings to their
defaults:

- theme, font size, line height
- cursor style and blinking
- ANSI renderer and ANSI debug
- scrollback and paste limits
- welcome/banner and keep-screen-on

It deliberately does **not** change:

- packages, workspaces, sessions, history
- repo configuration or files
- the `Start in real shell` preference

The command requires `--confirm` because Termode cannot show a blocking
confirmation dialog inside the terminal. Use the full destructive `Reset
Termode` action in the Settings screen only when you want to wipe everything.

## Status Readout

`status` prints a compact summary you can copy:

```
=== Termode Status ===
Mode: REAL PTY / NORMAL
Shell: running/stopped
Session: <name>
Workspace: <name or none>
Packages: healthy/limited
Runtime: frozen
Beta: ready with limitations
```

The tab badge also reflects the current mode (`REAL PTY`, `PTY RUNNING`, or
`NORMAL`) and updates after `default-shell`, `stop-shell`, shell exit, tab
switch, app resume, and cold restore.

## Terminal Readability Tips

- Use `theme-test` to confirm contrast after changing the theme.
- Increase line height to `1.4`–`1.5` if dense output feels cramped.
- Keep scrollback at `2000` unless you specifically need more history.
- Use `copy-last` and `copy-session <lines>` to grab readable output.
- Long commands and output wrap; the input line stays above the keyboard.
