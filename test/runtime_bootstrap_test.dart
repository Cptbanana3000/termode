import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RuntimeBootstrapService Tests', () {
    late Directory tempDir;
    late RuntimeBootstrapService bootstrapService;

    setUp(() async {
      // Create a clean temporary directory for each test
      tempDir = await Directory.systemTemp.createTemp('termode_runtime_test');
      bootstrapService = RuntimeBootstrapService();
      bootstrapService.overrideBaseDir = tempDir;
    });

    tearDown(() async {
      // Clean up the temporary directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Initializes folders and metadata JSON correctly', () async {
      await bootstrapService.init();

      final filesDir = Directory('${tempDir.path}/files');
      expect(await Directory('${filesDir.path}/home').exists(), isTrue);
      expect(await Directory('${filesDir.path}/usr').exists(), isTrue);
      expect(await Directory('${filesDir.path}/usr/bin').exists(), isTrue);
      expect(await Directory('${filesDir.path}/usr/tmp').exists(), isTrue);
      expect(await Directory('${filesDir.path}/tmp').exists(), isTrue);

      final metaFile = File('${filesDir.path}/usr/termode-runtime.json');
      expect(await metaFile.exists(), isTrue);

      final content = await metaFile.readAsString();
      final metadata = jsonDecode(content) as Map<String, dynamic>;

      expect(metadata['runtimeVersion'], '0.7.0');
      expect(metadata['createdAt'], isNotNull);
      expect(metadata['updatedAt'], isNotNull);
      expect(metadata['homePath'], contains('files/home'));
      expect(metadata['usrPath'], contains('files/usr'));
      expect(metadata['binPath'], contains('files/usr/bin'));
      expect(metadata['tmpPath'], contains('files/tmp'));
    });

    test('Checks status correctly (healthy and unhealthy)', () async {
      await bootstrapService.init();

      var status = await bootstrapService.checkStatus();
      expect(status.values.every((val) => val == true), isTrue);

      // Delete one folder to simulate corruption
      final filesDir = Directory('${tempDir.path}/files');
      await Directory('${filesDir.path}/usr/bin').delete(recursive: true);

      status = await bootstrapService.checkStatus();
      expect(status['files/usr/bin'], isFalse);
      expect(status['files/home'], isTrue);
    });

    test('CommandService termode-runtime command integrations', () async {
      await bootstrapService.init();

      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'test_session');

      // 1. Path command check
      final pathResult = await commandService.execute('termode-runtime path');
      expect(pathResult.isError, isFalse);
      expect(pathResult.output, contains('=== Termode Runtime Paths ==='));
      expect(pathResult.output, contains('Home:'));
      expect(pathResult.output, contains('files/home'));

      // 2. Status command check
      final statusResult = await commandService.execute('termode-runtime status');
      expect(statusResult.isError, isFalse);
      expect(statusResult.output, contains('=== Termode Runtime Directory Status ==='));
      expect(statusResult.output, contains('Overall status: HEALTHY'));

      // 3. Reset command check
      final resetResult = await commandService.execute('termode-runtime reset');
      expect(resetResult.isError, isFalse);
      expect(resetResult.output, contains('Runtime environment reset successfully.'));

      // Verify folders still exist after reset
      final filesDir = Directory('${tempDir.path}/files');
      expect(await Directory('${filesDir.path}/home').exists(), isTrue);
      expect(await File('${filesDir.path}/usr/termode-runtime.json').exists(), isTrue);

      // 4. Invalid subcommand check
      final invalidResult = await commandService.execute('termode-runtime invalid_subcmd');
      expect(invalidResult.isError, isTrue);
      expect(invalidResult.output, contains('unknown subcommand: invalid_subcmd'));
    });
  });
}
