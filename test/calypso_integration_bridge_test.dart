import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/termode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory projectDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('calypso_integration_test_');
    projectDir = Directory('${tempDir.path}/home/projects/test-project');
    projectDir.createSync(recursive: true);

    RuntimeBootstrapService().overrideBaseDir = tempDir;
    await RuntimeBootstrapService().init();

    // Mock method channel for real PTY calls
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.termode/native_shell'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'realPtyStart' ||
                methodCall.method == 'realPtySend' ||
                methodCall.method == 'realPtySendRaw' ||
                methodCall.method == 'realPtySendCtrlC' ||
                methodCall.method == 'realPtySendCtrlD') {
              return true;
            }
            if (methodCall.method == 'getPaths') {
              return {
                'home': '${tempDir.path}/home',
                'usr': '${tempDir.path}/usr',
              };
            }
            return null;
          },
        );
  });

  tearDown(() async {
    RuntimeBootstrapService().overrideBaseDir = null;
    PythonEnvironmentService.pythonExecutorForTesting = null;
    RuntimeBinaryPackageService.nodeExecutorForTesting = null;
    RuntimeBinaryPackageService.gitExecutorForTesting = null;
    RuntimeBinaryPackageService.pipExecutorForTesting = null;
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('Milestone v0.80: TermodeEngine Headless Bridge Tests', () {
    test('TermodeEngine initializes and exposes all runtime services', () async {
      final engine = TermodeEngine.instance;
      await engine.initialize(baseDir: tempDir);
      expect(engine.isInitialized, isTrue);

      // Verify all runtime accessors
      expect(engine.python, isNotNull);
      expect(engine.pip, isNotNull);
      expect(engine.osint, isNotNull);
      expect(engine.devServers, isNotNull);
      expect(engine.localhost, isNotNull);
      expect(engine.workspaces, isNotNull);
      expect(engine.npm, isNotNull);
      expect(engine.stacks, isNotNull);
      expect(engine.packages, isNotNull);
      expect(engine.files, isNotNull);
      expect(engine.sessions, isNotNull);
      expect(engine.activeSession, isNotNull);
    });

    test('TermodeEngine diagnostics aggregates runtimes and servers', () async {
      final engine = TermodeEngine.instance;
      await engine.initialize(baseDir: tempDir);

      final diag = await engine.diagnostics(workingDirectory: projectDir.path);
      expect(diag['milestone'], equals('v0.68'));
      expect(diag['engineMilestone'], anyOf(equals('v0.80'), equals('v0.81')));
      expect(diag['engine'], contains('Termode'));
      expect(diag['initialized'], isTrue);

      final runtimes = diag['runtimes'] as Map<String, dynamic>;
      expect(runtimes.containsKey('git'), isTrue);
      expect(runtimes.containsKey('node'), isTrue);
      expect(runtimes.containsKey('npm'), isTrue);
      expect(runtimes.containsKey('python'), isTrue);
      expect(runtimes.containsKey('pip'), isTrue);
      expect(runtimes.containsKey('osint'), isTrue);

      final servers = diag['servers'] as Map<String, dynamic>;
      expect(servers.containsKey('activeDevServers'), isTrue);
    });

    test('TermodeEngine execute and executeStream yield command results', () async {
      final engine = TermodeEngine.instance;
      await engine.initialize(baseDir: tempDir);

      final result = await engine.execute(
        'guide',
        workingDirectory: projectDir.path,
      );
      expect(result.isError, isFalse);
      expect(result.output, contains('Termode User Guide'));

      final streamResult = await engine.executeStream(
        'guide dx',
        workingDirectory: projectDir.path,
      ).first;
      expect(streamResult, contains('Android'));
    });

    test('TermodeEngine direct headless execution hooks work with test executors', () async {
      final engine = TermodeEngine.instance;
      await engine.initialize(baseDir: tempDir);

      // Test Python execution hook
      PythonEnvironmentService.pythonExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'Python 3.14.6 test output: ${args.join(" ")}',
          stderr: '',
          exitCode: 0,
        );
      };

      final pyResult = await engine.runPython(['-c', 'print("hello")']);
      expect(pyResult.exitCode, equals(0));
      expect(pyResult.stdout, contains('Python 3.14.6'));

      // Test Node execution hook
      RuntimeBinaryPackageService.nodeExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'v24.18.0 test: ${args.join(" ")}',
          stderr: '',
          exitCode: 0,
        );
      };

      final nodeResult = await engine.runNode(['-v']);
      expect(nodeResult.exitCode, equals(0));
      expect(nodeResult.stdout, contains('v24.18.0'));

      // Test Git execution hook
      RuntimeBinaryPackageService.gitExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'git version 2.44.0.test',
          stderr: '',
          exitCode: 0,
        );
      };

      final gitResult = await engine.runGit(['--version']);
      expect(gitResult.exitCode, equals(0));
      expect(gitResult.stdout, contains('git version 2.44.0'));

      // Test Pip execution hook
      RuntimeBinaryPackageService.pipExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'pip 26.2.1 test: ${args.join(" ")}',
          stderr: '',
          exitCode: 0,
        );
      };

      final pipResult = await engine.runPip(['--version']);
      expect(pipResult.exitCode, equals(0));
      expect(pipResult.stdout, contains('pip 26.2.1'));
    });
  });

  group('Milestone v0.80: TermodeTerminalController & Embeddable Widget Tests', () {
    test('TermodeTerminalController executes commands and manages sessions', () async {
      final controller = TermodeTerminalController();
      expect(controller.activeSession, isNotNull);
      expect(controller.lines, isNotNull);

      // Programmatic directory change
      controller.setWorkingDirectory(projectDir.path);
      expect(
        controller.activeSession.preferredWorkingDirectory,
        equals(projectDir.path),
      );

      // Programmatic execution
      await controller.execute('guide');
      expect(controller.lines.any((l) => l.text.contains('Termode User Guide')), isTrue);

      // Clear transcript
      controller.clear();
      expect(controller.lines.isEmpty, isTrue);

      // Test signals
      expect(() => controller.sendCtrlC(), returnsNormally);
      expect(() => controller.sendCtrlD(), returnsNormally);
      expect(() => controller.requestFocus(), returnsNormally);
    });

    testWidgets('TermodeEmbeddableTerminal renders with custom theme and controller', (tester) async {
      final controller = TermodeTerminalController();
      String? lastExecutedCommand;
      String? lastExecutedOutput;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              width: 600,
              child: TermodeEmbeddableTerminal(
                controller: controller,
                initialWorkingDirectory: projectDir.path,
                showTabs: true,
                showExtraKeyboardRow: true,
                theme: const TerminalThemeData(
                  backgroundColor: Color(0xFF101010),
                  textColor: Color(0xFFEEEEEE),
                  primaryColor: Color(0xFF00FF66),
                  fontFamily: 'monospace',
                  fontSize: 12.0,
                ),
                onCommandExecuted: (cmd, out) {
                  lastExecutedCommand = cmd;
                  lastExecutedOutput = out;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify widget tree contains TerminalView and ExtraKeyboardRow
      expect(find.byType(TermodeEmbeddableTerminal), findsOneWidget);
      expect(find.byType(ExtraKeyboardRow), findsOneWidget);

      // Verify theme background container
      final containerFinder = find.byType(Container).first;
      final container = tester.widget<Container>(containerFinder);
      expect(container.color, equals(const Color(0xFF101010)));

      // Execute command via controller
      await controller.execute('guide');
      await tester.pumpAndSettle();

      expect(controller.lines.any((l) => l.text.contains('Termode User Guide')), isTrue);
      expect(lastExecutedCommand, isNotNull);
      expect(lastExecutedOutput, isNotNull);
    });
  });
}
