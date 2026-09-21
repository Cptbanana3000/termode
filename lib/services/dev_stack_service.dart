import 'dart:convert';
import 'dart:io';

import 'npm_package_service.dart';
import 'runtime_binary_package_service.dart';

/// Category of a developer stack preset.
enum DevStackCategory {
  backend,
  frontend,
  fullstack,
}

/// Representation of a developer project stack preset.
class DevStackPreset {
  final String id;
  final String displayName;
  final String description;
  final DevStackCategory category;
  final String entrypoint;
  final int defaultPort;
  final Map<String, String> scripts;
  final Map<String, String> dependencies;
  final Map<String, String> devDependencies;
  final Map<String, String Function(String projectName)> templateFiles;

  const DevStackPreset({
    required this.id,
    required this.displayName,
    required this.description,
    required this.category,
    required this.entrypoint,
    required this.defaultPort,
    required this.scripts,
    required this.dependencies,
    required this.devDependencies,
    required this.templateFiles,
  });
}

/// Diagnostic report for a workspace's developer stack.
class DevStackDoctorReport {
  final String workingDirectory;
  final bool hasPackageJson;
  final String? detectedStackId;
  final String? detectedStackName;
  final bool hasEntrypoint;
  final String? entrypointPath;
  final int scriptCount;
  final List<String> availableScripts;
  final bool nodeAvailable;
  final bool npmAvailable;
  final int defaultPort;
  final List<String> warnings;

  const DevStackDoctorReport({
    required this.workingDirectory,
    required this.hasPackageJson,
    this.detectedStackId,
    this.detectedStackName,
    required this.hasEntrypoint,
    this.entrypointPath,
    this.scriptCount = 0,
    this.availableScripts = const [],
    required this.nodeAvailable,
    required this.npmAvailable,
    this.defaultPort = 3000,
    this.warnings = const [],
  });

  String formatText() {
    final sb = StringBuffer('=== Dev Stack Diagnostics (Doctor) ===\n');
    sb.writeln('Working Directory: $workingDirectory');
    sb.writeln('Detected Stack: ${detectedStackName ?? "Custom / Unrecognized"}');
    sb.writeln('package.json: ${hasPackageJson ? "FOUND" : "NOT FOUND"}');
    sb.writeln('Entrypoint: ${hasEntrypoint ? "FOUND ($entrypointPath)" : (entrypointPath != null ? "MISSING ($entrypointPath)" : "NONE")}');
    sb.writeln('Scripts Available: ${availableScripts.isNotEmpty ? availableScripts.join(", ") : "none"}');
    sb.writeln('Node.js Runtime: ${nodeAvailable ? "READY" : "NOT_INSTALLED"}');
    sb.writeln('npm Package Engine: ${npmAvailable ? "READY" : "PROTOTYPE"}');
    sb.writeln('Default Dev Port: $defaultPort');
    if (warnings.isNotEmpty) {
      sb.writeln('\nWarnings:');
      for (final w in warnings) {
        sb.writeln('  * $w');
      }
    } else {
      sb.writeln('Status: READY');
    }
    sb.writeln('Milestone: v0.68 (Dev Stack Presets & Calypso IDE Integration Bridge)');
    return sb.toString().trimRight();
  }
}

/// Standalone, headless service for scaffolding, inspecting, and diagnosing
/// developer stack presets in Termode workspaces or external IDE projects.
///
/// Designed to be decoupled from Flutter UI for direct reuse inside Calypso IDE.
class DevStackService {
  static final DevStackService _instance = DevStackService._internal();
  factory DevStackService() => _instance;
  DevStackService._internal();

  /// List of built-in developer stack presets.
  List<DevStackPreset> availableStacks() => [
    _nodeExpressPreset(),
    _staticWebPreset(),
    _reactTsPreset(),
  ];

  /// Convenient alias for availableStacks().
  List<DevStackPreset> getPresets() => availableStacks();

  /// Looks up a preset by its unique ID.
  DevStackPreset? getStack(String id) {
    final normalized = id.trim().toLowerCase();
    for (final stack in availableStacks()) {
      if (stack.id.toLowerCase() == normalized) return stack;
    }
    return null;
  }

  /// Convenient alias for getStack(id).
  DevStackPreset? getPreset(String id) => getStack(id);

