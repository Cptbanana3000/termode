import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main(List<String> args) async {
  print('=== Validating Node.js Runtime Artifact ===');
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

  // Check staged binary
  final stagedPath = 'tools/runtime-artifacts/node/$targetAbi/files/bin/node';
  final stagedFile = File(stagedPath);
  if (!stagedFile.existsSync()) {
    stderr.writeln('ERROR: Staged binary missing: $stagedPath');
    exit(1);
  }

  final stagedBytes = await stagedFile.readAsBytes();
  final stagedSha = sha256.convert(stagedBytes).toString();
  final expectedSha = manifest['original_binary_sha256'];
  if (stagedSha != expectedSha) {
    stderr.writeln('ERROR: Checksum mismatch ($stagedSha vs $expectedSha)');
    exit(1);
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
  if (jniSha != expectedSha) {
    stderr.writeln('ERROR: jniLibs checksum mismatch ($jniSha vs $expectedSha)');
    exit(1);
  }

  print('Manifest: OK');
  print('Staged Binary: OK (SHA256: $stagedSha)');
  print('jniLibs Payload: OK (Size: ${jniBytes.length} bytes)');
  print('Artifact VALIDATED successfully!');
}
