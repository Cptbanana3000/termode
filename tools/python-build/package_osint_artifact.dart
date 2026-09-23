import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

class WheelSource {
  final String name;
  final String filename;
  final String url;
  final String sha256;

  const WheelSource({
    required this.name,
    required this.filename,
    required this.url,
    required this.sha256,
  });
}

const List<WheelSource> osintWheels = [
  WheelSource(
    name: 'sherlock-project',
    filename: 'sherlock_project-0.16.2-py3-none-any.whl',
    url:
        'https://files.pythonhosted.org/packages/56/d7/eafc1647a11be6c55f2ed4a442cb80aab23fa431a265d2b40b2d581e813a/sherlock_project-0.16.2-py3-none-any.whl',
    sha256:
        '7f1341dcd554a39d529bcfff14b133410e8773e3e1083fc5bdd0cd0a579fb46f',
  ),
  WheelSource(
    name: 'requests-futures',
    filename: 'requests_futures-1.1.0-py3-none-any.whl',
    url:
        'https://files.pythonhosted.org/packages/1c/55/a590f55d1273ce1a8a4d62aec8e1e92a484aa6374ffe87df2db334efd10b/requests_futures-1.1.0-py3-none-any.whl',
    sha256:
        'c9bd8a88d27630a5b418a809f1a89d451d4bc4bdca87c07a50735ab6f66f423a',
  ),
  WheelSource(
    name: 'colorama',
    filename: 'colorama-0.4.6-py2.py3-none-any.whl',
    url:
        'https://files.pythonhosted.org/packages/d1/d6/3965ed04c63042e047cb6a3e6ed1a63a35087b6a609aa3a15ed8ac56c221/colorama-0.4.6-py2.py3-none-any.whl',
    sha256:
        '4f1d9991f5acc0ca119f9d443620b77f9d6b33703e51011c16baf57afb285fc6',
  ),
  WheelSource(
    name: 'PySocks',
    filename: 'PySocks-1.7.1-py3-none-any.whl',
    url:
        'https://files.pythonhosted.org/packages/8d/59/b4572118e098ac8e46e399a1dd0f2d85403ce8bbaad9ec79373ed6badaf9/PySocks-1.7.1-py3-none-any.whl',
    sha256:
        '2725bd0a9925919b9b51739eea5f9e2bae91e83288108a9ad338b2e3a4435ee5',
  ),
  WheelSource(
    name: 'tomli',
    filename: 'tomli-2.0.1-py3-none-any.whl',
    url:
        'https://files.pythonhosted.org/packages/97/75/10a9ebee3fd790d20926a90a2547f0bf78f371b2f13aa822c759680ca7b9/tomli-2.0.1-py3-none-any.whl',
    sha256:
        '939de3e7a6161af0c887ef91b7d41a53e7c5a1ca976325f429cb46ea9bc30ecc',
  ),
];

