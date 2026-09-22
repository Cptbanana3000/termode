import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/runtime_artifact_registry_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v0.70 Node.js arm64 Authentic V8 Engine', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_node_test');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      commandService = CommandService(VirtualFileSystem(), 'node_test');

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
                  return {'abi': 'arm64-v8a', 'pid': 8888};
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

    test('command catalog includes node commands', () {
      expect(kTermodeCommands.contains('node'), isTrue);
      expect(kTermodeCommands.contains('node-status'), isTrue);
      expect(kTermodeCommands.contains('node-info'), isTrue);
      expect(kTermodeCommands.contains('node-doctor'), isTrue);
      expect(kTermodeCommands.contains('node-artifact'), isTrue);
    });

    test('node manifest template exists and has valid structure', () {
      final registry = RuntimeArtifactRegistryService();
      expect(registry.nodeTemplateExists(), isTrue);

      final template = registry.readNodeTemplateManifest();
      expect(template, isNotNull);
      expect(template!['name'], equals('node'));
      expect(template['kind'], equals('native-tool'));
      expect(template['command'], equals('node'));
      expect(template['abi'], equals('arm64-v8a'));
      expect(template['executable_strategy'], equals('native-library-dir'));
      expect(
        template['executable_package_name'],
        equals('libtermode_node_exec.so'),
      );
    });

    test('validateNodeManifest verifies fields correctly', () {
      final registry = RuntimeArtifactRegistryService();

      final validManifest = <String, dynamic>{
        'name': 'node',
        'version': '24.18.0',
        'kind': 'native-tool',
        'command': 'node',
        'abi': 'arm64-v8a',
        'entrypoint': 'bin/node',
        'logical_install_path': 'bin/node',
        'executable_strategy': 'native-library-dir',
        'executable_package_name': 'libtermode_node_exec.so',
        'source': 'upstream-termux-bionic',
        'files': [
          {'path': 'bin/node', 'sha256': 'a' * 64, 'bytes': 100}
        ],
      };

      final errors = registry.validateNodeManifest(validManifest, 'arm64-v8a');
      expect(errors, isEmpty);

      // Invalid name and command
      final invalidManifest = Map<String, dynamic>.from(validManifest)
        ..['name'] = 'not-node'
        ..['command'] = 'not-node';
      final invalidErrors = registry.validateNodeManifest(
        invalidManifest,
        'arm64-v8a',
      );
      expect(invalidErrors, contains('package name must be node'));
      expect(invalidErrors, contains('command must be node'));

      // Untrusted source
      final badSourceManifest = Map<String, dynamic>.from(validManifest)
        ..['source'] = 'random-untrusted';
      expect(
        registry.validateNodeManifest(badSourceManifest, 'arm64-v8a'),
        contains('unknown/untrusted source'),
      );

      // Unsafe path
      final badPathManifest = Map<String, dynamic>.from(validManifest)
        ..['entrypoint'] = '../escape/node'
        ..['logical_install_path'] = '../escape/node';
      expect(
        registry.validateNodeManifest(badPathManifest, 'arm64-v8a'),
        contains('invalid entrypoint'),
      );
    });

    test('node-doctor command returns honest diagnostic report', () async {
      final result = await commandService.execute('node-doctor');
      expect(result.output, contains('=== Node.js Diagnostics (Doctor) ==='));
      expect(result.output, contains('Package: node'));
      expect(result.output, contains('Artifact ABI: arm64-v8a'));
      expect(result.output, contains('NODE_PATH Integration: enabled'));
      expect(result.output, contains('Milestone: v0.70 (Authentic Node.js V8 Runtime & Full Bundling)'));
    });

    test('node-artifact status, verify, and template commands work', () async {
      final statusResult = await commandService.execute('node-artifact status');
      expect(statusResult.output, contains('=== Node.js Artifact Status ==='));
      expect(statusResult.output, contains('ABI: arm64-v8a'));

      final verifyResult = await commandService.execute('node-artifact verify');
      expect(verifyResult.output, contains('valid'));

      final templateResult =
          await commandService.execute('node-artifact template');
      expect(templateResult.output, contains('"name": "node"'));
      expect(
        templateResult.output,
        contains('"executable_package_name": "libtermode_node_exec.so"'),
      );
    });

    test('node-status and node-info output informative messages', () async {
      final status = await commandService.execute('node-status');
      expect(status.output, contains('Package: node'));
      expect(status.output, contains('Milestone: v0.70 (Authentic Node.js V8 Runtime & Full Bundling)'));

      final info = await commandService.execute('node-info');
      expect(info.output, contains('Package: node'));
      expect(info.output, contains('Node.js JavaScript runtime'));
    });

    test('bare node command reports uninstalled state guidance without faking',
        () async {
      final result = await commandService.execute('node');
      expect(result.output, contains('Node.js is not installed yet.'));
      expect(result.output, contains('Run: runtime-pkg install node'));
      expect(result.output, contains('Run: node-artifact status'));
      expect(result.output, contains('Run: node-doctor'));
      expect(result.output, contains('v0.70 provides the authentic Google V8 Node.js arm64 execution engine.'));
    });

    test('node command dispatches through test hook when active', () async {
      RuntimeBinaryPackageService.nodeExecutorForTesting =
          (args, {workingDirectory, timeoutMs}) async {
        if (args.contains('--version')) {
          return NativeCommandResult(
            exitCode: 0,
            stdout: 'v24.18.0\n',
            stderr: '',
          );
        }
        if (args.contains('-e')) {
          final exprIdx = args.indexOf('-e') + 1;
          final expr = exprIdx < args.length ? args[exprIdx] : '';
          return NativeCommandResult(
            exitCode: 0,
            stdout: 'evaluated: $expr\n',
            stderr: '',
          );
        }
        return NativeCommandResult(exitCode: 0, stdout: 'ok', stderr: '');
      };

      final pkg = RuntimeBinaryPackageService();
      expect(await pkg.nodeInstalled(), isTrue);

      final versionResult = await commandService.execute('node --version');
      expect(versionResult.output, equals('v24.18.0'));

      final evalResult =
          await commandService.execute('node -e "console.log(42)"');
      expect(evalResult.output, contains('evaluated: console.log(42)'));
    });

    test('runtime-pkg install and verify node works in test environment', () async {
      RuntimeBinaryPackageService.nodeExecutorForTesting =
          (args, {workingDirectory, timeoutMs}) async {
        return NativeCommandResult(
          exitCode: 0,
          stdout: 'v24.18.0\n',
          stderr: '',
        );
      };

      final installResult = await commandService.execute('runtime-pkg install node');
      expect(installResult.output, contains('Installed: node'));
      expect(installResult.output, contains('Command: node'));
      expect(installResult.output, contains('Execution verified: yes'));

      final verifyResult = await commandService.execute('runtime-pkg verify node');
      expect(verifyResult.output, contains('Status: HEALTHY'));

      final removeResult = await commandService.execute('runtime-pkg remove node');
      expect(removeResult.output, contains('Removed: node'));
    });
  });
}
