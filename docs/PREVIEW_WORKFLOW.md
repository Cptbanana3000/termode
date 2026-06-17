# Preview Workflow Prep

Termode v0.27 adds a preview command set that prepares for a future
dev-server preview workflow. These commands generate, copy, open, remember,
and diagnose localhost preview URLs. They ship **no runtime**: there is no
Node.js, npm, Python, Git, native binary, or in-app WebView panel yet.

## What Preview Commands Do

A modern frontend tool such as Vite or Next.js runs a local development server
and exposes a URL like `http://127.0.0.1:3000`. Before Termode can run such a
server itself, it needs a smooth way to work with those URLs. The preview
commands provide that:

- Generate a clean preview URL for a port.
- Copy a preview URL to the clipboard.
- Open a preview URL in an external browser (Android `ACTION_VIEW`).
- Remember recent preview URLs (a small history of up to 10 entries).
- Diagnose preview capabilities (clipboard, external open, port/HTTP checks).

## Why No Node/npm Yet

Termode deliberately stays runtime-free for now. Android app-private storage
often blocks direct execution, and a bundled runtime needs explicit ABI,
extraction, permission, and process-management proofs first. The preview
commands let Termode prove the *workflow* (URLs, clipboard, external open,
diagnostics) before any runtime exists, so the editor-to-preview experience is
ready when a dev server finally lands.

## Commands

```sh
preview                       # Compact preview status
preview-url 3000              # Print http://127.0.0.1:3000
preview-copy 3000             # Copy http://127.0.0.1:3000 to the clipboard
preview-open 3000             # Check the port, then open the URL externally
preview-open 3000 --force     # Open without checking the port first
preview-check 3000            # Combine port-check and http-test for a port
preview-history               # Show recent preview URLs (max 10)
preview-clear-history         # Clear preview history
preview-settings              # Show preview defaults
preview-doctor                # Diagnose preview capabilities
preview-doctor --verbose      # Include channel/platform diagnostics
preview-help                  # Show preview workflow help
```

### Behavior Notes

- The default host is `127.0.0.1` and the default scheme is `http`.
- Ports must be between 1 and 65535.
- `preview-open` runs a quick port check first. If the port is closed it does
  **not** open the URL and tells you to start your dev server, or to use
  `--force`. With `--force` it opens the URL regardless and reports a friendly
  failure if no browser is installed.
- Only `http://` and `https://` URLs can be opened externally. Unsafe schemes
  such as `javascript:`, `file:`, `content:`, and `intent:` are rejected.
- Preview history is stored with the existing Termode persistence and is
  capped at 10 entries. Each entry stores the URL, port, timestamp, and the
  active workspace name when available.

## Android Loopback Notes

Inside Termode, `127.0.0.1` points at the Android app process network
namespace. A future runtime that starts a server from inside Termode should
expose it on that same app-local loopback address so these preview commands can
reach it.

## Future Plan

1. Node proof
2. npm proof
3. Vite dev server
4. In-app preview panel
5. CalypsoIDE preview integration later
