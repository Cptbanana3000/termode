import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/python_environment_service.dart';
import 'package:termode/services/runtime_artifact_registry_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/runtime_prefix_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CommandService commandService;
  late RuntimeArtifactRegistryService registryService;
  late RuntimeBinaryPackageService binpkgService;
  late RuntimePrefixService prefixService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('termode_pip_runtime_test_');
    RuntimeBootstrapService().overrideBaseDir = tempDir;
    await RuntimeBootstrapService().init();
    await RuntimePrefixService().initPrefix();

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

    commandService = CommandService(VirtualFileSystem(), 'pip-test-session');
    registryService = RuntimeArtifactRegistryService();
    binpkgService = RuntimeBinaryPackageService();
    prefixService = RuntimePrefixService();
    RuntimeBinaryPackageService.pipExecutorForTesting = null;
    RuntimeBinaryPackageService.pythonExecutorForTesting = null;
    PythonEnvironmentService.pythonExecutorForTesting = null;
  });

  tearDown(() async {
    RuntimeBinaryPackageService.pipExecutorForTesting = null;
    RuntimeBinaryPackageService.pythonExecutorForTesting = null;
    PythonEnvironmentService.pythonExecutorForTesting = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.termode/native_shell'),
          null,
        );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Milestone v0.77 Pip Artifact Manifest & Validation Tests', () {
    test('Project pip manifest exists and validates against schema', () {
      final manifest = registryService.readProjectPipManifest();
      expect(manifest, isNotNull);
      expect(manifest!['name'], equals('pip'));
      expect(manifest['version'], equals('26.2.1'));
      expect(manifest['abi'], equals('universal'));
      expect(manifest['archive'], equals('pip.tar.gz'));
      expect(manifest['archive_sha256'], isNotEmpty);
      expect(manifest['archive_bytes'], greaterThan(0));

      final errors = registryService.validatePipManifest(manifest);
      expect(errors, isEmpty, reason: errors.join('; '));
    });

    test('pipArtifactStatus reports correct file paths and status', () async {
      final status = await registryService.pipArtifactStatus();
      expect(status.manifestPresent, isTrue);
      expect(status.available, isTrue);
      expect(status.installable, isTrue);
      expect(status.status, equals('AVAILABLE'));
      expect(status.version, equals('26.2.1'));
      expect(status.archiveSha256, isNotNull);
    });
  });

  group('Milestone v0.77 RuntimeBinaryPackageService Pip Integration', () {
    test('available packages includes pip', () async {
      final available = await binpkgService.available();
      expect(available, contains('pip - Official Python Package Installer'));
    });

    test('info for pip returns comprehensive metadata', () async {
      final info = await binpkgService.info('pip');
      expect(info, contains('=== Runtime Package: pip ==='));
      expect(info, contains('Name: pip'));
      expect(info, contains('Kind: package-manager'));
      expect(info, contains('Current ABI: universal'));
      expect(info, contains('Authentic upstream pip 26.2.1 package installer'));
    });

    test('install pip extracts artifact and updates installed.json', () async {
      // Mock python executor to simulate verification probe
      RuntimeBinaryPackageService.pythonExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'Python 3.14.6\n',
          stderr: '',
          exitCode: 0,
        );
      };
      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'pip 26.2.1 from ${tempDir.path}/files/usr/lib/python3.14/site-packages/pip (python 3.14)\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final result = await binpkgService.install('pip');
      expect(result.isError, isFalse, reason: result.output);
      expect(result.output, contains('Installed runtime package: pip'));
      expect(result.output, contains('26.2.1'));

      // Check module was extracted
      final paths = await prefixService.paths();
      final pipInit = File('${paths['pythonPrefixSite']}/pip/__init__.py');
      expect(await pipInit.exists(), isTrue);

      // Check wrapper scripts created
      final pipBin = File('${paths['bin']}/pip');
      expect(await pipBin.exists(), isTrue);

      // Check installed.json recorded
      final isInstalled = await binpkgService.pipInstalled();
      expect(isInstalled, isTrue);

      final metadata = await binpkgService.installedPipMetadata();
      expect(metadata, isNotNull);
      expect(metadata!['name'], equals('pip'));
      expect(metadata['version'], equals('26.2.1'));
    });

    test('runPip executes via pipExecutorForTesting when configured', () async {
      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'pip 26.2.1\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final result = await binpkgService.runPip(['--version']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('pip 26.2.1'));
    });
  });

  group('Milestone v0.77 Pip Command Catalog & CommandService Tests', () {
    test('CommandCatalog registers all v0.77 pip commands', () {
      expect(kTermodeCommands, contains('pip'));
      expect(kTermodeCommands, contains('pip3'));
      expect(kTermodeCommands, contains('pip-doctor'));
      expect(kTermodeCommands, contains('pip-setup'));
      expect(kTermodeCommands, contains('pip-list'));
      expect(kTermodeCommands, contains('pip-show'));
      expect(kTermodeCommands, contains('pip-install'));
      expect(kTermodeCommands, contains('pip-uninstall'));
    });

    test('pip-doctor executes and outputs diagnostic report', () async {
      final result = await commandService.execute('pip-doctor');
      expect(result.isError, isFalse);
      expect(result.output, contains('=== pip Diagnostics (Doctor) ==='));
      expect(result.output, contains('SSL Certificate Dir:     /system/etc/security/cacerts'));
    });

    test('pip-setup installs pip and reports success', () async {
      RuntimeBinaryPackageService.pythonExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'Python 3.14.6\n',
          stderr: '',
          exitCode: 0,
        );
      };
      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'pip 26.2.1 from ${tempDir.path}/files/usr/lib/python3.14/site-packages/pip (python 3.14)\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final result = await commandService.execute('pip-setup');
      expect(result.isError, isFalse);
      expect(result.output, contains('Installed runtime package: pip'));
      expect(result.output, contains('26.2.1'));
    });

    test('pip bare / help output', () async {
      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'pip <command> [options]\nCommands:\n  install  Install packages.\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final bare = await commandService.execute('pip');
      expect(bare.isError, isFalse);
      expect(bare.output, contains('pip <command> [options]'));

      final help = await commandService.execute('pip --help');
      expect(help.isError, isFalse);
      expect(help.output, contains('pip <command> [options]'));
    });

    test('pip-list executes and displays installed packages', () async {
      final paths = await prefixService.paths();
      final pipDistInfo = Directory(
        '${paths['pythonPrefixSite']}/pip-26.2.1.dist-info',
      );
      await pipDistInfo.create(recursive: true);
      await File('${pipDistInfo.path}/METADATA').writeAsString('''Metadata-Version: 2.1
Name: pip
Version: 26.2.1
Summary: The PyPA recommended tool for installing Python packages.
''');

      final result = await commandService.execute('pip-list');
      expect(result.isError, isFalse);
      expect(result.output, contains('Package             Version'));
      expect(result.output, contains('pip                 26.2.1'));
    });

    test('pip-show displays package metadata or usage on missing argument', () async {
      final missingArg = await commandService.execute('pip-show');
      expect(missingArg.output, contains('Usage: pip-show <package-name>'));

      final paths = await prefixService.paths();
      final certDistInfo = Directory(
        '${paths['pythonUserLib']}/certifi-2024.2.2.dist-info',
      );
      await certDistInfo.create(recursive: true);
      await File('${certDistInfo.path}/METADATA').writeAsString('''Metadata-Version: 2.1
Name: certifi
Version: 2024.2.2
Summary: Python package for providing Mozilla CA Bundle.
License: MPL-2.0
''');

      final result = await commandService.execute('pip-show certifi');
      expect(result.isError, isFalse);
      expect(result.output, contains('certifi'));
      expect(result.output, contains('2024.2.2'));
    });

    test('pip-install executes with --user flag', () async {
      final missingArg = await commandService.execute('pip-install');
      expect(missingArg.output, contains('Usage: pip-install <package-spec>'));

      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'Successfully installed urllib3-2.2.1\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final result = await commandService.execute('pip-install urllib3');
      expect(result.isError, isFalse);
      expect(result.output, contains('Successfully installed urllib3-2.2.1'));
    });

    test('pip-uninstall executes with -y flag', () async {
      final missingArg = await commandService.execute('pip-uninstall');
      expect(missingArg.output, contains('Usage: pip-uninstall <package-name>'));

      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'Successfully uninstalled urllib3-2.2.1\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final result = await commandService.execute('pip-uninstall urllib3');
      expect(result.isError, isFalse);
      expect(result.output, contains('Successfully uninstalled urllib3-2.2.1'));
    });

    test('pip and pip3 route to pip execution with arguments', () async {
      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'pip 26.2.1 from site-packages\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final res1 = await commandService.execute('pip --version');
      expect(res1.isError, isFalse);
      expect(res1.output, contains('pip 26.2.1'));

      final res2 = await commandService.execute('pip3 --version');
      expect(res2.isError, isFalse);
      expect(res2.output, contains('pip 26.2.1'));
    });
  });

  group('Milestone v0.77 REAL PTY & TerminalSessionService Integration', () {
    test('TerminalSessionService intercepts pip commands when PTY active', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('pip-doctor');
      final output = session.lines.map((l) => l.text).join('\n');
      expect(output, contains('pip Diagnostics (Doctor)'));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });
  });
}
