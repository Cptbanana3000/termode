# Localhost / Dev Server Readiness

Termode v0.26 adds diagnostics for future developer-server workflows. The goal
is to prove that Termode can check local ports, test HTTP URLs, and produce
preview URLs before adding Node.js, npm, Vite, or a built-in preview panel.

## Why Localhost Matters

Modern frontend tools such as Vite and Next.js usually run a local development
server and expose a URL like `http://127.0.0.1:3000`. Termode needs reliable
diagnostics for those URLs before it can provide a smooth editor-to-preview
workflow.

## Android Loopback Notes

Inside Termode, `127.0.0.1` points at the Android app process network namespace.
If a future runtime starts a server from inside Termode, localhost checks should
target that same app-local loopback address.

`localhost` usually resolves to loopback as well, but `127.0.0.1` is preferred
for diagnostics because it avoids hostname resolution differences across
devices.

## Commands

Check general readiness:

```sh
localhost-doctor
localhost-doctor --verbose
```

Check whether a local port is accepting TCP connections:

```sh
port-check 3000
port-check 5173
```

Test a local HTTP server:

```sh
http-test 3000
http-test http://127.0.0.1:3000
http-test localhost:5173
```

Generate a clean preview URL:

```sh
preview-url 3000
```

## Current Limitations

- Termode does not ship Node.js yet.
- Termode does not ship npm yet.
- Termode does not start Vite or Next.js dev servers yet.
- Termode does not include a built-in WebView preview panel yet.
- Localhost diagnostics only test readiness and reachability.

## Future Plan

1. Node proof
2. npm proof
3. Vite dev server
4. WebView/browser preview
5. CalypsoIDE preview panel later
