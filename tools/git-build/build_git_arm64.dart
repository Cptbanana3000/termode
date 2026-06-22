import 'dart:io';

import 'build_inputs.dart';
import 'check_build_env.dart';

void main(List<String> args) {
  final root = _projectRoot(args);
  final report = detectGitBuildEnvironment(projectRoot: root);
  final inputs = loadAndValidateBuildInputs(projectRoot: root);

  stdout.writeln('=== Git arm64-v8a Build Preflight ===');
  
  if (report.perl == null) {
    stderr.writeln('Cannot start Git arm64 build.');
    stderr.writeln('Missing: Perl');
    stderr.writeln('Run: perl --version');
    stderr.writeln('Then rerun: dart tools/git-build/check_build_env.dart');
    exitCode = 78;
    return;
  }

  final ready = report.ready && inputs.valid;
  if (!ready) {
    final blockers = <String>{...report.blockers, ...inputs.errors}.toList();
    stderr.writeln('Cannot start Git arm64 build.');
    stderr.writeln('Missing: ${blockers.join(', ')}');
    exitCode = 78;
    return;
  }

  stdout.writeln('Build prerequisites are ready.');
  stdout.writeln('Next milestone can attempt Git arm64 build.');
}

String? _projectRoot(List<String> args) {
  if (args.length == 2 && args[0] == '--project-root') return args[1];
  return null;
}
