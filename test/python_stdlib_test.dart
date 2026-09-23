import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/python_environment_service.dart';
import 'package:termode/services/runtime_artifact_registry_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/runtime_prefix_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PythonEnvironmentService pythonService;
  late RuntimePrefixService prefixService;
  late CommandService commandService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('termode_python_stdlib_test_');
    RuntimeBootstrapService().overrideBaseDir = tempDir;
    await RuntimeBootstrapService().init();
    await RuntimePrefixService().initPrefix();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.termode/native_shell'),
          (call) async {
            switch (call.method) {
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

    pythonService = PythonEnvironmentService();
    prefixService = RuntimePrefixService();
    commandService = CommandService(VirtualFileSystem(), 'test-stdlib-session');
    PythonEnvironmentService.pythonExecutorForTesting = null;
    RuntimeBinaryPackageService.pythonExecutorForTesting = null;
  });

  tearDown(() async {
    PythonEnvironmentService.pythonExecutorForTesting = null;
    RuntimeBinaryPackageService.pythonExecutorForTesting = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.termode/native_shell'),
          null,
        );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Milestone v0.76 Python Standard Library & REPL Tests', () {
    test('Standard library status checks report not installed initially in fresh prefix', () async {
      final installed = await pythonService.isStdlibInstalled();
      expect(installed, isFalse);

      final count = await pythonService.stdlibModuleCount();
      expect(count, equals(0));

      final report = await pythonService.doctor();
      expect(report.stdlibInstalled, isFalse);
      expect(report.stdlibModuleCount, equals(0));
      expect(report.stdlibStatus, contains('PENDING EXTRACTION'));
      expect(report.replStatus, contains('REQUIRES_STDLIB'));
    });

    test('verifyCoreModules audits required stdlib modules', () async {
      final results = await pythonService.verifyCoreModules();
      // sys is a built-in module in CPython core
      expect(results, equals(['sys']));
    });

    test('Standard library setup creates directory structure and reports progress', () async {
      // Create simulated stdlib files in prefix to test detection
      final paths = await prefixService.paths();
      final usrLib = paths['lib'] ?? '${paths['usr']}/lib';
      final pyLibDir = Directory('$usrLib/python3.14');
      await pyLibDir.create(recursive: true);

      // Create simulated core modules
      await File('${pyLibDir.path}/os.py').writeAsString('name = "posix"');
      await File('${pyLibDir.path}/json.py').writeAsString('def loads(): pass');
      await File('${pyLibDir.path}/sqlite3.py').writeAsString('def connect(): pass');
      await File('${pyLibDir.path}/ssl.py').writeAsString('class SSLContext: pass');
      await File('${pyLibDir.path}/encodings.py').writeAsString('# encodings');

      final installed = await pythonService.isStdlibInstalled();
      expect(installed, isTrue);

      final count = await pythonService.stdlibModuleCount();
      expect(count, greaterThanOrEqualTo(5));

      final coreAudit = await pythonService.verifyCoreModules();
      expect(coreAudit, contains('os'));
      expect(coreAudit, contains('sys'));
      expect(coreAudit, contains('json'));
      expect(coreAudit, contains('sqlite3'));
      expect(coreAudit, contains('ssl'));

      final report = await pythonService.doctor();
      expect(report.stdlibInstalled, isTrue);
      expect(report.stdlibModuleCount, greaterThanOrEqualTo(5));
      expect(report.stdlibStatus, contains('INSTALLED'));
    });

    test('setupStandardLibrary returns RuntimeBinaryPackageResult', () async {
      RuntimeBinaryPackageService.pythonExecutorForTesting =
          (args, {workingDirectory}) async => NativeCommandResult(
                stdout: 'Python 3.14.6\n',
                stderr: '',
                exitCode: 0,
              );
      final result = await pythonService.setupStandardLibrary();
      expect(result.output, contains('Installed runtime package: python'));
      expect(result.isError, isFalse);
    });

    test('CommandService python-setup reports stdlib setup details', () async {
      RuntimeBinaryPackageService.pythonExecutorForTesting =
          (args, {workingDirectory}) async => NativeCommandResult(
                stdout: 'Python 3.14.6\n',
                stderr: '',
                exitCode: 0,
              );
      final res = await commandService.execute('python-setup');
      expect(res.isError, isFalse);
      expect(res.output, contains('Installed runtime package: python'));
      expect(res.output, contains('Standard library:'));
    });

    test('RuntimeArtifactRegistryService validates python-stdlib.tar.gz asset existence', () async {
      final archiveBytes = await RuntimeArtifactRegistryService().readBundledPythonArchive();
      // On development machine, bundled asset is present in tools/
      expect(archiveBytes, isNotNull);
      expect(archiveBytes!.length, greaterThan(1000000)); // stdlib archive is > 10MB
    });

    test('Bundled companion shared libraries can be read from registry', () async {
      final reg = RuntimeArtifactRegistryService();
      final sslBytes = await reg.readBundledPythonFile('usr/lib/libssl.so.3');
      expect(sslBytes, isNotNull);
      expect(sslBytes!.length, greaterThan(10000));

      final sqliteBytes = await reg.readBundledPythonFile('usr/lib/libsqlite3.so');
      expect(sqliteBytes, isNotNull);
      expect(sqliteBytes!.length, greaterThan(10000));

      final readlineBytes = await reg.readBundledPythonFile('usr/lib/libreadline.so.8');
      expect(readlineBytes, isNotNull);
      expect(readlineBytes!.length, greaterThan(10000));
    });
  });
}
