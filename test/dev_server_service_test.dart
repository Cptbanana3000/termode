import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/dev_server_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DevServerInfo Models & Serialization', () {
    test('DevServerInfo parses from JSON and computes properties correctly', () {
      final now = DateTime.now();
      final json = {
        'id': 'srv_12345',
        'pid': 1234,
        'command': 'node',
        'arguments': ['server.js', '--port', '3000'],
        'workingDirectory': '/data/user/0/com.termode.termode/files/home',
        'startTime': now.subtract(const Duration(minutes: 2, seconds: 15)).millisecondsSinceEpoch,
        'isAlive': true,
        'detectedPort': 3000,
        'recentStdout': 'Listening on http://localhost:3000',
        'recentStderr': '',
      };

      final info = DevServerInfo.fromJson(json);
      expect(info.id, equals('srv_12345'));
      expect(info.pid, equals(1234));
      expect(info.command, equals('node'));
      expect(info.arguments, equals(['server.js', '--port', '3000']));
      expect(info.workingDirectory, equals('/data/user/0/com.termode.termode/files/home'));
      expect(info.isAlive, isTrue);
      expect(info.detectedPort, equals(3000));
      expect(info.effectivePort, equals(3000));
      expect(info.previewUrl, equals('http://127.0.0.1:3000'));
      expect(info.fullCommand, equals('node server.js --port 3000'));
      expect(info.formattedUptime, contains('m'));

      final outJson = info.toJson();
      expect(outJson['id'], equals('srv_12345'));
      expect(outJson['pid'], equals(1234));
      expect(outJson['detectedPort'], equals(3000));
    });
  });

  group('DevServerService Lifecycle & Supervision', () {
    setUp(() {
      DevServerService.resetForTesting();
    });

    tearDown(() {
      DevServerService.resetForTesting();
    });

    test('listServers returns empty when no servers are running', () async {
      DevServerService.serverListHookForTesting = [];
      final servers = await DevServerService().listServers();
      expect(servers, isEmpty);
    });

    test('listServers returns mocked servers and updates stream', () async {
      final mockServer = DevServerInfo(
        id: 'srv_test',
        pid: 9999,
        command: 'node',
        arguments: ['app.js'],
        workingDirectory: '/test/dir',
        startTime: DateTime.now(),
        isAlive: true,
        detectedPort: 8080,
      );
      DevServerService.serverListHookForTesting = [mockServer];

      final servers = await DevServerService().listServers();
      expect(servers.length, equals(1));
      expect(servers.first.id, equals('srv_test'));
      expect(servers.first.detectedPort, equals(8080));
    });

    test('stopServer removes target from list and returns true', () async {
      final mockServer = DevServerInfo(
        id: 'srv_stop_target',
        pid: 8888,
        command: 'node',
        arguments: ['server.js'],
        workingDirectory: '/test/dir',
        startTime: DateTime.now(),
        isAlive: true,
        detectedPort: 3000,
      );
      DevServerService.serverListHookForTesting = [mockServer];
      DevServerService.stopServerHookForTesting = true;

      await DevServerService().listServers();
      final stopped = await DevServerService().stopServer(port: 3000);
      expect(stopped, isTrue);
      expect(DevServerService().lastKnownServers, isEmpty);
    });

    test('getServerLogs returns mocked output', () async {
      DevServerService.serverLogsHookForTesting = 'Server listening on :3000\nReady for traffic';
      final logs = await DevServerService().getServerLogs(port: 3000);
      expect(logs, contains('Server listening on :3000'));
      expect(logs, contains('Ready for traffic'));
    });

    test('openInBrowser delegates to preview URL and returns true', () async {
      DevServerService.openBrowserHookForTesting = true;
      final opened = await DevServerService().openInBrowser(port: 3000);
      expect(opened, isTrue);
    });

    test('runDoctor generates comprehensive report', () async {
      final mockServer = DevServerInfo(
        id: 'srv_doctor_target',
        pid: 7777,
        command: 'node',
        arguments: ['server.js'],
        workingDirectory: '/home/project',
        startTime: DateTime.now(),
        isAlive: true,
        detectedPort: 3000,
      );
      DevServerService.serverListHookForTesting = [mockServer];

      final report = await DevServerService().runDoctor();
      expect(report.supervisorReady, isTrue);
      expect(report.activeServerCount, equals(1));
      expect(report.activePorts, contains(3000));
      final text = report.formatReport();
      expect(text, contains('=== Dev Server Doctor ==='));
      expect(text, contains('Supervisor: ACTIVE'));
      expect(text, contains('Running servers: 1'));
    });
  });

  group('CommandService Dev Server CLI Integration', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;
    late CommandService commandService;

    setUp(() async {
      DevServerService.resetForTesting();
      tempDir = await Directory.systemTemp.createTemp('termode_devserver_cmd_test');
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'devserver_cmd_test');
    });

    tearDown(() async {
      DevServerService.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('dev-server help prints usage overview', () async {
      final res = await commandService.execute('dev-server help');
      expect(res.isError, isFalse);
      expect(res.output, contains('=== Dev Server Supervisor (v0.71) ==='));
      expect(res.output, contains('dev-server list'));
      expect(res.output, contains('dev-server stop'));
      expect(res.output, contains('dev-server logs'));
      expect(res.output, contains('dev-server open'));
      expect(res.output, contains('dev-server doctor'));
    });

    test('dev-server list shows empty message when no servers running', () async {
      DevServerService.serverListHookForTesting = [];
      final res = await commandService.execute('dev-server list');
      expect(res.isError, isFalse);
      expect(res.output, contains('No active background dev servers running'));
    });

    test('dev-server list and server-list alias display active table', () async {
      final mock = DevServerInfo(
        id: 'srv_cmd_test',
        pid: 12345,
        command: 'node',
        arguments: ['server.js'],
        workingDirectory: '/home/test',
        startTime: DateTime.now(),
        isAlive: true,
        detectedPort: 3000,
      );
      DevServerService.serverListHookForTesting = [mock];

      final res1 = await commandService.execute('dev-server list');
      expect(res1.isError, isFalse);
      expect(res1.output, contains('=== Active Dev Servers ==='));
      expect(res1.output, contains('srv_cmd_test'));
      expect(res1.output, contains('12345'));
      expect(res1.output, contains('3000'));
      expect(res1.output, contains('ONLINE'));

      final res2 = await commandService.execute('server-list');
      expect(res2.isError, isFalse);
      expect(res2.output, contains('=== Active Dev Servers ==='));
      expect(res2.output, contains('srv_cmd_test'));
    });

    test('dev-server stop stops server by port and releases socket', () async {
      final mock = DevServerInfo(
        id: 'srv_stop_test',
        pid: 23456,
        command: 'node',
        arguments: ['server.js'],
        workingDirectory: '/home/test',
        startTime: DateTime.now(),
        isAlive: true,
        detectedPort: 3000,
      );
      DevServerService.serverListHookForTesting = [mock];
      DevServerService.stopServerHookForTesting = true;

      final res = await commandService.execute('dev-server stop 3000');
      expect(res.isError, isFalse);
      expect(res.output, contains('Stopped dev server on port 3000'));
      expect(res.output, contains('OS socket and process resources released'));
    });

    test('dev-server stop --all stops all servers', () async {
      DevServerService.stopServerHookForTesting = true;
      final res = await commandService.execute('dev-server stop --all');
      expect(res.isError, isFalse);
      expect(res.output, contains('All active dev servers stopped. Sockets released.'));
    });

    test('dev-server logs displays buffered server output', () async {
      DevServerService.serverLogsHookForTesting = 'Sample stdout log from node server';
      final res = await commandService.execute('dev-server logs 3000');
      expect(res.isError, isFalse);
      expect(res.output, contains('=== Logs for 3000 ==='));
      expect(res.output, contains('Sample stdout log from node server'));
    });

    test('dev-server open launches browser', () async {
      DevServerService.openBrowserHookForTesting = true;
      final res = await commandService.execute('dev-server open 3000');
      expect(res.isError, isFalse);
      expect(res.output, contains('Opening http://127.0.0.1:3000 in browser'));
    });

    test('dev-server doctor runs diagnostic report', () async {
      DevServerService.serverListHookForTesting = [];
      final res = await commandService.execute('dev-server doctor');
      expect(res.isError, isFalse);
      expect(res.output, contains('=== Dev Server Doctor ==='));
      expect(res.output, contains('Supervisor: ACTIVE'));
      expect(res.output, contains('Running servers: 0'));
    });

    test('all aliases route correctly', () async {
      DevServerService.serverListHookForTesting = [];
      DevServerService.stopServerHookForTesting = true;
      DevServerService.serverLogsHookForTesting = 'log content';
      DevServerService.openBrowserHookForTesting = true;

      final r1 = await commandService.execute('server-list');
      expect(r1.output, contains('No active background dev servers running'));

      final r2 = await commandService.execute('server-stop --all');
      expect(r2.output, contains('All active dev servers stopped'));

      final r3 = await commandService.execute('server-logs 3000');
      expect(r3.output, contains('log content'));

      final r4 = await commandService.execute('server-open 3000');
      expect(r4.output, contains('Opening http://127.0.0.1:3000 in browser'));

      final r5 = await commandService.execute('server-doctor');
      expect(r5.output, contains('=== Dev Server Doctor ==='));
    });
  });
}
