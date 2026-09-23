import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const pipVersion = '26.2.1';
const wheelUrl =
    'https://files.pythonhosted.org/packages/f3/6e/1736e5b4ae2b778ef2f81c47d797de9f891d4d8acb047a24ca37a60294dd/pip-26.2.1-py3-none-any.whl';
const expectedWheelSha =
    '71138adf1f4ca900cdb7d289c21b7494329f2332b6d85f0e1c42108c0384ed3e';

void main() async {
  print('=== Packaging Authentic Upstream pip Universal Runtime Artifact ===');

  final scratchDir = Directory('tools/python-build/scratch_pip');
  if (!scratchDir.existsSync()) scratchDir.createSync(recursive: true);

  final wheelFile = File('${scratchDir.path}/pip-$pipVersion.whl');
  final zipFile = File('${scratchDir.path}/pip-$pipVersion.zip');

  if (!wheelFile.existsSync()) {
    print('Downloading pip wheel from $wheelUrl...');
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(wheelUrl));
    final res = await req.close();
    final sink = wheelFile.openWrite();
    await res.pipe(sink);
    print('Downloaded wheel: ${wheelFile.path} (${wheelFile.lengthSync()} bytes)');
  }

  final wheelBytes = await wheelFile.readAsBytes();
  final wheelSha = sha256.convert(wheelBytes).toString().toLowerCase();
  print('Wheel SHA256: $wheelSha');
  if (wheelSha != expectedWheelSha.toLowerCase()) {
    stderr.writeln('ERROR: Wheel checksum mismatch!');
    exit(1);
  }

  // Copy wheel as zip for extraction
  await wheelFile.copy(zipFile.path);

  final unpackedDir = Directory('${scratchDir.path}/unpacked');
  if (unpackedDir.existsSync()) unpackedDir.deleteSync(recursive: true);
  unpackedDir.createSync(recursive: true);

  print('Unpacking wheel archive...');
  if (Platform.isWindows) {
    final res = await Process.run('powershell', [
      '-Command',
      'Expand-Archive -Path "${zipFile.absolute.path}" -DestinationPath "${unpackedDir.absolute.path}" -Force',
    ]);
    if (res.exitCode != 0) {
      stderr.writeln('ERROR extracting wheel: ${res.stderr}');
      exit(1);
    }
  } else {
    final res = await Process.run('unzip', [
      '-q',
      zipFile.absolute.path,
      '-d',
      unpackedDir.absolute.path,
    ]);
    if (res.exitCode != 0) {
      stderr.writeln('ERROR extracting wheel: ${res.stderr}');
      exit(1);
    }
  }

  // Create target artifact directory
  final artifactDir = Directory('tools/runtime-artifacts/pip/universal');
  if (!artifactDir.existsSync()) artifactDir.createSync(recursive: true);

  final tarGzFile = File('${artifactDir.path}/pip.tar.gz');
  print('Compressing unpacked files to ${tarGzFile.path}...');

  final tarRes = await Process.run('tar', [
    '-czf',
    tarGzFile.absolute.path,
    '-C',
    unpackedDir.absolute.path,
    '.',
  ]);

  if (tarRes.exitCode != 0) {
    stderr.writeln('ERROR creating tar.gz: ${tarRes.stderr}');
    exit(1);
  }

  final tarGzBytes = await tarGzFile.readAsBytes();
  final tarGzSha = sha256.convert(tarGzBytes).toString().toLowerCase();
  final tarGzSize = tarGzBytes.length;

  print('pip.tar.gz created: $tarGzSize bytes, SHA256: $tarGzSha');

  // Count files inside
  int fileCount = 0;
  for (final entity in unpackedDir.listSync(recursive: true)) {
    if (entity is File) fileCount++;
  }
  print('Extracted files count: $fileCount');

  // Generate manifest.json
  final manifest = {
    'name': 'pip',
    'version': pipVersion,
    'termode_milestone': 'v0.77',
    'created_by': 'Termode official upstream pip distribution',
    'candidate': false,
    'template_only': false,
    'kind': 'package-manager',
    'abi': 'universal',
    'command': 'pip',
    'entrypoint': 'usr/bin/pip',
    'logical_install_path': 'usr/lib/python3.14/site-packages/pip',
    'executable_strategy': 'python-driver',
    'executable_package_name': 'pip',
    'archive': 'pip.tar.gz',
    'archive_sha256': tarGzSha,
    'archive_bytes': tarGzSize,
    'execution_policy_note':
        'Authentic upstream pip $pipVersion package manager driven by Termode CPython 3.14 runtime engine with user-site package isolation.',
    'local_only': false,
    'remote_features_deferred': false,
    'entrypoints': [
      'usr/bin/pip',
      'usr/bin/pip3',
    ],
    'dependencies': [
      'python',
    ],
    'source': 'pypi-official-wheel',
    'source_url': wheelUrl,
    'build_method':
        'bundled site-packages/pip tar.gz archive extracted into usr/lib/python3.14/site-packages with bin wrappers and shell helpers',
    'license': 'MIT',
    'trusted_by': 'Termode',
    'verification_command': 'python3 -m pip --version',
    'smoke_tests': [
      'pip --version',
      'pip3 --version',
      'pip list',
      'pip-doctor',
    ],
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };

  final manifestFile = File('${artifactDir.path}/manifest.json');
  final jsonContent = const JsonEncoder.withIndent('  ').convert(manifest);
  await manifestFile.writeAsString('$jsonContent\n');
  print('Wrote manifest to ${manifestFile.path}');

  print('=== pip Universal Artifact Packaging Complete ===');
}
