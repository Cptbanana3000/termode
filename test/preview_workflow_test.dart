import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/preview_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Preview Workflow (v0.27)', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;
    late CommandService commandService;

    // Controls the mocked native openUrl result.
    bool? openUrlReturn; // true = opened, false = no app
    bool openUrlThrows = false;

    const nativeChannel = MethodChannel('com.termode/native_shell');
    // Clipboard uses SystemChannels.platform (JSONMethodCodec); mock that exact
    // channel object so the codec matches.
    final platformChannel = SystemChannels.platform;

    setUp(() async {
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp('termode_preview_test');
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'preview_test');
      PreviewService().resetForTesting();

      openUrlReturn = true;
      openUrlThrows = false;

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'openUrl') {
          if (openUrlThrows) {
            throw PlatformException(code: 'OPEN_FAILED', message: 'boom');
          }
          return openUrlReturn;
        }
        return null;
      });

      // Mock clipboard so copy/doctor probes succeed deterministically.
      messenger.setMockMethodCallHandler(platformChannel, (call) async {
        if (call.method == 'Clipboard.setData') {
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': ''};
        }
        return null;
      });
    });

    tearDown(() async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(nativeChannel, null);
      messenger.setMockMethodCallHandler(platformChannel, null);
      PreviewService().resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    // ----- shared port validation helper -----

    test('validatePort accepts valid and rejects invalid ports', () {
      final service = PreviewService();
      expect(service.validatePort('3000').isValid, isTrue);
      expect(service.validatePort('3000').port, 3000);

      final tooLarge = service.validatePort('99999');
      expect(tooLarge.isValid, isFalse);
      expect(tooLarge.error, contains('between 1 and 65535'));

      final nonNumeric = service.validatePort('abc');
      expect(nonNumeric.isValid, isFalse);
      expect(nonNumeric.error, contains('numeric'));

      final missing = service.validatePort(null);
      expect(missing.isValid, isFalse);
      expect(missing.error, contains('Missing port'));

      expect(service.normalizePreviewUrl(3000), 'http://127.0.0.1:3000');
      expect(
        service.normalizeHttpTestUrl('5173'),
        'http://127.0.0.1:5173',
      );
    });

    // ----- preview status -----

    test('preview status reflects history', () async {
      final empty = await commandService.execute('preview');
      expect(empty.isError, isFalse);
      expect(empty.output, contains('Preview support: available'));
      expect(empty.output, contains('Last preview: none'));
      expect(empty.output, contains('Recent ports: none'));

      await commandService.execute('preview-copy 3000');
      final populated = await commandService.execute('preview');
      expect(populated.output, contains('Last preview: http://127.0.0.1:3000'));
      expect(populated.output, contains('Recent ports: 3000'));
      expect(populated.output, contains('Tip: preview-open 3000'));
    });

    // ----- preview-url -----

    test('preview-url prints clean URL and rejects invalid port', () async {
      final ok = await commandService.execute('preview-url 3000');
      expect(ok.isError, isFalse);
      expect(ok.output, contains('http://127.0.0.1:3000'));

      final bad = await commandService.execute('preview-url 99999');
      expect(bad.isError, isTrue);
      expect(bad.output, contains('between 1 and 65535'));
    });

    // ----- preview-copy -----

    test('preview-copy valid port copies and remembers', () async {
      final result = await commandService.execute('preview-copy 3000');
      expect(result.isError, isFalse);
      expect(result.output, contains('Copied preview URL.'));
      expect(result.output, contains('http://127.0.0.1:3000'));

      final history = await commandService.execute('preview-history');
      expect(history.output, contains('http://127.0.0.1:3000'));
    });

    test('preview-copy invalid port errors', () async {
      final result = await commandService.execute('preview-copy 99999');
      expect(result.isError, isTrue);
      expect(result.output, contains('between 1 and 65535'));
    });

    // ----- preview-open -----

    test('preview-open closed port blocks by default', () async {
      final result = await commandService.execute('preview-open 59999');
      expect(result.isError, isFalse);
      expect(result.output, contains('Port 59999 is closed.'));
      expect(result.output, contains('preview-open 59999 --force'));

      final history = await commandService.execute('preview-history');
      expect(history.output, contains('No preview history.'));
    });

    test('preview-open closed port --force attempts open', () async {
      openUrlReturn = true;
      final result = await commandService.execute('preview-open 59999 --force');
      expect(result.isError, isFalse);
      expect(
        result.output,
        contains('Opening preview: http://127.0.0.1:59999'),
      );

      final history = await commandService.execute('preview-history');
      expect(history.output, contains('http://127.0.0.1:59999'));
    });

    test('preview-open --force reports friendly failure when no app', () async {
      openUrlReturn = false;
      final result = await commandService.execute('preview-open 59999 --force');
      expect(result.isError, isTrue);
      expect(result.output, contains('Could not open'));
    });

    // ----- openExternally / unsafe schemes -----

    test('openExternally rejects unsafe schemes', () async {
      final service = PreviewService();
      expect(service.isSafeOpenUrl('http://127.0.0.1:3000'), isTrue);
      expect(service.isSafeOpenUrl('https://example.com'), isTrue);
      expect(service.isSafeOpenUrl('javascript:alert(1)'), isFalse);
      expect(service.isSafeOpenUrl('file:///etc/passwd'), isFalse);
      expect(service.isSafeOpenUrl('content://foo'), isFalse);
      expect(service.isSafeOpenUrl('intent://foo'), isFalse);

      final result = await service.openExternally('javascript:alert(1)');
      expect(result.isError, isTrue);
      expect(result.output, contains('http and https'));
    });

    test('openUrl MethodChannel success mock', () async {
      openUrlReturn = true;
      final result = await PreviewService().openExternally(
        'http://127.0.0.1:3000',
      );
      expect(result.isError, isFalse);
      expect(result.output, contains('Opening preview'));
    });

    test('openUrl MethodChannel failure mock', () async {
      openUrlReturn = false;
      final result = await PreviewService().openExternally(
        'http://127.0.0.1:3000',
      );
      expect(result.isError, isTrue);
      expect(result.output, contains('Could not open'));
    });

    test('openUrl MethodChannel platform exception is handled', () async {
      openUrlThrows = true;
      final result = await PreviewService().openExternally(
        'http://127.0.0.1:3000',
      );
      expect(result.isError, isTrue);
      expect(result.output, contains('Could not open'));
    });

    // ----- preview-check -----

    test('preview-check on closed port does not crash', () async {
      final result = await commandService.execute('preview-check 59999');
      expect(result.isError, isFalse);
      expect(result.output, contains('Port: closed'));
      expect(result.output, contains('HTTP: unreachable'));
      expect(result.output, contains('URL: http://127.0.0.1:59999'));
    });

    test('preview-check on live server reports open/reachable', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      server.listen((request) {
        request.response.write('ok');
        request.response.close();
      });

      final result = await commandService.execute('preview-check $port');
      await server.close(force: true);

      expect(result.output, contains('Port: open'));
      expect(result.output, contains('HTTP: reachable'));
      expect(result.output, contains('URL: http://127.0.0.1:$port'));
    });

    // ----- history -----

    test('preview-history stores entries newest first', () async {
      await commandService.execute('preview-copy 3000');
      await commandService.execute('preview-copy 5173');
      final history = await commandService.execute('preview-history');
      expect(history.output, contains('=== Preview History ==='));
      expect(history.output, contains('http://127.0.0.1:5173'));
      expect(history.output, contains('http://127.0.0.1:3000'));
      final firstIndex = history.output.indexOf('5173');
      final secondIndex = history.output.indexOf('3000');
      expect(firstIndex, lessThan(secondIndex));
    });

    test('preview history caps at 10 entries', () async {
      for (var port = 3000; port < 3015; port++) {
        await commandService.execute('preview-copy $port');
      }
      expect(PreviewService().history.length, 10);
    });

    test('preview-clear-history clears entries', () async {
      await commandService.execute('preview-copy 3000');
      final cleared = await commandService.execute('preview-clear-history');
      expect(cleared.output, contains('Cleared'));

      final history = await commandService.execute('preview-history');
      expect(history.output, contains('No preview history.'));
    });

    // ----- settings -----

    test('preview-settings output', () async {
      final result = await commandService.execute('preview-settings');
      expect(result.output, contains('Default host: 127.0.0.1'));
      expect(result.output, contains('Default scheme: http'));
      expect(result.output, contains('Port check before open: yes'));
      expect(result.output, contains('History limit: 10'));
    });

    // ----- doctor -----

    test('preview-doctor compact output', () async {
      final result = await commandService.execute('preview-doctor');
      expect(result.isError, isFalse);
      expect(result.output, contains('=== Preview Doctor ==='));
      expect(result.output, contains('URL generation: OK'));
      expect(result.output, contains('Clipboard: OK'));
      expect(result.output, contains('External open:'));
      expect(result.output, contains('Port check: OK'));
      expect(result.output, contains('HTTP test: OK'));
      expect(result.output, contains('History: OK'));
      expect(
        result.output,
        matches(RegExp(r'Overall: (HEALTHY|LIMITED|UNHEALTHY)')),
      );
    });

    test('preview-doctor verbose output', () async {
      final result = await commandService.execute('preview-doctor --verbose');
      expect(result.output, contains('Details:'));
      expect(
        result.output,
        contains('Native channel: com.termode/native_shell (openUrl)'),
      );
      expect(result.output, contains('Allowed open schemes:'));
      expect(result.output, contains('Platform:'));
    });

    // ----- help / autocomplete -----

    test('preview-help explains the workflow', () async {
      final result = await commandService.execute('preview-help');
      expect(result.output, contains('Termode Preview Workflow'));
      expect(result.output, contains('preview-open <port> --force'));
      expect(result.output, contains('Vite dev server'));
    });

    test('help and devserver-help include preview commands', () async {
      final help = await commandService.execute('help');
      final devserverHelp = await commandService.execute('devserver-help');
      for (final output in [help.output, devserverHelp.output]) {
        expect(output, contains('preview-open'));
        expect(output, contains('preview-copy'));
        expect(output, contains('preview-doctor'));
      }
    });

    test('command catalog includes preview commands', () {
      for (final cmd in [
        'preview',
        'preview-url',
        'preview-copy',
        'preview-open',
        'preview-check',
        'preview-history',
        'preview-clear-history',
        'preview-settings',
        'preview-doctor',
        'preview-help',
      ]) {
        expect(kTermodeCommands, contains(cmd));
      }
    });

    // ----- integration: existing surfaces still mention preview prep -----

    test('localhost-capabilities mentions preview support', () async {
      final result = await commandService.execute('localhost-capabilities');
      expect(result.output, contains('checking local ports'));
      expect(result.output, contains('generating preview URLs'));
      expect(result.output, contains('copying preview URLs to the clipboard'));
      expect(result.output, contains('preview history'));
    });

    test('runtime-plan reflects staged roadmap with preview workflow', () async {
      final result = await commandService.execute('runtime-plan');
      expect(result.output, contains('3. Localhost/preview workflow'));
      expect(result.output, contains('4. Bundled native proof'));
      expect(result.output, contains('8. Vite proof later'));
    });
  });
}