void main() async {
  print('=== Packaging Authentic Upstream OSINT (Sherlock) Universal Runtime Artifact ===');

  final scratchDir = Directory('tools/python-build/scratch_osint');
  if (!scratchDir.existsSync()) scratchDir.createSync(recursive: true);

  final unpackedDir = Directory('${scratchDir.path}/unpacked');
  if (unpackedDir.existsSync()) unpackedDir.deleteSync(recursive: true);
  unpackedDir.createSync(recursive: true);

  final client = HttpClient();

  for (final wheel in osintWheels) {
    final wheelFile = File('${scratchDir.path}/${wheel.filename}');
    final zipFile = File('${scratchDir.path}/${wheel.filename}.zip');

    if (!wheelFile.existsSync()) {
      print('Downloading ${wheel.name} wheel from ${wheel.url}...');
      final req = await client.getUrl(Uri.parse(wheel.url));
      final res = await req.close();
      final sink = wheelFile.openWrite();
      await res.pipe(sink);
      print('Downloaded: ${wheelFile.path} (${wheelFile.lengthSync()} bytes)');
    }

    final bytes = await wheelFile.readAsBytes();
    final actualSha = sha256.convert(bytes).toString().toLowerCase();
    if (actualSha != wheel.sha256.toLowerCase()) {
      stderr.writeln('ERROR: Checksum mismatch for ${wheel.filename}! Expected ${wheel.sha256}, got $actualSha');
      exit(1);
    }
    print('${wheel.name} verified: SHA-256 OK');

    await wheelFile.copy(zipFile.path);

    print('Extracting ${wheel.filename} into staging directory...');
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
        '-o',
        zipFile.absolute.path,
        '-d',
        unpackedDir.absolute.path,
      ]);
      if (res.exitCode != 0) {
        stderr.writeln('ERROR extracting wheel: ${res.stderr}');
        exit(1);
      }
    }
  }

  // Pure-Python adaptation of sherlock_project/sherlock.py for Android Bionic
  final sherlockFile = File('${unpackedDir.path}/sherlock_project/sherlock.py');
  if (!sherlockFile.existsSync()) {
    stderr.writeln('ERROR: sherlock_project/sherlock.py not found in unpacked directory!');
    exit(1);
  }

  print('Applying pure-Python fallback for optional pandas dependency...');
  var sherlockContent = await sherlockFile.readAsString();

  sherlockContent = sherlockContent.replaceFirst(
    'import pandas as pd',
    'try:\n    import pandas as pd\nexcept ImportError:\n    pd = None',
  );

  sherlockContent = sherlockContent.replaceFirst(
    '        if args.xlsx:\n            usernames = []',
    '        if args.xlsx:\n            if pd is None:\n                print("Error: Excel (.xlsx) export requires pandas and openpyxl.")\n                sys.exit(1)\n            usernames = []',
  );

  await sherlockFile.writeAsString(sherlockContent);
  print('sherlock.py patched for Android Bionic pure-Python execution.');

  // Pure-Python adaptation of sherlock_project/__init__.py for Android Bionic
  final initFile = File('${unpackedDir.path}/sherlock_project/__init__.py');
  if (initFile.existsSync()) {
    print('Applying tomllib compatibility to sherlock_project/__init__.py...');
    var initContent = await initFile.readAsString();
    initContent = initContent.replaceFirst(
      'import tomli',
      'try:\n    import tomllib as tomli\nexcept ImportError:\n    try:\n        import tomli\n    except ImportError:\n        tomli = None',
    );
    initContent = initContent.replaceFirst(
      'def get_version() -> str:\n    """Fetch the version number of the installed package."""\n    try:\n        return pkg_version("sherlock_project")\n    except PackageNotFoundError:',
      'def get_version() -> str:\n    """Fetch the version number of the installed package."""\n    try:\n        return pkg_version("sherlock_project")\n    except Exception:\n        try:\n            return pkg_version("sherlock-project")\n        except Exception:\n            return "0.16.2"\n    except PackageNotFoundError:',
    );
    await initFile.writeAsString(initContent);
    print('sherlock_project/__init__.py patched for tomllib/tomli compatibility.');
  }

  // Create target artifact directory
  final artifactDir = Directory('tools/runtime-artifacts/osint/universal');
  if (!artifactDir.existsSync()) artifactDir.createSync(recursive: true);

  final tarGzFile = File('${artifactDir.path}/sherlock.tar.gz');
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

  print('sherlock.tar.gz created: $tarGzSize bytes, SHA256: $tarGzSha');

  // Count files inside
  int fileCount = 0;
  for (final entity in unpackedDir.listSync(recursive: true)) {
    if (entity is File) fileCount++;
  }
  print('Extracted files count: $fileCount');

  // Generate manifest.json
  final manifest = {
    'schemaVersion': 1,
    'name': 'sherlock',
    'version': '0.16.2',
    'architecture': 'universal',
    'kind': 'osint-tool',
    'runtime': 'cpython-3.14',
    'description':
        'Hunt down social media accounts by username across 400+ social networks (pure-Python distribution for Android Bionic).',
    'entrypoints': [
      'sherlock_project',
      'usr/bin/sherlock',
    ],
    'archive': {
      'format': 'tar.gz',
      'filename': 'sherlock.tar.gz',
      'byteSize': tarGzSize,
      'sha256': tarGzSha,
    },
    'bundledPackages': [
      {'name': 'sherlock-project', 'version': '0.16.2'},
      {'name': 'requests-futures', 'version': '1.1.0'},
      {'name': 'colorama', 'version': '0.4.6'},
      {'name': 'PySocks', 'version': '1.7.1'},
      {'name': 'tomli', 'version': '2.0.1'},
    ],
    'fileCount': fileCount,
    'smokeTests': [
      {
        'command': 'python3',
        'arguments': ['-m', 'sherlock_project', '--help'],
        'expectedExitCode': 0,
        'expectedStdoutSubstring': 'Hunt down social media accounts by username across social networks',
      },
      {
        'command': 'python3',
        'arguments': ['-c', 'import sherlock_project, requests_futures, colorama, socks; print("OSINT_MODULES_OK")'],
        'expectedExitCode': 0,
        'expectedStdoutSubstring': 'OSINT_MODULES_OK',
      }
    ]
  };

  final manifestFile = File('${artifactDir.path}/manifest.json');
  await manifestFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
  print('manifest.json written to ${manifestFile.path}');

  print('\n=== Packaging Complete ===');
  print('Artifact: ${tarGzFile.path}');
  print('Manifest: ${manifestFile.path}');
  client.close();
}
