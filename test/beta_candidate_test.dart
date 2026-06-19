import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v0.40 Beta Candidate Packaging', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_beta40_test');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      commandService = CommandService(VirtualFileSystem(), 'beta40_test');

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
                  return {'abi': 'arm64-v8a', 'pid': 1234};
                case 'getPaths':
                  return {
                    'home': '${tempDir.path}/files/home',
                    'usr': '${tempDir.path}/files/usr',
                    'bin': '${tempDir.path}/files/usr/bin',
                    'tmp': '${tempDir.path}/files/tmp',
                  };
                case 'nativeTool':
                  final args = Map<String, dynamic>.from(call.arguments as Map);
                  if (args['command'] == 'doctor') {
                    return {
                      'ok': true,
                      'echoOk': true,
                      'cwd': '/native',
                      'abi': 'arm64-v8a',
                      'hashOk': true,
                    };
                  }
                  return {'ok': true};
                case 'jsProof':
                  final args = Map<String, dynamic>.from(call.arguments as Map);
                  if (args['command'] == 'doctor') {
                    return {
                      'ok': true,
                      'bridgeOk': true,
                      'evaluatorOk': true,
                      'errorsOk': true,
                    };
                  }
                  return {'ok': true, 'status': 'PROOF'};
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

    test('build-info output', () async {
      final result = await commandService.execute('build-info');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Build Info ==='));
      expect(result.output, contains('App: Termode'));
      expect(result.output, contains('Version: v0.49'));
      expect(result.output, contains('Build type:'));
      expect(result.output, contains('Runtime: prototype installer active'));
      expect(
        result.output,
        contains('Runtime package installer: prototype ready'),
      );
      expect(result.output, contains('Toolchains: planned'));
      expect(result.output, contains('Shell: REAL PTY'));
      expect(result.output, contains('Packages: script + runtime prototype'));
      expect(
        result.output,
        contains('Beta candidate: terminal foundation beta'),
      );
    });

    test('beta-candidate default/help output', () async {
      final bare = await commandService.execute('beta-candidate');
      final help = await commandService.execute('beta-candidate help');

      for (final out in [bare.output, help.output]) {
        expect(out, contains('=== Termode Beta Candidate ==='));
        expect(out, contains('beta-candidate status'));
        expect(out, contains('beta-candidate checklist'));
        expect(out, contains('beta-candidate ready'));
      }
    });

    test('beta-candidate status output', () async {
      final result = await commandService.execute('beta-candidate status');

      expect(result.output, contains('=== Termode Beta Candidate ==='));
      expect(result.output, contains('Version: v0.49'));
      expect(
        result.output,
        contains('Runtime package installer: prototype ready'),
      );
      expect(result.output, contains('Core shell: OK'));
      expect(result.output, contains('Packages: OK'));
      expect(result.output, contains('Workspaces: OK'));
      expect(result.output, contains('Sessions: OK'));
      expect(result.output, contains('Terminal UX: OK'));
      expect(result.output, contains('Runtime: FROZEN'));
      expect(result.output, contains('Prefix:'));
      expect(result.output, contains('PATH overlay:'));
      expect(result.output, contains('Known limitations: yes'));
      expect(result.output, contains('Overall: BETA CANDIDATE'));
      expect(result.isError, isFalse);
    });

    test('beta-candidate checklist output', () async {
      final result = await commandService.execute('beta-candidate checklist');

      expect(result.output, contains('=== Beta Candidate Checklist ==='));
      expect(result.output, contains('* doctor'));
      expect(result.output, contains('* beta-score'));
      expect(result.output, contains('* qa-status'));
      expect(result.output, contains('* pkg doctor'));
      expect(result.output, contains('* workspace-doctor'));
      expect(result.output, contains('* session-doctor'));
      expect(result.output, contains('* runtime-freeze doctor'));
      expect(result.output, contains('* settings-doctor'));
      expect(result.output, contains('* package install/remove test'));
    });

    test('beta-candidate notes output', () async {
      final result = await commandService.execute('beta-candidate notes');

      expect(result.output, contains('=== Termode v0.49 Beta Candidate ==='));
      expect(result.output, contains('prototype runtime package installer'));
      expect(result.output, contains('REAL PTY shell'));
      expect(result.output, contains('script packages'));
      expect(result.output, contains('Runtime remains frozen'));
    });

    test('beta-candidate limits output', () async {
      final result = await commandService.execute('beta-candidate limits');

      expect(result.output, contains('=== Beta Candidate Limits ==='));
      expect(result.output, contains('Node.js/npm are not included'));
      expect(result.output, contains('Python is not included'));
      expect(result.output, contains('Git has an artifact pipeline'));
      expect(
        result.output,
        contains('Runtime package installer is prototype-only'),
      );
      expect(result.output, contains('QuickJS/Duktape are deferred'));
      expect(result.output, contains('Beta software; bugs expected'));
    });

    test('beta-candidate ready treats frozen runtime as acceptable', () async {
      final result = await commandService.execute('beta-candidate ready');

      // Runtime is intentionally frozen and storage is unlinked, but core
      // subsystems are healthy, so Termode is beta-ready.
      expect(result.output, contains('Ready for beta testing.'));
      expect(result.isError, isFalse);
    });

    test('unknown beta-candidate subcommand errors', () async {
      final result = await commandService.execute('beta-candidate banana');
      expect(result.isError, isTrue);
      expect(result.output, contains('Unknown beta-candidate subcommand'));
    });

    test('version, release-notes, changelog mention v0.40', () async {
      final version = await commandService.execute('version');
      final notes = await commandService.execute('release-notes');
      final changelog = await commandService.execute('changelog');

      expect(version.output, contains('Termode v0.49'));
      expect(
        notes.output,
        contains('v0.44 Binary Package Installer Prototype'),
      );
      expect(
        notes.output,
        contains('v0.43 Prefix / PATH / Environment System'),
      );
      expect(notes.output, contains('v0.42 Runtime Expansion Architecture'));
      expect(
        changelog.output,
        contains('v0.42 Runtime Expansion Architecture'),
      );
    });

    test('bug-report and qa-report include v0.40', () async {
      final bug = await commandService.execute('bug-report');
      final qa = await commandService.execute('qa-report');

      expect(bug.output, contains('Termode version: v0.49'));
      expect(qa.output, contains('Termode v0.49'));
    });

    test('command catalog includes new v0.40 commands', () {
      for (final command in ['build-info', 'beta-candidate']) {
        expect(kTermodeCommands, contains(command));
      }
    });

    test('help includes a beta candidate section', () async {
      final result = await commandService.execute('help');
      expect(result.output, contains('Beta candidate:'));
      expect(result.output, contains('build-info'));
      expect(result.output, contains('beta-candidate status'));
    });

    test('commands and commands --all surface new commands', () async {
      final compact = await commandService.execute('commands');
      final all = await commandService.execute('commands --all');

      expect(compact.output, contains('beta-candidate status'));
      expect(all.output, contains('build-info'));
      expect(all.output, contains('beta-candidate'));
    });

    test('REAL PTY host interception includes new v0.40 commands', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('build-info');
      await sessionService.executeCommand('beta-candidate status');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('build-info'));
      expect(output, contains('=== Build Info ==='));
      expect(output, contains('beta-candidate status'));
      expect(output, contains('=== Termode Beta Candidate ==='));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });
  });
}
