import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/python_environment_service.dart';
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
    tempDir = await Directory.systemTemp.createTemp('termode_python_test_');
    RuntimeBootstrapService().overrideBaseDir = tempDir;
    await RuntimeBootstrapService().init();
    await RuntimePrefixService().initPrefix();

    pythonService = PythonEnvironmentService();
    prefixService = RuntimePrefixService();
    commandService = CommandService(VirtualFileSystem(), 'test-session');
    PythonEnvironmentService.pythonExecutorForTesting = null;
  });

  tearDown(() async {
    PythonEnvironmentService.pythonExecutorForTesting = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Milestone v0.75 Python Environment Architecture Tests', () {
    test('RuntimePrefixService defines Python path hierarchy and PATH integration', () async {
      final paths = await prefixService.paths();
      expect(paths['pythonUserBase'], endsWith('/.local'));
      expect(paths['pythonUserBin'], endsWith('/.local/bin'));
      expect(paths['pythonUserLib'], endsWith('/.local/lib/python3.14/site-packages'));
      expect(paths['pythonLib'], endsWith('/usr/lib/python3.14'));
      expect(paths['pythonBin'], endsWith('/usr/bin/python3'));

      final pathEntries = await prefixService.pathEntries();
      expect(pathEntries, contains(paths['pythonUserBin']));

      final env = await prefixService.envMap();
      expect(env['PATH'], contains(paths['pythonUserBin']!));
      expect(env['PYTHONUSERBASE'], equals(paths['pythonUserBase']));
      expect(env['PYTHONHOME'], equals(paths['prefix']));
      expect(env['PYTHONPATH'], contains(paths['pythonLib']!));
      expect(env['PYTHONPATH'], contains(paths['pythonUserLib']!));
    });

    test('PythonEnvironmentService directories and PATH verification', () async {
      final userBase = await pythonService.userBaseDir();
      final userBin = await pythonService.userBinDir();
      final userSite = await pythonService.userSitePackagesDir();
      final prefixLib = await pythonService.prefixLibDir();

      expect(userBase, endsWith('/.local'));
      expect(userBin, endsWith('/.local/bin'));
      expect(userSite, contains('site-packages'));
      expect(prefixLib, endsWith('/usr/lib/python3.14'));

      final inPath = await pythonService.isUserBinInPath();
      expect(inPath, isTrue);
    });

    test('PythonDoctorReport provides comprehensive diagnostics adhering to GEMINI.md', () async {
      final report = await pythonService.doctor();

      expect(report.abi, equals('arm64-v8a'));
      expect(report.pythonUserBinInPath, isTrue);
      expect(report.bionicDependencies, contains('libssl.so.3'));
      expect(report.bionicDependencies, contains('libsqlite3.so'));
      expect(report.bionicDependencies, contains('libz.so.1'));
      expect(report.bionicDependencies, contains('libandroid-support.so'));
      expect(report.milestone, contains('v0.75'));

      final formatted = report.formatOutput();
      expect(formatted, contains('=== Python Environment Doctor ==='));
      expect(formatted, contains('Milestone:           v0.75'));
      expect(formatted, contains('Target ABI:          arm64-v8a (Bionic libc)'));
      expect(formatted, contains('Sherlock, Maigret -> user bin (~/.local/bin) in PATH: YES'));
    });

    test('PythonEnvironmentService formats environment report correctly', () async {
      final envReport = await pythonService.formatEnvReport();
      expect(envReport, contains('=== Python Environment Configuration ==='));
      expect(envReport, contains('PYTHONHOME:'));
      expect(envReport, contains('PYTHONUSERBASE:'));
      expect(envReport, contains('PYTHONPATH:'));
      expect(envReport, contains('in PATH: YES'));
      expect(envReport, contains('Target OSINT Tools:sherlock, maigret'));
    });

    test('executePython returns honest error when binary is not installed', () async {
      // In non-Android / clean test without binary
      if (!await pythonService.isPythonAvailable()) {
        final result = await pythonService.executePython(['--version']);
        expect(result.exitCode, equals(127));
        expect(result.stderr, contains('termode: python3: command not found'));
        expect(result.stderr, contains('python-doctor'));
      }
    });

    test('executePython honors testing executor hook', () async {
      PythonEnvironmentService.pythonExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'Python 3.11.8 (arm64-v8a, authentic)\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final result = await pythonService.executePython(['--version']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('Python 3.11.8'));
    });

    test('CommandCatalog registers Python commands', () {
      expect(kTermodeCommands, contains('python'));
      expect(kTermodeCommands, contains('python3'));
      expect(kTermodeCommands, contains('python-doctor'));
      expect(kTermodeCommands, contains('python-env'));
      expect(kTermodeCommands, contains('python-status'));
    });

    test('CommandService executes python-doctor, python-env, and python-status', () async {
      final docResult = await commandService.execute('python-doctor');
      expect(docResult.isError, isFalse);
      expect(docResult.output, contains('=== Python Environment Doctor ==='));
      expect(docResult.output, contains('Milestone:           v0.75'));

      final envResult = await commandService.execute('python-env');
      expect(envResult.isError, isFalse);
      expect(envResult.output, contains('=== Python Environment Configuration ==='));

      final statusResult = await commandService.execute('python-status');
      expect(statusResult.isError, isFalse);
      expect(statusResult.output, contains('=== Python Status ==='));
      expect(statusResult.output, contains('Target ABI: arm64-v8a'));
    });

    test('CommandService routes python / python3 commands', () async {
      PythonEnvironmentService.pythonExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'Python 3.14.6\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final execHookResult = await commandService.execute('python3 --version');
      expect(execHookResult.output, contains('Python 3.14.6'));
    });

    test('tools/runtime-artifacts/python/manifest.template.json is valid and conforms to schema', () {
      final file = File('tools/runtime-artifacts/python/manifest.template.json');
      expect(file.existsSync(), isTrue);

      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(json['name'], equals('python'));
      expect(json['abi'], equals('arm64-v8a'));
      expect(json['termode_milestone'], equals('v0.74'));
      expect(json['candidate'], isTrue);
      expect(json['template_only'], isTrue);
      expect(json['entrypoint'], equals('bin/python3'));
      expect(json['executable_package_name'], equals('libtermode_python_exec.so'));
      expect(json['dependencies'], contains('libssl.so'));
      expect(json['dependencies'], contains('libsqlite3.so'));
    });
  });
}
