import 'dart:io';

import 'sha256_helper.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart tools/git-build/hash_git_artifact.dart <file>');
    exitCode = 64;
    return;
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('Missing file: ${file.path}');
    exitCode = 66;
    return;
  }
  final bytes = file.readAsBytesSync();
  stdout.writeln(
    '${calculateSha256(bytes)}  ${file.path}  bytes=${bytes.length}',
  );
}
