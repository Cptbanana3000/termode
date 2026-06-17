import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/persistence_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';
import 'package:termode/models/terminal_line.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VFS Serialization Tests', () {
    test('Serialize and deserialize VFS folders and files', () {
      final vfs = VirtualFileSystem();
      vfs.mkdir('projects');
      vfs.cd('projects');
      vfs.mkdir('termode');
      vfs.cd('termode');
      vfs.touch('main.dart', 'void main() {}');

      expect(vfs.getAbsolutePath(), '/home/projects/termode');

      // Convert VFS to JSON
      final jsonMap = vfs.toJson();

      // Restore VFS from JSON
      final restoredVfs = VirtualFileSystem.fromJson(jsonMap);

      // Verify initial directory before cd is /
      expect(restoredVfs.getAbsolutePath(), '/');

      // cd to original path
      final cdErr = restoredVfs.cd('/home/projects/termode');
      expect(cdErr, isNull);
      expect(restoredVfs.getAbsolutePath(), '/home/projects/termode');

      // Verify files and contents exist in restored VFS
      expect(restoredVfs.ls(), contains('main.dart'));
      expect(restoredVfs.cat('main.dart'), 'void main() {}');
    });
  });

  group('Session and State Persistence Tests', () {
    late Directory tempDir;
    late File tempFile;
    late PersistenceService testPersistence;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_test');
      tempFile = File('${tempDir.path}/test_state.json');
      testPersistence = PersistenceService(overrideFile: tempFile);
    });

    tearDown(() async {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('Tear down warning (ignored): $e');
      }
    });

    test('Save and load complete application state', () async {
      // 1. Setup mock services and configure some states
      final settings = SettingsService();
      settings.loadFromJson({
        'fontSize': 18.0,
        'themeColor': 'Amber',
        'startInRealShell': true,
      });

      final sessionService = TerminalSessionService();
      sessionService.persistenceService = testPersistence;

      // Add a session tab, run some VFS actions in it
      sessionService.addSession(); // session index 1 (Session 2)
      sessionService.executeCommand('mkdir docs');
      sessionService.executeCommand('cd docs');
      sessionService.executeCommand('touch text.txt "file content"');

      // Verify active session states
      expect(sessionService.activeSessionIndex, 1);
      expect(sessionService.currentPrompt, contains('~/docs'));

      // 2. Perform saveState to mock file
      await sessionService.saveState();

      // Verify file was written
      expect(await tempFile.exists(), isTrue);

      // 3. Reset memory session state (mimic app restart) and trigger loadState
      sessionService.clearMemoryStateForTesting();

      // Verify it is reset back to session 1 index 0
      expect(sessionService.activeSessionIndex, 0);

      // Load state from file
      await sessionService.loadPersistedState();

      // 4. Assert restored results
      expect(SettingsService().fontSize, 18.0);
      expect(SettingsService().themeColor, 'Amber');
      expect(SettingsService().startInRealShell, isTrue);
      expect(sessionService.sessions.length, 2);
      expect(sessionService.activeSessionIndex, 1);
      expect(sessionService.currentPrompt, contains('~/docs'));
      expect(sessionService.vfs.ls(), contains('text.txt'));
      expect(sessionService.vfs.cat('text.txt'), 'file content');
      expect(sessionService.activeSession.createdAt, isNotNull);
      expect(sessionService.activeSession.updatedAt, isNotNull);
      expect(sessionService.activeSession.isRealPtyActive, isFalse);
    });

    test('Scrollback trimming and command history persist safely', () async {
      SettingsService().loadFromJson({
        'startInRealShell': false,
        'maxScrollbackLines': 500,
      });
      final sessionService = TerminalSessionService();
      sessionService.persistenceService = testPersistence;
      sessionService.clearMemoryStateForTesting();

      for (var i = 0; i < 510; i++) {
        sessionService.activeSession.lines.add(
          TerminalLine(text: 'line $i', type: LineType.output),
        );
      }
      await sessionService.executeCommand('echo one');
      await sessionService.executeCommand('echo one');
      await sessionService.executeCommand('echo two');
      await sessionService.saveState();

      sessionService.clearMemoryStateForTesting();
      await sessionService.loadPersistedState();

      expect(sessionService.activeSession.lines.length, lessThanOrEqualTo(500));
      expect(sessionService.activeSession.commandHistory, [
        'echo one',
        'echo two',
      ]);
      expect(SettingsService().maxScrollbackLines, 500);
    });

    test('Cold restore marks old PTY sessions ended, not running', () async {
      SettingsService().loadFromJson({'startInRealShell': false});
      final sessionService = TerminalSessionService();
      sessionService.persistenceService = testPersistence;
      sessionService.clearMemoryStateForTesting();
      sessionService.activeSession.isRealPtyActive = true;
      sessionService.activeSession.isPtyInteractionActive = true;
      await sessionService.saveState();

      sessionService.clearMemoryStateForTesting();
      await sessionService.loadPersistedState();

      expect(sessionService.activeSession.isRealPtyActive, isFalse);
      expect(sessionService.activeSession.isPtyInteractionActive, isFalse);
      expect(
        sessionService.activeSession.lines.map((line) => line.text),
        contains('[previous shell session ended]'),
      );
    });
  });
}
