import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const abi = 'arm64-v8a';
const nodeVersion = '20.11.0';
const executablePackageName = 'libtermode_node_exec.so';

void main(List<String> args) async {
  print('=== Packaging Node.js Runtime Artifact ===');

  final sourcePath = args.isNotEmpty
      ? args[0]
      : 'tools/node-build/output/arm64-v8a/node/bin/node';
  final sourceFile = File(sourcePath);

  if (!sourceFile.existsSync()) {
    stderr.writeln('ERROR: Source binary missing: $sourcePath');
    exit(1);
  }

  final bytes = await sourceFile.readAsBytes();
  if (bytes.length < 4 ||
      bytes[0] != 0x7f ||
      bytes[1] != 0x45 ||
      bytes[2] != 0x4c ||
      bytes[3] != 0x46) {
    stderr.writeln('ERROR: File is not an ELF binary.');
    exit(1);
  }

  final sha = sha256.convert(bytes).toString();
  final size = bytes.length;

  print('Binary: $sourcePath ($size bytes)');
  print('SHA256: $sha');

  // 1. Stage into runtime-artifacts files/bin/node
  final stagedFile = File('tools/runtime-artifacts/node/arm64-v8a/files/bin/node');
  await stagedFile.parent.create(recursive: true);
  await stagedFile.writeAsBytes(bytes, flush: true);
  print('Staged: ${stagedFile.path}');

  // 2. Stage into Android jniLibs
  final jniLibFile = File('android/app/src/main/jniLibs/arm64-v8a/$executablePackageName');
  await jniLibFile.parent.create(recursive: true);
  await jniLibFile.writeAsBytes(bytes, flush: true);
  print('Native Payload: ${jniLibFile.path}');

  // 3. Write manifest.json
  final manifest = <String, dynamic>{
    'name': 'node',
    'version': nodeVersion,
    'termode_milestone': 'v0.69',
    'created_by': 'Termode reproducible NDK build',
    'candidate': false,
    'template_only': false,
    'kind': 'native-tool',
    'abi': abi,
    'command': 'node',
    'entrypoint': 'bin/node',
    'logical_install_path': 'bin/node',
    'executable_strategy': 'native-library-dir',
    'executable_package_name': executablePackageName,
    'original_binary_sha256': sha,
    'packaged_executable_sha256': sha,
    'execution_policy_note':
        'Logical prefix mapping only; execute the immutable APK payload from applicationInfo.nativeLibraryDir.',
    'local_only': true,
    'remote_features_deferred': false,
    'files': [
      {
        'path': 'bin/node',
        'sha256': sha,
        'bytes': size,
      }
    ],
    'sha256': {
      'bin/node': sha,
    },
    'source': 'termode-built',
    'source_url': 'https://nodejs.org',
    'build_method': 'reproducible-ndk-clang-build',
    'license': 'MIT',
    'trusted_by': 'Termode',
    'verification_command': 'node --version',
    'smoke_tests': [
      'node --version',
      'node -e "console.log(\'hello termode node\')"',
    ],
    'dependencies': <String>[],
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };

  final manifestFile = File('tools/runtime-artifacts/node/arm64-v8a/manifest.json');
  await manifestFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest) + '\n',
  );
  print('Manifest: ${manifestFile.path}');
  print('Packaging SUCCESS!');
}
