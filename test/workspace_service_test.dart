import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/package_manager_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Workspace and host file commands', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;
    late List<MethodCall> methodCalls;
    String? linkedStorage;
    List<String> storageFiles = [];
    Map<String, String> storageContent = {};

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_workspace_test');
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();

      SettingsService().loadFromJson({'startInRealShell': false});
      TerminalSessionService().clearMemoryStateForTesting();
      methodCalls = [];
      linkedStorage = null;
      storageFiles = [];
      storageContent = {};

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (MethodCall call) async {
              methodCalls.add(call);
              switch (call.method) {
                case 'realPtyStart':
                  return true;
                case 'realPtySend':
                  return true;
                case 'getStorageStatus':
                  if (linkedStorage == null) return null;
                  return {'uri': linkedStorage, 'displayName': 'MockStorage'};
                case 'listStorageFiles':
                  if (linkedStorage == null) {
                    throw PlatformException(
                      code: 'NOT_LINKED',
                      message: 'No linked folder',
                    );
                  }
                  return storageFiles;
                case 'readStorageFile':
                  final filename = call.arguments['filename'] as String;
                  if (!storageContent.containsKey(filename)) {
                    throw PlatformException(
                      code: 'FILE_NOT_FOUND',
                      message: 'File not found',
                    );
                  }
                  return storageContent[filename];
                case 'writeStorageFile':
                  final filename = call.arguments['filename'] as String;
                  final content = call.arguments['content'] as String;
                  storageContent[filename] = content;
                  if (!storageFiles.contains(filename)) {
                    storageFiles.add(filename);
                  }
                  return true;
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
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('workspace root creation and init/list safety', () async {
      final commandService = CommandService(VirtualFileSystem(), 'workspace');

      final status = await commandService.execute('workspace');
      expect(status.output, contains('Workspace:'));
      expect(
        Directory('${tempDir.path}/files/home/projects').existsSync(),
        isTrue,
      );

      final init = await commandService.execute('workspace-init demo');
      expect(init.isError, isFalse);
      expect(init.output, contains('Workspace ready: demo'));
      expect(
        File(
          '${tempDir.path}/files/home/projects/demo/.termode-project',
        ).existsSync(),
        isTrue,
      );

      final traversal = await commandService.execute('workspace-init ../bad');
      expect(traversal.isError, isTrue);
      expect(traversal.output, contains('cannot contain slashes'));

      final slash = await commandService.execute('workspace-init bad/name');
      expect(slash.isError, isTrue);
      expect(slash.output, contains('cannot contain slashes'));

      final list = await commandService.execute('workspace-list');
      expect(list.output, contains('demo'));
    });

    test(
      'workspace-cd updates preferred cwd and REAL PTY start uses it',
      () async {
        final commandService = CommandService(VirtualFileSystem(), 'workspace');
        final sessionService = TerminalSessionService();

        await commandService.execute('workspace-init demo');
        final cd = await commandService.execute('workspace-cd demo');
        expect(cd.output, contains('Workspace selected for next shell: demo'));
        expect(
          sessionService.activeSession.preferredWorkingDirectory,
          endsWith(
            '${Platform.pathSeparator}home${Platform.pathSeparator}projects${Platform.pathSeparator}demo',
          ),
        );

        final pwdHost = await commandService.execute('pwd-host');
        expect(pwdHost.output, contains('projects'));
        expect(pwdHost.output, contains('demo'));

        await sessionService.startRealPty(sessionService.activeSession.id);
        final startCall = methodCalls.lastWhere(
          (call) => call.method == 'realPtyStart',
        );
        expect(startCall.arguments['workingDirectory'], contains('demo'));
      },
    );

    test('invalid preferred directory falls back to home', () async {
      final sessionService = TerminalSessionService();
      sessionService.activeSession.preferredWorkingDirectory =
          '${tempDir.path}/files/home/projects/missing';

      await sessionService.startRealPty(sessionService.activeSession.id);
      final startCall = methodCalls.lastWhere(
        (call) => call.method == 'realPtyStart',
      );
      expect(
        startCall.arguments['workingDirectory'],
        Directory('${tempDir.path}/files/home').absolute.path,
      );
    });

    test('workspace-cd sends safe cd when REAL PTY is active', () async {
      final commandService = CommandService(VirtualFileSystem(), 'workspace');
      final sessionService = TerminalSessionService();
      await commandService.execute('workspace-init demo');
      sessionService.activeSession.isRealPtyActive = true;
      sessionService.activeSession.isPtyInteractionActive = true;

      final cd = await commandService.execute('workspace-cd demo');
      expect(cd.output, contains('Workspace: demo'));
      final sendCall = methodCalls.lastWhere(
        (call) => call.method == 'realPtySend',
      );
      expect(sendCall.arguments['text'], startsWith('cd '));
      expect(sendCall.arguments['text'], contains('demo'));
    });

    test('workspace-remove requires confirm and stays inside root', () async {
      final commandService = CommandService(VirtualFileSystem(), 'workspace');
      await commandService.execute('workspace-init demo');

      final warn = await commandService.execute('workspace-remove demo');
      expect(warn.output, contains('workspace-remove demo --confirm'));
      expect(
        Directory('${tempDir.path}/files/home/projects/demo').existsSync(),
        isTrue,
      );

      final bad = await commandService.execute(
        'workspace-remove ../bad --confirm',
      );
      expect(bad.isError, isTrue);

      final removed = await commandService.execute(
        'workspace-remove demo --confirm',
      );
      expect(removed.output, contains('Removed workspace: demo'));
      expect(
        Directory('${tempDir.path}/files/home/projects/demo').existsSync(),
        isFalse,
      );
    });

    test('host file commands operate inside workspace safely', () async {
      final commandService = CommandService(VirtualFileSystem(), 'workspace');
      await commandService.execute('workspace-init demo');
      await commandService.execute('workspace-cd demo');

      final write = await commandService.execute(
        'host-write hello.txt hello workspace',
      );
      expect(write.output, contains('Wrote 15 characters'));
      expect(
        (await commandService.execute('host-ls')).output,
        contains('hello.txt'),
      );
      expect(
        (await commandService.execute('host-cat hello.txt')).output,
        'hello workspace',
      );
      expect(
        (await commandService.execute('host-touch empty.txt')).output,
        contains('Touched'),
      );
      expect(
        (await commandService.execute('host-mkdir src')).output,
        contains('Created'),
      );
      expect(
        (await commandService.execute('host-rm empty.txt')).output,
        contains('Removed'),
      );

      final outside = File('${tempDir.path}/outside.txt')
        ..writeAsStringSync('x');
      final traversal = await commandService.execute(
        'host-cat ${outside.path}',
      );
      expect(traversal.isError, isTrue);
      expect(traversal.output, contains('path escapes'));
    });

    test('host-rm cannot delete protected files', () async {
      final paths = await runtime.getPaths();
      final protectedFile = File('${paths['usr']}/termode-shell-helpers.sh');
      protectedFile.createSync(recursive: true);
      protectedFile.writeAsStringSync('helpers');
      final commandService = CommandService(VirtualFileSystem(), 'workspace');

      final result = await commandService.execute(
        'host-rm ${protectedFile.path}',
      );
      expect(result.isError, isTrue);
      expect(result.output, contains('protected'));
      expect(protectedFile.existsSync(), isTrue);
    });

    test('storage projects and shallow workspace import/export', () async {
      linkedStorage = 'content://mock/tree';
      storageFiles = ['demo', 'demo-readme.txt', 'notes.txt'];
      storageContent = {'demo-readme.txt': 'from storage'};
      final commandService = CommandService(VirtualFileSystem(), 'workspace');

      final projects = await commandService.execute('storage-projects');
      expect(projects.output, contains('demo'));

      final imported = await commandService.execute(
        'workspace-import-storage demo imported',
      );
      expect(imported.output, contains('Imported 1 file'));
      expect(
        File(
          '${tempDir.path}/files/home/projects/imported/demo-readme.txt',
        ).readAsStringSync(),
        'from storage',
      );

      await commandService.execute('workspace-cd imported');
      await commandService.execute('host-write local.txt export me');
      final exported = await commandService.execute(
        'workspace-export-storage imported exported',
      );
      expect(exported.output, contains('Exported 2 file'));
      expect(storageContent['exported-local.txt'], 'export me');
    });

    test('workspace doctor and path-lite include workspace info', () async {
      final commandService = CommandService(VirtualFileSystem(), 'workspace');
      await commandService.execute('workspace-init demo');
      await commandService.execute('workspace-cd demo');

      final doctor = await commandService.execute('workspace-doctor');
      expect(doctor.isError, isFalse);
      expect(doctor.output, contains('=== Workspace Doctor ==='));
      expect(doctor.output, contains('Overall: HEALTHY'));

      final verbose = await commandService.execute(
        'workspace-doctor --verbose',
      );
      expect(verbose.output, contains('Projects path:'));

      final paths = await runtime.getPaths();
      final pm = PackageManagerService();
      await pm.installPackage('path-lite');
      final script = File('${paths['usr']}/bin/path-lite').readAsStringSync();
      expect(script, contains('TERMODE_PROJECTS'));
      expect(script, contains('WORKSPACE='));
    });
  });
}
