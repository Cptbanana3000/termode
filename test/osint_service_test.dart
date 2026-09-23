import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/osint_service.dart';
import 'package:termode/services/package_manager_service.dart';
import 'package:termode/services/python_environment_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/runtime_prefix_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late OsintService osintService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('termode_osint_test_');
    RuntimeBootstrapService().overrideBaseDir = tempDir;
    await RuntimeBootstrapService().init();
    await RuntimePrefixService().initPrefix();

    final homeDir = Directory('${tempDir.path}/files/home');
    final usrDir = Directory('${tempDir.path}/files/usr');
    final binDir = Directory('${tempDir.path}/files/usr/bin');
    final tmpDir = Directory('${tempDir.path}/files/tmp');
    final sitePackagesDir = Directory('${tempDir.path}/files/usr/lib/python3.14/site-packages');
    final userSiteDir = Directory('${tempDir.path}/files/home/.local/lib/python3.14/site-packages');

    await homeDir.create(recursive: true);
    await usrDir.create(recursive: true);
    await binDir.create(recursive: true);
    await tmpDir.create(recursive: true);
    await sitePackagesDir.create(recursive: true);
    await userSiteDir.create(recursive: true);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.termode/native_shell'),
          (call) async {
            switch (call.method) {
              case 'getDiagnostics':
                return {'abi': 'arm64-v8a', 'pid': 1234};
              case 'getPaths':
                return {
                  'home': homeDir.path,
                  'usr': usrDir.path,
                  'bin': binDir.path,
                  'tmp': tmpDir.path,
                };
            }
            return null;
          },
        );

    osintService = OsintService();
    osintService.osintDoctorProbeForTesting = null;
    osintService.sherlockExecutorForTesting = null;
    PythonEnvironmentService.pythonExecutorForTesting = null;
    RuntimeBinaryPackageService.pipExecutorForTesting = null;
  });

  tearDown(() async {
    osintService.osintDoctorProbeForTesting = null;
    osintService.sherlockExecutorForTesting = null;
    PythonEnvironmentService.pythonExecutorForTesting = null;
    RuntimeBinaryPackageService.pipExecutorForTesting = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.termode/native_shell'),
          null,
        );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('OsintDoctorReport Model', () {
    test('reports full readiness when all pure-Python OSINT deps are present', () {
      const report = OsintDoctorReport(
        pythonAvailable: true,
        pythonVersion: '3.14.6',
        pipAvailable: true,
        pipVersion: '26.2.1',
        requestsAvailable: true,
        requestsVersion: '2.34.2',
        requestsFuturesAvailable: true,
        requestsFuturesVersion: '1.1.0',
        coloramaAvailable: true,
        coloramaVersion: '0.4.6',
        pySocksAvailable: true,
        pySocksVersion: '1.7.1',
        sherlockAvailable: true,
        sherlockVersion: '0.16.2',
        sherlockSitesCount: 431,
        maigretAvailable: false,
        maigretStatus: 'LIMITED: C extensions require compilation',
        milestone: OsintService.currentMilestone,
      );

      expect(report.sherlockReady, isTrue);
      final json = report.toJson();
      expect(json['sherlock_ready'], isTrue);
      expect(json['sherlock_sites_count'], 431);

      final text = report.formatText();
      expect(text, contains('v0.78'));
      expect(text, contains('431 targets loaded'));
      expect(text, contains('READY (Sherlock operational)'));
    });

    test('reports NOT READY when dependencies are missing', () {
      const report = OsintDoctorReport(
        pythonAvailable: true,
        pythonVersion: '3.14.6',
        pipAvailable: true,
        pipVersion: '26.2.1',
        requestsAvailable: false,
        requestsFuturesAvailable: false,
        coloramaAvailable: false,
        pySocksAvailable: false,
        sherlockAvailable: false,
        sherlockSitesCount: 0,
        maigretAvailable: false,
        maigretStatus: 'LIMITED',
        milestone: OsintService.currentMilestone,
      );

      expect(report.sherlockReady, isFalse);
      final text = report.formatText();
      expect(text, contains('NEEDS SETUP (Run: osint-setup)'));
      expect(text, contains('Sherlock (sherlock-project): NOT INSTALLED'));
    });
  });

  group('OsintService Doctor Probing', () {
    test('returns uninstalled status when Python is unavailable', () async {
      PythonEnvironmentService.pythonExecutorForTesting = (args, {workingDirectory, timeoutMs = 30000}) async {
        return NativeCommandResult(stdout: '', stderr: 'python3: not found', exitCode: 127);
      };

      final report = await osintService.doctor();
      expect(report.pythonAvailable, isFalse);
      expect(report.sherlockReady, isFalse);
    });

    test('parses authentic Python probe output correctly', () async {
      // Create installed.json indicating python is installed
      final usrDir = Directory('${tempDir.path}/files/usr');
      final installedFile = File('${usrDir.path}/installed.json');
      await installedFile.writeAsString(jsonEncode({
        'packages': {
          'python': {'version': '3.14.6', 'entrypoint': 'usr/bin/python3'},
          'pip': {'version': '26.2.1', 'entrypoint': 'usr/bin/pip3'},
        }
      }));

      PythonEnvironmentService.pythonExecutorForTesting = (args, {workingDirectory, timeoutMs = 30000}) async {
        if (args.contains('-c')) {
          final probeJson = jsonEncode({
            'requests': '2.34.2',
            'requests_futures': '1.1.0',
            'colorama': '0.4.6',
            'socks': '1.7.1',
            'sherlock_project': '0.16.2',
            'sherlock_sites': 431,
            'maigret': null,
          });
          return NativeCommandResult(
            stdout: 'OSINT_PROBE_JSON:$probeJson\n',
            stderr: '',
            exitCode: 0,
          );
        }
        return NativeCommandResult(stdout: 'Python 3.14.6\n', stderr: '', exitCode: 0);
      };

      final report = await osintService.doctor();
      expect(report.pythonAvailable, isTrue);
      expect(report.requestsAvailable, isTrue);
      expect(report.requestsFuturesAvailable, isTrue);
      expect(report.coloramaAvailable, isTrue);
      expect(report.pySocksAvailable, isTrue);
      expect(report.sherlockAvailable, isTrue);
      expect(report.sherlockSitesCount, 431);
      expect(report.sherlockReady, isTrue);
    });
  });

  group('OsintService Setup & Execution', () {
    test('extracts bundled Sherlock archive during setup', () async {
      final usrDir = Directory('${tempDir.path}/files/usr');
      final installedFile = File('${usrDir.path}/installed.json');
      await installedFile.writeAsString(jsonEncode({
        'packages': {
          'python': {'version': '3.14.6', 'entrypoint': 'usr/bin/python3'},
        }
      }));

      PythonEnvironmentService.pythonExecutorForTesting = (args, {workingDirectory, timeoutMs = 30000}) async {
        return NativeCommandResult(stdout: 'OSINT_PROBE_JSON:{"sherlock_project":"0.16.2","requests":"2.34.2","sherlock_sites":431}\n', stderr: '', exitCode: 0);
      };

      final res = await osintService.setup(force: true);
      expect(res.exitCode, 0);
      expect(res.stdout, contains('OSINT Tooling Setup Complete'));
      expect(res.stdout, contains('Sherlock v0.16.2'));

      final sitePkgDir = Directory('${usrDir.path}/lib/python3.14/site-packages');
      expect(File('${sitePkgDir.path}/sherlock_project/sherlock.py').existsSync(), isTrue);
      expect(File('${sitePkgDir.path}/sherlock_project/resources/data.json').existsSync(), isTrue);
      expect(Directory('${sitePkgDir.path}/colorama').existsSync(), isTrue);
      expect(Directory('${sitePkgDir.path}/requests_futures').existsSync(), isTrue);
    });

    test('runSherlock dispatches arguments to python3 -m sherlock_project', () async {
      List<String>? capturedArgs;
      osintService.sherlockExecutorForTesting = (args, {workingDirectory, timeoutMs = 90000}) async {
        capturedArgs = args;
        return NativeCommandResult(
          stdout: '[*] Checking username octocat on: GitHub, Twitter, Reddit...\n[+] GitHub: https://github.com/octocat\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final res = await osintService.runSherlock(['octocat', '--print-found']);
      expect(res.exitCode, 0);
      expect(res.stdout, contains('[+] GitHub: https://github.com/octocat'));
      expect(capturedArgs, ['octocat', '--print-found']);
    });

    test('runMaigret prints honest limitation diagnostic when missing Bionic dependencies', () async {
      final res = await osintService.runMaigret(['octocat']);
      expect(res.exitCode, 0);
      expect(res.stdout, contains('engine limited'));
      expect(res.stdout, contains('curl-cffi'));
      expect(res.stdout, contains('sherlock <username>'));
    });
  });

  group('Shell Helpers Generation', () {
    test('generates W^X compliant sherlock and maigret functions in termode-shell-helpers.sh', () async {
      final usrDir = Directory('${tempDir.path}/files/usr');
      await usrDir.create(recursive: true);

      await PackageManagerService.updateShellHelpers();

      final helperFile = File('${usrDir.path}/termode-shell-helpers.sh');
      expect(helperFile.existsSync(), isTrue);

      final content = await helperFile.readAsString();
      expect(content, contains(r'sherlock() {'));
      expect(content, contains(r'python3 -m sherlock_project "$@"'));
      expect(content, contains(r'maigret() {'));
      expect(content, contains(r'python3 -m maigret "$@"'));
    });
  });

  group('CommandService OSINT Commands', () {
    test('dispatches osint-doctor, osint-setup, sherlock, and maigret', () async {
      osintService.osintDoctorProbeForTesting = ({workingDirectory}) async {
        return const OsintDoctorReport(
          pythonAvailable: true,
          pythonVersion: '3.14.6',
          pipAvailable: true,
          pipVersion: '26.2.1',
          requestsAvailable: true,
          requestsVersion: '2.34.2',
          requestsFuturesAvailable: true,
          requestsFuturesVersion: '1.1.0',
          coloramaAvailable: true,
          coloramaVersion: '0.4.6',
          pySocksAvailable: true,
          pySocksVersion: '1.7.1',
          sherlockAvailable: true,
          sherlockVersion: '0.16.2',
          sherlockSitesCount: 431,
          maigretAvailable: false,
          maigretStatus: 'LIMITED',
          milestone: OsintService.currentMilestone,
        );
      };

      osintService.sherlockExecutorForTesting = (args, {workingDirectory, timeoutMs = 90000}) async {
        return NativeCommandResult(
          stdout: 'Sherlock execution for ${args.join(" ")} OK',
          stderr: '',
          exitCode: 0,
        );
      };

      final cmdService = CommandService(VirtualFileSystem(), 'test-session');

      final docResult = await cmdService.execute('osint-doctor');
      expect(docResult.output, contains('=== OSINT Diagnostics (Doctor) ==='));
      expect(docResult.output, contains('431 targets loaded'));

      final sherlockEmpty = await cmdService.execute('sherlock');
      expect(sherlockEmpty.output, contains('Usage: sherlock <username>'));

      final sherlockScan = await cmdService.execute('sherlock octocat --print-found');
      expect(sherlockScan.output, contains('Sherlock execution for octocat --print-found OK'));

      final maigretResult = await cmdService.execute('maigret octocat');
      expect(maigretResult.output, contains('engine limited'));
    });
  });
}
