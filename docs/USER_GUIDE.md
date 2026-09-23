# Termode User Guide & Developer Experience (DX) Manual

Welcome to **Termode**, a guided, modern terminal and native runtime environment engineered specifically for Android (ARM64).

Termode is designed from the ground up to eliminate the friction, manual tinkering, and cryptic errors common to mobile terminal environments. Rather than requiring users to manually manage package manager mirrors, debug Android SELinux kernel blocks, or build complex shims, Termode provides authentic native execution with seamless ergonomics.

---

## 1. Termode Philosophy: Guided, Not Raw

Many Android terminal tools expect developers to behave like Linux system administrators working over SSH on an unconfigured server. Termode takes a different approach:

| Capability | Raw Android Terminal (e.g. Termux) | Termode Experience |
| :--- | :--- | :--- |
| **Setup & Bootstrapping** | Manual bootstrap scripts; fragile apt mirrors | Instant startup; authentic pre-staged native runtimes |
| **Android W^X Policy** | Executable scripts in app data fail with `Permission denied` | Automatic dynamic shell wrappers; bare commands run naturally |
| **Runtime Diagnostics** | Manual shell scripting & trial-and-error | Built-in doctor commands (`doctor`, `pip-doctor`, `node-doctor`) |
| **Background Processes** | Lost when terminal tab switches or screen dims | Managed `dev-server` supervisor with log rotation and status monitoring |
| **Web Previews** | Requires switching to external mobile browser | Integrated localhost web preview with address bar & tab integration |
| **Command Assistance** | Minimal or absent | Built-in catalog, tab-completion, and contextual guidance (`guide`) |

---

## 2. The Android W^X Rule & Dynamic CLI Shell Wrappers

### The Technical Challenge
On Android 10+ (API level 29+), the Linux kernel enforces **W^X (Write XOR Execute)** via SELinux. All writable directories inside application storage (`/data/user/0/com.termode.termode/files/...`) are mounted with the `noexec` flag.

When packages install CLI entry points into `$HOME/.local/bin/` (via `pip`) or `$HOME/.npm-global/bin/` (via `npm`), the generated script files are writable. Directly executing these scripts via the shell (`execve`) triggers an immediate kernel denial:
```text
/system/bin/sh: <tool>: Permission denied
```

### The Termode Solution
Termode solves this transparently without compromising security:
1. **Dynamic Shell Functions**: Termode scans `$HOME/.local/bin/` and `$HOME/.npm-global/bin/` and generates shell wrapper functions in `$TERMODE_USR/termode-shell-helpers.sh`.
2. **Native Binary Delegation**: When you type a bare command name (e.g., `pyfiglet "Termode"` or `cowsay "Moo"`), the shell function executes the script through the authentic native runtime binary (`python3` or `node`), which resides in executable native library storage (`applicationInfo.nativeLibraryDir`).
3. **Zero Configuration**:
   - When you run `pip install --user <pkg>` or `pip-install <pkg>`, Termode immediately updates and reloads the helpers.
   - You can invoke installed CLI tools directly by their standard desktop names:
     ```bash
     cowsay "Termode is alive"
     pyfiglet "Termode"
     ```
   - If you ever need to manually refresh wrappers in an existing session, simply run:
     ```bash
     reload-helpers
     ```

---

## 3. Python 3.14 & pip Workflow

Termode bundles an authentic, full **CPython 3.14.6** engine compiled for ARM64-v8a, paired with **pip 26.2.1**.

### Interactive REPL & Script Execution
- Launch interactive Python:
  ```bash
  python3
  ```
- Run a Python script:
  ```bash
  python3 myscript.py
  ```

### Package Management with pip
- Install pure-Python packages directly from PyPI:
  ```bash
  pip install --user cowsay
  # or using the host command:
  pip-install pyfiglet
  ```
- Inspect installed packages:
  ```bash
  pip-list
  pip-show cowsay
  ```
- Run in-app diagnostics to inspect user-site paths, SSL certificate stores, and cache:
  ```bash
  pip-doctor
  python-doctor
  ```

### Pure Python vs. Compiled C Extensions
> [!NOTE]
> Termode natively runs all **pure-Python** libraries and packages (e.g. `requests`, `urllib3`, `rich`, `click`, `cowsay`, `pyfiglet`, `black`, `flake8`, `jinja2`).
> Packages requiring C compilation (e.g. `numpy`, `scipy`, `cryptography`) require precompiled Android Bionic wheels, as Android does not use standard GNU glibc.