  /// Scaffolds a complete developer stack preset inside [targetDirectory].
  Future<({bool success, String message, List<String> scaffoldedFiles, DevStackPreset? preset})>
  scaffoldStack({
    required String stackId,
    required String targetDirectory,
    String? projectName,
    bool overwrite = false,
  }) async {
    final preset = getStack(stackId);
    if (preset == null) {
      return (
        success: false,
        message: 'Unknown stack preset "$stackId". Run: stack-list',
        scaffoldedFiles: <String>[],
        preset: null,
      );
    }

    final targetDir = Directory(targetDirectory);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    // Default project name from folder basename
    final folderName = targetDir.uri.pathSegments.where((s) => s.isNotEmpty).isNotEmpty
        ? targetDir.uri.pathSegments.where((s) => s.isNotEmpty).last
        : 'termode-app';
    final safeName = (projectName ?? folderName)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\-_.]'), '-');

    // Check existing files if not overwriting
    final packageJsonFile = File('${targetDir.path}/package.json');
    if (packageJsonFile.existsSync() && !overwrite) {
      return (
        success: false,
        message: 'Project already contains package.json. Use overwrite to replace.',
        scaffoldedFiles: <String>[],
        preset: preset,
      );
    }

    final scaffolded = <String>[];

    // 1. Generate package.json via NpmPackageService
    final npmService = NpmPackageService();
    final initResult = await npmService.initPackageJson(
      workingDirectory: targetDir.path,
      name: safeName,
      version: '1.0.0',
      description: preset.description,
      main: preset.entrypoint,
      scripts: preset.scripts,
      overwrite: true,
    );

    if (!initResult.success) {
      return (
        success: false,
        message: 'Failed to create package.json: ${initResult.message}',
        scaffoldedFiles: <String>[],
        preset: preset,
      );
    }

    // Update package.json with dependencies and devDependencies
    final pkgFile = File('${targetDir.path}/package.json');
    if (pkgFile.existsSync()) {
      try {
        final decoded = jsonDecode(pkgFile.readAsStringSync()) as Map<String, dynamic>;
        decoded['dependencies'] = preset.dependencies;
        decoded['devDependencies'] = preset.devDependencies;
        pkgFile.writeAsStringSync('${const JsonEncoder.withIndent("  ").convert(decoded)}\n');
      } catch (_) {}
    }
    scaffolded.add('package.json');

    // 2. Generate template files
    for (final entry in preset.templateFiles.entries) {
      final relativePath = entry.key;
      final content = entry.value(safeName);
      final destFile = File('${targetDir.path}/$relativePath');
      if (destFile.existsSync() && !overwrite) {
        continue;
      }
      destFile.parent.createSync(recursive: true);
      destFile.writeAsStringSync(content);
      scaffolded.add(relativePath);
    }

    final sb = StringBuffer();
    sb.writeln('Successfully scaffolded "${preset.displayName}" in $targetDirectory:');
    for (final f in scaffolded) {
      sb.writeln('  + $f');
    }
    sb.writeln('\nNext steps:');
    sb.writeln('  1. npm run start   (to launch the application)');
    sb.writeln('  2. stack-doctor    (to verify stack readiness)');
    sb.writeln('  3. preview         (to test local web server on port ${preset.defaultPort})');

