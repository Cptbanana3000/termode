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
      final generatedBinDir = Directory('${filesDir.path}/bin');
      if (await generatedBinDir.exists()) {
        await generatedBinDir.delete(recursive: true);
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
        expect(out, contains('git-artifact production-status'));
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
      expect(result.output, contains('git-artifact production-status'));
      expect(result.output, contains('git-artifact bundle-status'));
    });

    test(
      'git-artifact production-status reports Path B without artifact',
      () async {
        final result = await commandService.execute(
          'git-artifact production-status',
        );
        expect(
          result.output,
          contains('=== Git Artifact Production Status ==='),
        );
        expect(result.output, contains('Path: B'));
        expect(result.output, contains('Artifact exists: no'));
        expect(result.output, contains('Git installable: no'));
        expect(result.output, contains('Git executable: no'));
        expect(result.output, contains('Production pipeline: ready'));
        expect(result.output, contains('docs/GIT_TRUSTED_BUILD.md'));
        expect(result.isError, isFalse);
      },
    );

    test('git-build commands report honest Path B state', () async {
      final status = await commandService.execute('git-build-status');
      final plan = await commandService.execute('git-build-plan');
      final requirements = await commandService.execute(
        'git-build-requirements',
      );
      final next = await commandService.execute('git-build-next');

      expect(status.output, contains('=== Git Build Status ==='));
      expect(status.output, contains('Target ABI: arm64-v8a'));
      expect(status.output, contains('Selected path: B'));
      expect(status.output, contains('Trusted source: staged (archive present)'));
      expect(status.output, contains('Dependencies: staged (zlib archive present)'));
      expect(status.output, contains('Git installed: no'));
      expect(status.output, contains('Overall: PARTIAL'));
      expect(plan.output, contains('=== Git Build Plan ==='));
      expect(plan.output, contains('prove git --version on Android'));
      expect(requirements.output, contains('Android SDK and NDK'));
      expect(requirements.output, contains('SHA-256'));
      expect(
        next.output,
        contains('Next: resolve Perl on the host environment.'),
      );
      expect(next.output, contains('v0.57 Git arm64 Build Attempt'));
    });

    test('git source and dependency commands report honest blockers', () async {
      final source = await commandService.execute('git-source-status');
      final sourcePlan = await commandService.execute('git-source-plan');
      final dependencies = await commandService.execute('git-deps-status');
      final dependencyPlan = await commandService.execute('git-deps-plan');
      final inputs = await commandService.execute('git-build-inputs');
      final blockers = await commandService.execute('git-build-blockers');
      final help = await commandService.execute('help');
      final commands = await commandService.execute('commands');

      expect(source.output, contains('=== Git Source Status ==='));
      expect(source.output, contains('Trusted source: staged (archive present)'));
      expect(source.output, contains('Overall: STAGED'));
      expect(sourcePlan.output, contains('Obtain the reviewed Git 2.44.0'));
      expect(sourcePlan.output, contains('verify_git_source.dart'));
      expect(dependencies.output, contains('zlib: required for minimal local Git'));
      expect(dependencies.output, contains('curl: later for HTTPS'));
      expect(dependencies.output, contains('Overall: STAGED'));
      expect(dependencyPlan.output, contains('git --version'));
      expect(dependencyPlan.output, contains('HTTPS clone'));
      expect(inputs.output, contains('Project-side only'));
      expect(inputs.output, contains('check_build_inputs.dart'));
      expect(blockers.output, contains('Perl missing from the recorded host environment'));
      expect(blockers.output, contains('not beta-fatal'));
      expect(help.output, contains('git-source-status'));
      expect(commands.output, contains('git-deps-plan'));
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
      'git-artifact pipeline/requirements/sources/next explain production path',
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
          contains('v0.57 Git arm64 Build Attempt'),
        );
        expect(next.output, contains('docs/GIT_TRUSTED_BUILD.md'));
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
        expect(plan.output, contains('docs/GIT_TRUSTED_BUILD.md'));
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
      expect(status.reason, contains('missing artifact file: bin/git'));
      expect(check.output, contains('Overall: INVALID'));

      final install = await commandService.execute('runtime-pkg install git');
      expect(install.isError, isTrue);
      expect(install.output, contains('Git artifact failed verification.'));
      expect(install.output, contains('git-artifact bundle-check'));
      expect(install.output, contains('docs/GIT_TRUSTED_BUILD.md'));
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

    test('v0.51 NDK build docs and helper scripts are present', () {
      expect(
        File('docs/GIT_ARTIFACT_PRODUCTION_STATUS.md').existsSync(),
        isTrue,
      );
      expect(File('docs/GIT_TRUSTED_BUILD.md').existsSync(), isTrue);
      expect(
        File('tools/git-build/prepare_git_artifact.dart').existsSync(),
        isTrue,
      );
      expect(
        File('tools/git-build/hash_git_artifact.dart').existsSync(),
        isTrue,
      );
      expect(
        File('tools/git-build/manifest.schema.example.json').existsSync(),
        isTrue,
      );
      expect(File('docs/GIT_NDK_BUILD_STATUS.md').existsSync(), isTrue);
      expect(File('docs/GIT_NDK_SOURCE_BUILD.md').existsSync(), isTrue);
      expect(File('tools/git-build/check_build_env.dart').existsSync(), isTrue);
      expect(File('tools/git-build/build_git_arm64.dart').existsSync(), isTrue);
      expect(
        File('docs/GIT_SOURCE_ACQUISITION_STATUS.md').existsSync(),
        isTrue,
      );
      expect(File('docs/GIT_SOURCE_ACQUISITION.md').existsSync(), isTrue);
      expect(File('docs/GIT_DEPENDENCY_PLAN.md').existsSync(), isTrue);
      expect(
        File('tools/git-build/build-inputs.example.json').existsSync(),
        isTrue,
      );
      expect(
        File('tools/git-build/build-inputs.schema.example.json').existsSync(),
        isTrue,
      );
      expect(
        File('tools/git-build/check_build_inputs.dart').existsSync(),
        isTrue,
      );
      expect(
        File('tools/git-build/verify_git_source.dart').existsSync(),
        isTrue,
      );
      expect(
        File('tools/git-build/check_dependencies.dart').existsSync(),
        isTrue,
      );
      expect(File('tools/git-build/build-inputs.json').existsSync(), isTrue);
    });

    test(
      'catalog and host interception include git-artifact commands',
      () async {
        for (final command in [
          'git-artifact',
          'git-build-status',
          'git-build-plan',
          'git-build-requirements',
          'git-build-next',
          'git-source-status',
          'git-source-plan',
          'git-deps-status',
          'git-deps-plan',
          'git-build-inputs',
          'git-build-blockers',
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
        await sessionService.executeCommand('git-artifact production-status');
        await sessionService.executeCommand('git-build-status');
        await sessionService.executeCommand('git-source-status');
        await sessionService.executeCommand('git-deps-status');
        await sessionService.executeCommand('git-exec-probe');

        final output = session.lines.map((line) => line.text).join('\n');
        expect(output, contains('=== Git Artifact Status ==='));
        expect(output, contains('=== Git Artifact Production Status ==='));
        expect(output, contains('=== Git Build Status ==='));
        expect(output, contains('=== Git Source Status ==='));
        expect(output, contains('=== Git Dependency Status ==='));
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
