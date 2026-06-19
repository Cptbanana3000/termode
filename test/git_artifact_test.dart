import 'dart:convert';
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

  group('v0.47 Git Artifact Acquisition / Build Pipeline', () {
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
      await File(
        RuntimeArtifactRegistryService.gitProjectManifestPath('arm64-v8a'),
      ).delete().catchError((_) => File(''));
      final filesDir = Directory(
        RuntimeArtifactRegistryService.gitProjectFilesRoot('arm64-v8a'),
      );
      if (await filesDir.exists()) {
        await filesDir.delete(recursive: true);
      }
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
        expect(out, contains('git-artifact pipeline'));
        expect(out, contains('git-artifact bundle-status'));
        expect(out, contains('git-artifact smoke-plan'));
        expect(out, contains('git-workspace-smoke-plan'));
      }
    });

    test('git-artifact status reports template-only or unavailable', () async {
      final result = await commandService.execute('git-artifact status');
      expect(result.output, contains('=== Git Artifact Status ==='));
      expect(result.output, contains('Current ABI: arm64-v8a'));
      expect(result.output, contains('Artifact available: no'));
      expect(result.output, contains('Installable: no'));
      expect(result.output, contains('Template present:'));
      expect(
        result.output,
        anyOf(
          contains('Overall: TEMPLATE_ONLY'),
          contains('Overall: UNAVAILABLE'),
        ),
      );
    });

    test('git-artifact info explains requirement', () async {
      final result = await commandService.execute('git-artifact info');
      expect(result.output, contains('=== Git Artifact Info ==='));
      expect(result.output, contains('verified, ABI-matched Git package'));
      expect(result.output, contains('git --version'));
      expect(result.output, contains('This build has it: no'));
      expect(result.output, contains('git-artifact bundle-status'));
    });

    test('git-artifact manifest reports template state', () async {
      final result = await commandService.execute('git-artifact manifest');
      expect(
        result.output,
        contains('Git artifact manifest is not available in this build.'),
      );
      expect(result.output, contains('Template path:'));
      expect(result.output, contains('Installable: no'));
    });

    test('git-artifact verify when missing', () async {
      final result = await commandService.execute('git-artifact verify');
      expect(result.output, contains('=== Git Artifact Verify ==='));
      expect(result.output, contains('Nothing installable to verify'));
      expect(result.output, contains('git-artifact bundle-status'));
    });

    test('git-artifact doctor reports missing artifact as non-fatal', () async {
      final result = await commandService.execute('git-artifact doctor');
      expect(result.output, contains('=== Git Artifact Doctor ==='));
      expect(result.output, contains('Current ABI: arm64-v8a'));
      expect(
        result.output,
        anyOf(
          contains('Artifact: TEMPLATE_ONLY'),
          contains('Artifact: UNAVAILABLE'),
        ),
      );
      expect(result.output, contains('Manifest: missing'));
      expect(result.output, contains('not an app failure'));
      expect(result.isError, isFalse);
    });

    test(
      'git-artifact pipeline/requirements/sources/next explain v0.47 path',
      () async {
        final pipeline = await commandService.execute('git-artifact pipeline');
        final requirements = await commandService.execute(
          'git-artifact requirements',
        );
        final sources = await commandService.execute('git-artifact sources');
        final next = await commandService.execute('git-artifact next');

        expect(pipeline.output, contains('=== Git Artifact Pipeline ==='));
        expect(pipeline.output, contains('manifest.template.json'));
        expect(requirements.output, contains('Required manifest fields'));
        expect(
          requirements.output,
          contains('TEMPLATE_ONLY is not installable'),
        );
        expect(sources.output, contains('termode-built'));
        expect(sources.output, contains('copied Termux binaries'));
        expect(next.output, contains('Current state:'));
        expect(
          next.output,
          contains('v0.50 Git Artifact Production / Trusted Build'),
        );
        expect(next.output, contains('docs/GIT_ARM64_ARTIFACT_PIPELINE.md'));
        expect(
          next.output,
          contains('Do not download or execute unknown Git binaries.'),
        );
      },
    );

    test('git-exec-probe when Git not installed', () async {
      final result = await commandService.execute('git-exec-probe');
      expect(result.output, contains('Git is not installed yet.'));
      expect(result.output, contains('git-artifact bundle-status'));
      expect(result.output, contains('runtime-pkg install git'));
      expect(result.output, isNot(contains('git version')));
    });

    test('git-smoke-test when Git not installed', () async {
      final result = await commandService.execute('git-smoke-test');
      expect(result.output, contains('Git is not installed'));
      expect(result.output, contains('runtime-pkg install git'));
    });

    test('git-workspace-smoke-plan is blocked until Git exists', () async {
      final result = await commandService.execute('git-workspace-smoke-plan');
      expect(result.output, contains('=== Git Workspace Smoke Plan ==='));
      expect(result.output, contains('Blocked: missing trusted Git artifact.'));
      expect(result.output, contains('workspace-init gittests'));
      expect(result.output, contains('git commit -m "Initial commit"'));
      expect(result.isError, isFalse);
    });

    test('git-status and git-doctor include artifact unavailable', () async {
      final status = await commandService.execute('git-status');
      expect(status.output, contains('Artifact state:'));
      expect(status.output, contains('Overall: PLANNED'));

      final doctor = await commandService.execute('git-doctor');
      expect(doctor.output, contains('Git artifact:'));
      expect(doctor.output, contains('Overall: PLANNED'));
      expect(doctor.isError, isFalse);
    });

    test('git-version still does not fake Git', () async {
      final result = await commandService.execute('git-version');
      expect(result.output, contains('Git is not installed yet.'));
      expect(result.output, isNot(contains('git version')));
    });

    test('runtime-install status mentions Git artifact state', () async {
      final result = await commandService.execute('runtime-install status');
      expect(result.output, contains('Git artifact:'));
      expect(result.output, contains('Real Git installed: no'));
      expect(result.output, contains('Git execution: not verified'));
    });

    test(
      'git-artifact bundle commands report missing/template bundle',
      () async {
        final status = await commandService.execute(
          'git-artifact bundle-status',
        );
        final plan = await commandService.execute('git-artifact bundle-plan');
        final check = await commandService.execute('git-artifact bundle-check');
        final smoke = await commandService.execute('git-artifact smoke-plan');

        expect(status.output, contains('=== Git Bundle Status ==='));
        expect(status.output, contains('Project artifact:'));
        expect(status.output, contains('Bundled artifact:'));
        expect(status.output, contains('Installable: no'));
        expect(status.output, contains('Overall: NOT READY'));
        expect(
          plan.output,
          contains('Place files under tools/runtime-artifacts/git/<abi>/files'),
        );
        expect(plan.output, contains('Run git --version'));
        expect(plan.output, contains('docs/GIT_ARM64_ARTIFACT_PIPELINE.md'));
        expect(check.output, contains('=== Git Bundle Check ==='));
        expect(
          check.output,
          anyOf(
            contains('Overall: TEMPLATE_ONLY'),
            contains('Overall: UNAVAILABLE'),
          ),
        );
        expect(smoke.output, contains('=== Git Smoke Plan ==='));
        expect(smoke.output, contains('Git is not installed yet.'));
        expect(smoke.output, contains('git-artifact bundle-status'));
      },
    );

    test('project artifact manifest with missing files is INVALID', () async {
      final manifest = {
        'name': 'git',
        'version': '2.44.0',
        'kind': 'native-tool',
        'abi': 'arm64-v8a',
        'command': 'git',
        'entrypoint': 'bin/git',
        'source': 'termode-built',
        'source_url': 'https://example.invalid/git-source',
        'build_method': 'termode test fixture',
        'license': 'GPL-2.0-only',
        'trusted_by': 'Termode',
        'verification_command': 'git --version',
        'smoke_tests': ['git --version'],
        'dependencies': <String>[],
        'created_at': '2026-06-19T00:00:00Z',
        'files': [
          {
            'path': 'bin/git',
            'sha256': List.filled(64, 'a').join(),
            'bytes': 10,
          },
        ],
      };
      final manifestFile = File(
        RuntimeArtifactRegistryService.gitProjectManifestPath('arm64-v8a'),
      );
      await manifestFile.parent.create(recursive: true);
      await manifestFile.writeAsString(jsonEncode(manifest));

      final status = await RuntimeArtifactRegistryService()
          .projectGitArtifactStatus();
      final check = await commandService.execute('git-artifact bundle-check');

      expect(status.status, 'INVALID');
      expect(status.installable, isFalse);
      expect(status.reason, contains('artifact files directory missing'));
      expect(check.output, contains('Overall: INVALID'));

      final install = await commandService.execute('runtime-pkg install git');
      expect(install.isError, isTrue);
      expect(install.output, contains('Git artifact failed verification.'));
      expect(install.output, contains('git-artifact bundle-check'));
      expect(install.output, contains('docs/GIT_ARM64_ARTIFACT_PIPELINE.md'));
    });

    test('project artifact with matching checksum can be AVAILABLE', () async {
      final registry = RuntimeArtifactRegistryService();
      final filesRoot = Directory(
        RuntimeArtifactRegistryService.gitProjectFilesRoot('arm64-v8a'),
      );
      final gitFile = File('${filesRoot.path}/bin/git');
      await gitFile.parent.create(recursive: true);
      await gitFile.writeAsString(
        'real git placeholder bytes for checksum only',
      );
      final sha = registry.calculateSha256(await gitFile.readAsBytes());
      final manifest = {
        'name': 'git',
        'version': '2.44.0',
        'kind': 'native-tool',
        'abi': 'arm64-v8a',
        'command': 'git',
        'entrypoint': 'bin/git',
        'source': 'termode-built',
        'source_url': 'https://example.invalid/git-source',
        'build_method': 'termode test fixture',
        'license': 'GPL-2.0-only',
        'trusted_by': 'Termode',
        'verification_command': 'git --version',
        'smoke_tests': ['git --version'],
        'dependencies': <String>[],
        'created_at': '2026-06-19T00:00:00Z',
        'files': [
          {'path': 'bin/git', 'sha256': sha, 'bytes': await gitFile.length()},
        ],
      };
      final manifestFile = File(
        RuntimeArtifactRegistryService.gitProjectManifestPath('arm64-v8a'),
      );
      await manifestFile.parent.create(recursive: true);
      await manifestFile.writeAsString(jsonEncode(manifest));

      final status = await registry.projectGitArtifactStatus();
      final check = await commandService.execute('git-artifact bundle-check');

      expect(status.status, 'AVAILABLE');
      expect(status.installable, isTrue);
      expect(check.output, contains('Overall: AVAILABLE'));
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
        'source_url': 'https://example.invalid/git-source',
        'build_method': 'termode test fixture',
        'license': 'GPL-2.0-only',
        'trusted_by': 'Termode',
        'verification_command': 'git --version',
        'smoke_tests': ['git --version'],
        'dependencies': <String>[],
        'created_at': '2026-06-19T00:00:00Z',
        'files': [
          {
            'path': 'bin/git',
            'sha256': List.filled(64, 'a').join(),
            'bytes': 10,
          },
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

      final placeholder = Map<String, dynamic>.from(valid);
      placeholder['version'] = '0.0.0-template';
      placeholder['created_at'] = 'TEMPLATE_ONLY';
      placeholder['files'] = [
        {'path': 'bin/git', 'sha256': List.filled(64, '0').join(), 'bytes': 0},
      ];
      final placeholderErrors = registry.validateGitManifest(
        placeholder,
        'arm64-v8a',
      );
      expect(
        placeholderErrors,
        contains('placeholder manifest is not installable'),
      );
      expect(placeholderErrors, contains('placeholder checksum'));
      expect(placeholderErrors, contains('invalid file byte count'));
    });

    test('registry template state is not installable', () async {
      final status = await RuntimeArtifactRegistryService().gitArtifactStatus();
      expect(status.available, isFalse);
      expect(status.installable, isFalse);
      expect(['TEMPLATE_ONLY', 'UNAVAILABLE'], contains(status.status));
      expect(
        RuntimeArtifactRegistryService().validateGitTemplateManifest(),
        isEmpty,
      );
    });

    test(
      'catalog and host interception include git-artifact commands',
      () async {
        for (final command in [
          'git-artifact',
          'git-exec-probe',
          'git-smoke-test',
          'git-workspace-smoke-plan',
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
      },
    );

    test(
      'beta-candidate ready still succeeds when Git artifact missing',
      () async {
        final result = await commandService.execute('beta-candidate ready');
        expect(result.output, contains('Ready for beta testing.'));
        expect(result.isError, isFalse);
      },
    );
  });
}
