import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main(List<String> args) async {
  print('=== Validating Node.js Authentic V8 Runtime Artifact ===');
  final targetAbi = args.isNotEmpty ? args[0] : 'arm64-v8a';
  final manifestFile = File('tools/runtime-artifacts/node/$targetAbi/manifest.json');

  if (!manifestFile.existsSync()) {
    stderr.writeln('ERROR: Manifest does not exist: ${manifestFile.path}');
    exit(1);
  }

  final Map<String, dynamic> manifest;
  try {
    manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('ERROR: Manifest is not valid JSON: $e');
    exit(1);
  }

  // Validate fields
  if (manifest['name'] != 'node') {
    stderr.writeln('ERROR: Package name must be node');
    exit(1);
  }
  if (manifest['abi'] != targetAbi) {
    stderr.writeln('ERROR: ABI mismatch (${manifest['abi']} vs $targetAbi)');
    exit(1);
  }
  if (manifest['executable_strategy'] != 'native-library-dir') {
    stderr.writeln('ERROR: Expected native-library-dir executable strategy');
    exit(1);
  }
  if (manifest['executable_package_name'] != 'libtermode_node_exec.so') {
    stderr.writeln('ERROR: Expected libtermode_node_exec.so');
    exit(1);
  }

  // Validate all files in manifest
  final files = manifest['files'] as List;
  for (final item in files) {
    final relPath = item['path'] as String;
    final expectedSha = item['sha256'] as String;
    final expectedBytes = item['bytes'] as int;
    final file = File('tools/runtime-artifacts/node/$targetAbi/files/$relPath');
    if (!file.existsSync()) {
      stderr.writeln('ERROR: Staged file missing: ${file.path}');
      exit(1);
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != expectedBytes) {
      stderr.writeln('ERROR: File size mismatch for $relPath (${bytes.length} vs $expectedBytes)');
      exit(1);
    }
    final actualSha = sha256.convert(bytes).toString();
    if (actualSha != expectedSha) {
      stderr.writeln('ERROR: Checksum mismatch for $relPath ($actualSha vs $expectedSha)');
      exit(1);
    }
    print('  [OK] $relPath ($expectedBytes bytes)');
  }

  // Check jniLibs binary
  final jniPath = 'android/app/src/main/jniLibs/$targetAbi/libtermode_node_exec.so';
  final jniFile = File(jniPath);
  if (!jniFile.existsSync()) {
    stderr.writeln('ERROR: jniLibs payload missing: $jniPath');
    exit(1);
  }
  final jniBytes = await jniFile.readAsBytes();
  final jniSha = sha256.convert(jniBytes).toString();
  final expectedJniSha = manifest['packaged_executable_sha256'];
  if (jniSha != expectedJniSha) {
    stderr.writeln('ERROR: jniLibs checksum mismatch ($jniSha vs $expectedJniSha)');
    exit(1);
  }

  print('Manifest: OK');
  print('jniLibs Payload: OK (Size: ${jniBytes.length} bytes, SHA256: $jniSha)');
  print('Artifact VALIDATED successfully! (${files.length} files verified)');
}
