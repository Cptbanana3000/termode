import 'dart:io';

import 'build_inputs.dart';

const dependencyRoles = <String, String>{
  'zlib': 'required now for minimal local Git (Stage 1)',
  'curl': 'deferred until HTTPS remotes (Stage 3)',
  'openssl/tls': 'deferred until HTTPS remotes (Stage 3)',
  'expat': 'deferred/planned depending selected features (Stage 4)',
  'pcre2': 'optional/planned (Stage 4)',
};

void main(List<String> args) {
  final root = args.length == 2 && args[0] == '--project-root' ? args[1] : null;
  final inputs = loadAndValidateBuildInputs(projectRoot: root);
  final configured = <String, Map<String, dynamic>>{
    for (final dependency in inputs.dependencies)
      dependency['name']?.toString().toLowerCase() ?? '': dependency,
  };

  stdout.writeln('=== Git Dependency Verification ===');
  for (final entry in dependencyRoles.entries) {
    final direct = configured[entry.key];
    final tls = entry.key == 'openssl/tls'
        ? configured['openssl'] ?? configured['tls']
        : direct;
    final dependency = direct ?? tls;
    final name = dependency?['name']?.toString() ?? entry.key;
    final hasErrors = inputs.errors.any((error) => error.startsWith('$name '));
    final state = dependency == null
        ? 'not configured'
        : hasErrors
        ? 'partial'
        : 'present';
    
    // Determine stage reporting
    String stageGroup;
    if (entry.key == 'zlib') {
      stageGroup = 'required now';
    } else if (entry.key == 'pcre2') {
      stageGroup = 'optional';
    } else {
      stageGroup = 'deferred';
    }

    stdout.writeln('${entry.key}: $state ($stageGroup) [${entry.value}]');
  }
  String manifestStatus;
  if (inputs.exists) {
    manifestStatus = inputs.isCandidate ? 'candidate' : 'present';
  } else if (inputs.candidateExists) {
    manifestStatus = 'candidate';
  } else {
    manifestStatus = 'missing';
  }
  stdout.writeln('Input manifest: $manifestStatus');
  if (!inputs.exists && !inputs.candidateExists) {
    stdout.writeln('Example: $buildInputsExamplePath');
  }

  final zlibReady =
      configured['zlib'] != null &&
      !inputs.errors.any((error) => error.startsWith('zlib '));
  final overall = zlibReady
      ? (inputs.isCandidate ? 'PARTIAL' : 'READY')
      : 'PLANNED';
  stdout.writeln('Overall: $overall');
  if (overall != 'READY') exitCode = 2;
}