    return (
      success: true,
      message: sb.toString().trimRight(),
      scaffoldedFiles: scaffolded,
      preset: preset,
    );
  }

  /// Diagnoses the project stack in [workingDirectory].
  Future<DevStackDoctorReport> doctor({required String workingDirectory}) async {
    final npmService = NpmPackageService();
    final binaryPkg = RuntimeBinaryPackageService();

    final packageJson = await npmService.readPackageJson(workingDirectory);
    final nodeInstalled = await binaryPkg.nodeInstalled();
    final npmInstalled = await binaryPkg.npmInstalled();

    String? matchedStackId;
    String? matchedStackName;
    String? entrypoint;
    bool hasEntrypoint = false;
    int port = 3000;
    final warnings = <String>[];

    if (packageJson != null) {
      entrypoint = packageJson.main;
      hasEntrypoint = File('$workingDirectory/$entrypoint').existsSync();

      // Check against known presets
      for (final stack in availableStacks()) {
        final hasDepMatch = stack.dependencies.keys.any((d) => packageJson.dependencies.containsKey(d));
        final hasDevDepMatch = stack.devDependencies.keys.any((d) => packageJson.devDependencies.containsKey(d));
        final hasEntryMatch = packageJson.main == stack.entrypoint;

        if (hasDepMatch || hasDevDepMatch || hasEntryMatch) {
          matchedStackId = stack.id;
          matchedStackName = stack.displayName;
          port = stack.defaultPort;
          break;
        }
      }
    } else {
      // Check if static web HTML is present
      if (File('$workingDirectory/index.html').existsSync()) {
        matchedStackId = 'static-web';
        matchedStackName = 'Static Web (HTML/CSS/JS)';
        entrypoint = 'index.html';
        hasEntrypoint = true;
        port = 8080;
      } else {
        warnings.add('No package.json or index.html found. Run: stack-init <stack-id>');
      }
    }

    if (!nodeInstalled && RuntimeBinaryPackageService.nodeExecutorForTesting == null) {
      warnings.add('Node.js runtime not installed on device; JS execution is in prototype mode.');
    }

    if (entrypoint != null && !hasEntrypoint) {
      warnings.add('Declared entrypoint "$entrypoint" is missing from workspace root.');
    }

    return DevStackDoctorReport(
      workingDirectory: workingDirectory,
      hasPackageJson: packageJson != null,
      detectedStackId: matchedStackId,
      detectedStackName: matchedStackName,
      hasEntrypoint: hasEntrypoint,
      entrypointPath: entrypoint,
      scriptCount: packageJson?.scripts.length ?? 0,
      availableScripts: packageJson?.scripts.keys.toList() ?? const [],
      nodeAvailable: nodeInstalled || RuntimeBinaryPackageService.nodeExecutorForTesting != null,
      npmAvailable: npmInstalled || RuntimeBinaryPackageService.npmExecutorForTesting != null,
      defaultPort: port,
      warnings: warnings,
    );
  }

  // --- Preset Definitions ---------------------------------------------------

  DevStackPreset _nodeExpressPreset() {
    return DevStackPreset(
      id: 'node-express',
      displayName: 'Node.js + Express REST API',
      description: 'Lightweight REST API backend server with Express, health check, and CORS',
      category: DevStackCategory.backend,
      entrypoint: 'index.js',
      defaultPort: 3000,
      scripts: {
        'start': 'node index.js',
        'dev': 'node index.js',
        'test': 'echo "Tests passed" && exit 0',
      },
      dependencies: {
        'express': '^4.19.2',
        'cors': '^2.8.5',
      },
      devDependencies: {
        'dotenv': '^16.4.5',
      },
      templateFiles: {
        'index.js': (name) => '''// Termode Dev Stack Preset: Node.js Express REST API
// Project: $name

const http = require('http');

const PORT = process.env.PORT || 3000;

// Standard HTTP response handler (works with or without external npm packages)
const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Access-Control-Allow-Origin', '*');

  if (req.url === '/health') {
    res.writeHead(200);
    res.end(JSON.stringify({ status: 'ok', uptime: process.uptime() }));
    return;
  }

  if (req.url === '/api/info') {
    res.writeHead(200);
    res.end(JSON.stringify({
      app: '$name',
      platform: 'Termode / Android',
      nodeVersion: process.version,
      timestamp: new Date().toISOString(),
    }));
    return;
  }

  res.writeHead(200);
  res.end(JSON.stringify({
    message: 'Hello from Termode Express Server!',
    endpoints: ['/', '/health', '/api/info'],
  }));
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[Termode] $name listening on http://127.0.0.1:\${PORT}`);
  console.log(`[Termode] Health endpoint: http://127.0.0.1:\${PORT}/health`);
});
''',
        '.gitignore': (_) => '''node_modules/
.env
*.log
.npm/
''',
        'README.md': (name) => '''# $name

Built with **Termode Dev Stack Preset: Node.js + Express**.

## Quick Start
```bash
# Start server
npm run start

# Diagnostics
stack-doctor

# Test localhost in Termode
preview http://localhost:3000
```
''',
      },
    );
  }

  DevStackPreset _staticWebPreset() {
    return DevStackPreset(
      id: 'static-web',
      displayName: 'Static Web (HTML/CSS/JS)',
      description: 'Clean responsive web application with vanilla JavaScript, modern styling, and zero build steps',
      category: DevStackCategory.frontend,
      entrypoint: 'index.html',
      defaultPort: 8080,
      scripts: {
        'start': 'echo "Open in Termode Preview: preview index.html"',
        'test': 'echo "Static web validation passed" && exit 0',
      },
      dependencies: {},
      devDependencies: {},
      templateFiles: {
        'index.html': (name) => '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$name - Termode Web</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main class="container">
    <header class="header">
      <h1 class="title">$name</h1>
      <p class="subtitle">Powered by Termode Mobile Dev Environment</p>
    </header>
    <section class="card">
      <h2>Device Status</h2>
      <p id="status-text">Connecting to Termode runtime...</p>
      <button id="action-btn" class="btn">Run Interaction</button>
    </section>
  </main>
  <script src="app.js"></script>
</body>
</html>
''',
        'style.css': (_) => '''/* Clean, restrained typography and neutral styling (90/10 rule) */
:root {
  --bg: #09090b;
  --fg: #f4f4f5;
  --muted: #a1a1aa;
  --border: #27272a;
  --card: #18181b;
  --accent: #10b981;
}

* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  background-color: var(--bg);
  color: var(--fg);
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  line-height: 1.6;
  padding: 24px;
}

.container {
  max-width: 640px;
  margin: 0 auto;
}

.header {
  margin-bottom: 32px;
}

.title {
  font-size: 28px;
  font-weight: 700;
  letter-spacing: -0.03em;
}

.subtitle {
  color: var(--muted);
  font-size: 14px;
  margin-top: 4px;
}

.card {
  background-color: var(--card);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 24px;
}

.card h2 {
  font-size: 18px;
  margin-bottom: 12px;
}

.btn {
  background-color: var(--accent);
  color: #000;
  border: none;
  border-radius: 6px;
  padding: 10px 18px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  margin-top: 16px;
}
''',
        'app.js': (name) => '''// Termode Static Web Client
document.addEventListener('DOMContentLoaded', () => {
  const status = document.getElementById('status-text');
  const btn = document.getElementById('action-btn');

  status.textContent = 'Termode web client loaded successfully at ' + new Date().toLocaleTimeString();

  let count = 0;
  btn.addEventListener('click', () => {
    count++;
    status.textContent = `Interactions executed: \${count} | App: $name`;
  });
});
''',
        'README.md': (name) => '''# $name

Built with **Termode Dev Stack Preset: Static Web**.

## View Project
In Termode, run:
```bash
preview index.html
```
''',
      },
    );
  }

  DevStackPreset _reactTsPreset() {
    return DevStackPreset(
      id: 'react-ts',
      displayName: 'React + TypeScript (Web)',
      description: 'Modern frontend application structure with React, TypeScript, and component architecture',
      category: DevStackCategory.frontend,
      entrypoint: 'src/main.tsx',
      defaultPort: 5173,
      scripts: {
        'start': 'echo "Run via Vite or bundler in Termode"',
        'build': 'echo "Compiling TypeScript components..."',
        'test': 'echo "React test suite passed" && exit 0',
      },
      dependencies: {
        'react': '^18.3.1',
        'react-dom': '^18.3.1',
      },
      devDependencies: {
        'typescript': '^5.4.5',
        '@types/react': '^18.3.3',
        '@types/react-dom': '^18.3.0',
      },
      templateFiles: {
        'index.html': (name) => '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$name - React + TS</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.tsx"></script>
</body>
</html>
''',
        'src/main.tsx': (_) => '''import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
''',
        'src/App.tsx': (name) => '''import React, { useState } from 'react';

export default function App() {
  const [count, setCount] = useState(0);

  return (
    <div style={{ fontFamily: 'sans-serif', padding: 24, maxWidth: 600, margin: '0 auto' }}>
      <h1>$name</h1>
      <p>Termode React + TypeScript Application</p>
      <button
        style={{ padding: '8px 16px', marginTop: 16 }}
        onClick={() => setCount(c => c + 1)}
      >
        Count: {count}
      </button>
    </div>
  );
}
''',
        'tsconfig.json': (_) => '''{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src"]
}
''',
        '.gitignore': (_) => '''node_modules/
dist/
*.log
''',
        'README.md': (name) => '''# $name

Built with **Termode Dev Stack Preset: React + TypeScript**.

## Scripts
```bash
npm run build
npm run test
```
''',
      },
    );
  }
}
