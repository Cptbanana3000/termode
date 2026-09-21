# Git Local Smoke Test Results - Termode v0.64

Test date: 2026-09-01/02  
Device: Samsung SM-X510 tablet  
Android: 16 (API 36)  
ABI: arm64-v8a

## Results

| Check | Result |
| --- | --- |
| APK native entry size/hash | PASS |
| Android native extraction | PASS |
| execution as Termode app UID | `git version 2.44.0` |
| `runtime-pkg install git` | PASS, execution verified |
| `runtime-pkg verify git` | PASS |
| `bin-which git` | PASS, logical/backing paths reported |
| `git-version` | PASS |
| direct REAL PTY `git --version` | PASS |
| `git init` | PASS |
| `git status` | PASS |
| `git-smoke-test` | HEALTHY |

The smoke workspace is app-private and disposable. The test performs no clone,
fetch, pull, push, credential, or network operation. Remote Git remains
deferred. Successful smoke metadata is persisted only after all three local
commands pass.
