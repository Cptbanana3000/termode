import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('v0.64 Git runtime artifact packager', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_git_package');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<ProcessResult> package(String source, String destination) {
      return Process.run(Platform.isWindows ? 'dart.bat' : 'dart', [
        'tools/git-build/package_git_artifact.dart',
        source,
        destination,
      ]);
    }

    test(
      'packages only the real verified Git ELF and writes manifest last',
      () async {
        const source = 'tools/git-build/output/arm64-v8a/git/bin/git';
        final destination = '${tempDir.path}/artifact';
        final result = await package(source, destination);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout, contains('Build output: VERIFIED'));
        final binary = File('$destination/files/usr/bin/git');
        final manifestFile = File('$destination/manifest.json');
        expect(await binary.length(), 5463168);
        expect(await manifestFile.exists(), isTrue);
        final manifest =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        expect(manifest['version'], '2.44.0');
        expect(manifest['candidate'], isFalse);
        expect(manifest['template_only'], isFalse);
        expect(manifest['install_target'], 'usr/bin/git');
        expect(manifest['logical_install_path'], 'usr/bin/git');
        expect(manifest['executable_strategy'], 'native-library-dir');
        expect(manifest['executable_package_name'], 'libtermode_git_exec.so');
        expect(manifest['local_only'], isTrue);
        expect(manifest['remote_features_deferred'], isTrue);
        final nativeExecutable = File(
          '$destination/android-native/arm64-v8a/libtermode_git_exec.so',
        );
        expect(await nativeExecutable.length(), 5463168);
      },
    );

    test('refuses a missing binary without creating an artifact', () async {
      final destination = '${tempDir.path}/missing-artifact';
      final result = await package('${tempDir.path}/missing-git', destination);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Git binary is missing'));
      expect(Directory(destination).existsSync(), isFalse);
    });

    test('refuses a zero-byte binary without writing a manifest', () async {
      final source = File('${tempDir.path}/zero-git');
      await source.create();
      final destination = '${tempDir.path}/zero-artifact';
      final result = await package(source.path, destination);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('zero bytes'));
      expect(File('$destination/manifest.json').existsSync(), isFalse);
    });

    test('refuses a checksum mismatch without writing a manifest', () async {
      final source = File('${tempDir.path}/wrong-git');
      final wrongBytes = List<int>.filled(5463168, 1);
      wrongBytes.setRange(0, 4, [0x7f, 0x45, 0x4c, 0x46]);
      await source.writeAsBytes(wrongBytes);
      final destination = '${tempDir.path}/wrong-artifact';
      final result = await package(source.path, destination);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('checksum mismatch'));
      expect(File('$destination/manifest.json').existsSync(), isFalse);
    });
  });
}
