import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/package_manager_service.dart';
import 'package:termode/services/python_environment_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late VirtualFileSystem vfs;
  late CommandService commandService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('termode_guide_test_');
    RuntimeBootstrapService().overrideBaseDir = tempDir;
    await RuntimeBootstrapService().init();

    vfs = VirtualFileSystem();
    commandService = CommandService(vfs, 'test-session');
  });

  tearDown(() async {
    RuntimeBootstrapService().overrideBaseDir = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Milestone v0.79: User Guide Command Tests', () {
    test('guide command is registered in kTermodeCommands catalog', () {
      expect(kTermodeCommands.contains('guide'), isTrue);
      expect(kTermodeCommands.contains('user-guide'), isTrue);
      expect(kTermodeCommands.contains('android-guide'), isTrue);
    });

    test('guide default output displays overview and topics', () async {
      final res = await commandService.execute('guide');
      expect(res.isError, isFalse);
      expect(res.output, contains('Termode User Guide'));
      expect(res.output, contains('guide python'));
      expect(res.output, contains('guide node'));
      expect(res.output, contains('guide git'));
      expect(res.output, contains('guide dx'));
    });

    test('user-guide and android-guide aliases return the user guide', () async {
      final res1 = await commandService.execute('user-guide');
      expect(res1.isError, isFalse);
      expect(res1.output, contains('Termode User Guide'));

      final res2 = await commandService.execute('android-guide');
      expect(res2.isError, isFalse);
      expect(res2.output, contains('Termode User Guide'));
    });

    test('guide python returns Python & pip guidance', () async {
      final res = await commandService.execute('guide python');
      expect(res.isError, isFalse);
      expect(res.output, contains('=== Termode Guide: Python & pip ==='));
      expect(res.output, contains('CPython 3.14'));
      expect(res.output, contains('pip install --user <pkg>'));
      expect(res.output, contains('Android W^X & Bare Commands'));
    });

    test('guide node returns Node.js & npm guidance', () async {
      final res = await commandService.execute('guide node');
      expect(res.isError, isFalse);
      expect(res.output, contains('=== Termode Guide: Node.js & npm ==='));
      expect(res.output, contains('Node.js v24'));
      expect(res.output, contains('npm install -g'));
    });

    test('guide git returns local Git guidance', () async {
      final res = await commandService.execute('guide git');
      expect(res.isError, isFalse);
      expect(res.output, contains('=== Termode Guide: Local Git ==='));
      expect(res.output, contains('Git 2.44.0'));
      expect(res.output, contains('git init'));
    });

    test('guide dx returns Android DX & architecture rationale', () async {
      final res = await commandService.execute('guide dx');
      expect(res.isError, isFalse);
      expect(res.output, contains('=== Termode Guide: Android DX & Architecture ==='));
      expect(res.output, contains('Automatic W^X Compliance'));
      expect(res.output, contains('Zero Setup Friction'));
    });

    test('welcome and commands outputs include guide and active runtimes', () async {
      final welcome = await commandService.execute('welcome');
      expect(welcome.output, contains('guide'));
      expect(welcome.output, contains('Node.js v24.18.0'));
      expect(welcome.output, contains('Python 3.14.6'));
      expect(welcome.output, contains('Git 2.44.0'));

      final commands = await commandService.execute('commands');
      expect(commands.output, contains('guide'));
      expect(commands.output, contains('Python & pip'));
      expect(commands.output, contains('Node.js & npm'));
    });
  });

  group('Milestone v0.79: Dynamic Shell Wrapper Automation Tests', () {
    test('updateShellHelpers generates dynamic wrappers for scanned ~/.local/bin tools', () async {
      final paths = await RuntimeBootstrapService().getPaths();
      final homeDir = paths['home']!;
      final localBin = Directory('$homeDir/.local/bin');
      await localBin.create(recursive: true);

      // Simulate pip installing entry points
      final cowsayScript = File('${localBin.path}/cowsay');
      await cowsayScript.writeAsString('#!/usr/bin/python3\nprint("moo")\n');
      final pyfigletScript = File('${localBin.path}/pyfiglet');
      await pyfigletScript.writeAsString('#!/usr/bin/python3\nprint("figlet")\n');

      // Update shell helpers
      await PackageManagerService.updateShellHelpers();

      final usrDir = paths['usr']!;
      final helpersFile = File('$usrDir/termode-shell-helpers.sh');
      expect(await helpersFile.exists(), isTrue);

      final content = await helpersFile.readAsString();
      expect(content, contains('cowsay() {'));
      expect(content, contains('python3 "\$TERMODE_HOME/.local/bin/cowsay" "\$@"'));
      expect(content, contains('pyfiglet() {'));
      expect(content, contains('python3 "\$TERMODE_HOME/.local/bin/pyfiglet" "\$@"'));
      expect(content, contains('unset -f cowsay'));
      expect(content, contains('unset -f pyfiglet'));
      expect(content, contains('export PYTHONHOME='));
      expect(content, contains('export PYTHONPATH='));
    });

    test('updateShellHelpers generates dynamic wrappers for scanned ~/.npm-global/bin tools', () async {
      final paths = await RuntimeBootstrapService().getPaths();
      final homeDir = paths['home']!;
      final npmBin = Directory('$homeDir/.npm-global/bin');
      await npmBin.create(recursive: true);

      final prettierScript = File('${npmBin.path}/prettier');
      await prettierScript.writeAsString('#!/usr/bin/node\n');

      await PackageManagerService.updateShellHelpers();

      final usrDir = paths['usr']!;
      final helpersFile = File('$usrDir/termode-shell-helpers.sh');
      final content = await helpersFile.readAsString();

      expect(content, contains('prettier() {'));
      expect(content, contains('node "\$TERMODE_HOME/.npm-global/bin/prettier" "\$@"'));
      expect(content, contains('unset -f prettier'));
    });

    test('updateShellHelpers includes live in-memory scanner inside pip wrapper', () async {
      await PackageManagerService.updateShellHelpers();
      final paths = await RuntimeBootstrapService().getPaths();
      final usrDir = paths['usr']!;
      final helpersFile = File('$usrDir/termode-shell-helpers.sh');
      final content = await helpersFile.readAsString();

      expect(content, contains('pip() {'));
      expect(
        content,
        contains(
          r'eval "$_tool() { python3 \"$TERMODE_HOME/.local/bin/$_tool\" \"\$@\"; }"',
        ),
      );
    });

    test('CommandService fallback executes tool from ~/.local/bin if present', () async {
      final paths = await RuntimeBootstrapService().getPaths();
      final homeDir = paths['home']!;
      final localBin = Directory('$homeDir/.local/bin');
      await localBin.create(recursive: true);

      final script = File('${localBin.path}/mycustomtool');
      await script.writeAsString('#!/usr/bin/python3\n');

      // Set python test executor hook
      PythonEnvironmentService.pythonExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'Executed ${args.first} successfully',
          stderr: '',
          exitCode: 0,
        );
      };

      try {
        final result = await commandService.execute('mycustomtool --arg1 test');
        expect(result.isError, isFalse);
        expect(result.output, contains('Executed'));
        expect(result.output, contains('mycustomtool'));
      } finally {
        PythonEnvironmentService.pythonExecutorForTesting = null;
      }
    });
  });
}
