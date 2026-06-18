import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/runtime_prefix_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v0.44 Binary Package Installer Prototype', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_binpkg_test');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      commandService = CommandService(VirtualFileSystem(), 'binpkg_test');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (call) async {
              switch (call.method) {
                case 'getStorageStatus':
                  return null;
                case 'realPtySend':
                case 'realPtySendRaw':
                  return true;
                case 'getDiagnostics':
                  return {'abi': 'arm64-v8a', 'pid': 4321};
                case 'getPaths':
                  return {
                    'home': '${tempDir.path}/files/home',
                    'usr': '${tempDir.path}/files/usr',
                    'bin': '${tempDir.path}/files/usr/bin',
                    'tmp': '${tempDir.path}/files/tmp',
                  };
              }
              return null;
            },
          );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            null,
          );
      SettingsService().loadFromJson(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('runtime-pkg default/help and available output', () async {
      final bare = await commandService.execute('runtime-pkg');
      final help = await commandService.execute('runtime-pkg help');
      final available = await commandService.execute('runtime-pkg available');

      for (final output in [bare.output, help.output]) {
        expect(output, contains('Runtime Package Prototype'));
        expect(output, contains('Prototype package: hello-bin'));
        expect(output, contains('No Git, Node.js, npm, Python'));
      }
      expect(available.output, contains('Prototype available now:'));
      expect(available.output, contains('hello-bin'));
      expect(available.output, contains('Real Git/Node/npm/Python'));
    });

    test('runtime-pkg info handles hello-bin and unknown packages', () async {
      final info = await commandService.execute('runtime-pkg info hello-bin');
      expect(info.output, contains('=== Runtime Package: hello-bin ==='));
      expect(info.output, contains('Kind: script-tool'));
      expect(info.output, contains('Command: hello-bin'));
      expect(info.output, contains('Status: available'));

      final unknown = await commandService.execute('runtime-pkg info banana');
      expect(unknown.isError, isTrue);
      expect(unknown.output, contains('Unknown runtime package: banana'));
    });

    test(
      'install, list, verify, run, bin, shim, and remove hello-bin',
      () async {
        final listBefore = await commandService.execute('runtime-pkg list');
        expect(listBefore.output, contains('No runtime packages installed'));

        final whichBefore = await commandService.execute('bin-which hello-bin');
        expect(whichBefore.output, contains('Not found in Termode PATH'));

        final install = await commandService.execute(
          'runtime-pkg install hello-bin',
        );
        expect(install.isError, isFalse);
        expect(install.output, contains('Installed: hello-bin'));
        expect(install.output, contains('Command: hello-bin'));
        expect(install.output, contains('Run: hello-bin'));

        final listAfter = await commandService.execute('runtime-pkg list');
        expect(listAfter.output, contains('hello-bin [1.0.0] script-tool'));

        final verify = await commandService.execute(
          'runtime-pkg verify hello-bin',
        );
        expect(verify.output, contains('Checksum: OK'));
        expect(verify.output, contains('Status: HEALTHY'));

        final run = await commandService.execute('hello-bin');
        expect(
          run.output,
          contains('Hello from Termode binary package prototype.'),
        );

        final binList = await commandService.execute('bin-list');
        expect(binList.output, contains('hello-bin'));

        final whichAfter = await commandService.execute('bin-which hello-bin');
        expect(whichAfter.output, contains('usr/bin/hello-bin'));

        final shimList = await commandService.execute('shim-list');
        expect(
          shimList.output,
          contains('hello-bin -> runtime package prototype'),
        );

        final remove = await commandService.execute(
          'runtime-pkg remove hello-bin',
        );
        expect(remove.isError, isFalse);
        expect(remove.output, contains('Removed: hello-bin'));

        final runAfterRemove = await commandService.execute('hello-bin');
        expect(runAfterRemove.isError, isTrue);
        expect(
          runAfterRemove.output,
          contains('runtime-pkg install hello-bin'),
        );
      },
    );

    test('unknown install/remove/verify are rejected safely', () async {
      final install = await commandService.execute(
        'runtime-pkg install banana',
      );
      expect(install.isError, isTrue);
      expect(install.output, contains('Unknown runtime package: banana'));

      final remove = await commandService.execute('runtime-pkg remove banana');
      expect(remove.isError, isTrue);
      expect(remove.output, contains('Runtime package not installed: banana'));

      final verify = await commandService.execute('runtime-pkg verify banana');
      expect(verify.isError, isTrue);
      expect(verify.output, contains('Runtime package not installed: banana'));
    });

    test('status, doctor, repair, and corrupt metadata handling', () async {
      final statusBefore = await commandService.execute('runtime-pkg status');
      expect(statusBefore.output, contains('Installed runtime packages: 0'));
      expect(statusBefore.output, contains('Available prototype packages: 1'));

      final doctorBefore = await commandService.execute('runtime-pkg doctor');
      expect(doctorBefore.output, contains('Prototype installer: enabled'));
      expect(doctorBefore.output, contains('Overall: LIMITED'));

      final repair = await commandService.execute('runtime-pkg repair');
      expect(repair.output, contains('Runtime Package Repair'));
      expect(repair.output, contains('Unknown files deleted: 0'));

      final paths = await RuntimePrefixService().paths();
      final metadataFile = File(
        '${paths['var']}/termode/runtime-packages/installed.json',
      );
      await metadataFile.parent.create(recursive: true);
      await metadataFile.writeAsString('{corrupt json');

      final list = await commandService.execute('runtime-pkg list');
      expect(list.isError, isFalse);
      expect(list.output, contains('No runtime packages installed'));

      final repairCorrupt = await commandService.execute('runtime-pkg repair');
      expect(repairCorrupt.output, contains('Status: OK'));
      final decoded = jsonDecode(await metadataFile.readAsString()) as Map;
      expect(decoded['packages'], isA<Map>());
    });

    test('manifest validation rejects unsafe manifests', () {
      final service = RuntimeBinaryPackageService();
      final valid = service.helloBinManifest();
      expect(service.validateManifest(valid), isEmpty);

      final absolute = Map<String, dynamic>.from(valid);
      absolute['files'] = [
        {'path': '/system/bin/bad', 'sha256': List.filled(64, '0').join()},
      ];
      expect(service.validateManifest(absolute), contains('unsafe file path'));

      final traversal = Map<String, dynamic>.from(valid);
      traversal['files'] = [
        {'path': '../bad', 'sha256': List.filled(64, '0').join()},
      ];
      expect(service.validateManifest(traversal), contains('unsafe file path'));

      final badCommand = Map<String, dynamic>.from(valid);
      badCommand['command'] = '../hello';
      expect(
        service.validateManifest(badCommand),
        contains('invalid command name'),
      );
    });

    test('runtime-install, dev-doctor, and runtime-abi integration', () async {
      final status = await commandService.execute('runtime-install status');
      expect(status.output, contains('Mode: prototype installer available'));
      expect(status.output, contains('Prototype package: hello-bin'));
      expect(status.output, contains('Next milestone: v0.45 Git Support'));

      final list = await commandService.execute('runtime-install list');
      expect(list.output, contains('Prototype available now:'));
      expect(list.output, contains('* hello-bin'));
      expect(list.output, contains('Planned future runtimes:'));
      expect(list.output, contains('* git'));

      final doctor = await commandService.execute('runtime-install doctor');
      expect(doctor.output, contains('Prototype installer: enabled'));
      expect(doctor.output, contains('Overall: PROTOTYPE READY'));

      final devDoctor = await commandService.execute('dev-doctor');
      expect(
        devDoctor.output,
        contains('Runtime package installer: prototype ready'),
      );
      expect(devDoctor.output, contains('Git: planned'));
      expect(devDoctor.output, contains('Overall: PROTOTYPE READY'));

      final abi = await commandService.execute('runtime-abi');
      expect(abi.output, contains('=== Runtime ABI ==='));
      expect(abi.output, contains('Android ABI: arm64-v8a'));
      expect(abi.output, contains('Prototype package install: enabled'));
    });

    test(
      'catalog, help, commands, and REAL PTY interception include v0.44 commands',
      () async {
        for (final command in ['runtime-pkg', 'runtime-abi', 'hello-bin']) {
          expect(kTermodeCommands, contains(command));
        }

        final help = await commandService.execute('help');
        expect(help.output, contains('runtime-pkg status'));
        expect(help.output, contains('runtime-abi'));

        final commands = await commandService.execute('commands');
        expect(commands.output, contains('runtime-pkg install hello-bin'));
        expect(commands.output, contains('hello-bin'));

        final all = await commandService.execute('commands --all');
        expect(all.output, contains('runtime-pkg'));
        expect(all.output, contains('runtime-abi'));
        expect(all.output, contains('hello-bin'));

        final sessionService = TerminalSessionService();
        final session = sessionService.activeSession;
        session.lines.clear();
        session.isRealPtyActive = true;
        session.isPtyInteractionActive = true;

        await sessionService.executeCommand('runtime-pkg available');
        await sessionService.executeCommand('runtime-abi');
        await sessionService.executeCommand('runtime-pkg install hello-bin');
        await sessionService.executeCommand('hello-bin');

        final output = session.lines.map((line) => line.text).join('\n');
        expect(output, contains('Available Runtime Packages'));
        expect(output, contains('Runtime ABI'));
        expect(output, contains('Installed: hello-bin'));
        expect(
          output,
          contains('Hello from Termode binary package prototype.'),
        );

        session.isPtyInteractionActive = false;
        session.isRealPtyActive = false;
      },
    );

    test('beta ready and version surfaces mention v0.44', () async {
      final ready = await commandService.execute('beta-candidate ready');
      expect(ready.isError, isFalse);
      expect(ready.output, contains('Ready for beta testing.'));

      final version = await commandService.execute('version');
      expect(version.output, contains('Termode v0.44'));

      final notes = await commandService.execute('release-notes');
      expect(
        notes.output,
        contains('v0.44 Binary Package Installer Prototype'),
      );

      final bug = await commandService.execute('bug-report');
      expect(bug.output, contains('Termode version: v0.44'));

      final qa = await commandService.execute('qa-report');
      expect(qa.output, contains('Termode v0.44'));
    });
  });
}
