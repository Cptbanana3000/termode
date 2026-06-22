import 'dart:io';
import 'build_inputs.dart';
import 'check_build_env.dart';

void main(List<String> args) {
  final root = _projectRoot(args);
  final inputs = loadAndValidateBuildInputs(projectRoot: root);
  final environment = detectGitBuildEnvironment(projectRoot: root);

  final gitPresent = inputs.exists &&
      inputs.git != null &&
      !inputs.errors.any((error) => error.startsWith('git '));

  final depStatus = _dependencyStatus(inputs);
  final zlibReady = depStatus == 'present';

  final gitReady = gitPresent;
  final inputsReady = inputs.valid;
  final ndkReady = environment.androidNdk != null;
  final compilerReady = environment.compiler != null;
  final perlReady = environment.perl != null;

  final overallReady = gitReady && zlibReady && inputsReady && ndkReady && compilerReady && perlReady;
  final overallPartial = gitReady && zlibReady && inputsReady && ndkReady && compilerReady && !perlReady;

  final overall = overallReady
      ? 'READY'
      : overallPartial
          ? 'PARTIAL'
          : 'NOT READY';

  stdout.writeln('=== Git arm64 Build Readiness ===');
  stdout.writeln('Git source: ${gitReady ? 'READY' : 'MISSING'}');
  stdout.writeln('zlib: ${zlibReady ? 'READY' : 'MISSING'}');
  stdout.writeln('build-inputs.json: ${inputsReady ? 'READY' : 'MISSING'}');
  stdout.writeln('Android NDK: ${ndkReady ? 'READY' : 'MISSING'}');
  stdout.writeln('arm64 compiler: ${compilerReady ? 'READY' : 'MISSING'}');
  stdout.writeln('Perl: ${perlReady ? 'READY' : 'MISSING'}');
  stdout.writeln('Overall: $overall');

  if (overallReady) {
    stdout.writeln('Next: v0.58 Git arm64 Build Attempt.');
  } else if (overallPartial) {
    stdout.writeln('Next: Install/configure Perl on host, then rerun check_build_env.dart.');
  } else {
    final blockers = <String>[];
    if (!gitReady) blockers.add('Git source missing');
    if (!zlibReady) blockers.add('zlib source missing');
    if (!inputsReady) blockers.add('build-inputs.json missing or invalid');
    if (!ndkReady) blockers.add('Android NDK missing');
    if (!compilerReady) blockers.add('arm64 compiler missing');
    stdout.writeln('Next: Resolve blockers: ${blockers.join(', ')}');
  }
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
