import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Polish and Clarity Command Tests', () {
    late Directory tempDir;
    late RuntimeBootstrapService bootstrapService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_polish_test');
      bootstrapService = RuntimeBootstrapService();
      bootstrapService.overrideBaseDir = tempDir;
      await bootstrapService.init();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'getStorageStatus') {
                return null;
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

    test(
      'whereami displays both VFS and native sandbox environments',
      () async {
        final vfs = VirtualFileSystem();
        vfs.cd('/home');
        final commandService = CommandService(vfs, 'session_polish');

        final result = await commandService.execute('whereami');
        expect(result.isError, isFalse);
        expect(result.output, contains('=== Active Working Environments ==='));
        expect(result.output, contains('Dart Virtual Filesystem (VFS):'));
        expect(result.output, contains('CWD: /home'));
        expect(result.output, contains('Native Sandbox Runtime:'));
        expect(result.output, contains('Home:'));
        expect(result.output, contains('Bin:'));
        expect(result.output, contains('Tmp:'));
        expect(result.output, contains('Real Workspace Files:'));
        expect(result.output, contains('State: HEALTHY'));
        expect(
          result.output,
          contains('workspace/host-* commands use real Termode files'),
        );
      },
    );

    test('runtime-help lists only native commands and warning message', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_polish');

      final result = await commandService.execute('runtime-help');
      expect(result.isError, isFalse);
      expect(
        result.output,
        contains(
          'WARNING: Native sandbox commands operate directly on physical storage.',
        ),
      );
      expect(result.output, contains('Native Sandbox Commands:'));
      expect(result.output, contains('android-shell [cmd]'));
      expect(result.output, contains('android-shell-env'));
      expect(result.output, contains('android-shell-diag'));
      expect(result.output, contains('termode-runtime status'));
      expect(result.output, contains('toybox [args...]'));
      expect(result.output, contains('runtime-pwd'));
      expect(result.output, contains('runtime-ls'));
      expect(result.output, contains('runtime-cat [file]'));
      expect(result.output, contains('runtime-write [fl] [t]'));
      expect(result.output, contains('workspace-*'));
      expect(result.output, contains('host-*'));
    });

    test(
      'default help lists VFS commands in mobile-optimized layout',
      () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_polish');

        final result = await commandService.execute('help');
        expect(result.isError, isFalse);
        expect(
          result.output,
          contains('Termode runs in a true native REAL PTY shell by default.'),
        );
        expect(
          result.output,
          contains('whereami    - View active sandbox directories'),
        );
        expect(result.output, contains('Termode VFS Commands:'));
        expect(
          result.output,
          contains('pwd         - Print VFS working directory'),
        );
        expect(result.output, contains('ls [path]   - List VFS directory'));
        expect(result.output, contains('rm [path]   - Remove VFS file/dir'));
        // Ensure native commands are excluded from the main VFS list
        expect(result.output, isNot(contains('android-shell [command]')));
        expect(result.output, isNot(contains('toybox [args...]')));
      },
    );
  });
}
