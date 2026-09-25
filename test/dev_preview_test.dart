import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/termode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PortMonitorService.resetForTesting();
    DevServerService.resetForTesting();
  });

  tearDown(() {
    PortMonitorService.resetForTesting();
    DevServerService.resetForTesting();
  });

  group('Milestone v0.82: PortMonitorService Unit Tests', () {
    test('registerPort and unregisterPort manage custom ports', () {
      final monitor = PortMonitorService();
      monitor.registerPort(9090);
      monitor.registerPort(9091);
      // Valid range check
      monitor.registerPort(70000); // Invalid port (>65535)

      monitor.unregisterPort(9091);
    });

    test('mockActivePorts updates activePorts and emits to activePortsStream', () async {
      final monitor = PortMonitorService();
      PortMonitorService.mockActivePorts = [3000, 5173];

      final emitted = <List<int>>[];
      final sub = monitor.activePortsStream.listen(emitted.add);

      final ports = await monitor.triggerScan();
      expect(ports, equals([3000, 5173]));
      expect(monitor.activePorts, equals([3000, 5173]));
      expect(monitor.hasActiveServer, isTrue);

      await Future.delayed(const Duration(milliseconds: 10));
      expect(emitted.isNotEmpty, isTrue);
      expect(emitted.last, equals([3000, 5173]));

      await sub.cancel();
    });

    test('PortInspectionResult formats HTTP status and metrics accurately', () {
      final success = PortInspectionResult(
        port: 3000,
        url: 'http://127.0.0.1:3000/',
        isReachable: true,
        statusCode: 200,
        statusReason: 'OK',
        contentType: 'text/html; charset=utf-8',
        serverHeader: 'NodeJS',
        contentLength: 104,
        latencyMs: 5,
        headers: const {'content-type': 'text/html; charset=utf-8', 'server': 'NodeJS'},
        timestamp: DateTime(2026, 1, 1),
      );

      expect(success.isHttpSuccess, isTrue);
      expect(success.formattedStatus, equals('200 OK'));

      final offline = PortInspectionResult(
        port: 8080,
        url: 'http://127.0.0.1:8080/',
        isReachable: false,
        latencyMs: 200,
        headers: const {},
        timestamp: DateTime(2026, 1, 1),
      );

      expect(offline.isHttpSuccess, isFalse);
      expect(offline.formattedStatus, equals('OFFLINE'));
    });

    test('inspectPort returns mocked inspection result when set', () async {
      final monitor = PortMonitorService();
      final mock = PortInspectionResult(
        port: 5173,
        url: 'http://127.0.0.1:5173/',
        isReachable: true,
        statusCode: 200,
        statusReason: 'OK',
        latencyMs: 3,
        headers: const {'x-powered-by': 'Vite'},
        timestamp: DateTime.now(),
      );

      PortMonitorService.mockInspectionResult = mock;
      final result = await monitor.inspectPort(5173);

      expect(result.port, equals(5173));
      expect(result.isReachable, isTrue);
      expect(result.statusCode, equals(200));
      expect(result.headers['x-powered-by'], equals('Vite'));
    });
  });

  group('Milestone v0.82: DevPreviewSheet Widget Tests', () {
    testWidgets('renders address bar, port badge, and fallback preview frame', (tester) async {
      PortMonitorService.mockInspectionResult = PortInspectionResult(
        port: 3000,
        url: 'http://127.0.0.1:3000/',
        isReachable: true,
        statusCode: 200,
        statusReason: 'OK',
        latencyMs: 4,
        headers: const {'content-type': 'text/html'},
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DevPreviewSheet(
              initialPort: 3000,
              forceFallbackForTesting: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check port badge in address bar
      expect(find.text(':3000'), findsOneWidget);
      // Check address bar input
      expect(find.byType(TextField), findsOneWidget);
      // Check tab bars
      expect(find.text('PREVIEW'), findsOneWidget);
      expect(find.text('NETWORK'), findsOneWidget);
      expect(find.text('CONSOLE'), findsOneWidget);

      // Check fallback preview message
      expect(find.text('Dev Server Live at :3000'), findsOneWidget);
      expect(find.text('HTTP 200 OK'), findsOneWidget);
    });

    testWidgets('switches to Network tab and displays headers and metrics', (tester) async {
      PortMonitorService.mockInspectionResult = PortInspectionResult(
        port: 3000,
        url: 'http://127.0.0.1:3000/',
        isReachable: true,
        statusCode: 200,
        statusReason: 'OK',
        contentLength: 256,
        latencyMs: 7,
        headers: const {
          'content-type': 'text/html; charset=utf-8',
          'server': 'Node.js V8 Engine',
        },
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DevPreviewSheet(
              initialPort: 3000,
              forceFallbackForTesting: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the NETWORK tab
      await tester.tap(find.text('NETWORK'));
      await tester.pumpAndSettle();

      // Verify metrics cards
      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('200'), findsAtLeastNWidgets(1));
      expect(find.text('LATENCY'), findsOneWidget);
      expect(find.text('7ms'), findsOneWidget);
      expect(find.text('SIZE'), findsOneWidget);
      expect(find.text('256 B'), findsOneWidget);

      // Verify response headers
      expect(find.text('RESPONSE HEADERS'), findsOneWidget);
      expect(find.text('content-type'), findsOneWidget);
      expect(find.text('server'), findsOneWidget);
      expect(find.text('Node.js V8 Engine'), findsOneWidget);
    });

    testWidgets('switches to Console tab and filters logs', (tester) async {
      DevServerService.serverLogsHookForTesting = 'Server listening at http://localhost:3000\n[STDERR] Uncaught warning';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DevPreviewSheet(
              initialPort: 3000,
              forceFallbackForTesting: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap CONSOLE tab
      await tester.tap(find.text('CONSOLE'));
      await tester.pumpAndSettle();

      // Check log lines
      expect(find.textContaining('Server listening'), findsOneWidget);
      expect(find.textContaining('Uncaught warning'), findsOneWidget);

      // Filter by ERRORS
      await tester.tap(find.textContaining('Errors'));
      await tester.pumpAndSettle();

      // Error should still be visible
      expect(find.textContaining('Uncaught warning'), findsOneWidget);

      // Tap clear console
      await tester.tap(find.byTooltip('Clear Console'));
      await tester.pumpAndSettle();

      expect(find.text('No console output recorded.'), findsOneWidget);
    });

    testWidgets('changing URL input navigates and updates port', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DevPreviewSheet(
              initialPort: 3000,
              forceFallbackForTesting: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter new URL into address bar
      await tester.enterText(find.byType(TextField), 'http://127.0.0.1:8000/api/users');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Port badge should now display :8000
      expect(find.text(':8000'), findsOneWidget);
    });
  });
}
