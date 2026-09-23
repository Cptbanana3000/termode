import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/pip_package_service.dart';
import 'package:termode/services/python_environment_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/runtime_prefix_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PipPackageService pipService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('termode_pip_service_test_');
    RuntimeBootstrapService().overrideBaseDir = tempDir;
    await RuntimeBootstrapService().init();
    await RuntimePrefixService().initPrefix();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.termode/native_shell'),
          (call) async {
            switch (call.method) {
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

    pipService = PipPackageService();
    RuntimeBinaryPackageService.pipExecutorForTesting = null;
    PythonEnvironmentService.pythonExecutorForTesting = null;
  });

  tearDown(() async {
    RuntimeBinaryPackageService.pipExecutorForTesting = null;
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

  group('Milestone v0.77 PipPackageInfo & PipDoctorReport Models', () {
    test('PipPackageInfo model serializes and formats correctly', () {
      final pkg = PipPackageInfo(
        name: 'requests',
        version: '2.32.3',
        summary: 'Python HTTP for Humans.',
        location: '/data/data/com.termode/files/home/.local/lib/python3.14/site-packages',
        isUserSite: true,
        license: 'Apache-2.0',
        installer: 'pip',
        entryPoints: ['requests-cli'],
      );

      expect(pkg.name, equals('requests'));
      expect(pkg.version, equals('2.32.3'));
      expect(pkg.isUserSite, isTrue);
      expect(pkg.summary, equals('Python HTTP for Humans.'));
      expect(pkg.license, equals('Apache-2.0'));
      expect(pkg.installer, equals('pip'));
      expect(pkg.entryPoints, contains('requests-cli'));

      final json = pkg.toJson();
      expect(json['name'], equals('requests'));
      expect(json['version'], equals('2.32.3'));
      expect(json['is_user_site'], isTrue);
    });

    test('PipDoctorReport formatting reflects installation state', () {
      final uninstalled = PipDoctorReport(
        pythonAvailable: true,
        pythonStatus: 'AVAILABLE (CPython 3.14)',
        pipAvailable: false,
        pipStatus: 'NOT INSTALLED (Run: pip-setup)',
        workingDirectory: '/test/home/projects',
        userBase: '/test/home/.local',
        userBin: '/test/home/.local/bin',
        userBinExists: false,
        userBinInPath: true,
        userSitePackages: '/test/home/.local/lib/python3.14/site-packages',
        userSitePackagesExists: false,
        prefixSitePackages: '/test/usr/lib/python3.14/site-packages',
        prefixSitePackagesExists: false,
        totalInstalledPackagesCount: 0,
        userInstalledPackagesCount: 0,
        installedPackageNames: [],
        cacheDir: '/test/home/.cache/pip',
        cacheSizeBytes: 0,
        cacheSizeDisplay: '0.0 KB',
        sslCertDir: '/system/etc/security/cacerts',
        sslCertDirExists: true,
        milestone: 'v0.77 (Pip Package Management & User-Site Installation)',
      );

      final uninstalledOut = uninstalled.formatText();
      expect(uninstalledOut, contains('=== pip Diagnostics (Doctor) ==='));
      expect(uninstalledOut, contains('Milestone:               v0.77'));
      expect(uninstalledOut, contains('NOT INSTALLED (Run: pip-setup)'));
      expect(uninstalledOut, contains('SSL Certificate Dir:     /system/etc/security/cacerts (exists: YES)'));
      expect(uninstalledOut, contains('Status:                  STDLIB_READY (Run: pip-setup)'));

      final ready = PipDoctorReport(
        pythonAvailable: true,
        pythonStatus: 'AVAILABLE (CPython 3.14)',
        pipAvailable: true,
        pipStatus: 'INSTALLED (v26.2.1)',
        pipVersion: '26.2.1',
        workingDirectory: '/test/home/projects',
        userBase: '/test/home/.local',
        userBin: '/test/home/.local/bin',
        userBinExists: true,
        userBinInPath: true,
        userSitePackages: '/test/home/.local/lib/python3.14/site-packages',
        userSitePackagesExists: true,
        prefixSitePackages: '/test/usr/lib/python3.14/site-packages',
        prefixSitePackagesExists: true,
        totalInstalledPackagesCount: 1,
        userInstalledPackagesCount: 0,
        installedPackageNames: ['pip==26.2.1'],
        cacheDir: '/test/home/.cache/pip',
        cacheSizeBytes: 1048576,
        cacheSizeDisplay: '1.0 MB',
        sslCertDir: '/system/etc/security/cacerts',
        sslCertDirExists: true,
        milestone: 'v0.77 (Pip Package Management & User-Site Installation)',
      );

      final readyOut = ready.formatText();
      expect(readyOut, contains('pip Package Manager:     AVAILABLE (26.2.1)'));
      expect(readyOut, contains('Total Installed Packages: 1'));
      expect(readyOut, contains('Installed Distributions: pip==26.2.1'));
      expect(readyOut, contains('Status:                  READY'));
    });
  });

  group('Milestone v0.77 PipPackageService Core Methods', () {
    test('isPipAvailable returns false initially, true when module exists', () async {
      expect(await pipService.isPipAvailable(), isFalse);

      final prefixService = RuntimePrefixService();
      final paths = await prefixService.paths();
      final pipDir = Directory('${paths['pythonPrefixSite']}/pip');
      await pipDir.create(recursive: true);

      expect(await pipService.isPipAvailable(), isTrue);
    });

    test('doctor returns accurate uninstalled diagnostics', () async {
      final report = await pipService.doctor();
      expect(report.pipAvailable, isFalse);
      expect(report.userSitePackages, contains('.local/lib/python3.14/site-packages'));
      expect(report.userBin, contains('.local/bin'));
      expect(report.sslCertDir, equals('/system/etc/security/cacerts'));
    });

    test('listPackages parses dist-info directories', () async {
      final prefixService = RuntimePrefixService();
      final paths = await prefixService.paths();

      // Create fake dist-info in user site-packages
      final userDistInfo = Directory(
        '${paths['pythonUserLib']}/requests-2.32.3.dist-info',
      );
      await userDistInfo.create(recursive: true);
      final metaFile = File('${userDistInfo.path}/METADATA');
      await metaFile.writeAsString('''Metadata-Version: 2.1
Name: requests
Version: 2.32.3
Summary: Python HTTP for Humans.
License: Apache-2.0
''');

      final packages = await pipService.listPackages();
      expect(packages.length, equals(1));
      expect(packages[0].name, equals('requests'));
      expect(packages[0].version, equals('2.32.3'));
      expect(packages[0].summary, equals('Python HTTP for Humans.'));
      expect(packages[0].license, equals('Apache-2.0'));
      expect(packages[0].isUserSite, isTrue);

      final singlePkg = await pipService.showPackage('requests');
      expect(singlePkg, isNotNull);
      expect(singlePkg!.name, equals('requests'));
      expect(singlePkg.version, equals('2.32.3'));
    });

    test('installPackage executes with --user flag by default', () async {
      List<String>? capturedArgs;
      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        capturedArgs = args;
        return NativeCommandResult(
          stdout: 'Successfully installed six-1.17.0\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final result = await pipService.installPackage('six');
      expect(result.success, isTrue);
      expect(capturedArgs, contains('install'));
      expect(capturedArgs, contains('--user'));
      expect(capturedArgs, contains('six'));
      expect(result.output, contains('Successfully installed six-1.17.0'));
    });

    test('uninstallPackage executes with -y flag', () async {
      List<String>? capturedArgs;
      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        capturedArgs = args;
        return NativeCommandResult(
          stdout: 'Successfully uninstalled six-1.17.0\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final result = await pipService.uninstallPackage('six');
      expect(result.success, isTrue);
      expect(capturedArgs, contains('uninstall'));
      expect(capturedArgs, contains('-y'));
      expect(capturedArgs, contains('six'));
      expect(result.output, contains('Successfully uninstalled six-1.17.0'));
    });

    test('cacheClean executes pip cache purge', () async {
      List<String>? capturedArgs;
      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        capturedArgs = args;
        return NativeCommandResult(
          stdout: 'Files removed: 5 (2.3 MB)\n',
          stderr: '',
          exitCode: 0,
        );
      };

      final result = await pipService.cacheClean();
      expect(result.success, isTrue);
      expect(capturedArgs, contains('cache'));
      expect(capturedArgs, contains('purge'));
    });
  });
}
