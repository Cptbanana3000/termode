import 'dart:io';
import 'build_inputs.dart';
import 'check_build_env.dart';

void main(List<String> args) {
  final root = _projectRoot(args);
  final inputs = loadAndValidateBuildInputs(projectRoot: root);
  final environment = detectGitBuildEnvironment(projectRoot: root);

  stdout.writeln('=== Git Build Next Steps ===');

  if (environment.perl == null) {
    stdout.writeln('* Perl: missing from host. Perl is a build-time dependency required by Git.');
    stdout.writeln('  For Windows, see: docs/GIT_PERL_SETUP_WINDOWS.md');
    stdout.writeln('  Run: perl --version');
    stdout.writeln('  Then rerun: dart tools/git-build/check_build_env.dart');
  } else {
    stdout.writeln('* Perl: found (${environment.perlVersion})');
  }

  final gitPresent = inputs.exists &&
      inputs.git != null &&
      !inputs.errors.any((error) => error.startsWith('git '));
  if (!gitPresent) {
    stdout.writeln('* Git source: missing. Staging location: $selectedGitArchivePath or $selectedGitTreePath/');
  } else {
    stdout.writeln('* Git source: ready (${inputs.selectedVersion})');
  }

  final depStatus = _dependencyStatus(inputs);
  if (depStatus == 'missing' || depStatus == 'partial') {
    stdout.writeln('* zlib: strategy/source missing or unverified. zlib is required for minimal local Git.');
  } else {
    stdout.writeln('* zlib: ready');
  }

  if (inputs.isCandidate) {
    stdout.writeln('* build-inputs.json: candidate manifest tools/git-build/build-inputs.candidate.json is present, but human review is required before promoting to build-inputs.json.');
  } else if (!inputs.exists) {
    stdout.writeln('* build-inputs.json: missing. Please copy tools/git-build/build-inputs.example.json to tools/git-build/build-inputs.json.');
  } else if (!inputs.valid) {
    stdout.writeln('* build-inputs.json: contains errors/blockers');
  } else {
    stdout.writeln('* build-inputs.json: ready');
  }

  stdout.writeln('Overall status: No artifact yet. Git remains unavailable.');
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
  final idx = args.indexOf('--project-root');
  if (idx != -1 && idx + 1 < args.length) return args[idx + 1];
  return null;
}
