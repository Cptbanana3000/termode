import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const targetAbi = 'arm64-v8a';
const nodeVersion = '20.11.0';

String? findNdkClang() {
  final candidates = [
    r'C:\Users\joell\AppData\Local\Android\Sdk\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android21-clang.cmd',
    if (Platform.environment['ANDROID_NDK'] != null)
      '${Platform.environment['ANDROID_NDK']}/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android21-clang.cmd',
    if (Platform.environment['ANDROID_NDK_ROOT'] != null)
      '${Platform.environment['ANDROID_NDK_ROOT']}/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android21-clang.cmd',
    if (Platform.environment['LOCALAPPDATA'] != null) ...[
      '${Platform.environment['LOCALAPPDATA']}/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android21-clang.cmd',
    ],
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

void main() async {
  print('=== Termode Node.js arm64-v8a Native Build ===');

  final clang = findNdkClang();
  if (clang == null) {
    stderr.writeln('ERROR: NDK aarch64 clang compiler not found.');
    exit(1);
  }
  print('Compiler: $clang');

  final sourceFile = File('tools/node-build/src/node_runner.c');
  if (!sourceFile.existsSync()) {
    stderr.writeln('ERROR: Source file missing: ${sourceFile.path}');
    exit(1);
  }

  final outputDir = Directory('tools/node-build/output/arm64-v8a/node/bin');
  await outputDir.create(recursive: true);
  final outputFile = File('${outputDir.path}/node');

  print('Source: ${sourceFile.path}');
  print('Output: ${outputFile.path}');

  final process = await Process.run(clang, [
    sourceFile.path,
    '-O2',
    '-fPIC',
    '-o',
    outputFile.path,
  ]);

  if (process.exitCode != 0) {
    stderr.writeln('Compilation failed (code ${process.exitCode}):');
    stderr.writeln(process.stderr);
    stderr.writeln(process.stdout);
    exit(process.exitCode);
  }

  if (!outputFile.existsSync()) {
    stderr.writeln('ERROR: Output binary not created.');
    exit(1);
  }

  final bytes = await outputFile.readAsBytes();
  if (bytes.length < 4 ||
      bytes[0] != 0x7f ||
      bytes[1] != 0x45 ||
      bytes[2] != 0x4c ||
      bytes[3] != 0x46) {
    stderr.writeln('ERROR: Output is not an ELF binary.');
    exit(1);
  }

  if (bytes[18] != 0xb7 && bytes[18] != 183) {
    stderr.writeln('ERROR: Binary is not AArch64 (0xb7).');
    exit(1);
  }

  final sha = sha256.convert(bytes).toString();
  print('Build SUCCESS!');
  print('Size: ${bytes.length} bytes');
  print('SHA256: $sha');
  print('Architecture: AArch64 (arm64-v8a)');
  print('ELF Magic: Verified');
}
