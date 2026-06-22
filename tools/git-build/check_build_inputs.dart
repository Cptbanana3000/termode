import 'dart:io';

import 'build_inputs.dart';
import 'check_build_env.dart';

void main(List<String> args) {
  final root = _projectRoot(args);
  final inputs = loadAndValidateBuildInputs(projectRoot: root);
  final environment = detectGitBuildEnvironment(projectRoot: root);
  final gitPresent =
      inputs.git != null &&
      !inputs.errors.any((error) => error.startsWith('git '));
  final dependencies = _dependencyStatus(inputs);
  final ready =
      inputs.valid && environment.perl != null && environment.toolchainPresent;
  final overall = ready
      ? 'READY'
      : environment.toolchainPresent
      ? 'PARTIAL'
      : 'NOT READY';

  String manifestStatus;
  if (inputs.exists) {
    manifestStatus = inputs.isCandidate ? 'candidate' : 'present';
  } else if (inputs.candidateExists) {
    manifestStatus = 'candidate';
  } else {
    manifestStatus = 'missing';
  }

  stdout.writeln('=== Git Build Inputs ===');
  stdout.writeln('Input manifest: $manifestStatus');
  stdout.writeln('Git source: ${gitPresent ? 'present' : 'missing'}');
  stdout.writeln('Dependencies: $dependencies');
  if (environment.perl == null) {
    stdout.writeln('Perl: missing');
    stdout.writeln('Role: host build prerequisite');
    stdout.writeln('Blocks Git build: yes');
    stdout.writeln('Blocks Termode beta: no');
    stdout.writeln('Next: install/configure Perl on host, then rerun check_build_env.dart');
  } else {
    stdout.writeln('Perl: found');
    stdout.writeln('Version: ${environment.perlVersion}');
    stdout.writeln('Role: host build prerequisite');
    stdout.writeln('Blocks Git build: no');
  }
  stdout.writeln(
    'NDK: ${environment.androidNdk == null ? 'missing' : 'found'}',
  );
  stdout.writeln(
    'Target ABI: ${inputs.exists || inputs.candidateExists ? inputs.targetAbi : gitBuildTargetAbi}',
  );
  if (!inputs.exists && !inputs.candidateExists) {
    stdout.writeln('Example: $buildInputsExamplePath');
  }
  if (inputs.isCandidate) {
    stdout.writeln('Note: candidate manifest tools/git-build/build-inputs.candidate.json does not make the pipeline READY or Git installable.');
  }
  for (final error in inputs.errors) {
    stdout.writeln('Blocker: $error');
  }
  stdout.writeln('Overall: $overall');
  if (!ready) exitCode = overall == 'PARTIAL' ? 2 : 1;
}

String _dependencyStatus(BuildInputsDocument inputs) {
  if (!inputs.exists || inputs.dependencies.isEmpty) return 'missing';
  if (inputs.errors.any(
    (error) =>
        error.contains('dependency') ||
        inputs.dependencies.any((dep) => error.startsWith('${dep['name']} ')),
  )) {
    return 'partial';
  }
  return 'present';
}

String? _projectRoot(List<String> args) {
  if (args.length == 2 && args[0] == '--project-root') return args[1];
  return null;
}
