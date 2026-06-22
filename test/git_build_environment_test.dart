import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/git-build/check_build_env.dart';
import '../tools/git-build/build_inputs.dart';

String _dartExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 10; i++) {
    for (final relative in [
      'dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
      'bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
    ]) {
      final candidate = File('${directory.path}/$relative');
      if (candidate.existsSync()) return candidate.absolute.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('Unable to locate the Dart SDK executable.');
}

void main() {
  group('v0.51-v0.55 Git build and acquisition environment', () {
    test('environment report is explicit and machine-readable', () {
      const report = GitBuildEnvironment(
        hostOs: 'test-os',
        androidSdk: '/sdk',
        androidNdk: '/sdk/ndk/1',
        ndkVersion: '1.0',
        shell: '/bin/sh',
        compiler: '/ndk/clang',
        cmake: '/sdk/cmake',
        make: '/ndk/make',
        perl: null,
        archiveTool: '/bin/tar',
        gitSourcePresent: false,
        dependenciesPresent: false,
        outputWritable: true,
      );

      expect(report.overall, 'PARTIAL');
      expect(report.blockers, contains('Perl'));
      expect(report.blockers, contains('trusted Git source'));
      expect(report.format(), contains('=== Git Build Environment ==='));
      expect(report.format(), contains('Target ABI: arm64-v8a'));
      expect(report.format(), contains('Git source: missing'));
      expect(report.format(), contains('Overall: PARTIAL'));
    });

    test('prepare script rejects missing staged output', () async {
      final root = Directory.current.absolute.path;
      final temp = await Directory.systemTemp.createTemp('termode_git_stage');
      addTearDown(() => temp.delete(recursive: true));

      final result = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/prepare_git_artifact.dart',
        'arm64-v8a',
        '${temp.path}/missing',
      ], workingDirectory: temp.path);

      expect(result.exitCode, 66);
      expect(result.stderr.toString(), contains('Missing staged build output'));
    });

    test('prepare script rejects zero-byte placeholder payload', () async {
      final root = Directory.current.absolute.path;
      final temp = await Directory.systemTemp.createTemp('termode_git_zero');
      addTearDown(() => temp.delete(recursive: true));
      final staged = Directory('${temp.path}/stage/bin')
        ..createSync(recursive: true);
      File('${staged.path}/git').createSync();

      final result = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/prepare_git_artifact.dart',
        'arm64-v8a',
        '${temp.path}/stage',
      ], workingDirectory: temp.path);

      expect(result.exitCode, 65);
      expect(result.stderr.toString(), contains('Rejected zero-byte'));
      expect(
        File(
          '${temp.path}/tools/runtime-artifacts/git/arm64-v8a/manifest.json',
        ).existsSync(),
        isFalse,
      );
    });

    test('prepare script rejects unsafe staged names', () async {
      final root = Directory.current.absolute.path;
      final temp = await Directory.systemTemp.createTemp('termode_git_unsafe');
      addTearDown(() => temp.delete(recursive: true));
      final staged = Directory('${temp.path}/stage/bin')
        ..createSync(recursive: true);
      File('${staged.path}/bad name').writeAsStringSync('payload');

      final result = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/prepare_git_artifact.dart',
        'arm64-v8a',
        '${temp.path}/stage',
      ], workingDirectory: temp.path);

      expect(result.exitCode, 65);
      expect(
        result.stderr.toString(),
        contains('Rejected unsafe or unsupported staged path'),
      );
    });

    test('hash helper emits a real SHA-256 value', () async {
      final root = Directory.current.absolute.path;
      final temp = await Directory.systemTemp.createTemp('termode_git_hash');
      addTearDown(() => temp.delete(recursive: true));
      final input = File('${temp.path}/input.bin')..writeAsStringSync('abc');

      final result = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/hash_git_artifact.dart',
        input.path,
      ], workingDirectory: temp.path);

      expect(result.exitCode, 0);
      expect(
        result.stdout.toString(),
        contains(
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
      );
    });

    test('build inputs example is explicitly not real inputs', () {
      final example = File('tools/git-build/build-inputs.example.json');
      final decoded = jsonDecode(example.readAsStringSync()) as Map;
      expect(decoded['template_only'], isTrue);
      expect(File('tools/git-build/build-inputs.json').existsSync(), isTrue);
      expect((decoded['git'] as Map)['sha256'], List.filled(64, '0').join());
    });

    test('build input validation rejects unsafe and template paths', () {
      final data = {
        'template_only': true,
        'git': {
          'version': '2.50.0',
          'source_type': 'archive',
          'source_path': '../git.tar.xz',
          'source_url': 'https://example.invalid/git.tar.xz',
          'sha256': List.filled(64, 'a').join(),
          'license': 'GPL-2.0-only',
          'trusted_by': 'Termode',
        },
        'dependencies': <Map<String, Object>>[],
        'host_requirements': {
          'perl': 'required',
          'android_ndk': 'required',
          'cmake': 'required',
          'make': 'required',
          'archive_tool': 'required',
        },
        'target': {'abi': 'x86_64', 'min_android_api': 24},
        'build_mode': 'minimal-local-git',
        'build_method': 'test',
        'acquired_at': '2026-06-20',
      };
      final errors = validateBuildInputs(
        Map<String, dynamic>.from(data),
        Directory.current.absolute,
      );
      expect(errors, contains('template-only inputs are not build-ready'));
      expect(errors, contains('git unsafe source_path'));
      expect(errors, contains('missing dependency entries'));
      expect(errors, contains('target ABI must be arm64-v8a'));
    });

    test('host input checker reports missing build-inputs.json', () async {
      final root = Directory.current.absolute.path;
      final temp = await Directory.systemTemp.createTemp('termode_git_inputs');
      addTearDown(() => temp.delete(recursive: true));
      final result = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/check_build_inputs.dart',
        '--project-root',
        temp.path,
      ]);
      expect(result.exitCode, 2);
      expect(result.stdout.toString(), contains('Input manifest: missing'));
      expect(result.stdout.toString(), contains('Git source: missing'));
      expect(result.stdout.toString(), contains('Overall: PARTIAL'));
    });

    test('Git source verifier reports missing source', () async {
      final root = Directory.current.absolute.path;
      final temp = await Directory.systemTemp.createTemp('termode_git_source');
      addTearDown(() => temp.delete(recursive: true));
      final result = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/verify_git_source.dart',
        '--project-root',
        temp.path,
      ]);
      expect(result.exitCode, 1);
      expect(result.stdout.toString(), contains('Source: missing'));
      expect(result.stdout.toString(), contains('Checksum: missing'));
      expect(result.stdout.toString(), contains('Overall: NOT READY'));
    });

    test('dependency checker reports staged roles without inputs', () async {
      final root = Directory.current.absolute.path;
      final temp = await Directory.systemTemp.createTemp('termode_git_deps');
      addTearDown(() => temp.delete(recursive: true));
      final result = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/check_dependencies.dart',
        '--project-root',
        temp.path,
      ]);
      expect(result.exitCode, 2);
      expect(result.stdout.toString(), contains('zlib: not configured'));
      expect(result.stdout.toString(), contains('curl: not configured'));
      expect(result.stdout.toString(), contains('Overall: PLANNED'));
    });

    test('print_next_steps script prints missing prerequisites', () async {
      final root = Directory.current.absolute.path;
      final temp = await Directory.systemTemp.createTemp('termode_git_next');
      addTearDown(() => temp.delete(recursive: true));
      final result = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/print_next_steps.dart',
        '--project-root',
        temp.path,
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('=== Git Build Next Steps ==='));
      expect(result.stdout.toString(), contains('Perl: missing'));
      expect(result.stdout.toString(), contains('Git source: missing'));
      expect(result.stdout.toString(), contains('build-inputs.json: missing'));
    });

    test('host input checker reports candidate manifest state', () async {
      final root = Directory.current.absolute.path;
      final temp = await Directory.systemTemp.createTemp('termode_git_candidate');
      addTearDown(() => temp.delete(recursive: true));
      
      final resultCreate = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/create_build_inputs_candidate.dart',
        '--git-sha256',
        'e358738dcb5b5ea340ce900a0015c03ae86e804e7ff64e47aa4631ddee681de3',
        '--zlib-sha256',
        '38ef96b8dfe510d42707d9c781877914792541133e1870841463bfa73f883e32',
      ], workingDirectory: temp.path);
      expect(resultCreate.exitCode, 0);

      final result = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/check_build_inputs.dart',
        '--project-root',
        temp.path,
      ]);
      expect(result.exitCode, 2);
      expect(result.stdout.toString(), contains('Input manifest: candidate'));
      expect(result.stdout.toString(), contains('Blocker: candidate inputs require human review before build'));
      expect(result.stdout.toString(), contains('Overall: PARTIAL'));
    });

    test('create_build_inputs_candidate rejects invalid input', () async {
      final root = Directory.current.absolute.path;
      final temp = await Directory.systemTemp.createTemp('termode_git_create_fail');
      addTearDown(() => temp.delete(recursive: true));
      
      final result = await Process.run(_dartExecutable(), [
        '$root/tools/git-build/create_build_inputs_candidate.dart',
        '--git-sha256',
        'short',
      ], workingDirectory: temp.path);
      expect(result.exitCode, 1);
    });
  });
}
