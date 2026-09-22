import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/python_environment_service.dart';
import 'package:termode/services/runtime_artifact_registry_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/runtime_prefix_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('termode_py_runtime_test_');
    RuntimeBootstrapService().overrideBaseDir = tempDir;
    await RuntimeBootstrapService().init();
    await RuntimePrefixService().initPrefix();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Milestone v0.75 Python ARM64 Runtime Artifact Tests', () {
    test('Python manifest exists and is valid JSON', () {
      final manifestFile =
          File('tools/runtime-artifacts/python/arm64-v8a/manifest.json');
      expect(manifestFile.existsSync(), isTrue);

      final content = manifestFile.readAsStringSync();
      final manifest = jsonDecode(content) as Map<String, dynamic>;

      expect(manifest['name'], equals('python'));
      expect(manifest['version'], equals('3.14.6'));
      expect(manifest['termode_milestone'], equals('v0.75'));
      expect(manifest['kind'], equals('native-tool'));
      expect(manifest['abi'], equals('arm64-v8a'));
      expect(manifest['executable_package_name'],
          equals('libtermode_python_exec.so'));
      expect(manifest['archive_name'], equals('python-stdlib.tar.gz'));
      expect(manifest['archive_bytes'], greaterThan(1000000));
      expect(manifest['archive_sha256'], isNotEmpty);
      expect(manifest['files'], isA<List>());
      expect((manifest['files'] as List).length, greaterThanOrEqualTo(14));
    });

    test('libtermode_python_exec.so exists in jniLibs and has valid ELF header',
        () {
      final jniExec =
          File('android/app/src/main/jniLibs/arm64-v8a/libtermode_python_exec.so');
      expect(jniExec.existsSync(), isTrue);

      final bytes = jniExec.readAsBytesSync();
      expect(bytes.length, greaterThan(1000));
      // ELF Magic: 0x7F, 'E', 'L', 'F'
      expect(bytes[0], equals(0x7F));
      expect(bytes[1], equals(0x45));
      expect(bytes[2], equals(0x4C));
      expect(bytes[3], equals(0x46));
      // Class: 2 = ELF64
      expect(bytes[4], equals(2));
      // Machine: 0xB7 = AArch64 (183 decimal)
      expect(bytes[18], equals(183));
    });

    test('libpython3.14.so exists in jniLibs and has valid ELF header', () {
      final jniLib =
          File('android/app/src/main/jniLibs/arm64-v8a/libpython3.14.so');
      expect(jniLib.existsSync(), isTrue);

      final bytes = jniLib.readAsBytesSync();
      expect(bytes.length, greaterThan(1000000));
      expect(bytes[0], equals(0x7F));
      expect(bytes[1], equals(0x45));
      expect(bytes[2], equals(0x4C));
      expect(bytes[3], equals(0x46));
      expect(bytes[4], equals(2));
      expect(bytes[18], equals(183));
    });

    test('libandroid-support.so exists in jniLibs and has valid ELF header', () {
      final jniLib =
          File('android/app/src/main/jniLibs/arm64-v8a/libandroid-support.so');
      expect(jniLib.existsSync(), isTrue);

      final bytes = jniLib.readAsBytesSync();
      expect(bytes.length, greaterThan(10000));
      expect(bytes[0], equals(0x7F));
      expect(bytes[1], equals(0x45));
      expect(bytes[2], equals(0x4C));
      expect(bytes[3], equals(0x46));
      expect(bytes[4], equals(2));
      expect(bytes[18], equals(183));
    });

    test('python-stdlib.tar.gz archive exists and is non-empty', () {
      final archive =
          File('tools/runtime-artifacts/python/arm64-v8a/python-stdlib.tar.gz');
      expect(archive.existsSync(), isTrue);
      expect(archive.lengthSync(), greaterThan(2000000));
    });

    test('RuntimeArtifactRegistryService reports Python artifact exists', () {
      final registry = RuntimeArtifactRegistryService();
      expect(registry.bundledPythonArtifactExists(), isTrue);
      final manifest = registry.readProjectPythonManifest();
      expect(manifest, isNotNull);
      expect(manifest!['name'], equals('python'));
      expect(manifest['version'], equals('3.14.6'));
    });

    test('PythonEnvironmentService reports available and correct version', () async {
      final pyService = PythonEnvironmentService();
      final isAvail = await pyService.isPythonAvailable();
      expect(isAvail, isTrue);

      final report = await pyService.doctor();
      expect(report.pythonAvailable, isTrue);
      expect(report.pythonStatus, contains('AVAILABLE (CPython v3.14.6)'));
      expect(report.pythonVersion, equals('3.14.6'));
    });

    test('NativeCommandService has executeBundledPython method', () {
      final nativeService = NativeCommandService();
      expect(nativeService.executeBundledPython, isNotNull);
    });
  });
}
