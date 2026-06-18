import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Localhost and Dev Server Diagnostics', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;
    late CommandService commandService;

    setUp(() async {
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp('termode_localhost_test');
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'localhost_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('localhost-doctor compact output', () async {
      final result = await commandService.execute('localhost-doctor');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Localhost Doctor ==='));
      expect(result.output, contains('Loopback: OK'));
      expect(result.output, contains('HTTP client: OK'));
      expect(result.output, contains('Port check: OK'));
      expect(result.output, contains('Workspace: OK'));
      expect(result.output, contains('Preview URL: http://127.0.0.1:3000'));
      expect(result.output, contains('Overall: HEALTHY'));
    });

    test('localhost-doctor verbose output', () async {
      final result = await commandService.execute('localhost-doctor --verbose');

      expect(result.isError, isFalse);
      expect(result.output, contains('Tested hostnames: 127.0.0.1, localhost'));
      expect(result.output, contains('127.0.0.1 result:'));
      expect(result.output, contains('localhost result:'));
      expect(result.output, contains('Android loopback notes:'));
      expect(result.output, contains('Last checked:'));
    });

    test('localhost-capabilities output', () async {
      final result = await commandService.execute('localhost-capabilities');

      expect(result.isError, isFalse);
      expect(result.output, contains('checking local ports'));
      expect(result.output, contains('testing HTTP localhost URLs'));
      expect(result.output, contains('generating preview URLs'));
      expect(result.output, contains('automatic port discovery'));
      expect(result.output, contains('bundled Node.js'));
      expect(result.output, contains('npm dev servers'));
    });

    test('port-check invalid ports return friendly errors', () async {
      final nonNumeric = await commandService.execute('port-check abc');
      final tooLarge = await commandService.execute('port-check 99999');

      expect(nonNumeric.isError, isTrue);
      expect(nonNumeric.output, contains('Port must be numeric'));
      expect(tooLarge.isError, isTrue);
      expect(tooLarge.output, contains('between 1 and 65535'));
    });

    test('port-check valid closed port does not crash', () async {
      final result = await commandService.execute('port-check 9');

      expect(result.isError, isFalse);
      expect(result.output, matches(RegExp(r'Port 9: (open|closed)')));
    });

    test('port-check verbose output includes host and timeout', () async {
      final result = await commandService.execute('port-check 9 --verbose');

      expect(result.isError, isFalse);
      expect(result.output, contains('Port 9:'));
      expect(result.output, contains('Host: 127.0.0.1'));
      expect(result.output, contains('Timeout:'));
    });

    test('http-test number becomes 127.0.0.1 URL and is friendly', () async {
      final result = await commandService.execute('http-test 9');

      expect(result.isError, isTrue);
      expect(
        result.output,
        contains('Error: Could not reach http://127.0.0.1:9'),
      );
      expect(
        result.output,
        contains('Tip: Make sure the dev server is running.'),
      );
    });

    test('http-test URL without scheme adds http', () async {
      final result = await commandService.execute('http-test localhost:9');

      expect(result.isError, isTrue);
      expect(
        result.output,
        contains('Error: Could not reach http://localhost:9'),
      );
    });

    test('http-test prints metadata and never response body', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestFuture = server.first.then((request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html><body>secret-body</body></html>');
        return request.response.close();
      });

      final result = await commandService.execute('http-test ${server.port}');

      await requestFuture;
      await server.close(force: true);

      expect(result.isError, isFalse);
      expect(result.output, contains('HTTP: 200 OK'));
      expect(result.output, contains('Content-Type: text/html'));
      expect(result.output, contains('Bytes:'));
      expect(result.output, isNot(contains('secret-body')));
    });

    test('http-test --headers prints compact headers', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestFuture = server.first.then((request) {
        request.response.headers.set('x-termode-test', 'yes');
        request.response.write('ok');
        return request.response.close();
      });

      final result = await commandService.execute(
        'http-test http://127.0.0.1:${server.port} --headers',
      );

      await requestFuture;
      await server.close(force: true);

      expect(result.isError, isFalse);
      expect(result.output, contains('Headers:'));
      expect(result.output.toLowerCase(), contains('x-termode-test'));
    });

    test('preview-url output and invalid port', () async {
      final result = await commandService.execute('preview-url 3000');
      final invalid = await commandService.execute('preview-url 99999');

      expect(result.isError, isFalse);
      expect(result.output, contains('Preview URL:'));
      expect(result.output, contains('http://127.0.0.1:3000'));
      expect(invalid.isError, isTrue);
      expect(invalid.output, contains('between 1 and 65535'));
    });

    test(
      'runtime plan and capabilities include localhost diagnostics',
      () async {
        final plan = await commandService.execute('runtime-plan');
        final capabilities = await commandService.execute(
          'runtime-capabilities',
        );

        expect(plan.output, contains('3. Localhost/preview workflow'));
        expect(plan.output, contains('15. Vite proof later'));
        expect(capabilities.output, contains('Localhost diagnostics'));
      },
    );

    test('help and devserver-help include localhost commands', () async {
      final help = await commandService.execute('help');
      final runtimeHelp = await commandService.execute('runtime-help');
      final devserverHelp = await commandService.execute('devserver-help');

      for (final output in [
        help.output,
        runtimeHelp.output,
        devserverHelp.output,
      ]) {
        expect(output, contains('localhost-doctor'));
        expect(output, contains('localhost-capabilities'));
        expect(output, contains('port-check'));
        expect(output, contains('http-test'));
        expect(output, contains('preview-url'));
        expect(output, contains('devserver-help'));
      }
      expect(devserverHelp.output, contains('http-test <url> --headers'));
    });
  });
}
