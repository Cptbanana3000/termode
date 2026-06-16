import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/persistence_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Experimental Shell Mode CLI Commands and Services Tests', () {
    final List<MethodCall> methodCalls = [];
    bool ptyStartValue = true;
    Map<String, dynamic>? ptyStatusValue = {'running': true, 'pid': 1234};
    bool ptyStopValue = true;
    bool ptySendValue = true;
    bool ptySendCtrlCValue = true;
    bool ptySendCtrlDValue = true;
    bool realPtyStartValue = true;
    Map<String, dynamic>? realPtyStatusValue = {'running': true, 'pid': 5678};
    bool realPtyStopValue = true;
    bool realPtySendValue = true;
    bool realPtySendCtrlCValue = true;
    bool realPtySendCtrlDValue = true;
    bool realPtyResizeValue = true;
    bool realPtySendRawValue = true;

    setUp(() {
      methodCalls.clear();
      ptyStartValue = true;
      ptyStatusValue = {'running': true, 'pid': 1234};
      ptyStopValue = true;
      ptySendValue = true;
      ptySendCtrlCValue = true;
      ptySendCtrlDValue = true;
      realPtyStartValue = true;
      realPtyStatusValue = {'running': true, 'pid': 5678};
      realPtyStopValue = true;
      realPtySendValue = true;
      realPtySendCtrlCValue = true;
      realPtySendCtrlDValue = true;
      realPtyResizeValue = true;
      realPtySendRawValue = true;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (MethodCall methodCall) async {
              methodCalls.add(methodCall);
              switch (methodCall.method) {
                case 'ptyStart':
                  return ptyStartValue;
                case 'ptyStatus':
                  return ptyStatusValue;
                case 'ptyStop':
                  return ptyStopValue;
                case 'ptySend':
                  return ptySendValue;
                case 'ptySendCtrlC':
                  return ptySendCtrlCValue;
                case 'ptySendCtrlD':
                  return ptySendCtrlDValue;
                case 'realPtyStart':
                  return realPtyStartValue;
                case 'realPtyStatus':
                  return realPtyStatusValue;
                case 'realPtyStop':
                  return realPtyStopValue;
                case 'realPtySend':
                  return realPtySendValue;
                case 'realPtySendCtrlC':
                  return realPtySendCtrlCValue;
                case 'realPtySendCtrlD':
                  return realPtySendCtrlDValue;
                case 'realPtyResize':
                  return realPtyResizeValue;
                case 'realPtySendRaw':
                  return realPtySendRawValue;
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            null,
          );
    });

    test(
      'shell-start executes correctly and toggles session active flag',
      () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;

        final commandService = CommandService(vfs, sessionId);

        // Start shell successfully
        final result = await commandService.execute('shell-start');
        expect(result.isError, isFalse);
        expect(result.output, contains('Shell process started successfully'));
        expect(sessionService.activeSession.isShellActive, isTrue);

        expect(methodCalls.length, 1);
        expect(methodCalls[0].method, 'ptyStart');
        expect(methodCalls[0].arguments['sessionId'], sessionId);
      },
    );

    test(
      'shell-start fails when already running or native returns false',
      () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        ptyStartValue = false;
        final result = await commandService.execute('shell-start');
        expect(result.isError, isTrue);
        expect(result.output, contains('Shell session is already running'));
      },
    );

    test('shell-status displays running process state and PID', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      final commandService = CommandService(vfs, sessionId);

      // Status when running
      final resultRunning = await commandService.execute('shell-status');
      expect(resultRunning.isError, isFalse);
      expect(
        resultRunning.output,
        contains('Shell Status: RUNNING (PID: 1234)'),
      );

      // Status when not running
      ptyStatusValue = {'running': false, 'pid': -1};
      final resultNotRunning = await commandService.execute('shell-status');
      expect(resultNotRunning.isError, isFalse);
      expect(resultNotRunning.output, contains('Shell Status: NOT RUNNING'));
    });

    test('shell-send transmits data to stdin successfully', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      final commandService = CommandService(vfs, sessionId);

      final result = await commandService.execute('shell-send ls -la');
      expect(result.isError, isFalse);
      expect(
        result.output,
        isEmpty,
      ); // Streamed output is async, CLI returns empty

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'ptySend');
      expect(methodCalls[0].arguments['sessionId'], sessionId);
      expect(methodCalls[0].arguments['text'], 'ls -la');
    });

    test('shell-send fails when missing arguments or not running', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      final commandService = CommandService(vfs, sessionId);

      // Missing arguments
      final resultMissing = await commandService.execute('shell-send');
      expect(resultMissing.isError, isTrue);
      expect(resultMissing.output, contains('Usage: shell-send <text>'));

      // Native returns PlatformException for NOT_RUNNING
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'ptySend') {
                throw PlatformException(
                  code: 'NOT_RUNNING',
                  message: 'Process not running',
                );
              }
              return null;
            },
          );

      final resultNotRunning = await commandService.execute(
        'shell-send echo 123',
      );
      expect(resultNotRunning.isError, isTrue);
      expect(
        resultNotRunning.output,
        contains('No active shell process. Start one with shell-start'),
      );
    });

    test('shell-stop stops the process successfully', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      sessionService.activeSession.isShellActive = true;
      final commandService = CommandService(vfs, sessionId);

      final result = await commandService.execute('shell-stop');
      expect(result.isError, isFalse);
      expect(result.output, contains('Shell process stopped'));
      expect(sessionService.activeSession.isShellActive, isFalse);

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'ptyStop');
    });

    test('shell-send-ctrl-c transmits SIGINT signal', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      final commandService = CommandService(vfs, sessionId);

      final result = await commandService.execute('shell-send-ctrl-c');
      expect(result.isError, isFalse);
      expect(result.output, contains('Sent Ctrl-C (SIGINT) to shell process'));

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'ptySendCtrlC');
    });

    test('shell-send-ctrl-d transmits EOF signal', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      final commandService = CommandService(vfs, sessionId);

      final result = await commandService.execute('shell-send-ctrl-d');
      expect(result.isError, isFalse);
      expect(result.output, contains('Sent Ctrl-D (EOF) to shell process'));

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'ptySendCtrlD');
    });

    test('shell-help prints help documentation', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'test');
      final result = await commandService.execute('shell-help');
      expect(result.isError, isFalse);
      expect(result.output, contains('Termode Experimental Shell Mode Help'));
      expect(result.output, contains('interactive process bridge'));
    });

    test(
      'deprecated pty-* alias commands display warnings and delegate correctly',
      () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        // pty-start alias
        final resultStart = await commandService.execute('pty-start');
        expect(
          resultStart.output,
          contains('WARNING: "pty-start" is deprecated/experimental'),
        );
        expect(
          resultStart.output,
          contains('Shell process started successfully'),
        );
        expect(sessionService.activeSession.isShellActive, isTrue);

        // pty-status alias
        final resultStatus = await commandService.execute('pty-status');
        expect(
          resultStatus.output,
          contains('WARNING: "pty-status" is deprecated/experimental'),
        );
        expect(
          resultStatus.output,
          contains('Shell Status: RUNNING (PID: 1234)'),
        );

        // pty-send alias
        final resultSend = await commandService.execute('pty-send uname -a');
        expect(
          resultSend.output,
          contains('WARNING: "pty-send" is deprecated/experimental'),
        );

        // pty-stop alias
        final resultStop = await commandService.execute('pty-stop');
        expect(
          resultStop.output,
          contains('WARNING: "pty-stop" is deprecated/experimental'),
        );
        expect(resultStop.output, contains('Shell process stopped'));
        expect(sessionService.activeSession.isShellActive, isFalse);
      },
    );

    test('session tab removal terminates running shell process', () async {
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();

      sessionService.addSession(); // Creates index 1
      final session = sessionService.sessions[1];
      sessionService.setShellActive(session.id, true);

      expect(sessionService.sessions.length, 2);
      expect(sessionService.sessions[1].isShellActive, isTrue);

      // Remove session
      sessionService.removeSession(1);

      // Verify MethodChannel stop was invoked
      final stopCall = methodCalls.firstWhere(
        (call) =>
            call.method == 'ptyStop' &&
            call.arguments['sessionId'] == session.id,
      );
      expect(stopCall, isNotNull);
    });

    test(
      'real-pty-start allocates pseudo-terminal and toggles active state',
      () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        final result = await commandService.execute('real-pty-start');
        expect(result.isError, isFalse);
        expect(result.output, contains('Real PTY started'));
        expect(sessionService.activeSession.isRealPtyActive, isTrue);

        expect(methodCalls.length, 1);
        expect(methodCalls[0].method, 'realPtyStart');
      },
    );

    test('real-pty-status displays running PID', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      final commandService = CommandService(vfs, sessionId);

      final result = await commandService.execute('real-pty-status');
      expect(result.isError, isFalse);
      expect(result.output, contains('Real PTY Status: RUNNING (PID: 5678)'));
    });

    test('real-pty-send inputs command successfully', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      final commandService = CommandService(vfs, sessionId);

      final result = await commandService.execute('real-pty-send ls');
      expect(result.isError, isFalse);
      expect(result.output, isEmpty);

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'realPtySend');
      expect(methodCalls[0].arguments['text'], 'ls');
    });

    test('real-pty-stop terminates process', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      sessionService.activeSession.isRealPtyActive = true;
      final commandService = CommandService(vfs, sessionId);

      final result = await commandService.execute('real-pty-stop');
      expect(result.isError, isFalse);
      expect(result.output, contains('Real PTY process stopped'));
      expect(sessionService.activeSession.isRealPtyActive, isFalse);
    });

    test('real-pty-help prints native pty instructions', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'test');
      final result = await commandService.execute('real-pty-help');
      expect(result.isError, isFalse);
      expect(result.output, contains('Termode Native PTY Prototype Help'));
      expect(result.output, contains('real-pty-send-ctrl-c'));
      expect(result.output, contains('real-pty-send-ctrl-d'));
      expect(result.output, contains('real-pty-resize'));
    });

    test('real-pty-send-ctrl-c transmits SIGINT to native PTY', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      final commandService = CommandService(vfs, sessionId);

      final result = await commandService.execute('real-pty-send-ctrl-c');
      expect(result.isError, isFalse);
      expect(
        result.output,
        contains('Sent Ctrl-C (SIGINT) to real PTY process'),
      );

      final ctrlCCall = methodCalls.firstWhere(
        (call) => call.method == 'realPtySendCtrlC',
      );
      expect(ctrlCCall.arguments['sessionId'], sessionId);
    });

    test('real-pty-send-ctrl-d transmits EOF to native PTY', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      final commandService = CommandService(vfs, sessionId);

      final result = await commandService.execute('real-pty-send-ctrl-d');
      expect(result.isError, isFalse);
      expect(result.output, contains('Sent Ctrl-D (EOF) to real PTY process'));

      final ctrlDCall = methodCalls.firstWhere(
        (call) => call.method == 'realPtySendCtrlD',
      );
      expect(ctrlDCall.arguments['sessionId'], sessionId);
    });

    test('real-pty-resize changes PTY cols and rows', () async {
      final vfs = VirtualFileSystem();
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();
      final sessionId = sessionService.activeSession.id;
      final commandService = CommandService(vfs, sessionId);

      final result = await commandService.execute('real-pty-resize 120 40');
      expect(result.isError, isFalse);
      expect(result.output, contains('Resized real PTY to 120 cols x 40 rows'));

      final resizeCall = methodCalls.firstWhere(
        (call) => call.method == 'realPtyResize',
      );
      expect(resizeCall.arguments['sessionId'], sessionId);
      expect(resizeCall.arguments['cols'], 120);
      expect(resizeCall.arguments['rows'], 40);
    });

    test(
      'real-pty-resize validation fails on missing or invalid args',
      () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        final resultMissing = await commandService.execute(
          'real-pty-resize 120',
        );
        expect(resultMissing.isError, isTrue);
        expect(
          resultMissing.output,
          contains('Usage: real-pty-resize <cols> <rows>'),
        );

        final resultInvalid = await commandService.execute(
          'real-pty-resize abc 40',
        );
        expect(resultInvalid.isError, isTrue);
        expect(
          resultInvalid.output,
          contains('cols and rows must be positive integers'),
        );
      },
    );

    group('PTY Output Sanitization Tests', () {
      test(
        'normal text, tabs, newlines, carriage returns, and ESC are preserved',
        () {
          final sessionService = TerminalSessionService();
          final input = 'Hello\tWorld!\r\nThis has \u001B[31mcolors\u001B[0m.';
          final sanitized = sessionService.sanitizePtyOutput(input);
          expect(
            sanitized,
            equals('Hello\tWorld!\r\nThis has \u001B[31mcolors\u001B[0m.'),
          );
        },
      );

      test(
        'control characters (except preserved ones) are removed by default',
        () {
          final sessionService = TerminalSessionService();
          // Null character (0x00) and alarm bell (0x07) and delete (0x7F)
          final input = 'A\u0000B\u0007C\u007FD';
          final sanitized = sessionService.sanitizePtyOutput(input);
          expect(sanitized, equals('ABCD'));
        },
      );

      test('control characters are escaped as hex in debug mode', () {
        final settings = SettingsService();
        settings.setShowControlCharsHex(true);

        final sessionService = TerminalSessionService();
        final input = 'A\u0000B\u0007C\u007FD';
        final sanitized = sessionService.sanitizePtyOutput(input);
        expect(sanitized, equals('A[0x00]B[0x07]C[0x7F]D'));

        // Reset settings
        settings.setShowControlCharsHex(false);
      });

      test(
        'CRLF and standalone CR are normalized to LF during PTY output processing',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final sessionId = sessionService.activeSession.id;

          sessionService.appendRealPtyOutput(
            sessionId,
            'Line 1\r\nLine 2\rLine 3\n',
          );

          final lines = sessionService.activeSession.lines;
          expect(lines.any((l) => l.text == 'Line 1'), isTrue);
          expect(lines.any((l) => l.text == 'Line 2'), isTrue);
          expect(lines.any((l) => l.text == 'Line 3'), isTrue);
        },
      );

      test(
        'trailing shell prompt is ignored to prevent duplicated prompts',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final sessionId = sessionService.activeSession.id;

          sessionService.appendRealPtyOutput(
            sessionId,
            'Output line\n/system/bin/sh \$ ',
          );

          final lines = sessionService.activeSession.lines;
          expect(lines.any((l) => l.text == 'Output line'), isTrue);
          expect(lines.any((l) => l.text == '/system/bin/sh \$ '), isFalse);
        },
      );
    });

    group('Real PTY Interaction Mode Tests', () {
      test('enter-pty-mode validates that a real PTY is running', () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        sessionService.activeSession.isRealPtyActive = false;
        final result = await commandService.execute('enter-pty-mode');
        expect(result.isError, isTrue);
        expect(
          result.output,
          contains('Start real PTY first using real-pty-start'),
        );
        expect(sessionService.activeSession.isPtyInteractionActive, isFalse);
      });

      test(
        'enter-pty-mode, exit-pty-mode, and real-pty-mode-status function correctly',
        () async {
          final vfs = VirtualFileSystem();
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final sessionId = sessionService.activeSession.id;
          final commandService = CommandService(vfs, sessionId);

          sessionService.activeSession.isRealPtyActive = true;

          // Check enter
          final resultEnter = await commandService.execute('enter-pty-mode');
          expect(resultEnter.isError, isFalse);
          expect(sessionService.activeSession.isPtyInteractionActive, isTrue);

          // Check status
          final resultStatus = await commandService.execute(
            'real-pty-mode-status',
          );
          expect(resultStatus.output, contains('PTY Interaction Mode: ACTIVE'));

          // Check exit
          final resultExit = await commandService.execute('exit-pty-mode');
          expect(resultExit.isError, isFalse);
          expect(sessionService.activeSession.isPtyInteractionActive, isFalse);

          // Check status inactive
          final resultStatus2 = await commandService.execute(
            'real-pty-mode-status',
          );
          expect(
            resultStatus2.output,
            contains('PTY Interaction Mode: INACTIVE'),
          );
        },
      );

      test(
        'executeCommand routes to realPtySend when PTY interaction is active',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final sessionId = sessionService.activeSession.id;

          sessionService.activeSession.isRealPtyActive = true;
          sessionService.activeSession.isPtyInteractionActive = true;

          sessionService.executeCommand('ls');

          final sendCall = methodCalls.firstWhere(
            (call) => call.method == 'realPtySend',
          );
          expect(sendCall.arguments['sessionId'], sessionId);
          expect(sendCall.arguments['text'], 'ls');
        },
      );

      test('sendRawRealPtyInput triggers realPtySendRaw method call', () async {
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;

        await sessionService.sendRawRealPtyInput('\u001B[A');

        final rawCall = methodCalls.firstWhere(
          (call) => call.method == 'realPtySendRaw',
        );
        expect(rawCall.arguments['sessionId'], sessionId);
        expect(rawCall.arguments['text'], '\u001B[A');
      });

      test(
        'sendRealPtyCtrlC and sendRealPtyCtrlD call correct native endpoints',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final sessionId = sessionService.activeSession.id;

          await sessionService.sendRealPtyCtrlC();
          expect(methodCalls.last.method, 'realPtySendCtrlC');
          expect(methodCalls.last.arguments['sessionId'], sessionId);

          await sessionService.sendRealPtyCtrlD();
          expect(methodCalls.last.method, 'realPtySendCtrlD');
          expect(methodCalls.last.arguments['sessionId'], sessionId);
        },
      );

      test(
        'PTY process exit automatically turns off isPtyInteractionActive and prints exit message',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final sessionId = sessionService.activeSession.id;

          sessionService.activeSession.isRealPtyActive = true;
          sessionService.activeSession.isPtyInteractionActive = true;

          final byteData = const StandardMethodCodec().encodeMethodCall(
            MethodCall('realPtyExit', {'sessionId': sessionId}),
          );
          await TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .handlePlatformMessage(
                'com.termode/native_shell',
                byteData,
                null,
              );

          expect(sessionService.activeSession.isRealPtyActive, isFalse);
          expect(sessionService.activeSession.isPtyInteractionActive, isFalse);
          expect(
            sessionService.activeSession.lines.last.text,
            contains('Real PTY shell exited. Returned to NORMAL mode.'),
          );
        },
      );

      test('termode-shell starts PTY and enters interaction mode', () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        sessionService.activeSession.isRealPtyActive = false;
        sessionService.activeSession.isPtyInteractionActive = false;

        final result = await commandService.execute('termode-shell');
        expect(result.isError, isFalse);
        expect(
          result.output,
          contains(
            'Started Termode shell. Type normal-mode to return to commands.',
          ),
        );
        expect(sessionService.activeSession.isRealPtyActive, isTrue);
        expect(sessionService.activeSession.isPtyInteractionActive, isTrue);
      });

      test('termode-shell handles already-running PTY', () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        sessionService.activeSession.isRealPtyActive = true;
        sessionService.activeSession.isPtyInteractionActive = false;

        final result = await commandService.execute('termode-shell');
        expect(result.isError, isFalse);
        expect(result.output, contains('Entered Real PTY Interaction Mode.'));
        expect(sessionService.activeSession.isPtyInteractionActive, isTrue);

        // Already in mode
        final resultAlready = await commandService.execute('termode-shell');
        expect(resultAlready.output, contains('Already in real shell.'));
      });

      test('stop-shell exits PTY mode and stops PTY', () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        sessionService.activeSession.isRealPtyActive = true;
        sessionService.activeSession.isPtyInteractionActive = true;

        final result = await commandService.execute('stop-shell');
        expect(result.isError, isFalse);
        expect(
          result.output,
          contains('Real PTY shell stopped. Returned to NORMAL mode.'),
        );
        expect(sessionService.activeSession.isRealPtyActive, isFalse);
        expect(sessionService.activeSession.isPtyInteractionActive, isFalse);

        // Friendly message when no PTY running
        final resultNoPty = await commandService.execute('stop-shell');
        expect(
          resultNoPty.output,
          contains('No active real PTY shell is running.'),
        );
      });

      test('real-pty-help includes termode-shell and stop-shell', () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        final result = await commandService.execute('real-pty-help');
        expect(result.isError, isFalse);
        expect(result.output, contains('termode-shell'));
        expect(result.output, contains('stop-shell'));
      });

      test(
        'isLastLinePty ensures PTY outputs do not attach to VFS status messages',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final sessionId = sessionService.activeSession.id;

          // Simulate VFS command printing output
          sessionService.executeCommand('help');
          expect(sessionService.activeSession.isLastLinePty, isFalse);

          // Simulate PTY printing output
          sessionService.appendRealPtyOutput(sessionId, 'hello');
          expect(sessionService.activeSession.isLastLinePty, isTrue);

          // First part must be a separate line because isLastLinePty was false before append
          expect(
            sessionService
                .activeSession
                .lines[sessionService.activeSession.lines.length - 2]
                .text,
            isNot(contains('hello')),
          );
          expect(sessionService.activeSession.lines.last.text, equals('hello'));
        },
      );

      test('default-shell starts PTY and enters interaction mode', () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        sessionService.activeSession.isRealPtyActive = false;
        sessionService.activeSession.isPtyInteractionActive = false;

        final result = await commandService.execute('default-shell');
        expect(result.isError, isFalse);
        expect(
          result.output,
          contains(
            'Started Termode shell. Type normal-mode to return to commands.',
          ),
        );
        expect(sessionService.activeSession.isRealPtyActive, isTrue);
        expect(sessionService.activeSession.isPtyInteractionActive, isTrue);
      });

      test(
        'normal-mode command exits interaction mode but does not kill PTY',
        () async {
          final vfs = VirtualFileSystem();
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final sessionId = sessionService.activeSession.id;
          final commandService = CommandService(vfs, sessionId);

          sessionService.activeSession.isRealPtyActive = true;
          sessionService.activeSession.isPtyInteractionActive = true;

          final result = await commandService.execute('normal-mode');
          expect(result.isError, isFalse);
          expect(
            result.output,
            contains('Returned to NORMAL mode. Real PTY is still running.'),
          );
          expect(sessionService.activeSession.isRealPtyActive, isTrue);
          expect(sessionService.activeSession.isPtyInteractionActive, isFalse);
        },
      );

      test(
        'typing normal-mode in interaction mode is intercepted to return to NORMAL mode',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();

          sessionService.activeSession.isRealPtyActive = true;
          sessionService.activeSession.isPtyInteractionActive = true;

          await sessionService.executeCommand('normal-mode');

          expect(sessionService.activeSession.isPtyInteractionActive, isFalse);
          expect(
            sessionService.activeSession.lines.last.text,
            contains('Returned to NORMAL mode. Real PTY is still running.'),
          );
        },
      );

      test('keyboard-help command output prints keyboard mappings', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'test');
        final result = await commandService.execute('keyboard-help');
        expect(result.isError, isFalse);
        expect(result.output, contains('Termode Keyboard & Input Help'));
        expect(result.output, contains('ESC'));
        expect(result.output, contains('TAB'));
        expect(result.output, contains('CTRL'));
      });

      test(
        'startInRealShell config automatically spawns shell for new session',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();

          final settings = SettingsService();
          settings.setStartInRealShell(true);

          sessionService.addSession();
          await Future.delayed(Duration.zero);
          final newSession = sessionService.sessions.last;

          // Verify that native method call to start real PTY was invoked
          final startCall = methodCalls.firstWhere(
            (call) =>
                call.method == 'realPtyStart' &&
                call.arguments['sessionId'] == newSession.id,
          );
          expect(startCall, isNotNull);
          expect(newSession.isRealPtyActive, isTrue);
          expect(newSession.isPtyInteractionActive, isTrue);

          // Clean up settings
          settings.setStartInRealShell(false);
        },
      );

      test(
        'stale restored sessions explicitly reset transient state variables',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final session = sessionService.activeSession;

          session.isRealPtyActive = true;
          session.isPtyInteractionActive = true;
          session.isShellActive = true;
          session.isExecutingNativeCommand = true;
          session.isLastLinePty = true;

          // Mock persistence state save and load
          final state = {
            'settings': SettingsService().toJson(),
            'activeSessionIndex': 0,
            'sessions': [session.toJson()],
          };

          final mockPersistence = FakePersistenceService(state);
          sessionService.persistenceService = mockPersistence;

          await sessionService.loadPersistedState();

          final restoredSession = sessionService.activeSession;
          expect(restoredSession.isRealPtyActive, isFalse);
          expect(restoredSession.isPtyInteractionActive, isFalse);
          expect(restoredSession.isShellActive, isFalse);
          expect(restoredSession.isExecutingNativeCommand, isFalse);
          expect(restoredSession.isLastLinePty, isFalse);
        },
      );

      test(
        'startInRealShell auto-start only triggers once per session',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();

          final settings = SettingsService();
          settings.setStartInRealShell(true);

          sessionService.addSession();
          await Future.delayed(Duration.zero);

          final newSession = sessionService.sessions.last;
          expect(newSession.hasAttemptedAutoStart, isTrue);

          final startCallsCount = methodCalls
              .where((c) => c.method == 'realPtyStart')
              .length;
          expect(startCallsCount, 1);

          // Clean up
          settings.setStartInRealShell(false);
        },
      );

      test('default-shell does not double-start native PTY', () async {
        final vfs = VirtualFileSystem();
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;
        final commandService = CommandService(vfs, sessionId);

        methodCalls.clear();

        // First invoke - starts PTY
        final res1 = await commandService.execute('default-shell');
        expect(res1.isError, isFalse);
        expect(res1.output, contains('Started Termode shell.'));
        expect(methodCalls.where((c) => c.method == 'realPtyStart').length, 1);

        // Second invoke - already active, enters interaction or returns friendly message
        final res2 = await commandService.execute('default-shell');
        expect(res2.output, contains('Already in real shell.'));
        expect(
          methodCalls.where((c) => c.method == 'realPtyStart').length,
          1,
        ); // no new spawn
      });

      test(
        'stop-shell and real-pty-stop reset both active and interaction flags',
        () async {
          final vfs = VirtualFileSystem();
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final sessionId = sessionService.activeSession.id;
          final commandService = CommandService(vfs, sessionId);

          // Setup active state
          sessionService.activeSession.isRealPtyActive = true;
          sessionService.activeSession.isPtyInteractionActive = true;

          // Stop using stop-shell
          final res1 = await commandService.execute('stop-shell');
          expect(res1.isError, isFalse);
          expect(sessionService.activeSession.isRealPtyActive, isFalse);
          expect(sessionService.activeSession.isPtyInteractionActive, isFalse);

          // Setup active state again
          sessionService.activeSession.isRealPtyActive = true;
          sessionService.activeSession.isPtyInteractionActive = true;

          // Stop using real-pty-stop
          final res2 = await commandService.execute('real-pty-stop');
          expect(res2.isError, isFalse);
          expect(sessionService.activeSession.isRealPtyActive, isFalse);
          expect(sessionService.activeSession.isPtyInteractionActive, isFalse);
        },
      );

      test('realPtyExit callback resets flags to false', () async {
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final sessionId = sessionService.activeSession.id;

        sessionService.activeSession.isRealPtyActive = true;
        sessionService.activeSession.isPtyInteractionActive = true;

        // Trigger exit callback
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

        final codec = const StandardMethodCodec();
        final data = codec.encodeMethodCall(
          MethodCall('realPtyExit', {'sessionId': sessionId}),
        );
        await messenger.handlePlatformMessage(
          'com.termode/native_shell',
          data,
          (ByteData? data) {},
        );

        expect(sessionService.activeSession.isRealPtyActive, isFalse);
        expect(sessionService.activeSession.isPtyInteractionActive, isFalse);
      });

      test(
        'shell-doctor diagnostics command handles state matching and mismatch fixes',
        () async {
          final vfs = VirtualFileSystem();
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final sessionId = sessionService.activeSession.id;
          final commandService = CommandService(vfs, sessionId);

          // Mock native status as running
          realPtyStatusValue = {'running': true, 'pid': 999};
          sessionService.activeSession.isRealPtyActive = true;
          sessionService.activeSession.isPtyInteractionActive = true;

          final resOk = await commandService.execute('shell-doctor');
          expect(resOk.isError, isFalse);
          expect(resOk.output, contains('Current Mode:'));
          expect(resOk.output, contains('REAL PTY'));
          expect(resOk.output, contains('Native PTY Running:'));
          expect(resOk.output, contains('true (PID: 999)'));
          expect(resOk.output, contains('No issues detected.'));

          // Mock mismatch status
          sessionService.activeSession.isRealPtyActive = false;
          final resMismatch = await commandService.execute('shell-doctor');
          expect(resMismatch.isError, isFalse);
          expect(resMismatch.output, contains('Mismatch detected.'));
          expect(
            resMismatch.output,
            contains('Run stop-shell to reset the session state.'),
          );
        },
      );

      test(
        'removeSession method channel invokes are idempotent and safe',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();

          sessionService.addSession();
          final session = sessionService.sessions[1];

          session.isRealPtyActive = true;
          sessionService.removeSession(1);

          // Call twice (idempotency check) - it should not crash even if the process was already deleted
          // and platform channel returns false or throws
          expect(() => sessionService.removeSession(1), returnsNormally);
        },
      );
    });

    group('Runtime Tools CLI Tests', () {
      late Directory tempDir;
      late RuntimeBootstrapService bootstrapService;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'termode_runtime_tools_test',
        );
        bootstrapService = RuntimeBootstrapService();
        bootstrapService.overrideBaseDir = tempDir;
        await bootstrapService.init();
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test(
        'runtime-tools status formatting under clean and installed states',
        () async {
          final vfs = VirtualFileSystem();
          final commandService = CommandService(vfs, 'session_tools');

          // Clean state
          final resClean = await commandService.execute('runtime-tools status');
          expect(resClean.isError, isFalse);
          expect(resClean.output, contains('HEALTHY (no tools installed yet)'));
          expect(resClean.output, contains('Installed Tools:      None'));
          expect(resClean.output, contains('Missing Tools:        None'));
          expect(resClean.output, contains('Chmod Executable:     None'));
          expect(resClean.output, contains('Direct Executable:    None'));
          expect(resClean.output, contains('Interpreter Runnable: None'));

          // Installed state
          final resInstall = await commandService.execute(
            'runtime-tools install-test',
          );
          expect(resInstall.isError, isFalse);
          expect(
            resInstall.output,
            contains('Success: Installed hello-termode test tool'),
          );

          final resInstalled = await commandService.execute(
            'runtime-tools status',
          );
          expect(resInstalled.isError, isFalse);
          if (Platform.isAndroid) {
            expect(
              resInstalled.output,
              contains('Health:               HEALTHY'),
            );
            expect(
              resInstalled.output,
              contains('Interpreter Runnable: hello-termode: Yes'),
            );
          } else {
            expect(
              resInstalled.output,
              contains('Health:               UNHEALTHY (missing interpreter)'),
            );
            expect(
              resInstalled.output,
              contains('Interpreter Runnable: hello-termode: No'),
            );
          }
          expect(
            resInstalled.output,
            contains('Installed Tools:      hello-termode'),
          );
          expect(resInstalled.output, contains('Missing Tools:        None'));
          expect(
            resInstalled.output,
            contains('Chmod Executable:     hello-termode: Yes'),
          );
          expect(
            resInstalled.output,
            contains('Direct Executable:    hello-termode: Yes'),
          );
        },
      );

      test(
        'runtime-tools install-test copies file and generates metadata',
        () async {
          final vfs = VirtualFileSystem();
          final commandService = CommandService(vfs, 'session_tools');

          final res = await commandService.execute(
            'runtime-tools install-test',
          );
          expect(res.isError, isFalse);

          final paths = await bootstrapService.getPaths();
          final binDir = paths['bin']!;
          final usrDir = paths['usr']!;

          final helloFile = File('$binDir/hello-termode');
          expect(await helloFile.exists(), isTrue);
          expect(
            await helloFile.readAsString(),
            contains('Hello from Termode runtime tools'),
          );

          final metaFile = File('$usrDir/termode-tools.json');
          expect(await metaFile.exists(), isTrue);

          final metaContent = await metaFile.readAsString();
          expect(metaContent, contains('hello-termode'));
          expect(metaContent, contains('0.16.0'));
        },
      );

      test(
        'runtime-tools test-run subcommand runs script and returns PASS/FAIL',
        () async {
          final vfs = VirtualFileSystem();
          final commandService = CommandService(vfs, 'session_tools');

          // Try test-run when not installed
          final resNotInstalled = await commandService.execute(
            'runtime-tools test-run',
          );
          expect(resNotInstalled.isError, isTrue);
          expect(
            resNotInstalled.output,
            contains('hello-termode test tool is not installed'),
          );

          // Install first
          await commandService.execute('runtime-tools install-test');

          // Mock executeCommand channel call
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                (MethodCall methodCall) async {
                  if (methodCall.method == 'executeCommand') {
                    final cmd = methodCall.arguments['command'] as String;
                    if (cmd.contains('hello-termode')) {
                      return {
                        'stdout': 'Hello from Termode runtime tools\n',
                        'stderr': '',
                        'exitCode': 0,
                      };
                    }
                  }
                  return null;
                },
              );

          final resRun = await commandService.execute('runtime-tools test-run');
          expect(resRun.isError, isFalse);
          expect(
            resRun.output,
            contains('Executing /system/bin/sh \$TERMODE_BIN/hello-termode...'),
          );
          expect(
            resRun.output,
            contains('Output: Hello from Termode runtime tools'),
          );
          expect(resRun.output, contains('Result: PASS'));

          // Cleanup mock
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                null,
              );
        },
      );

      test(
        'run-tool hello-termode command executes tool and handles args',
        () async {
          final vfs = VirtualFileSystem();
          final commandService = CommandService(vfs, 'session_tools');

          // Usage validation
          final resUsage = await commandService.execute('run-tool');
          expect(resUsage.isError, isTrue);
          expect(
            resUsage.output,
            contains('Usage: run-tool <tool-name> [args...]'),
          );

          // Invalid tool name traversal
          final resTraversal = await commandService.execute(
            'run-tool ../hello',
          );
          expect(resTraversal.isError, isTrue);
          expect(resTraversal.output, contains('run-tool: invalid tool name'));

          // Non-existent tool
          final resNotFound = await commandService.execute(
            'run-tool fake-tool',
          );
          expect(resNotFound.isError, isTrue);
          expect(
            resNotFound.output,
            contains('run-tool: tool not found: fake-tool'),
          );

          // Install hello-termode
          await commandService.execute('runtime-tools install-test');

          // Mock executeCommand channel call
          var lastCommandRun = '';
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                (MethodCall methodCall) async {
                  if (methodCall.method == 'executeCommand') {
                    lastCommandRun = methodCall.arguments['command'] as String;
                    return {
                      'stdout':
                          'Arg count: 2\nHello from Termode runtime tools\n',
                      'stderr': '',
                      'exitCode': 0,
                    };
                  }
                  return null;
                },
              );

          final resRun = await commandService.execute(
            'run-tool hello-termode val1 "val 2"',
          );
          expect(resRun.isError, isFalse);
          expect(resRun.output, contains('Hello from Termode runtime tools'));
          expect(lastCommandRun, contains('/system/bin/sh'));
          expect(lastCommandRun, contains('hello-termode'));
          expect(lastCommandRun, contains('val1 "val 2"'));

          // Cleanup mock
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                null,
              );
        },
      );

      test(
        'install-test creates termode-shell-helpers.sh and reset leaves cleanup script',
        () async {
          final vfs = VirtualFileSystem();
          final commandService = CommandService(vfs, 'session_tools');

          final paths = await bootstrapService.getPaths();
          final usrDir = paths['usr']!;
          final helpersFile = File('$usrDir/termode-shell-helpers.sh');

          expect(await helpersFile.exists(), isFalse);

          // Install
          await commandService.execute('runtime-tools install-test');
          expect(await helpersFile.exists(), isTrue);
          final content = await helpersFile.readAsString();
          expect(content, contains('alias hello-termode='));

          // Reset
          await commandService.execute('runtime-tools reset');
          expect(await helpersFile.exists(), isTrue);
          final resetContent = await helpersFile.readAsString();
          expect(resetContent, contains('unalias hello-termode'));
        },
      );

      test('runtime-tools path environment outputs', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_tools');

        final res = await commandService.execute('runtime-tools path');
        expect(res.isError, isFalse);
        expect(res.output, contains('HOME:'));
        expect(res.output, contains('TERMODE_USR:'));
        expect(res.output, contains('TERMODE_BIN:'));
        expect(res.output, contains('PTY PATH:'));
      });

      test(
        'runtime-tools reset cleanly and safely removes only managed tools',
        () async {
          final vfs = VirtualFileSystem();
          final commandService = CommandService(vfs, 'session_tools');

          // Install first
          await commandService.execute('runtime-tools install-test');

          final paths = await bootstrapService.getPaths();
          final binDir = paths['bin']!;
          final usrDir = paths['usr']!;

          final helloFile = File('$binDir/hello-termode');
          final metaFile = File('$usrDir/termode-tools.json');

          expect(await helloFile.exists(), isTrue);
          expect(await metaFile.exists(), isTrue);

          // Reset
          final resReset = await commandService.execute('runtime-tools reset');
          expect(resReset.isError, isFalse);
          expect(
            resReset.output,
            contains('Success: Cleaned up managed runtime tools and metadata'),
          );

          expect(await helloFile.exists(), isFalse);
          expect(await metaFile.exists(), isFalse);
        },
      );

      test('metadata JSON creation and checksum verification', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_tools');

        await commandService.execute('runtime-tools install-test');

        final paths = await bootstrapService.getPaths();
        final usrDir = paths['usr']!;
        final metaFile = File('$usrDir/termode-tools.json');

        final content = await metaFile.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        expect(data['managedBy'], 'Termode');
        expect(data['version'], '0.16.0');

        final checksums = data['checksums'] as Map<String, dynamic>;
        expect(checksums.containsKey('hello-termode'), isTrue);
        final helloHash = checksums['hello-termode'] as String;
        expect(helloHash.length, 8); // FNV-1a 32-bit hex has 8 characters
      });

      test('safety checks block path traversal deletions', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_tools');

        // Install first
        await commandService.execute('runtime-tools install-test');

        final paths = await bootstrapService.getPaths();
        final binDir = paths['bin']!;
        final usrDir = paths['usr']!;

        // Write a test external file that is outside binDir, e.g. in usrDir
        final externalFile = File('$usrDir/dummy_traversal.txt');
        await externalFile.writeAsString('sensitive data');
        expect(await externalFile.exists(), isTrue);

        // Modify metadata to inject path traversal
        final metaFile = File('$usrDir/termode-tools.json');
        final metaContent = await metaFile.readAsString();
        final data = jsonDecode(metaContent) as Map<String, dynamic>;
        data['installedTools'] = ['hello-termode', '../dummy_traversal.txt'];
        await metaFile.writeAsString(jsonEncode(data));

        // Reset
        final resReset = await commandService.execute('runtime-tools reset');
        expect(resReset.isError, isFalse);

        // hello-termode should be deleted
        expect(await File('$binDir/hello-termode').exists(), isFalse);
        // externalFile should NOT be deleted
        expect(await externalFile.exists(), isTrue);

        // Cleanup the external file manually
        await externalFile.delete();
      });

      test('runtime-tools help output documentation warnings', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_tools');

        final res = await commandService.execute('runtime-tools help');
        expect(res.isError, isFalse);
        expect(res.output, contains('Termode Runtime Tools Help'));
        expect(res.output, contains('runtime-tools status'));
        expect(res.output, contains('runtime-tools install-test'));
        expect(res.output, contains('runtime-tools reset'));
        expect(res.output, contains('runtime-tools path'));
        expect(res.output, contains('runtime-tools help'));
      });
    });

    group('Package Manager CLI Tests', () {
      late Directory tempDir;
      late RuntimeBootstrapService bootstrapService;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'termode_pkg_manager_test',
        );
        bootstrapService = RuntimeBootstrapService();
        bootstrapService.overrideBaseDir = tempDir;
        await bootstrapService.init();
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test('pkg help output', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_pkg');

        final res = await commandService.execute('pkg help');
        expect(res.isError, isFalse);
        expect(res.output, contains('Termode Package Manager (pkg)'));
        expect(res.output, contains('pkg help'));
        expect(res.output, contains('pkg update'));
        expect(res.output, contains('pkg list'));
        expect(res.output, contains('pkg search'));
        expect(res.output, contains('pkg info'));
        expect(res.output, contains('pkg install'));
        expect(res.output, contains('pkg remove'));
        expect(res.output, contains('pkg installed'));
        expect(res.output, contains('pkg doctor'));
      });

      test('pkg update output', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_pkg');

        final res = await commandService.execute('pkg update');
        expect(res.isError, isFalse);
        expect(res.output, contains('Updating package index...'));
        expect(res.output, contains('Loaded local Termode package index.'));
        expect(
          res.output,
          contains('Success: Index updated (3 packages available).'),
        );
      });

      test('pkg list output', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_pkg');

        final res = await commandService.execute('pkg list');
        expect(res.isError, isFalse);
        expect(res.output, contains('=== Termode Package Repository ==='));
        expect(res.output, contains('hello [1.0.0]'));
        expect(res.output, contains('cowsay-lite [1.0.0]'));
        expect(res.output, contains('sysinfo-lite [1.0.0]'));
        expect(res.output, contains('(Status: Not Installed)'));
      });

      test('pkg search output', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_pkg');

        final res = await commandService.execute('pkg search cowsay');
        expect(res.isError, isFalse);
        expect(res.output, contains('=== Search Results for "cowsay" ==='));
        expect(res.output, contains('cowsay-lite [1.0.0]'));
        expect(res.output, contains('(Status: Not Installed)'));

        final resEmpty = await commandService.execute(
          'pkg search non_existent_pkg',
        );
        expect(resEmpty.isError, isFalse);
        expect(resEmpty.output, contains('No matching packages found.'));
      });

      test('pkg info output', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_pkg');

        final res = await commandService.execute('pkg info hello');
        expect(res.isError, isFalse);
        expect(res.output, contains('Package:     hello'));
        expect(res.output, contains('Version:     1.0.0'));
        expect(res.output, contains('Type:        script'));
        expect(res.output, contains('Status:      Not Installed'));
        expect(
          res.output,
          contains(
            'Description: Prints a hello message from Termode package manager.',
          ),
        );
        expect(res.output, contains('Files:'));
        expect(res.output, contains('- usr/bin/hello'));

        final resError = await commandService.execute('pkg info non_existent');
        expect(resError.isError, isTrue);
        expect(
          resError.output,
          contains('Package "non_existent" not found in index.'),
        );
      });

      test('pkg install, installed, and double-install validation', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_pkg');

        // Verify initially not installed
        final resEmpty = await commandService.execute('pkg installed');
        expect(resEmpty.isError, isFalse);
        expect(resEmpty.output, contains('No packages currently installed.'));

        // Install hello
        final resInst = await commandService.execute('pkg install hello');
        expect(resInst.isError, isFalse);
        expect(resInst.output, contains('Success: Installed package hello'));
        expect(
          resInst.output,
          contains('Tip: Command is available now. Try: hello'),
        );

        // Check path and files
        final paths = await bootstrapService.getPaths();
        final baseDir = '${paths['home']!}/..';
        final helloFile = File('$baseDir/usr/bin/hello');
        expect(await helloFile.exists(), isTrue);
        expect(
          await helloFile.readAsString(),
          contains('Hello from Termode package manager!'),
        );

        // Check metadata in termode-packages.json
        final usrDir = paths['usr']!;
        final metaFile = File('$usrDir/termode-packages.json');
        expect(await metaFile.exists(), isTrue);
        final metaContent = await metaFile.readAsString();
        final data = jsonDecode(metaContent) as Map<String, dynamic>;
        expect(data['packages'].containsKey('hello'), isTrue);
        final helloData = data['packages']['hello'] as Map<String, dynamic>;
        expect(helloData['checksums'].containsKey('usr/bin/hello'), isTrue);
        expect(
          helloData['checksums']['usr/bin/hello'].length,
          8,
        ); // FNV-1a hash length

        // Check helpers file contains function
        final helpersFile = File('$usrDir/termode-shell-helpers.sh');
        expect(await helpersFile.exists(), isTrue);
        final helpersContent = await helpersFile.readAsString();
        expect(helpersContent, contains('hello() {'));
        expect(
          helpersContent,
          contains('/system/bin/sh "\$TERMODE_BIN/hello" "\$@"'),
        );

        // Try double-install
        final resDouble = await commandService.execute('pkg install hello');
        expect(resDouble.isError, isTrue);
        expect(
          resDouble.output,
          contains('Error: package already installed: hello'),
        );

        // List installed
        final resInstalled = await commandService.execute('pkg installed');
        expect(resInstalled.isError, isFalse);
        expect(resInstalled.output, contains('=== Installed Packages ==='));
        expect(resInstalled.output, contains('hello [1.0.0] - Installed at:'));
      });

      test('pkg remove cleans files and helper functions', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_pkg');

        // Try removing non-installed
        final resRemErr = await commandService.execute('pkg remove hello');
        expect(resRemErr.isError, isTrue);
        expect(
          resRemErr.output,
          contains('Error: package not installed: hello'),
        );

        // Install and remove hello
        await commandService.execute('pkg install hello');

        final paths = await bootstrapService.getPaths();
        final baseDir = '${paths['home']!}/..';
        final helloFile = File('$baseDir/usr/bin/hello');
        final usrDir = paths['usr']!;
        final helpersFile = File('$usrDir/termode-shell-helpers.sh');

        expect(await helloFile.exists(), isTrue);
        expect(await helpersFile.exists(), isTrue);

        final resRem = await commandService.execute('pkg remove hello');
        expect(resRem.isError, isFalse);
        expect(resRem.output, contains('Success: Removed package hello'));

        // File should be deleted and helper script should clear stale functions
        expect(await helloFile.exists(), isFalse);
        expect(await helpersFile.exists(), isTrue);
        final helpersContent = await helpersFile.readAsString();
        expect(helpersContent, contains('unset -f hello'));
        expect(helpersContent, isNot(contains('hello() {')));

        final metaFile = File('$usrDir/termode-packages.json');
        final metaContent = await metaFile.readAsString();
        final data = jsonDecode(metaContent) as Map<String, dynamic>;
        expect(data['packages'].containsKey('hello'), isFalse);
      });

      test('pkg doctor audit formatting and corrupt metadata safety', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_pkg');

        // Check doctor on clean environment
        final resClean = await commandService.execute('pkg doctor');
        expect(resClean.isError, isFalse);
        expect(resClean.output, contains('Metadata File:      MISSING'));
        expect(resClean.output, contains('Helper Script:      MISSING'));
        expect(resClean.output, contains('Installed Packages: 0'));
        expect(resClean.output, contains('Helper Function Count: 0'));
        expect(resClean.output, contains('Helper Reload Command:'));
        expect(resClean.output, contains('Current Shell May Need Reload: NO'));
        expect(resClean.output, contains('All registered files: Present'));
        expect(resClean.output, contains('Overall Status:     HEALTHY'));

        // Install hello
        await commandService.execute('pkg install hello');

        final resInstalled = await commandService.execute('pkg doctor');
        expect(resInstalled.isError, isFalse);
        expect(resInstalled.output, contains('Metadata File:      EXISTS'));
        expect(resInstalled.output, contains('Helper Script:      EXISTS'));
        expect(resInstalled.output, contains('Installed Packages: 1'));
        expect(resInstalled.output, contains('Helper Function Count: 1'));
        expect(
          resInstalled.output,
          contains('Current Shell May Need Reload: YES'),
        );
        expect(resInstalled.output, contains('Helper Functions:   OK'));
        expect(resInstalled.output, contains('Overall Status:     HEALTHY'));

        // Corrupt metadata
        final paths = await bootstrapService.getPaths();
        final usrDir = paths['usr']!;
        final metaFile = File('$usrDir/termode-packages.json');
        await metaFile.writeAsString('invalid_json{');

        final resCorrupted = await commandService.execute('pkg doctor');
        expect(
          resCorrupted.isError,
          isFalse,
        ); // doctor handles parse error gracefully
        expect(
          resCorrupted.output,
          contains('Installed Packages: 0'),
        ); // treats as 0 installed

        // Trying to install/remove with corrupt metadata returns error
        final resInstErr = await commandService.execute('pkg install hello');
        expect(resInstErr.isError, isTrue);
        expect(resInstErr.output, contains('Error: metadata corrupted'));

        final resRemErr = await commandService.execute('pkg remove hello');
        expect(resRemErr.isError, isTrue);
        expect(resRemErr.output, contains('Error: metadata corrupted'));
      });

      test('pkg install path traversal block safety', () async {
        final vfs = VirtualFileSystem();
        final commandService = CommandService(vfs, 'session_pkg');

        final paths = await bootstrapService.getPaths();
        final usrDir = paths['usr']!;

        final metaFile = File('$usrDir/termode-packages.json');
        final data = {
          'packages': {
            'malicious': {
              'name': 'malicious',
              'version': '1.0.0',
              'type': 'script',
              'description': 'Malicious package',
              'executable': 'malicious',
              'installedAt': DateTime.now().toIso8601String(),
              'files': ['usr/bin/malicious', '../sensitive_file.txt'],
              'checksums': {
                'usr/bin/malicious': '12345678',
                '../sensitive_file.txt': '12345678',
              },
            },
          },
        };
        await metaFile.writeAsString(jsonEncode(data));

        // Write sensitive file outside usr/bin
        final sensitiveFile = File('${paths['home']}/../sensitive_file.txt');
        await sensitiveFile.writeAsString('confidential content');
        expect(await sensitiveFile.exists(), isTrue);

        // Run pkg remove malicious
        final resRemove = await commandService.execute('pkg remove malicious');
        expect(
          resRemove.isError,
          isFalse,
        ); // returns success for the package overall

        // sensitiveFile should still exist because traversal path was skipped/blocked!
        expect(await sensitiveFile.exists(), isTrue);

        // Cleanup
        await sensitiveFile.delete();
      });
    });

    group('Host Command Interception and Shell-first UX Tests', () {
      late Directory tempDir;
      late RuntimeBootstrapService bootstrapService;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'termode_interception_test',
        );
        bootstrapService = RuntimeBootstrapService();
        bootstrapService.overrideBaseDir = tempDir;
        await bootstrapService.init();

        // Reset settings
        SettingsService().loadFromJson(null);
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test(
        'startInRealShell default true for fresh settings and loads false',
        () async {
          final settings = SettingsService();

          // Fresh initialization
          settings.loadFromJson(null);
          expect(settings.startInRealShell, isTrue);

          // Load json with startInRealShell: false
          settings.loadFromJson({'startInRealShell': false});
          expect(settings.startInRealShell, isFalse);

          // Load json with startInRealShell: true
          settings.loadFromJson({'startInRealShell': true});
          expect(settings.startInRealShell, isTrue);

          // Load empty json (key absent) fallback to true
          settings.loadFromJson({});
          expect(settings.startInRealShell, isTrue);
        },
      );

      test('PTY mode interception vs PTY command forwarding', () async {
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();

        // Add session (auto starts in PTY because startInRealShell defaults to true)
        // Let's mock the MethodChannel calls
        final List<MethodCall> methodCalls = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.termode/native_shell'),
              (MethodCall methodCall) async {
                methodCalls.add(methodCall);
                if (methodCall.method == 'realPtyStart') {
                  return true;
                }
                if (methodCall.method == 'realPtySend') {
                  return true;
                }
                if (methodCall.method == 'realPtyStop') {
                  return true;
                }
                return null;
              },
            );

        sessionService.addSession();
        await Future.delayed(Duration.zero);

        final session = sessionService.activeSession;
        // Verify started in PTY mode automatically
        expect(session.isRealPtyActive, isTrue);
        expect(session.isPtyInteractionActive, isTrue);

        // 1. Normal command like 'ls -la' should NOT be intercepted (forwarded directly to PTY)
        methodCalls.clear();
        await sessionService.executeCommand('ls -la');

        expect(methodCalls.length, 1);
        expect(methodCalls.first.method, 'realPtySend');
        expect(methodCalls.first.arguments['text'], 'ls -la');

        // 2. Intercepted host command like 'pkg update'
        methodCalls.clear();
        await sessionService.executeCommand('pkg update');

        // Should execute locally, printing command + output
        // And send a blank line to realPtySend to refresh prompt
        expect(methodCalls.length, 1);
        expect(methodCalls.first.method, 'realPtySend');
        expect(
          methodCalls.first.arguments['text'],
          '',
        ); // prompt refresh triggered!

        // Check command output exists in lines
        final outputLines = session.lines.map((l) => l.text).join('\n');
        expect(outputLines, contains('pkg update'));
        expect(outputLines, contains('Success: Index updated'));

        // 3. Command prefix matching: 'echo pkg update' should NOT be intercepted
        methodCalls.clear();
        await sessionService.executeCommand('echo pkg update');
        expect(methodCalls.length, 1);
        expect(methodCalls.first.method, 'realPtySend');
        expect(methodCalls.first.arguments['text'], 'echo pkg update');

        // Cleanup MethodChannel mock
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.termode/native_shell'),
              null,
            );
      });

      test(
        'pkg install triggers helper reload when REAL PTY mode is active',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final List<MethodCall> methodCalls = [];

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                (MethodCall methodCall) async {
                  methodCalls.add(methodCall);
                  if (methodCall.method == 'realPtyStart' ||
                      methodCall.method == 'realPtySend' ||
                      methodCall.method == 'realPtySendRaw') {
                    return true;
                  }
                  return null;
                },
              );

          sessionService.addSession();
          await Future.delayed(Duration.zero);
          methodCalls.clear();

          await sessionService.executeCommand('pkg install hello');

          final rawCall = methodCalls.firstWhere(
            (call) => call.method == 'realPtySendRaw',
          );
          expect(
            rawCall.arguments['text'],
            TerminalSessionService.shellHelperReloadCommand,
          );
          final promptRefresh = methodCalls.lastWhere(
            (call) => call.method == 'realPtySend',
          );
          expect(promptRefresh.arguments['text'], '');

          final output = sessionService.activeSession.lines
              .map((l) => l.text)
              .join('\n');
          expect(output, contains('Success: Installed package hello'));
          expect(output, contains('Tip: Command is available now. Try: hello'));

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                null,
              );
        },
      );

      test(
        'pkg remove triggers helper reload when REAL PTY mode is active',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();
          final List<MethodCall> methodCalls = [];

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                (MethodCall methodCall) async {
                  methodCalls.add(methodCall);
                  if (methodCall.method == 'realPtyStart' ||
                      methodCall.method == 'realPtySend' ||
                      methodCall.method == 'realPtySendRaw') {
                    return true;
                  }
                  return null;
                },
              );

          sessionService.addSession();
          await Future.delayed(Duration.zero);
          await sessionService.executeCommand('pkg install hello');
          methodCalls.clear();

          await sessionService.executeCommand('pkg remove hello');

          final rawCall = methodCalls.firstWhere(
            (call) => call.method == 'realPtySendRaw',
          );
          expect(
            rawCall.arguments['text'],
            TerminalSessionService.shellHelperReloadCommand,
          );
          final output = sessionService.activeSession.lines
              .map((l) => l.text)
              .join('\n');
          expect(output, contains('Success: Removed package hello'));
          expect(
            output,
            contains('If it still appears cached, run: reload-helpers'),
          );

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                null,
              );
        },
      );

      test('reload-helpers sends source command to active REAL PTY', () async {
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final List<MethodCall> methodCalls = [];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.termode/native_shell'),
              (MethodCall methodCall) async {
                methodCalls.add(methodCall);
                if (methodCall.method == 'realPtyStart' ||
                    methodCall.method == 'realPtySend' ||
                    methodCall.method == 'realPtySendRaw') {
                  return true;
                }
                return null;
              },
            );

        sessionService.addSession();
        await Future.delayed(Duration.zero);
        methodCalls.clear();

        await sessionService.executeCommand('reload-helpers');

        final rawCall = methodCalls.firstWhere(
          (call) => call.method == 'realPtySendRaw',
        );
        expect(
          rawCall.arguments['text'],
          TerminalSessionService.shellHelperReloadCommand,
        );
        final output = sessionService.activeSession.lines
            .map((l) => l.text)
            .join('\n');
        expect(output, contains('Reloaded Termode shell helpers.'));

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.termode/native_shell'),
              null,
            );
      });

      test('reload-helpers in NORMAL mode prints guidance', () async {
        final sessionService = TerminalSessionService();
        sessionService.clearMemoryStateForTesting();
        final commandService = CommandService(
          VirtualFileSystem(),
          sessionService.activeSession.id,
        );

        final res = await commandService.execute('reload-helpers');

        expect(res.isError, isFalse);
        expect(
          res.output,
          contains('helpers are sourced inside REAL PTY shell sessions'),
        );
      });

      test(
        'helper reload failure after pkg install gives fallback message',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                (MethodCall methodCall) async {
                  if (methodCall.method == 'realPtyStart' ||
                      methodCall.method == 'realPtySend') {
                    return true;
                  }
                  if (methodCall.method == 'realPtySendRaw') {
                    return false;
                  }
                  return null;
                },
              );

          sessionService.addSession();
          await Future.delayed(Duration.zero);

          await sessionService.executeCommand('pkg install hello');

          final output = sessionService.activeSession.lines
              .map((l) => l.text)
              .join('\n');
          expect(
            output,
            contains(
              'Package installed, but helper reload failed. Run: reload-helpers',
            ),
          );

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                null,
              );
        },
      );

      test('real PTY prompt no longer uses Bash-only backslash-w', () async {
        final source = await File(
          'android/app/src/main/kotlin/com/termode/termode/MainActivity.kt',
        ).readAsString();

        expect(source, isNot(contains(r'termode:\\w')));
        expect(source, contains(r'termode:\$ '));
      });

      test(
        'Intercepted commands: mode, host-help, normal-mode, stop-shell',
        () async {
          final sessionService = TerminalSessionService();
          sessionService.clearMemoryStateForTesting();

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                (MethodCall methodCall) async {
                  if (methodCall.method == 'realPtyStart' ||
                      methodCall.method == 'realPtySend' ||
                      methodCall.method == 'realPtyStop') {
                    return true;
                  }
                  return null;
                },
              );

          sessionService.addSession();
          await Future.delayed(Duration.zero);
          final session = sessionService.activeSession;
          expect(session.isPtyInteractionActive, isTrue);

          // 1. mode command
          session.lines.clear();
          await sessionService.executeCommand('mode');
          expect(
            session.lines.map((l) => l.text).join('\n'),
            contains('Current Mode:                   REAL PTY'),
          );

          // 2. host-help command
          session.lines.clear();
          await sessionService.executeCommand('host-help');
          final helpOut = session.lines.map((l) => l.text).join('\n');
          expect(
            helpOut,
            contains('=== Termode Host Command Interception ==='),
          );
          expect(helpOut, contains('pkg'));
          expect(helpOut, contains('normal-mode'));

          // 3. normal-mode command
          await sessionService.executeCommand('normal-mode');
          expect(session.isPtyInteractionActive, isFalse);
          expect(
            session.isRealPtyActive,
            isTrue,
          ); // keeps running in background

          // Re-enter PTY interaction mode
          sessionService.setPtyInteractionActive(session.id, true);
          expect(session.isPtyInteractionActive, isTrue);

          // 4. stop-shell command
          await sessionService.executeCommand('stop-shell');
          expect(session.isPtyInteractionActive, isFalse);
          expect(session.isRealPtyActive, isFalse); // stopped completely

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.termode/native_shell'),
                null,
              );
        },
      );
    });
  });
}

class FakePersistenceService extends PersistenceService {
  Map<String, dynamic>? state;
  FakePersistenceService(this.state);

  @override
  Future<void> saveState(Map<String, dynamic> state) async {
    this.state = state;
  }

  @override
  Future<Map<String, dynamic>?> loadState() async {
    return state;
  }

  @override
  Future<void> clearState() async {
    state = null;
  }
}
