import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/dev_stack_service.dart';
import 'package:termode/services/npm_package_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';
import 'package:termode/termode_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v0.68 Dev Stack Presets & Calypso IDE Integration Bridge', () {
    late Directory tempDir;
    late Directory projectDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_stack_test');
      projectDir = Directory('${tempDir.path}/workspace/demo-stack');
      await projectDir.create(recursive: true);

      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      TerminalSessionService().activeSession.preferredWorkingDirectory = projectDir.path;
      commandService = CommandService(VirtualFileSystem(), 'stack_test');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (call) async {
              switch (call.method) {
                case 'getStorageStatus':
                  return null;
                case 'realPtySend':
                case 'realPtySendRaw':
                  return true;
                case 'getDiagnostics':
                  return {'abi': 'arm64-v8a', 'pid': 9999};
                case 'getPaths':
                  return {
                    'home': '${tempDir.path}/files/home',
                    'usr': '${tempDir.path}/files/usr',
                    'bin': '${tempDir.path}/files/usr/bin',
                    'tmp': '${tempDir.path}/files/tmp',
                  };
              }
              return null;
            },
          );
    });

    tearDown(() async {
      RuntimeBinaryPackageService.npmExecutorForTesting = null;
      RuntimeBinaryPackageService.nodeExecutorForTesting = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            null,
          );
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('command catalog includes stack-* commands', () {
      expect(kTermodeCommands.contains('stack-list'), isTrue);
      expect(kTermodeCommands.contains('stack-init'), isTrue);
      expect(kTermodeCommands.contains('stack-info'), isTrue);
      expect(kTermodeCommands.contains('stack-doctor'), isTrue);
    });

    test('DevStackService lists all available presets', () {
      final service = DevStackService();
      final presets = service.getPresets();

      expect(presets.length, equals(3));
      final ids = presets.map((p) => p.id).toList();
      expect(ids, contains('node-express'));
      expect(ids, contains('static-web'));
      expect(ids, contains('react-ts'));
    });

    test('DevStackService returns detailed metadata for presets', () {
      final service = DevStackService();

      final express = service.getPreset('node-express');
      expect(express, isNotNull);
      expect(express!.displayName, equals('Node.js + Express REST API'));
      expect(express.defaultPort, equals(3000));
      expect(express.entrypoint, equals('index.js'));
      expect(express.scripts.containsKey('start'), isTrue);
      expect(express.scripts.containsKey('dev'), isTrue);
      expect(express.dependencies.containsKey('express'), isTrue);
      expect(express.devDependencies.containsKey('dotenv'), isTrue);

      final staticWeb = service.getPreset('static-web');
      expect(staticWeb, isNotNull);
      expect(staticWeb!.displayName, equals('Static Web (HTML/CSS/JS)'));
      expect(staticWeb.defaultPort, equals(8080));
      expect(staticWeb.entrypoint, equals('index.html'));
      expect(staticWeb.templateFiles.containsKey('style.css'), isTrue);
      expect(staticWeb.templateFiles.containsKey('app.js'), isTrue);

      final reactTs = service.getPreset('react-ts');
      expect(reactTs, isNotNull);
      expect(reactTs!.displayName, equals('React + TypeScript (Web)'));
      expect(reactTs.defaultPort, equals(5173));
      expect(reactTs.entrypoint, equals('src/main.tsx'));
      expect(reactTs.dependencies.containsKey('react'), isTrue);
      expect(reactTs.devDependencies.containsKey('typescript'), isTrue);
      expect(reactTs.templateFiles.containsKey('tsconfig.json'), isTrue);
    });

    test('scaffoldStack node-express creates expected directory and files', () async {
      final service = DevStackService();
      final result = await service.scaffoldStack(
        stackId: 'node-express',
        targetDirectory: projectDir.path,
        projectName: 'my-express-api',
      );

      expect(result.success, isTrue);
      expect(result.scaffoldedFiles.length, greaterThanOrEqualTo(3));
      expect(result.preset!.id, equals('node-express'));

      final pkgFile = File('${projectDir.path}/package.json');
      expect(pkgFile.existsSync(), isTrue);
      final pkg = jsonDecode(pkgFile.readAsStringSync());
      expect(pkg['name'], equals('my-express-api'));
      expect(pkg['dependencies']['express'], isNotNull);

      final indexFile = File('${projectDir.path}/index.js');
      expect(indexFile.existsSync(), isTrue);
      final indexContent = indexFile.readAsStringSync();
      expect(indexContent, contains('/health'));

      final readmeFile = File('${projectDir.path}/README.md');
      expect(readmeFile.existsSync(), isTrue);
      expect(readmeFile.readAsStringSync(), contains('Node.js + Express'));
    });

    test('scaffoldStack static-web creates expected directory and files', () async {
      final service = DevStackService();
      final result = await service.scaffoldStack(
        stackId: 'static-web',
        targetDirectory: projectDir.path,
        projectName: 'web-landing',
      );

      expect(result.success, isTrue);
      expect(File('${projectDir.path}/index.html').existsSync(), isTrue);
      expect(File('${projectDir.path}/style.css').existsSync(), isTrue);
      expect(File('${projectDir.path}/app.js').existsSync(), isTrue);
      expect(File('${projectDir.path}/package.json').existsSync(), isTrue);

      final html = File('${projectDir.path}/index.html').readAsStringSync();
      expect(html, contains('web-landing'));
    });

    test('scaffoldStack react-ts creates expected directory and files', () async {
      final service = DevStackService();
      final result = await service.scaffoldStack(
        stackId: 'react-ts',
        targetDirectory: projectDir.path,
        projectName: 'react-dashboard',
      );

      expect(result.success, isTrue);
      expect(File('${projectDir.path}/index.html').existsSync(), isTrue);
      expect(File('${projectDir.path}/src/main.tsx').existsSync(), isTrue);
      expect(File('${projectDir.path}/src/App.tsx').existsSync(), isTrue);
      expect(File('${projectDir.path}/tsconfig.json').existsSync(), isTrue);
    });

    test('scaffoldStack prevents overwrite unless specified', () async {
      final service = DevStackService();
      await service.scaffoldStack(
        stackId: 'node-express',
        targetDirectory: projectDir.path,
        projectName: 'first-pass',
      );

      final conflict = await service.scaffoldStack(
        stackId: 'node-express',
        targetDirectory: projectDir.path,
        projectName: 'second-pass',
        overwrite: false,
      );
      expect(conflict.success, isFalse);
      expect(conflict.message, contains('already contains package.json'));

      final overwrite = await service.scaffoldStack(
        stackId: 'node-express',
        targetDirectory: projectDir.path,
        projectName: 'overwritten-app',
        overwrite: true,
      );
      expect(overwrite.success, isTrue);
      final pkg = jsonDecode(File('${projectDir.path}/package.json').readAsStringSync());
      expect(pkg['name'], equals('overwritten-app'));
    });

    test('DevStackService doctor detects stack preset and diagnostics', () async {
      final service = DevStackService();
      
      // Before scaffold: no package.json
      final reportBefore = await service.doctor(workingDirectory: projectDir.path);
      expect(reportBefore.hasPackageJson, isFalse);
      expect(reportBefore.detectedStackId, isNull);

      // After scaffold: express detected
      await service.scaffoldStack(
        stackId: 'node-express',
        targetDirectory: projectDir.path,
        projectName: 'diag-express',
      );

      final reportAfter = await service.doctor(workingDirectory: projectDir.path);
      expect(reportAfter.hasPackageJson, isTrue);
      expect(reportAfter.detectedStackId, equals('node-express'));
      expect(reportAfter.hasEntrypoint, isTrue);
      expect(reportAfter.scriptCount, greaterThanOrEqualTo(2));
      expect(reportAfter.defaultPort, equals(3000));

      final text = reportAfter.formatText();
      expect(text, contains('=== Dev Stack Diagnostics (Doctor) ==='));
      expect(text, contains('Detected Stack: Node.js + Express REST API'));
      expect(text, contains('package.json: FOUND'));
      expect(text, contains('Entrypoint: FOUND (index.js)'));
    });

    test('CommandService handles stack-list', () async {
      final res = await commandService.execute('stack-list');
      expect(res.isError, isFalse);
      expect(res.output, contains('=== Available Dev Stack Presets ==='));
      expect(res.output, contains('node-express'));
      expect(res.output, contains('static-web'));
      expect(res.output, contains('react-ts'));
      expect(res.output, contains('stack-init <stack-id>'));
    });

    test('CommandService handles stack-info with and without arguments', () async {
      final bare = await commandService.execute('stack-info');
      expect(bare.output, contains('Usage: stack-info <stack-id>'));

      final invalid = await commandService.execute('stack-info unknown-stack');
      expect(invalid.output, contains('Unknown stack preset: "unknown-stack"'));

      final valid = await commandService.execute('stack-info node-express');
      expect(valid.isError, isFalse);
      expect(valid.output, contains('=== Dev Stack: Node.js + Express REST API ==='));
      expect(valid.output, contains('Default Port: 3000'));
      expect(valid.output, contains('Template Files:'));
      expect(valid.output, contains('index.js'));
    });

    test('CommandService handles stack-init with scaffolding', () async {
      final bare = await commandService.execute('stack-init');
      expect(bare.output, contains('Usage: stack-init <stack-id>'));

      final res = await commandService.execute('stack-init node-express');
      expect(res.isError, isFalse);
      expect(res.output, contains('Successfully scaffolded "Node.js + Express REST API"'));
      expect(res.output, contains('index.js'));

      // Check npm-ls immediately sees the express dependency from newly created package.json
      final npmLs = await commandService.execute('npm ls');
      expect(npmLs.output, contains('express@^4.19.2 (UNMET DEPENDENCY)'));

      // Conflict without -f
      final conflict = await commandService.execute('stack-init node-express');
      expect(conflict.output, contains('already contains package.json'));

      // Force overwrite with -f
      final force = await commandService.execute('stack-init node-express -f');
      expect(force.isError, isFalse);
      expect(force.output, contains('Successfully scaffolded "Node.js + Express REST API"'));
    });

    test('CommandService handles stack-doctor', () async {
      await commandService.execute('stack-init static-web -f');

      final doc = await commandService.execute('stack-doctor');
      expect(doc.isError, isFalse);
      expect(doc.output, contains('=== Dev Stack Diagnostics (Doctor) ==='));
      expect(doc.output, contains('Detected Stack: Static Web (HTML/CSS/JS)'));
      expect(doc.output, contains('package.json: FOUND'));
      expect(doc.output, contains('Entrypoint: FOUND (index.html)'));
      expect(doc.output, contains('Default Dev Port: 8080'));
    });

    test('TermodeEngine headless bridge facade provides programmatic access', () async {
      final engine = TermodeEngine.instance;
      await engine.initialize(baseDir: tempDir);
      expect(engine.isInitialized, isTrue);

      // Verify services accessors
      expect(engine.workspaces, isNotNull);
      expect(engine.npm, isNotNull);
      expect(engine.stacks, isNotNull);
      expect(engine.packages, isNotNull);
      expect(engine.sessions, isNotNull);

      // Programmatic execution
      final result = await engine.execute(
        'stack-info react-ts',
        workingDirectory: projectDir.path,
      );
      expect(result.isError, isFalse);
      expect(result.output, contains('React + TypeScript (Web)'));

      // Diagnostics aggregation
      final diag = await engine.diagnostics(workingDirectory: projectDir.path);
      expect(diag.containsKey('activeWorkingDirectory'), isTrue);
      expect(diag.containsKey('milestone'), isTrue);
      expect(diag['milestone'], equals('v0.68'));
      expect(diag.containsKey('runtimes'), isTrue);
      expect(diag['runtimes'].containsKey('node'), isTrue);
      expect(diag['runtimes'].containsKey('npm'), isTrue);
      expect(diag.containsKey('stack'), isTrue);

      // Session creation
      final session = engine.createSession(
        name: 'calypso-session',
        workingDirectory: projectDir.path,
      );
      expect(session.name, equals('calypso-session'));
      expect(session.preferredWorkingDirectory, equals(projectDir.path));
    });
  });
}
