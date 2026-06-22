import 'dart:io';

import 'build_inputs.dart';
import 'check_build_env.dart';

void main(List<String> args) {
  final isDryRun = args.contains('--dry-run');
  final root = _projectRoot(args);
  final report = detectGitBuildEnvironment(projectRoot: root);
  final inputs = loadAndValidateBuildInputs(projectRoot: root);

  stdout.writeln('=== Git arm64-v8a Build Preflight ===');
  if (isDryRun) {
    stdout.writeln('Running dry-run check...');
  }
  
  if (report.perl == null) {
    stderr.writeln('Cannot start Git arm64 build.');
    stderr.writeln('Missing: Perl');
    stderr.writeln('Run: perl --version');
    stderr.writeln('Then rerun: dart tools/git-build/check_build_env.dart');
    exitCode = 1;
    return;
  }

  final ready = report.ready && inputs.valid;
  if (!ready) {
    final blockers = <String>{...report.blockers, ...inputs.errors}.toList();
    stderr.writeln('Cannot start Git arm64 build.');
    stderr.writeln('Missing: ${blockers.join(', ')}');
    exitCode = 1;
    return;
  }

  stdout.writeln('Build prerequisites are ready.');
  stdout.writeln('Pipeline is ready for v0.58.');
}

String? _projectRoot(List<String> args) {
  final idx = args.indexOf('--project-root');
  if (idx != -1 && idx + 1 < args.length) return args[idx + 1];
  return null;
}
