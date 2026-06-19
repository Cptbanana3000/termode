import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_artifact_registry_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v0.46 Real Git Package Artifact / Execution Probe', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_gitart_test');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      commandService = CommandService(VirtualFileSystem(), 'gitart_test');

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
                  return {'abi': 'arm64-v8a', 'pid': 7777};
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
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            null,
          );
      SettingsService().loadFromJson(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('git-artifact default/help', () async {
      final bare = await commandService.execute('git-artifact');
      final help = await commandService.execute('git-artifact help');
      for (final out in [bare.output, help.output]) {
        expect(out, contains('=== Git Artifact ==='));
        expect(out, contains('git-artifact status'));
        expect(out, contains('git-artifact doctor'));
      }
    });

    test('git-artifact status reports UNAVAILABLE', () async {
      final result = await commandService.execute('git-artifact status');
      expect(result.output, contains('=== Git Artifact Status ==='));
      expect(result.output, contains('Current ABI: arm64-v8a'));
      expect(result.output, contains('Artifact available: no'));
      expect(result.output, contains('Installable: no'));
      expect(result.output, contains('Source: unavailable'));
      expect(result.output, contains('Overall: UNAVAILABLE'));
    });

    test('git-artifact info explains requirement', () async {
      final result = await commandService.execute('git-artifact info');
      expect(result.output, contains('=== Git Artifact Info ==='));
      expect(result.output, contains('verified, ABI-matched Git package'));
      expect(result.output, contains('git --version'));
      expect(result.output, contains('This build has it: no'));
    });

    test('git-artifact manifest missing', () async {
      final result = await commandService.execute('git-artifact manifest');
      expect(
        result.output,
        contains('Git artifact manifest is not available in this build.'),
      );
    });

    test('git-artifact verify when missing', () async {
      final result = await commandService.execute('git-artifact verify');
      expect(result.output, contains('=== Git Artifact Verify ==='));
      expect(result.output, contains('Artifact: unavailable'));
      expect(result.output, contains('Overall: UNAVAILABLE'));
    });

    test('git-artifact doctor reports UNAVAILABLE, not app failure', () async {
      final result = await commandService.execute('git-artifact doctor');
      expect(result.output, contains('=== Git Artifact Doctor ==='));
      expect(result.output, contains('Current ABI: arm64-v8a'));
      expect(result.output, contains('Artifact: UNAVAILABLE'));
      expect(result.output, contains('Manifest: missing'));
      expect(result.output, contains('not an app failure'));
      expect(result.output, contains('Overall: UNAVAILABLE'));
      expect(result.isError, isFalse);
    });

    test('git-exec-probe when Git not installed', () async {
      final result = await commandService.execute('git-exec-probe');
      expect(result.output, contains('Git is not installed yet.'));
      expect(result.output, contains('git-artifact status'));
      expect(result.output, contains('runtime-pkg install git'));
      expect(result.output, isNot(contains('git version')));
    });

    test('git-smoke-test when Git not installed', () async {
      final result = await commandService.execute('git-smoke-test');
      expect(result.output, contains('Git is not installed'));
      expect(result.output, contains('runtime-pkg install git'));
    });

    test('git-status and git-doctor include artifact unavailable', () async {
      final status = await commandService.execute('git-status');
      expect(status.output, contains('Artifact: unavailable'));
      expect(status.output, contains('Overall: PLANNED'));

      final doctor = await commandService.execute('git-doctor');
      expect(doctor.output, contains('Git artifact: unavailable'));
      expect(doctor.output, contains('Overall: PLANNED'));
      expect(doctor.isError, isFalse);
    });

    test('git-version still does not fake Git', () async {
      final result = await commandService.execute('git-version');
      expect(result.output, contains('Git is not installed yet.'));
      expect(result.output, isNot(contains('git version')));
    });

    test('runtime-install status mentions Git artifact unavailable', () async {
      final result = await commandService.execute('runtime-install status');
      expect(result.output, contains('Git artifact: unavailable'));
      expect(result.output, contains('Real Git installed: no'));
    });

    test('Git manifest validation rejects unsafe manifests', () {
      final registry = RuntimeArtifactRegistryService();
      final valid = {
        'name': 'git',
        'version': '2.44.0',
        'kind': 'native-tool',
        'abi': 'arm64-v8a',
        'command': 'git',
        'entrypoint': 'bin/git',
        'source': 'termode-vendored',
        'files': [
          {'path': 'bin/git', 'sha256': List.filled(64, 'a').join(), 'bytes': 10},
        ],
      };
      expect(registry.validateGitManifest(valid, 'arm64-v8a'), isEmpty);

      final absolute = Map<String, dynamic>.from(valid);
      absolute['files'] = [
        {'path': '/system/bin/git', 'sha256': List.filled(64, 'a').join()},
      ];
      expect(
        registry.validateGitManifest(absolute, 'arm64-v8a'),
        contains('unsafe file path'),
      );

      final traversal = Map<String, dynamic>.from(valid);
      traversal['entrypoint'] = '../git';
      expect(
        registry.validateGitManifest(traversal, 'arm64-v8a'),
        contains('invalid entrypoint'),
      );

      final untrusted = Map<String, dynamic>.from(valid);
      untrusted['source'] = 'random-internet';
      expect(
        registry.validateGitManifest(untrusted, 'arm64-v8a'),
        contains('unknown/untrusted source'),
      );

      final badKind = Map<String, dynamic>.from(valid);
      badKind['kind'] = 'script-tool';
      expect(
        registry.validateGitManifest(badKind, 'arm64-v8a'),
        contains('kind must be native-tool'),
      );

      final badAbi = Map<String, dynamic>.from(valid);
      badAbi['abi'] = 'mips';
      expect(
        registry.validateGitManifest(badAbi, 'arm64-v8a'),
        contains('unsupported abi'),
      );
    });

    test('catalog and host interception include git-artifact commands', () async {
      for (final command in [
        'git-artifact',
        'git-exec-probe',
        'git-smoke-test',
      ]) {
        expect(kTermodeCommands, contains(command));
      }

      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('git-artifact status');
      await sessionService.executeCommand('git-exec-probe');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('=== Git Artifact Status ==='));
      expect(output, contains('Git is not installed yet.'));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });

    test('beta-candidate ready still succeeds when Git artifact missing', () async {
      final result = await commandService.execute('beta-candidate ready');
      expect(result.output, contains('Ready for beta testing.'));
      expect(result.isError, isFalse);
    });
  });
}
