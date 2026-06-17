import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageAccessService and Commands Tests', () {
    late Directory tempDir;
    late RuntimeBootstrapService bootstrapService;
    String? mockLinkedUri;
    String? mockDisplayName;
    List<String> mockFileList = [];
    Map<String, String> mockFilesContent = {};
    bool mockForceRevoked = false;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_storage_test');
      bootstrapService = RuntimeBootstrapService();
      bootstrapService.overrideBaseDir = tempDir;
      await bootstrapService.init();

      mockLinkedUri = null;
      mockDisplayName = null;
      mockFileList = [];
      mockFilesContent = {};
      mockForceRevoked = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (MethodCall methodCall) async {
              if (mockForceRevoked) {
                throw PlatformException(
                  code: 'PERMISSION_REVOKED',
                  message: 'Permission revoked',
                );
              }

              switch (methodCall.method) {
                case 'pickStorageFolder':
                  mockLinkedUri =
                      'content://com.android.providers.downloads.documents/tree/raw%3A%2Fstorage%2Femulated%2F0%2FDownload%2Ftest';
                  mockDisplayName = 'MyTestFolder';
                  return mockLinkedUri;
                case 'getStorageStatus':
                  if (mockLinkedUri == null) {
                    return null;
                  }
                  return {'uri': mockLinkedUri, 'displayName': mockDisplayName};
                case 'unlinkStorage':
                  mockLinkedUri = null;
                  mockDisplayName = null;
                  return null;
                case 'listStorageFiles':
                  if (mockLinkedUri == null) {
                    throw PlatformException(
                      code: 'NOT_LINKED',
                      message: 'No linked folder',
                    );
                  }
                  return mockFileList;
                case 'readStorageFile':
                  if (mockLinkedUri == null) {
                    throw PlatformException(
                      code: 'NOT_LINKED',
                      message: 'No linked folder',
                    );
                  }
                  final filename = methodCall.arguments['filename'] as String;
                  if (!mockFilesContent.containsKey(filename)) {
                    throw PlatformException(
                      code: 'FILE_NOT_FOUND',
                      message: 'File not found',
                    );
                  }
                  return mockFilesContent[filename];
                case 'writeStorageFile':
                  if (mockLinkedUri == null) {
                    throw PlatformException(
                      code: 'NOT_LINKED',
                      message: 'No linked folder',
                    );
                  }
                  final filename = methodCall.arguments['filename'] as String;
                  final content = methodCall.arguments['content'] as String;
                  mockFilesContent[filename] = content;
                  if (!mockFileList.contains(filename)) {
                    mockFileList.add(filename);
                  }
                  return true;
                case 'deleteStorageFile':
                  if (mockLinkedUri == null) {
                    throw PlatformException(
                      code: 'NOT_LINKED',
                      message: 'No linked folder',
                    );
                  }
                  final filename = methodCall.arguments['filename'] as String;
                  if (!mockFileList.contains(filename)) {
                    throw PlatformException(
                      code: 'FILE_NOT_FOUND',
                      message: 'File not found',
                    );
                  }
                  mockFileList.remove(filename);
                  mockFilesContent.remove(filename);
                  return true;
                case 'supportsDelete':
                  if (mockLinkedUri == null) {
                    throw PlatformException(
                      code: 'NOT_LINKED',
                      message: 'No linked folder',
                    );
                  }
                  final filename = methodCall.arguments['filename'] as String;
                  if (!mockFileList.contains(filename)) {
                    throw PlatformException(
                      code: 'FILE_NOT_FOUND',
                      message: 'File not found',
                    );
                  }
                  return true;
                case 'createStorageDirectory':
                  if (mockLinkedUri == null) {
                    throw PlatformException(
                      code: 'NOT_LINKED',
                      message: 'No linked folder',
                    );
                  }
                  final folderName =
                      methodCall.arguments['folderName'] as String;
                  if (!mockFileList.contains(folderName)) {
                    mockFileList.add(folderName);
                  }
                  return true;
                case 'getDiagnostics':
                  return {
                    'userDir': '/data/user/0/com.termode.termode/files',
                    'pathEnv': '/sbin:/system/bin',
                    'uid': 10234,
                    'testOutput': 'shell-ok',
                    'fileChecks': [],
                    'runtimeHome':
                        '/data/user/0/com.termode.termode/files/home',
                    'runtimePath':
                        '/data/user/0/com.termode.termode/files/usr/bin:/system/bin',
                  };
                case 'getPaths':
                  return {
                    'home': '/data/user/0/com.termode.termode/files/home',
                    'usr': '/data/user/0/com.termode.termode/files/usr',
                    'bin': '/data/user/0/com.termode.termode/files/usr/bin',
                    'tmp': '/data/user/0/com.termode.termode/files/tmp',
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
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('storage-link and storage-status commands', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_storage');

      // Pre-link status
      final statusResult1 = await commandService.execute('storage-status');
      expect(statusResult1.output, contains('Storage linked: no'));
      expect(statusResult1.output, contains('Tip: storage-link'));

      // Link folder
      final linkResult = await commandService.execute('storage-link');
      expect(linkResult.isError, isFalse);
      expect(linkResult.output, contains('Folder linked successfully'));
      expect(linkResult.output, contains('content://'));

      // Post-link status
      final statusResult2 = await commandService.execute('storage-status');
      expect(statusResult2.isError, isFalse);
      expect(statusResult2.output, contains('Storage linked: yes'));
      expect(statusResult2.output, contains('Name: MyTestFolder'));
      expect(statusResult2.output, contains('Tip: storage-list'));

      final aliasResult = await commandService.execute('storage');
      expect(aliasResult.output, contains('Storage linked: yes'));
    });

    test('storage-unlink command resets permission', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_storage');

      // Link first
      await commandService.execute('storage-link');
      var status = await commandService.execute('storage-status');
      expect(status.output, contains('Storage linked: yes'));

      // Unlink
      final unlinkResult = await commandService.execute('storage-unlink');
      expect(
        unlinkResult.output,
        contains('Storage link removed successfully'),
      );

      // Verify status is back to unlinked
      status = await commandService.execute('storage-status');
      expect(status.output, contains('Storage linked: no'));
    });

    test('storage read, write, and list operations', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_storage');

      // Link first
      await commandService.execute('storage-link');

      // List empty
      final listResult1 = await commandService.execute('storage-list');
      expect(listResult1.output, contains('(empty directory)'));

      // Write file
      final writeResult = await commandService.execute(
        'storage-write notes.txt Buy groceries and code Flutter',
      );
      expect(writeResult.isError, isFalse);
      expect(writeResult.output, contains('Wrote 30 characters'));

      // List populated
      final listResult2 = await commandService.execute('storage-list');
      expect(listResult2.output, contains('notes.txt'));

      // Read file
      final readResult = await commandService.execute('storage-read notes.txt');
      expect(readResult.isError, isFalse);
      expect(readResult.output, contains('Buy groceries and code Flutter'));
    });

    test('storage-delete and storage-mkdir operations', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_storage');

      // Link first
      await commandService.execute('storage-link');

      // Create folder
      final mkdirResult = await commandService.execute('storage-mkdir docs');
      expect(mkdirResult.isError, isFalse);
      expect(mkdirResult.output, contains('Created directory "docs"'));

      // Write file
      await commandService.execute('storage-write file1.txt hello');

      // Delete file
      final deleteResult = await commandService.execute(
        'storage-delete file1.txt',
      );
      expect(deleteResult.isError, isFalse);
      expect(deleteResult.output, contains('Deleted file "file1.txt"'));

      // List should only show docs now
      final listResult = await commandService.execute('storage-list');
      expect(listResult.output, contains('docs'));
      expect(listResult.output, isNot(contains('file1.txt')));

      final projectsResult = await commandService.execute('storage-projects');
      expect(projectsResult.output, contains('docs'));
    });

    test(
      'support spaces in filenames using quotes and space joining',
      () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_storage');

        // Link first
        await commandService.execute('storage-link');

        // Write quoted space file
        final writeResult = await commandService.execute(
          'storage-write "my test notes.txt" hello spaces',
        );
        expect(writeResult.isError, isFalse);
        expect(writeResult.output, contains('my test notes.txt'));

        // Read with space (both quoted and unquoted)
        final readResultQuoted = await commandService.execute(
          'storage-read "my test notes.txt"',
        );
        expect(readResultQuoted.output, contains('hello spaces'));

        final readResultUnquoted = await commandService.execute(
          'storage-read my test notes.txt',
        );
        expect(readResultUnquoted.output, contains('hello spaces'));

        // Delete with space (unquoted)
        final deleteResult = await commandService.execute(
          'storage-delete my test notes.txt',
        );
        expect(deleteResult.isError, isFalse);
        expect(
          deleteResult.output,
          contains('Deleted file "my test notes.txt"'),
        );
      },
    );

    test('storage-test diagnostics runs complete verification loop', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_storage');

      // Pre-link test (should fail)
      final testResultFail = await commandService.execute('storage-test');
      expect(testResultFail.isError, isTrue);
      expect(testResultFail.output, contains('Result: FAIL'));
      expect(testResultFail.output, contains('No folder is currently linked'));

      // Link first
      await commandService.execute('storage-link');

      // Run test (should pass)
      final testResultPass = await commandService.execute('storage-test');
      expect(testResultPass.isError, isFalse);
      expect(testResultPass.output, contains('Result: PASS'));
      expect(
        testResultPass.output,
        contains('Checking storage status... PASS'),
      );
      expect(testResultPass.output, contains('Writing temporary test file'));
      expect(testResultPass.output, contains('Reading test file back... PASS'));
      expect(
        testResultPass.output,
        contains('Deleting temporary test file... PASS'),
      );
    });

    test('whereami displays display name and URI of linked storage', () async {
      final vfs = VirtualFileSystem();
      vfs.cd('/home');
      final commandService = CommandService(vfs, 'session_storage');

      // Before link
      var whereamiResult = await commandService.execute('whereami');
      expect(whereamiResult.output, contains('Status: NOT LINKED'));

      // After link
      await commandService.execute('storage-link');
      whereamiResult = await commandService.execute('whereami');
      expect(
        whereamiResult.output,
        contains('Status: LINKED (Name: MyTestFolder)'),
      );
      expect(whereamiResult.output, contains('Uri: content://'));
    });

    test('error mappings return user friendly descriptions', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_storage');

      // 1. Not linked error
      final listErr = await commandService.execute('storage-list');
      expect(listErr.isError, isTrue);
      expect(listErr.output, contains('No storage folder is currently linked'));

      // Link first
      await commandService.execute('storage-link');

      // 2. File not found error
      final readErr = await commandService.execute(
        'storage-read missing_file.txt',
      );
      expect(readErr.isError, isTrue);
      expect(readErr.output, contains('File not found in linked storage'));

      // 3. Permission revoked error
      mockForceRevoked = true;
      final statusErr = await commandService.execute('storage-status');
      expect(statusErr.isError, isTrue);
      expect(
        statusErr.output,
        contains('Permission revoked or folder access denied'),
      );
    });

    test('storage-help describes commands and limitation details', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_storage');

      final helpResult = await commandService.execute('storage-help');
      expect(
        helpResult.output,
        contains('=== Termode User-Approved Storage Help ==='),
      );
      expect(helpResult.output, contains('storage-link'));
      expect(helpResult.output, contains('storage-status'));
      expect(helpResult.output, contains('storage-unlink'));
      expect(helpResult.output, contains('storage-list'));
      expect(helpResult.output, contains('storage-read'));
      expect(helpResult.output, contains('storage-write'));
      expect(helpResult.output, contains('storage-mkdir'));
      expect(helpResult.output, contains('storage-delete'));
      expect(helpResult.output, contains('storage-projects'));
      expect(helpResult.output, contains('storage-test'));
      expect(
        helpResult.output,
        contains('Android security limits direct storage access'),
      );
    });
  });
}
