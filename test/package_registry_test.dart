import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/termode.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone v0.85 Live Package Registries (npm & pip Network Downloads)', () {
    late Directory tempDir;
    late Directory projectDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_registry_test');
      projectDir = Directory('${tempDir.path}/workspace/app');
      await projectDir.create(recursive: true);

      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      TerminalSessionService().activeSession.preferredWorkingDirectory = projectDir.path;
      commandService = CommandService(VirtualFileSystem(), 'registry_test');

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
      PackageRegistryService.npmPingForTesting = null;
      PackageRegistryService.pypiPingForTesting = null;
      RuntimeBinaryPackageService.npmExecutorForTesting = null;
      RuntimeBinaryPackageService.pipExecutorForTesting = null;
      RuntimeBinaryPackageService.gitExecutorForTesting = null;
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('PackageRegistryService reports online status for npm and PyPI registries', () async {
      PackageRegistryService.npmPingForTesting = (url) async {
        return const RegistryEndpointStatus(
          name: 'npm',
          url: PackageRegistryService.defaultNpmRegistry,
          online: true,
          latencyMs: 85,
          statusCode: 200,
          message: 'OK',
        );
      };

      PackageRegistryService.pypiPingForTesting = (url) async {
        return const RegistryEndpointStatus(
          name: 'PyPI',
          url: PackageRegistryService.defaultPypiRegistry,
          online: true,
          latencyMs: 110,
          statusCode: 200,
          message: 'OK',
        );
      };

      final service = PackageRegistryService();
      final doctor = await service.doctor();

      expect(doctor.npmStatus.online, isTrue);
      expect(doctor.npmStatus.latencyMs, 85);
      expect(doctor.pypiStatus.online, isTrue);
      expect(doctor.pypiStatus.latencyMs, 110);
      expect(doctor.allOnline, isTrue);

      final text = doctor.formatText();
      expect(text, contains('=== Package Registries Diagnostic (Doctor) ==='));
      expect(text, contains('npm Registry:            ONLINE'));
      expect(text, contains('PyPI Registry:           ONLINE'));
      expect(text, contains('v0.85'));
    });

    test('PackageRegistryService handles offline or unreachable endpoints gracefully', () async {
      PackageRegistryService.npmPingForTesting = (url) async {
        return const RegistryEndpointStatus(
          name: 'npm',
          url: PackageRegistryService.defaultNpmRegistry,
          online: false,
          latencyMs: 5000,
          statusCode: null,
          message: 'SocketException: Connection refused',
        );
      };

      PackageRegistryService.pypiPingForTesting = (url) async {
        return const RegistryEndpointStatus(
          name: 'PyPI',
          url: PackageRegistryService.defaultPypiRegistry,
          online: false,
          latencyMs: 5000,
          statusCode: null,
          message: 'SocketException: Network is unreachable',
        );
      };

      final service = PackageRegistryService();
      final doctor = await service.doctor();

      expect(doctor.allOnline, isFalse);
      expect(doctor.npmStatus.online, isFalse);
      expect(doctor.pypiStatus.online, isFalse);

      final text = doctor.formatText();
      expect(text, contains('npm Registry:            OFFLINE'));
      expect(text, contains('PyPI Registry:           OFFLINE'));
      expect(text, contains('Overall Registries:      DEGRADED'));
    });

    test('registry-doctor and pkg-doctor CLI commands return diagnostic report', () async {
      PackageRegistryService.npmPingForTesting = (url) async {
        return const RegistryEndpointStatus(
          name: 'npm',
          url: PackageRegistryService.defaultNpmRegistry,
          online: true,
          latencyMs: 72,
          statusCode: 200,
          message: 'OK',
        );
      };
      PackageRegistryService.pypiPingForTesting = (url) async {
        return const RegistryEndpointStatus(
          name: 'PyPI',
          url: PackageRegistryService.defaultPypiRegistry,
          online: true,
          latencyMs: 95,
          statusCode: 200,
          message: 'OK',
        );
      };

      final res1 = await commandService.execute('registry-doctor');
      expect(res1.isError, isFalse);
      expect(res1.output, contains('=== Package Registries Diagnostic (Doctor) ==='));
      expect(res1.output, contains('npm Registry:            ONLINE'));
      expect(res1.output, contains('PyPI Registry:           ONLINE'));

      final res2 = await commandService.execute('pkg-doctor');
      expect(res2.isError, isFalse);
      expect(res2.output, contains('=== Package Registries Diagnostic (Doctor) ==='));
    });

    test('npm commands (install, audit, view, update) execute via authentic engine runner', () async {
      final executedArgs = <List<String>>[];
      RuntimeBinaryPackageService.npmExecutorForTesting = (args, {workingDirectory}) async {
        executedArgs.add(args);
        if (args.contains('install')) {
          return NativeCommandResult(
            exitCode: 0,
            stdout: 'added 2 packages in 1s\n1 package is looking for funding',
            stderr: '',
          );
        }
        if (args.contains('audit')) {
          return NativeCommandResult(
            exitCode: 0,
            stdout: 'found 0 vulnerabilities',
            stderr: '',
          );
        }
        if (args.contains('view')) {
          return NativeCommandResult(
            exitCode: 0,
            stdout: 'is-odd@3.0.1 | MIT | deps: 1 | versions: 10',
            stderr: '',
          );
        }
        if (args.contains('update')) {
          return NativeCommandResult(
            exitCode: 0,
            stdout: 'up to date in 500ms',
            stderr: '',
          );
        }
        return NativeCommandResult(exitCode: 0, stdout: 'ok', stderr: '');
      };

      // 1. npm-install
      final installRes = await commandService.execute('npm-install is-odd');
      expect(installRes.output, contains('added 2 packages'));
      expect(installRes.shouldReloadShellHelpers, isTrue);

      // 2. npm i (alias)
      final installAlias = await commandService.execute('npm-i is-even');
      expect(installAlias.output, contains('added 2 packages'));

      // 3. npm-audit
      final auditRes = await commandService.execute('npm-audit');
      expect(auditRes.output, contains('found 0 vulnerabilities'));

      // 4. npm-view
      final viewRes = await commandService.execute('npm-view is-odd');
      expect(viewRes.output, contains('is-odd@3.0.1'));

      // 5. npm-update
      final updateRes = await commandService.execute('npm-update');
      expect(updateRes.output, contains('up to date'));
      expect(updateRes.shouldReloadShellHelpers, isTrue);

      expect(executedArgs.length, 5);
      expect(executedArgs[0], ['install', 'is-odd']);
      expect(executedArgs[1], ['install', 'is-even']);
      expect(executedArgs[2], ['audit']);
      expect(executedArgs[3], ['view', 'is-odd']);
      expect(executedArgs[4], ['update']);
    });

    test('pip commands (freeze, upgrade, outdated) execute via authentic engine runner', () async {
      final executedArgs = <List<String>>[];
      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        executedArgs.add(args);
        if (args.contains('--format=freeze')) {
          return NativeCommandResult(
            exitCode: 0,
            stdout: 'six==1.17.0\ntextwrap3==0.9.2\nurllib3==2.2.3',
            stderr: '',
          );
        }
        if (args.contains('--upgrade')) {
          return NativeCommandResult(
            exitCode: 0,
            stdout: 'Successfully installed textwrap3-0.9.2',
            stderr: '',
          );
        }
        if (args.contains('--outdated')) {
          return NativeCommandResult(
            exitCode: 0,
            stdout: 'Package Version Latest Type\n------- ------- ------ -----\nsix     1.16.0  1.17.0 wheel',
            stderr: '',
          );
        }
        return NativeCommandResult(exitCode: 0, stdout: 'ok', stderr: '');
      };

      // 1. pip-freeze
      final freezeRes = await commandService.execute('pip-freeze');
      expect(freezeRes.output, contains('six==1.17.0'));
      expect(freezeRes.output, contains('textwrap3==0.9.2'));

      // 2. pip-upgrade
      final upgradeRes = await commandService.execute('pip-upgrade textwrap3');
      expect(upgradeRes.output, contains('Successfully installed textwrap3-0.9.2'));
      expect(upgradeRes.shouldReloadShellHelpers, isTrue);

      // 3. pip-outdated
      final outdatedRes = await commandService.execute('pip-outdated');
      expect(outdatedRes.output, contains('six'));
      expect(outdatedRes.output, contains('1.16.0'));

      expect(executedArgs.length, 3);
      expect(executedArgs[0], ['list', '--format=freeze']);
      expect(executedArgs[1], ['install', '--user', '--upgrade', 'textwrap3']);
      expect(executedArgs[2], ['list', '--outdated']);
    });

    test('TermodeEngine exposes npm, pip, and registry programmatic services', () {
      final engine = TermodeEngine();
      expect(engine.npm, isA<NpmPackageService>());
      expect(engine.pip, isA<PipPackageService>());
      expect(engine.registry, isA<PackageRegistryService>());
    });

    test('Command catalog includes all new v0.85 commands for shell autocompletion', () {
      expect(kTermodeCommands, contains('registry-doctor'));
      expect(kTermodeCommands, contains('pkg-doctor'));
      expect(kTermodeCommands, contains('npm-install'));
      expect(kTermodeCommands, contains('npm-audit'));
      expect(kTermodeCommands, contains('npm-view'));
      expect(kTermodeCommands, contains('npm-update'));
      expect(kTermodeCommands, contains('pip-freeze'));
      expect(kTermodeCommands, contains('pip-upgrade'));
      expect(kTermodeCommands, contains('pip-outdated'));
    });

    test('Self-healing reconciliation refreshes stale executable_backing_path dynamically', () async {
      final binaryService = RuntimeBinaryPackageService();
      final usrDir = Directory('${tempDir.path}/files/usr');
      await usrDir.create(recursive: true);
      final binDir = Directory('${tempDir.path}/files/usr/bin');
      await binDir.create(recursive: true);
      final installedJson = File('${tempDir.path}/files/usr/var/termode/runtime-packages/installed.json');
      await installedJson.parent.create(recursive: true);

      // Create dummy native library directory (simulating newly installed APK)
      final dummyLibDir = Directory('${tempDir.path}/app_lib/arm64-v8a');
      await dummyLibDir.create(recursive: true);
      final dummyGitLib = File('${dummyLibDir.path}/libtermode_git_exec.so');
      await dummyGitLib.writeAsString('#!/system/bin/sh\necho git version 2.47.1\n');

      // Stale path from a previous APK install that no longer exists
      const staleBackingPath = '/data/app/~~stale_dir_123/base.apk!/lib/arm64-v8a/libtermode_git_exec.so';
      final staleMetadata = {
        'version': 1,
        'packages': {
          'git': {
            'package': 'git',
            'version': '2.47.1',
            'installed_at': DateTime.now().toIso8601String(),
            'logical_path': 'usr/bin/git',
            'executable_backing_path': staleBackingPath,
            'sha256': {
              'usr/bin/git': 'stale_checksum',
            },
            'files': [],
            'managed_files': [],
            'dependencies': [],
            'status': 'INSTALLED',
          }
        }
      };
      await installedJson.writeAsString(jsonEncode(staleMetadata));

      // Reconcile with native library directory
      await binaryService.reconcileNativeSymlinks(nativeLibraryDirOverride: dummyLibDir.path);

      // Verify installed.json was updated with existing path and valid checksum
      final updatedJson = jsonDecode(await installedJson.readAsString()) as Map<String, dynamic>;
      final gitPkg = (updatedJson['packages'] as Map<String, dynamic>)['git'] as Map<String, dynamic>;
      expect(gitPkg['executable_backing_path'], dummyGitLib.path);
      expect(gitPkg['sha256'], isNot('stale_checksum'));
      expect(gitPkg['status'], 'INSTALLED');

      RuntimeBinaryPackageService.gitExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(exitCode: 0, stdout: 'git version 2.47.1', stderr: '');
      };

      final verifyResult = await binaryService.verify('git', nativeLibraryDirOverride: dummyLibDir.path);
      expect(verifyResult.isError, isFalse);
      expect(verifyResult.output, contains('HEALTHY'));
    });
  });
}
