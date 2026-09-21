import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const abi = 'arm64-v8a';
const nodeVersion = '24.18.0';
const executablePackageName = 'libtermode_node_exec.so';

void main(List<String> args) async {
  print('=== Packaging Node.js Authentic V8 Runtime Artifact ===');

  final nodeBinFile = File('tools/runtime-artifacts/node/arm64-v8a/files/bin/node');
  if (!nodeBinFile.existsSync()) {
    stderr.writeln('ERROR: Source binary missing: ${nodeBinFile.path}');
    exit(1);
  }

  final nodeBytes = await nodeBinFile.readAsBytes();
  if (nodeBytes.length < 4 ||
      nodeBytes[0] != 0x7f ||
      nodeBytes[1] != 0x45 ||
      nodeBytes[2] != 0x4c ||
      nodeBytes[3] != 0x46) {
    stderr.writeln('ERROR: File is not an ELF binary.');
    exit(1);
  }

  final nodeSha = sha256.convert(nodeBytes).toString();
  print('Node ELF: ${nodeBinFile.path} (${nodeBytes.length} bytes)');
  print('SHA256: $nodeSha');

  // Stage into Android jniLibs
  final jniLibFile = File('android/app/src/main/jniLibs/arm64-v8a/$executablePackageName');
  await jniLibFile.parent.create(recursive: true);
  await jniLibFile.writeAsBytes(nodeBytes, flush: true);
  print('Native Payload: ${jniLibFile.path}');

  // Scan all files in tools/runtime-artifacts/node/arm64-v8a/files
  final filesRoot = Directory('tools/runtime-artifacts/node/arm64-v8a/files');
  final fileList = <Map<String, dynamic>>[];
  final shaMap = <String, String>{};

  final allEntities = filesRoot.listSync(recursive: true);
  for (final entity in allEntities) {
    if (entity is File) {
      final relPath = entity.path
          .replaceAll('\\', '/')
          .replaceFirst('tools/runtime-artifacts/node/arm64-v8a/files/', '');
      final bytes = await entity.readAsBytes();
      final sha = sha256.convert(bytes).toString();
      fileList.add({
        'path': relPath,
        'sha256': sha,
        'bytes': bytes.length,
      });
      shaMap[relPath] = sha;
      print('  + $relPath (${bytes.length} bytes, sha: ${sha.substring(0, 8)}...)');
    }
  }

  // Sort files by path for deterministic manifest
  fileList.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));

  final manifest = <String, dynamic>{
    'name': 'node',
    'version': nodeVersion,
    'termode_milestone': 'v0.70',
    'created_by': 'Termode upstream Android Bionic V8 build',
    'candidate': false,
    'template_only': false,
    'kind': 'native-tool',
    'abi': abi,
    'command': 'node',
    'entrypoint': 'bin/node',
    'logical_install_path': 'bin/node',
    'executable_strategy': 'native-library-dir',
    'executable_package_name': executablePackageName,
    'original_binary_sha256': nodeSha,
    'packaged_executable_sha256': nodeSha,
    'execution_policy_note':
        'Logical prefix mapping only; execute the immutable APK payload from applicationInfo.nativeLibraryDir with LD_LIBRARY_PATH pointing to usr/lib.',
    'local_only': true,
    'remote_features_deferred': false,
    'files': fileList,
    'sha256': shaMap,
    'source': 'upstream-termux-bionic',
    'source_url': 'https://nodejs.org',
    'build_method': 'bionic-ndk-build',
    'license': 'MIT',
    'trusted_by': 'Termode',
    'verification_command': 'node --version',
    'smoke_tests': [
      'node --version',
      'node -e "console.log(\'hello termode node\')"',
    ],
    'dependencies': <String>[
      'c-ares',
      'libicu',
      'libsqlite',
      'openssl',
      'zlib',
      'libc++_shared',
    ],
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };

  final manifestFile = File('tools/runtime-artifacts/node/arm64-v8a/manifest.json');
  await manifestFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest) + '\n',
  );
  print('Manifest: ${manifestFile.path}');
  print('Packaging SUCCESS! (${fileList.length} files tracked)');
}
