import 'dart:io';

import 'build_inputs.dart';
import 'check_build_env.dart';

void main(List<String> args) {
  final report = detectGitBuildEnvironment();
  final inputs = loadAndValidateBuildInputs();
  stdout.writeln(report.format());
  stdout.writeln();
  stdout.writeln('=== Git arm64-v8a Build Preflight ===');
  stdout.writeln('1. Verify trusted Git source provenance and checksum.');
  stdout.writeln('2. Verify dependency source provenance and checksums.');
  stdout.writeln('3. Cross-compile dependencies with the Android NDK.');
  stdout.writeln('4. Cross-compile Git for arm64-v8a.');
  stdout.writeln('5. Stage output under tools/git-build/output.');
  stdout.writeln('6. Prepare and validate an artifact candidate.');

  if (!report.ready || !inputs.valid) {
    final blockers = <String>{...report.blockers, ...inputs.errors}.toList();
    stderr.writeln('Build not started. Blockers: ${blockers.join(', ')}.');
    stderr.writeln('No artifact or manifest was generated.');
    exitCode = 78;
    return;
  }

  stderr.writeln(
    'Preflight is READY, but automatic compilation is intentionally disabled '
    'until the reviewed Git/dependency build recipe is checked in.',
  );
  stderr.writeln('Follow docs/GIT_NDK_SOURCE_BUILD.md.');
  exitCode = 78;
}
