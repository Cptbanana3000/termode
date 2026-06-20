import 'dart:io';

import 'build_inputs.dart';

const dependencyRoles = <String, String>{
  'zlib': 'required now for minimal local Git',
  'curl': 'required later for HTTPS remotes',
  'openssl/tls': 'required later for HTTPS remotes',
  'expat': 'planned depending selected features',
  'pcre2': 'optional/planned',
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
    stdout.writeln('${entry.key}: $state (${entry.value})');
  }
  if (!inputs.exists) {
    stdout.writeln('Input manifest: missing');
    stdout.writeln('Example: $buildInputsExamplePath');
  }
  final zlibReady =
      configured['zlib'] != null &&
      !inputs.errors.any((error) => error.startsWith('zlib '));
  final overall = zlibReady ? 'PARTIAL' : 'PLANNED';
  stdout.writeln('Overall: $overall');
  if (!zlibReady) exitCode = 2;
}
