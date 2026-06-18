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

  group('v0.42 Runtime Expansion Architecture', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_rexp_test');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      commandService = CommandService(VirtualFileSystem(), 'rexp_test');

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

    test('prefix-info before and after init', () async {
      final before = await commandService.execute('prefix-info');
      expect(before.output, contains('=== Termode Prefix ==='));
      expect(before.output, contains('Home:'));
      expect(before.output, contains('Prefix:'));
      expect(before.output, contains('Bin:'));
      expect(before.output, contains('Toolchains:'));
      expect(before.output, contains('Status: not initialized'));

      await commandService.execute('prefix-init');
      final after = await commandService.execute('prefix-info');
      expect(after.output, contains('Status: initialized'));
    });

    test('prefix-init is idempotent and never deletes', () async {
      final first = await commandService.execute('prefix-init');
      expect(first.output, contains('=== Termode Prefix Init ==='));
      expect(first.output, contains('Created:'));
      expect(first.output, contains('Status: initialized'));
      expect(first.isError, isFalse);

      final second = await commandService.execute('prefix-init');
      expect(second.output, contains('Created: 0'));
      expect(second.output, contains('Already existed:'));
      expect(second.output, contains('Status: initialized'));
    });

    test('prefix-doctor LIMITED before init, HEALTHY after', () async {
      final before = await commandService.execute('prefix-doctor');
      expect(before.output, contains('=== Termode Prefix Doctor ==='));
      expect(before.output, contains('Path safety: OK'));
      expect(before.output, contains('Overall: LIMITED'));

      await commandService.execute('prefix-init');
      final after = await commandService.execute('prefix-doctor');
      expect(after.output, contains('Write access: OK'));
      expect(after.output, contains('Overall: HEALTHY'));
      expect(after.isError, isFalse);
    });

    test('path-info and env-info are planning-only', () async {
      final path = await commandService.execute('path-info');
      expect(path.output, contains('=== Termode PATH ==='));
      expect(path.output, contains('Future PATH order:'));
      expect(path.output, contains('not modified yet'));

      final env = await commandService.execute('env-info');
      expect(env.output, contains('TERMODE_HOME:'));
      expect(env.output, contains('TERMODE_PREFIX:'));
      expect(env.output, contains('TERMODE_BIN:'));
      expect(env.output, contains('TERMODE_WORKSPACES:'));
    });

    test('toolchain-status and toolchain-list', () async {
      final status = await commandService.execute('toolchain-status');
      expect(status.output, contains('=== Toolchain Status ==='));
      expect(status.output, contains('Git: planned'));
      expect(status.output, contains('Node.js: planned'));
      expect(status.output, contains('Overall: ARCHITECTURE PHASE'));

      final list = await commandService.execute('toolchain-list');
      expect(list.output, contains('* git'));
      expect(list.output, contains('* node'));
      expect(list.output, contains('* python'));
    });

    test('toolchain-info git, node, and unknown', () async {
      final git = await commandService.execute('toolchain-info git');
      expect(git.output, contains('=== Toolchain: Git ==='));
      expect(git.output, contains('Status: not installed yet'));
      expect(git.output, contains('Expected command: git'));
      expect(git.output, contains('runtime-install git'));

      final node = await commandService.execute('toolchain-info node');
      expect(node.output, contains('Node.js'));
      expect(node.output, contains('node, npm later'));
      expect(node.output, contains('Node comes before npm'));

      final unknown = await commandService.execute('toolchain-info banana');
      expect(unknown.isError, isTrue);
      expect(unknown.output, contains('Unknown toolchain: banana'));
    });

    test('toolchain-doctor does not fail for missing tools', () async {
      final result = await commandService.execute('toolchain-doctor');
      expect(result.output, contains('=== Toolchain Doctor ==='));
      expect(result.output, contains('Overall: ARCHITECTURE PHASE'));
      expect(result.isError, isFalse);
    });

    test('runtime-install default/help and list', () async {
      final bare = await commandService.execute('runtime-install');
      final help = await commandService.execute('runtime-install help');
      for (final out in [bare.output, help.output]) {
        expect(out, contains('=== Runtime Install (planning) ==='));
        expect(out, contains('planning surface only'));
        expect(out, contains('runtime-install list'));
      }

      final list = await commandService.execute('runtime-install list');
      expect(list.output, contains('Available planned runtimes:'));
      expect(list.output, contains('* git'));
      expect(list.output, contains('* node'));
    });

    test('runtime-install plan node and git', () async {
      final node = await commandService.execute('runtime-install plan node');
      expect(node.output, contains('=== Runtime Install Plan: Node.js ==='));
      expect(node.output, contains('Status: planned'));
      expect(node.output, contains('Install support: not implemented yet'));
      expect(node.output, contains('Run node --version.'));
      expect(node.output, contains('Run: toolchain-info node'));

      final git = await commandService.execute('runtime-install plan git');
      expect(git.output, contains('=== Runtime Install Plan: Git ==='));
      expect(git.output, contains('Run git --version.'));
    });

    test('runtime-install status and doctor are planning-only', () async {
      final status = await commandService.execute('runtime-install status');
      expect(status.output, contains('=== Runtime Install Status ==='));
      expect(status.output, contains('Mode: planning only'));
      expect(status.output, contains('Real installs: not enabled yet'));
      expect(
        status.output,
        contains('Next milestone: v0.43 Prefix / PATH / Environment System'),
      );

      final doctor = await commandService.execute('runtime-install doctor');
      expect(doctor.output, contains('=== Runtime Install Doctor ==='));
      expect(doctor.output, contains('Android ABI: arm64-v8a'));
      expect(doctor.output, contains('Overall: ARCHITECTURE PHASE'));
      expect(doctor.isError, isFalse);
    });

    test('dev-setup default/help, list, and plans', () async {
      final bare = await commandService.execute('dev-setup');
      expect(bare.output, contains('=== Dev Setup (planning) ==='));
      expect(bare.output, contains('dev-setup list'));

      final list = await commandService.execute('dev-setup list');
      expect(list.output, contains('Available future presets:'));
      expect(list.output, contains('* web'));
      expect(list.output, contains('* node'));
      expect(list.output, contains('* python'));
      expect(list.output, contains('* basic-tools'));

      final web = await commandService.execute('dev-setup plan web');
      expect(web.output, contains('=== Dev Setup Plan: web ==='));
      expect(web.output, contains('Install Node.js.'));
      expect(web.output, contains('Open preview URL.'));

      final node = await commandService.execute('dev-setup plan node');
      expect(node.output, contains('=== Dev Setup Plan: node ==='));
      expect(node.output, contains('Run dev-doctor.'));

      final python = await commandService.execute('dev-setup plan python');
      expect(python.output, contains('=== Dev Setup Plan: python ==='));
      expect(python.output, contains('Install Python.'));
    });

    test('dev-doctor reports foundation and planned toolchains', () async {
      final result = await commandService.execute('dev-doctor');
      expect(result.output, contains('=== Dev Doctor ==='));
      expect(result.output, contains('Terminal: OK'));
      expect(result.output, contains('REAL PTY: OK'));
      expect(result.output, contains('Git: planned'));
      expect(result.output, contains('Node.js: planned'));
      expect(
        result.output,
        anyOf(contains('Overall: FOUNDATION READY'),
            contains('Overall: ARCHITECTURE PHASE')),
      );
    });

    test('beta-candidate ready despite planned missing toolchains', () async {
      final result = await commandService.execute('beta-candidate ready');
      expect(result.output, contains('Ready for beta testing.'));
      expect(result.isError, isFalse);
    });

    test('command catalog includes new runtime-expansion commands', () {
      for (final command in [
        'prefix-info',
        'prefix-init',
        'prefix-doctor',
        'path-info',
        'env-info',
        'toolchain-status',
        'toolchain-doctor',
        'toolchain-plan',
        'toolchain-list',
        'toolchain-info',
        'runtime-install',
        'dev-setup',
        'dev-doctor',
      ]) {
        expect(kTermodeCommands, contains(command));
      }
    });

    test('REAL PTY host interception includes runtime-expansion commands', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('prefix-info');
      await sessionService.executeCommand('toolchain-status');
      await sessionService.executeCommand('runtime-install list');
      await sessionService.executeCommand('dev-doctor');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('=== Termode Prefix ==='));
      expect(output, contains('=== Toolchain Status ==='));
      expect(output, contains('Available planned runtimes:'));
      expect(output, contains('=== Dev Doctor ==='));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });
  });
}
