import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/models/terminal_session.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v0.65 Local Git Workflow and UX', () {
    late Directory tempDir;
    late CommandService commandService;
    final List<Map<String, dynamic>> invokedGitCalls = [];

    setUp(() async {
      invokedGitCalls.clear();
      tempDir = await Directory.systemTemp.createTemp('termode_git_local_test');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      commandService = CommandService(VirtualFileSystem(), 'git_workflow_test');

      RuntimeBinaryPackageService.gitExecutorForTesting = (
        arguments, {
        workingDirectory,
      }) async {
        invokedGitCalls.add({
          'arguments': arguments,
          'workingDirectory': workingDirectory,
        });
        final sub = arguments.firstOrNull;

        if (sub == 'commit' && arguments.contains('--no-identity')) {
          return NativeCommandResult(
            stdout: '',
            stderr:
                'Author identity unknown\n*** Please tell me who you are.\nRun\n  git config --global user.email "you@example.com"',
            exitCode: 128,
          );
        }
        if (sub == 'commit') {
          return NativeCommandResult(
            stdout: '[main 1234567] commit successful\n 1 file changed',
            stderr: '',
            exitCode: 0,
          );
        }
        if (sub == 'add') {
          return NativeCommandResult(stdout: '', stderr: '', exitCode: 0);
        }
        if (sub == 'status') {
          return NativeCommandResult(
            stdout: 'On branch main\nNothing to commit, working tree clean',
            stderr: '',
            exitCode: 0,
          );
        }
        if (sub == 'log') {
          return NativeCommandResult(
            stdout:
                'commit 1234567 (HEAD -> main)\nAuthor: Test <test@test.com>\nDate: Sun Sep 20 2026\n\n    initial commit',
            stderr: '',
            exitCode: 0,
          );
        }
        if (sub == 'diff') {
          return NativeCommandResult(
            stdout: 'diff --git a/file.txt b/file.txt\n+hello world',
            stderr: '',
            exitCode: 0,
          );
        }
        if (sub == 'branch') {
          return NativeCommandResult(
            stdout: '* main',
            stderr: '',
            exitCode: 0,
          );
        }
        if (sub == 'config') {
          return NativeCommandResult(
            stdout: 'test@example.com',
            stderr: '',
            exitCode: 0,
          );
        }
        return NativeCommandResult(
          stdout: 'git 2.44.0 command executed: ${arguments.join(' ')}',
          stderr: '',
          exitCode: 0,
        );
      };

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
                  return {'abi': 'arm64-v8a', 'pid': 9001};
                case 'getExecutablePaths':
                  return {
                    'nativeLibraryDir': '/data/app/example/lib/arm64',
                    'gitExecutable':
                        '/data/app/example/lib/arm64/libtermode_git_exec.so',
                  };
              }
              return null;
            },
          );

      // Mark Git as installed in metadata for testing
      final p = await runtime.getPaths();
      final varDir = Directory('${p['usr']}/var/termode/runtime-packages');
      await varDir.create(recursive: true);
      final metaFile = File('${varDir.path}/installed.json');
      await metaFile.writeAsString('''
{
  "schema": "termode.runtime-packages.v1",
  "packages": {
    "git": {
      "name": "git",
      "version": "2.44.0",
      "kind": "native-tool",
      "abi": "arm64-v8a",
      "entrypoint": "usr/bin/git",
      "entrypoints": ["git"],
      "logical_path": "usr/bin/git",
      "executable_backing_path": "/data/app/example/lib/arm64/libtermode_git_exec.so",
      "executable_storage": "native-library-dir",
      "executable_strategy": "native-library-dir",
      "execution_verified": true,
      "local_smoke_verified": true,
      "local_only": true,
      "remote_features_deferred": true,
      "status": "installed"
    }
  }
}
''');
    });

    tearDown(() async {
      RuntimeBinaryPackageService.gitExecutorForTesting = null;
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

    test('git status executes and returns working tree status', () async {
      final result = await commandService.execute('git status');
      expect(result.output, contains('On branch main'));
      expect(result.isError, isFalse);
    });

    test('git add and git commit execute local workflow', () async {
      final addResult = await commandService.execute('git add .');
      expect(addResult.isError, isFalse);

      final commitResult =
          await commandService.execute('git commit -m "commit successful"');
      expect(commitResult.output, contains('commit successful'));
      expect(commitResult.isError, isFalse);
    });

    test('git log and git diff return history and diffs', () async {
      final logResult = await commandService.execute('git log');
      expect(logResult.output, contains('commit 1234567'));
      expect(logResult.output, contains('initial commit'));

      final diffResult = await commandService.execute('git diff');
      expect(diffResult.output, contains('+hello world'));
    });

    test('git branch and git config are supported', () async {
      final branchResult = await commandService.execute('git branch');
      expect(branchResult.output, contains('* main'));

      final configResult =
          await commandService.execute('git config user.email');
      expect(configResult.output, contains('test@example.com'));
    });

    test('git commit hints on missing author identity', () async {
      final result =
          await commandService.execute('git commit --no-identity -m "test"');
      expect(result.output, contains('Author identity unknown'));
      expect(result.output, contains('git config --global user.name'));
      expect(result.output, contains('git config --global user.email'));
    });

    test('remote git operations return clean deferred messages', () async {
      final pushResult = await commandService.execute('git push origin main');
      expect(pushResult.output, contains('Remote Git operations (push) are deferred.'));
      expect(pushResult.output, contains('v0.65 supports offline local Git workflows only.'));

      final cloneResult =
          await commandService.execute('git clone https://github.com/example/repo.git');
      expect(cloneResult.output, contains('Remote Git operations (clone) are deferred.'));

      final pullResult = await commandService.execute('git pull');
      expect(pullResult.output, contains('Remote Git operations (pull) are deferred.'));

      final fetchResult = await commandService.execute('git fetch');
      expect(fetchResult.output, contains('Remote Git operations (fetch) are deferred.'));
    });

    test('git resolves session preferred working directory', () async {
      final session = TerminalSessionService().activeSession;
      session.preferredWorkingDirectory =
          '${tempDir.path}/files/home/projects/my_project';

      await commandService.execute('git status');
      expect(invokedGitCalls.isNotEmpty, isTrue);
      expect(
        invokedGitCalls.last['workingDirectory'],
        '${tempDir.path}/files/home/projects/my_project',
      );
    });
  });
}
