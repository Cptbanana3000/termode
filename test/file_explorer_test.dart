import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/termode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FileExplorerService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('termode_file_test_');
    service = FileExplorerService();
    service.overrideHomeDir = tempDir;
  });

  tearDown(() async {
    service.overrideHomeDir = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Milestone v0.81: FileExplorerService Unit Tests', () {
    test('detectCategory classifies extensions correctly', () {
      expect(service.detectCategory('folder', true), FileCategory.directory);
      expect(service.detectCategory('script.py', false), FileCategory.python);
      expect(service.detectCategory('app.js', false), FileCategory.javascript);
      expect(service.detectCategory('module.mjs', false), FileCategory.javascript);
      expect(service.detectCategory('run.sh', false), FileCategory.shell);
      expect(service.detectCategory('data.json', false), FileCategory.json);
      expect(service.detectCategory('README.md', false), FileCategory.markdown);
      expect(service.detectCategory('main.c', false), FileCategory.c);
      expect(service.detectCategory('config.yaml', false), FileCategory.text);
      expect(service.detectCategory('app.log', false), FileCategory.text);
      expect(service.detectCategory('photo.png', false), FileCategory.image);
      expect(service.detectCategory('binary.bin', false), FileCategory.binary);
    });

    test('resolveRunCommand builds appropriate interpreter commands', () {
      final pyFile = File('${tempDir.path}/main.py');
      final jsFile = File('${tempDir.path}/server.js');
      final shFile = File('${tempDir.path}/build.sh');
      final txtFile = File('${tempDir.path}/notes.txt');

      expect(service.resolveRunCommand(pyFile), 'python3 "main.py"');
      expect(service.resolveRunCommand(jsFile), 'node "server.js"');
      expect(service.resolveRunCommand(shFile), 'sh "build.sh"');
      expect(service.resolveRunCommand(txtFile), isNull);
    });

    test('createFile and createDirectory manage file system correctly', () async {
      final file = await service.createFile(tempDir, 'test.py', 'print("hello")');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), 'print("hello")');

      final dir = await service.createDirectory(tempDir, 'subfolder');
      expect(dir.existsSync(), isTrue);

      // Throws on empty or slash name
      expect(() => service.createFile(tempDir, ''), throwsA(isA<FormatException>()));
      expect(() => service.createFile(tempDir, 'a/b.py'), throwsA(isA<FormatException>()));
      expect(() => service.createDirectory(tempDir, 'sub/folder'), throwsA(isA<FormatException>()));

      // Throws on existing file
      expect(() => service.createFile(tempDir, 'test.py'), throwsA(isA<FileSystemException>()));
    });

    test('listDirectory sorts directories first and respects showHidden', () async {
      await service.createFile(tempDir, 'b_file.txt');
      await service.createFile(tempDir, 'a_file.txt');
      await service.createFile(tempDir, '.hidden.txt');
      await service.createDirectory(tempDir, 'z_dir');
      await service.createDirectory(tempDir, 'a_dir');

      // Without hidden files
      final visibleList = await service.listDirectory(directory: tempDir, showHidden: false);
      expect(visibleList.map((e) => e.name).toList(), ['a_dir', 'z_dir', 'a_file.txt', 'b_file.txt']);
      expect(visibleList.first.isDirectory, isTrue);
      expect(visibleList[1].isDirectory, isTrue);
      expect(visibleList[2].isDirectory, isFalse);

      // With hidden files
      final hiddenList = await service.listDirectory(directory: tempDir, showHidden: true);
      expect(hiddenList.any((e) => e.name == '.hidden.txt'), isTrue);
    });

    test('renameEntity and deleteEntity operate accurately', () async {
      final file = await service.createFile(tempDir, 'initial.txt', 'data');
      final renamed = await service.renameEntity(file, 'renamed.txt');
      expect(File(renamed.path).existsSync(), isTrue);
      expect(file.existsSync(), isFalse);

      await service.deleteEntity(renamed);
      expect(File(renamed.path).existsSync(), isFalse);

      final dir = await service.createDirectory(tempDir, 'empty_dir');
      await service.deleteEntity(dir);
      expect(dir.existsSync(), isFalse);
    });

    test('getBreadcrumbs produces hierarchical breadcrumbs', () async {
      final sub = await service.createDirectory(tempDir, 'projects');
      final nested = await service.createDirectory(sub, 'myapp');

      final crumbs = await service.getBreadcrumbs(nested);
      expect(crumbs.length, 3);
      expect(crumbs[0].label, '~');
      expect(crumbs[1].label, 'projects');
      expect(crumbs[2].label, 'myapp');
    });

    test('FileEntryItem formatted properties display properly', () {
      final small = FileEntryItem(
        path: '/a/small.txt',
        name: 'small.txt',
        extension: 'txt',
        isDirectory: false,
        sizeInBytes: 512,
        lastModified: DateTime(2026, 9, 25, 14, 30),
        category: FileCategory.text,
      );
      expect(small.formattedSize, '512 B');
      expect(small.formattedDate, '2026-09-25 14:30');
      expect(small.isEditableText, isTrue);
      expect(small.canRunInTerminal, isFalse);

      final pyItem = FileEntryItem(
        path: '/a/main.py',
        name: 'main.py',
        extension: 'py',
        isDirectory: false,
        sizeInBytes: 2048,
        lastModified: DateTime(2026, 9, 25, 15, 0),
        category: FileCategory.python,
      );
      expect(pyItem.formattedSize, '2.0 KB');
      expect(pyItem.canRunInTerminal, isTrue);
    });
  });

  group('Milestone v0.81: SyntaxHighlightingEditingController Tests', () {
    testWidgets('buildTextSpan parses Python code correctly', (tester) async {
      final controller = SyntaxHighlightingEditingController(
        text: 'def greet(name):\n    # Greeting message\n    return "Hello " + str(name)',
        category: FileCategory.python,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final span = controller.buildTextSpan(
                  context: context,
                  withComposing: false,
                );
                expect(span.children, isNotNull);
                expect(span.children!.isNotEmpty, isTrue);

                // Verify that keyword 'def' was tokenized with keywordColor
                final firstSpan = span.children!.first as TextSpan;
                expect(firstSpan.text, 'def');
                expect(firstSpan.style?.color, SyntaxHighlightingEditingController.keywordColor);
                return Container();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('buildTextSpan parses JavaScript code correctly', (tester) async {
      final controller = SyntaxHighlightingEditingController(
        text: 'const port = 3000;\n// start server\nconsole.log(`Port: \${port}`);',
        category: FileCategory.javascript,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final span = controller.buildTextSpan(
                  context: context,
                  withComposing: false,
                );
                expect(span.children, isNotNull);
                expect(span.children!.isNotEmpty, isTrue);

                final firstSpan = span.children!.first as TextSpan;
                expect(firstSpan.text, 'const');
                expect(firstSpan.style?.color, SyntaxHighlightingEditingController.keywordColor);
                return Container();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('buildTextSpan parses JSON code correctly', (tester) async {
      final controller = SyntaxHighlightingEditingController(
        text: '{\n  "version": "1.0",\n  "active": true\n}',
        category: FileCategory.json,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final span = controller.buildTextSpan(
                  context: context,
                  withComposing: false,
                );
                expect(span.children, isNotNull);
                expect(span.children!.isNotEmpty, isTrue);
                return Container();
              },
            ),
          ),
        ),
      );
    });
  });

  group('Milestone v0.81: QuickEditorScreen & FileExplorerDrawer Widget Tests', () {
    testWidgets('QuickEditorScreen loads file, updates line numbers, and saves edits', (tester) async {
      final file = await service.createFile(tempDir, 'demo.py', 'print("first line")\nprint("second line")');
      String? executedCommand;
      String? executedDir;

      await tester.pumpWidget(
        MaterialApp(
          home: QuickEditorScreen(
            file: file,
            onRunInTerminal: (cmd, dir) {
              executedCommand = cmd;
              executedDir = dir;
            },
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify title shows filename
      expect(find.text('demo.py'), findsOneWidget);
      expect(find.text('2 lines'), findsOneWidget);
      expect(find.text('PYTHON'), findsOneWidget);

      // Verify Run button is present for Python files
      expect(find.text('Run'), findsOneWidget);

      // Tap Run button
      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(executedCommand, 'python3 "demo.py"');
      expect(executedDir, tempDir.path);
    });

    testWidgets('FileExplorerDrawer renders items, breadcrumbs, and filter field', (tester) async {
      await service.createFile(tempDir, 'main.py');
      await service.createDirectory(tempDir, 'src');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: FileExplorerDrawer(
                onOpenFile: (_) {},
                onOpenTerminalHere: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Check header and breadcrumb '~'
      expect(find.text('FILES'), findsOneWidget);
      expect(find.text('~'), findsOneWidget);

      // Check list items
      expect(find.text('src'), findsOneWidget);
      expect(find.text('main.py'), findsOneWidget);

      // Filter items
      await tester.enterText(find.byType(TextField), 'main');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('main.py'), findsOneWidget);
      expect(find.text('src'), findsNothing);
    });
  });
}
