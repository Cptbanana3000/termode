# Calypso IDE Integration Guide: Termode Embedded Engine & Terminal Bridge

This guide documents how **Calypso IDE** (`D:\Projects\calypso_ide`) integrates **Termode** as its embedded terminal, execution engine, and runtime provider on Android.

---

## 1. Architectural Philosophy: In-Process vs. IPC

Traditional Android IDEs either:
1. Attempt to launch Termux via external Android `Intent`s or URI schemes (fragile, requires separate app install, breaks on Android background execution limits).
2. Attempt to run an SSH daemon on `localhost` (slow, requires SSH keys, port conflicts, high battery drain).

**Termode takes a radically superior approach: In-Process Native Engine.**
- Termode is consumed as a standard Dart/Flutter package (`package:termode/termode.dart`).
- **Zero Intents, Zero SSH keys, Zero external APKs.**
- The real Linux pseudo-terminal (PTY master/slave) runs directly inside Calypso IDE's process space.
- CPython 3.14, Google V8 Node.js, and Git 2.44.0 execute natively in Android Bionic user space with Android 10+ Write XOR Execute (`W^X`) compliance.

---

## 2. Linking Termode in Calypso IDE (`pubspec.yaml`)

In `D:\Projects\calypso_ide\pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  # Add Termode as a local path dependency
  termode:
    path: ../termode
```

---

## 3. Initializing Termode on Startup

Before running terminal sessions or headless commands, initialize `TermodeEngine`:

```dart
import 'package:termode/termode.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Termode runtime bootstrap and prefix directories
  await TermodeEngine.instance.initialize();

  runApp(const CalypsoApp());
}
```

You can optionally specify a custom base directory:
```dart
await TermodeEngine.instance.initialize(baseDir: Directory('/custom/storage/path'));
```

---

## 4. Embedding the Terminal Widget

Drop `TermodeEmbeddableTerminal` directly into your multi-panel layout, bottom drawer, or tab sheet:

```dart
import 'package:flutter/material.dart';
import 'package:termode/termode.dart';

class CalypsoBottomPanel extends StatefulWidget {
  final String activeProjectPath;

  const CalypsoBottomPanel({super.key, required this.activeProjectPath});

  @override
  State<CalypsoBottomPanel> createState() => _CalypsoBottomPanelState();
}

class _CalypsoBottomPanelState extends State<CalypsoBottomPanel> {
  late final TermodeTerminalController _terminalController;

  @override
  void initState() {
    super.initState();
    _terminalController = TermodeTerminalController();
  }

  @override
  void dispose() {
    _terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TermodeEmbeddableTerminal(
      controller: _terminalController,
      initialWorkingDirectory: widget.activeProjectPath,
      showTabs: true,
      showExtraKeyboardRow: true,
      theme: const TerminalThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        textColor: Color(0xFFD4D4D4),
        primaryColor: Color(0xFF00FF66), // Termode terminal emerald
        fontFamily: 'monospace',
        fontSize: 13.0,
      ),
      onCommandExecuted: (command, output) {
        debugPrint('Calypso terminal executed: $command');
      },
    );
  }
}
```

---

## 5. Programmatic Control (`TermodeTerminalController`)

Calypso IDE can control the terminal programmatically without keyboard input:

```dart
// Send a command to run in the terminal
await _terminalController.execute('npm install');

// Send raw escape sequence or Ctrl signals
_terminalController.sendCtrlC(); // Interrupt process
_terminalController.sendCtrlD(); // EOF / exit shell

// Change working directory when user switches projects in the IDE
_terminalController.setWorkingDirectory('/data/user/0/.../projects/my-app');

// Clear terminal output
_terminalController.clear();

// Inspect active terminal state
final currentLines = _terminalController.lines;
final isPtyRunning = _terminalController.isPtyActive;
```

---

## 6. Headless Execution for IDE Background Tasks

Calypso IDE can run linters, build tools, git commands, and test suites headlessly without rendering a terminal:

### Running Python
```dart
final result = await TermodeEngine.instance.runPython(
  ['-m', 'flake8', 'main.py'],
  workingDirectory: projectPath,
);
if (result.exitCode == 0) {
  print('Lint passed: ${result.stdout}');
}
```

### Running Node.js / Build Tools
```dart
final result = await TermodeEngine.instance.runNode(
  ['build.js'],
  workingDirectory: projectPath,
);
```

### Running Git Commands
```dart
final result = await TermodeEngine.instance.runGit(
  ['status', '--porcelain'],
  workingDirectory: projectPath,
);
```

### Streaming Command Output
```dart
TermodeEngine.instance.executeStream(
  'npm test',
  workingDirectory: projectPath,
).listen((chunk) {
  print('Test output: $chunk');
});
```

---

## 7. Dev Server Supervision & Live Preview

When a web project runs (`npm start`, `python -m http.server`, etc.), Termode's `DevServerService` tracks running processes and bound network ports:

```dart
final devServers = TermodeEngine.instance.devServers;

// List all active dev servers
for (final server in devServers.servers) {
  print('Server ${server.id} running on port ${server.effectivePort}');
  print('Preview URL: ${server.previewUrl}'); // e.g. http://127.0.0.1:3000
}

// Stop a running server
await devServers.stopServer(serverId);
```

---

## 8. Aggregated Environment Diagnostics

To populate Calypso IDE's system doctor or status bar:

```dart
final diag = await TermodeEngine.instance.diagnostics(workingDirectory: projectPath);

print('Engine Version: ${diag['engineMilestone']}'); // v0.80
print('Node.js: ${diag['runtimes']['node']}');
print('Python: ${diag['runtimes']['python']}');
print('Git: ${diag['runtimes']['git']}');
print('Active Dev Servers: ${diag['servers']['activeDevServers']}');
```

---

## 9. Android Security & Execution Notes

- **`W^X` SELinux Compliance**: Never attempt to run `Process.run()` on scripts in writable app directories. Always use `TermodeEngine.instance.runPython()`, `runNode()`, or `execute()` so Termode routes execution through Android Bionic shared libraries in `nativeLibraryDir`.
- **Environment Isolation**: Termode automatically configures `LD_LIBRARY_PATH`, `PYTHONHOME`, `PYTHONPATH`, and `NODE_PATH` inside the engine so user scripts execute reliably.
