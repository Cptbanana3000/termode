import 'dart:io';

import 'build_inputs.dart';

void main(List<String> args) {
  final root = args.length == 2 && args[0] == '--project-root' ? args[1] : null;
  final inputs = loadAndValidateBuildInputs(projectRoot: root);
  final git = inputs.git;
  final version = git?['version']?.toString() ?? 'unknown';
  final licenseRecorded = (git?['license']?.toString().trim() ?? '').isNotEmpty;
  final sourceErrors = inputs.errors
      .where(
        (error) => error.startsWith('git ') || error.contains('git source'),
      )
      .toList();
  final sourcePresent = buildInputSourceExists(inputs, git, isGit: true);
  final type = git?['source_type']?.toString();
  String checksum;
  if (git == null ||
      sourceErrors.any(
        (error) => error.contains('checksum') && !error.contains('mismatch'),
      )) {
    checksum = 'missing';
  } else if (sourceErrors.any((error) => error.contains('checksum mismatch'))) {
    checksum = 'mismatch';
  } else if (type == 'archive') {
    checksum = 'matched';
  } else {
    checksum = 'not applicable (tree provenance recorded)';
  }
  final ready =
      inputs.exists &&
      sourcePresent &&
      sourceErrors.isEmpty &&
      licenseRecorded &&
      inputs.data?['template_only'] != true;
  final overall = ready
      ? 'READY'
      : inputs.exists
      ? 'PARTIAL'
      : 'NOT READY';

  stdout.writeln('=== Git Source Verification ===');
  stdout.writeln('Source: ${sourcePresent ? 'present' : 'missing'}');
  stdout.writeln('Version: $version');
  stdout.writeln('Checksum: $checksum');
  stdout.writeln('License: ${licenseRecorded ? 'recorded' : 'missing'}');
  if (!inputs.exists) stdout.writeln('Example: $buildInputsExamplePath');
  for (final error in sourceErrors) {
    stdout.writeln('Blocker: $error');
  }
  stdout.writeln('Overall: $overall');
  if (!ready) exitCode = overall == 'PARTIAL' ? 2 : 1;
}
