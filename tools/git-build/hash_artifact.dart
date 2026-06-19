import 'dart:convert';
import 'dart:io';

import 'sha256_helper.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart tools/git-build/hash_artifact.dart <file> [...]',
    );
    exitCode = 64;
    return;
  }
  for (final path in args) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('Missing: $path');
      exitCode = 66;
      continue;
    }
    final bytes = file.readAsBytesSync();
    final out = {
      'path': path.replaceAll('\\', '/'),
      'sha256': calculateSha256(bytes),
      'bytes': bytes.length,
    };
    stdout.writeln(jsonEncode(out));
  }
}