---

## 4. Node.js v24 & npm Workflow

Termode bundles an authentic **Node.js v24.18.0** engine with V8 runtime support.

### Interactive REPL & Script Execution
- Launch interactive Node.js:
  ```bash
  node
  ```
- Run a JavaScript application:
  ```bash
  node server.js
  ```

### Global npm CLI Tools
- Install global packages:
  ```bash
  npm install -g <package>
  ```
- Installed CLI tools in `~/.npm-global/bin/` are automatically wrapped and executable directly from the shell.
- Run health checks:
  ```bash
  node-doctor
  npm-doctor
  ```

---

## 5. DevServer & Background Daemon Supervision

Running persistent development servers on mobile devices can lead to crashes if processes are tied to foreground UI lifecycles. Termode includes a supervised daemon runner:

### Starting and Managing Servers
- Start a background dev server:
  ```bash
  dev-server start api -- node server.js
  dev-server start web -- python3 -m http.server 8080
  ```
- List running servers and check status:
  ```bash
  dev-server list
  ```
- View real-time server output:
  ```bash
  dev-server logs api
  ```
- Stop a server:
  ```bash
  dev-server stop api
  ```

### Localhost Web Previews
- Open the built-in browser panel directly to your local port:
  ```bash
  preview-open http://localhost:8080
  ```
- Check port availability:
  ```bash
  port-check 8080
  ```

---

## 6. Local Git 2.44.0 Version Control

Termode includes a verified, standalone **Git 2.44.0** build running natively on ARM64.

### Supported Operations
Full local repository workflows are supported:
```bash
git init my-project
cd my-project
echo "# My Project" > README.md
git add README.md
git commit -m "Initial commit"
git status
git log --oneline
git branch feature-1
git checkout feature-1
```

### Limitations & Roadmap
> [!NOTE]
> Git currently functions as a **local version control system**. Remote network transports (e.g. `git push` / `git clone` over SSH/HTTPS) are actively in development.

---

## 7. OSINT CLI Tooling (Sherlock & Maigret)

Termode comes preconfigured with pure-Python OSINT investigation engines:

- **Sherlock v0.16.2**: Scan over 480 social networks and web platforms:
  ```bash
  sherlock username --print-found
  ```
- **OSINT Health Checks**:
  ```bash
  osint-doctor
  ```

---

## 8. Sandboxed Workspaces vs. Device Storage

### Private App Sandboxing
By default, Termode runs inside its secure private app sandbox (`/data/user/0/com.termode.termode/files/home/`). This isolates project files and ensures maximum performance.

### Working with Workspaces
- Initialize a new isolated workspace:
  ```bash
  workspace-init my-app
  workspace-cd my-app
  ```
- Inspect workspace health:
  ```bash
  workspace-doctor
  ```

### Accessing External Tablet Storage
To access shared device storage (e.g., Downloads, Documents, SD card):
1. Link an external directory using Android's Storage Access Framework (SAF):
   ```bash
   storage-link
   ```
2. Verify connection:
   ```bash
   storage-status
   ```

---

## 9. Quick Command Reference

| Command | Category | Description |
| :--- | :--- | :--- |
| `guide` | Guidance | Open in-terminal user guide and topics (`guide python`, `guide dx`) |
| `default-shell` | Shell | Enter the full interactive REAL PTY shell (`/system/bin/sh`) |
| `stop-shell` | Shell | Terminate the active PTY session and return to app command mode |
| `reload-helpers`| Shell | Re-source shell functions and newly installed CLI wrappers |
| `doctor` | Diagnostics | Run unified system health check |
| `python3` | Python | Enter CPython 3.14 interactive REPL or run script |
| `pip-doctor` | Python | Diagnose pip, user-site directories, and SSL certificates |
| `pip install` | Python | Install pure-Python packages from PyPI into user-site |
| `node` | Node.js | Enter Node.js v24 interactive REPL or run JavaScript |
| `node-doctor` | Node.js | Diagnose Node.js executable, V8 engine, and module paths |
| `git status` | Git | Check repository status with Git 2.44.0 |
| `dev-server` | Background | Manage supervised background server daemons |
| `preview-open` | Web Preview | Open embedded localhost web preview panel |
| `osint-doctor` | OSINT | Verify Sherlock & Maigret OSINT CLI engine |
