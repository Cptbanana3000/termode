import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Toybox Runtime Layer Tests', () {
    late Directory tempDir;
    late RuntimeBootstrapService bootstrapService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_toybox_test');
      bootstrapService = RuntimeBootstrapService();
      bootstrapService.overrideBaseDir = tempDir;
      await bootstrapService.init();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.termode/native_shell'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'executeCommand') {
            final command = methodCall.arguments['command'] as String;
            if (command == '/system/bin/toybox') {
              return {
                'stdout': 'toybox 0.8.9-android\nls ps cat echo uname\n',
                'stderr': '',
                'exitCode': 0,
              };
            }
            if (command == '/system/bin/toybox uname -a') {
              return {
                'stdout': 'Linux termode-sandbox-phone\n',
                'stderr': '',
                'exitCode': 0,
              };
            }
          }
          return null;
        },
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.termode/native_shell'),
        null,
      );
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('toybox and toybox-list execution', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_toybox');

      // toybox-list
      final listResult = await commandService.execute('toybox-list');
      expect(listResult.isError, isFalse);
      expect(listResult.output, contains('toybox 0.8.9-android'));

      // toybox uname -a
      final cmdResult = await commandService.execute('toybox uname -a');
      expect(cmdResult.isError, isFalse);
      expect(cmdResult.output, contains('Linux termode-sandbox-phone'));
    });

    test('runtime-pwd print working directory path', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_toybox');

      final pwdResult = await commandService.execute('runtime-pwd');
      expect(pwdResult.isError, isFalse);
      expect(pwdResult.output, contains('files/home'));
    });

    test('runtime-write and runtime-cat file operations', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_toybox');

      // Write text
      final writeResult = await commandService.execute('runtime-write test.txt Hello from Termode Toybox Runtime!');
      expect(writeResult.isError, isFalse);
      expect(writeResult.output, contains('Wrote 34 characters'));

      // Cat text
      final catResult = await commandService.execute('runtime-cat test.txt');
      expect(catResult.isError, isFalse);
      expect(catResult.output, 'Hello from Termode Toybox Runtime!');
    });

    test('Path traversal prevention checks', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_toybox');

      // Try reading outside home using ../
      final catTraversal = await commandService.execute('runtime-cat ../usr/termode-runtime.json');
      expect(catTraversal.isError, isTrue);
      expect(catTraversal.output, contains('path traversal detected'));

      // Try writing outside home using ../
      final writeTraversal = await commandService.execute('runtime-write ../outside.txt traversal-attack');
      expect(writeTraversal.isError, isTrue);
      expect(writeTraversal.output, contains('path traversal detected'));
    });

    test('runtime-ls lists sandbox home files', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_toybox');

      // Empty directory check
      final lsEmptyResult = await commandService.execute('runtime-ls');
      expect(lsEmptyResult.output, contains('(empty directory)'));

      // Write a file
      await commandService.execute('runtime-write file1.txt hello');
      await commandService.execute('runtime-write file2.txt world');

      // Populate list check
      final lsResult = await commandService.execute('runtime-ls');
      expect(lsResult.output, contains('file1.txt'));
      expect(lsResult.output, contains('file2.txt'));
    });
  });
}
