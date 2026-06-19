# Git Artifact Layout

The v0.50 project-side candidate layout is:

```text
tools/runtime-artifacts/git/
  manifest.template.json
  arm64-v8a/
    manifest.json.example
    manifest.json        # only when a real trusted payload exists
    files/
      bin/git            # only when real Git exists
```

Installable payload paths must be relative and must stay under:

```text
bin/
lib/
libexec/
share/
```

Do not create `manifest.json` for placeholders. A manifest plus missing files
is intentionally `INVALID`; a template-only checkout remains `TEMPLATE_ONLY` or
`UNAVAILABLE`.
