import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/npm_package_service.dart';
import 'package:termode/services/runtime_artifact_registry_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v0.67 npm Package Management Prototype', () {
    late Directory tempDir;
    late Directory projectDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_npm_test');
      projectDir = Directory('${tempDir.path}/workspace/my-node-app');
      await projectDir.create(recursive: true);

      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      TerminalSessionService().activeSession.preferredWorkingDirectory = projectDir.path;
      commandService = CommandService(VirtualFileSystem(), 'npm_test');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (call) async {
              switch (call.method) {
                case 'getStorageStatus':
                  return null;
                case 'realPtySend':
                case 'realPtySendRaw':
                  return true;
                case 'getDiagnostics':
                  return {'abi': 'arm64-v8a', 'pid': 9999};
                case 'getPaths':
                  return {
                    'home': '${tempDir.path}/files/home',
                    'usr': '${tempDir.path}/files/usr',
                    'bin': '${tempDir.path}/files/usr/bin',
                    'tmp': '${tempDir.path}/files/tmp',
                  };
              }
              return null;
            },
          );
    });

    tearDown(() async {
      RuntimeBinaryPackageService.npmExecutorForTesting = null;
      RuntimeBinaryPackageService.nodeExecutorForTesting = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            null,
          );
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('command catalog includes npm commands', () {
      expect(kTermodeCommands.contains('npm'), isTrue);
      expect(kTermodeCommands.contains('npx'), isTrue);
      expect(kTermodeCommands.contains('npm-doctor'), isTrue);
      expect(kTermodeCommands.contains('npm-status'), isTrue);
      expect(kTermodeCommands.contains('npm-info'), isTrue);
      expect(kTermodeCommands.contains('npm-init'), isTrue);
    });

    test('npm manifest template exists and is valid', () {
      final registry = RuntimeArtifactRegistryService();
      expect(registry.npmTemplateExists(), isTrue);

      final template = registry.readNpmTemplateManifest();
      expect(template, isNotNull);
      expect(template!['name'], equals('npm'));
      expect(template['termode_milestone'], equals('v0.67'));
      expect(template['kind'], equals('js-cli-package'));
      expect(template['command'], equals('npm'));
      expect(template['entrypoint'], equals('bin/npm-cli.js'));
      expect(template['dependencies'], contains('node'));
    });

    test('initPackageJson creates a standard package.json file', () async {
      final service = NpmPackageService();
      final result = await service.initPackageJson(
        workingDirectory: projectDir.path,
        name: 'test-project',
        version: '1.2.3',
        description: 'Test project description',
      );

      expect(result.success, isTrue);
      expect(result.metadata, isNotNull);
      expect(result.metadata!.name, equals('test-project'));
      expect(result.metadata!.version, equals('1.2.3'));
      expect(result.metadata!.description, equals('Test project description'));
      expect(result.metadata!.main, equals('index.js'));
      expect(result.metadata!.scripts.containsKey('test'), isTrue);
      expect(result.metadata!.scripts.containsKey('start'), isTrue);

      final file = File('${projectDir.path}/package.json');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync());
      expect(json['name'], equals('test-project'));
    });

    test('initPackageJson prevents accidental overwrite without flag', () async {
      final service = NpmPackageService();
      await service.initPackageJson(
        workingDirectory: projectDir.path,
        name: 'original',
      );

      final secondAttempt = await service.initPackageJson(
        workingDirectory: projectDir.path,
        name: 'new-name',
        overwrite: false,
      );
      expect(secondAttempt.success, isFalse);
      expect(secondAttempt.message, contains('already exists'));

      final overwriteAttempt = await service.initPackageJson(
        workingDirectory: projectDir.path,
        name: 'new-name',
        overwrite: true,
      );
      expect(overwriteAttempt.success, isTrue);
      expect(overwriteAttempt.metadata!.name, equals('new-name'));
    });

    test('readPackageJson and getScripts read fields correctly', () async {
      final service = NpmPackageService();
      final file = File('${projectDir.path}/package.json');
      file.writeAsStringSync(
        jsonEncode({
          'name': 'awesome-app',
          'version': '2.0.0',
          'scripts': {'build': 'esbuild src/index.ts', 'lint': 'eslint .'},
          'dependencies': {'chalk': '^4.1.2', 'express': '^4.18.2'},
          'devDependencies': {'typescript': '^5.0.0'},
        }),
      );

      final metadata = await service.readPackageJson(projectDir.path);
      expect(metadata, isNotNull);
      expect(metadata!.name, equals('awesome-app'));
      expect(metadata.version, equals('2.0.0'));
      expect(metadata.dependencies['express'], equals('^4.18.2'));
      expect(metadata.devDependencies['typescript'], equals('^5.0.0'));

      final scripts = await service.getScripts(projectDir.path);
      expect(scripts['build'], equals('esbuild src/index.ts'));
      expect(scripts['lint'], equals('eslint .'));
    });

    test('listDependencies inspects regular and scoped node_modules', () async {
      final service = NpmPackageService();
      final file = File('${projectDir.path}/package.json');
      file.writeAsStringSync(
        jsonEncode({
          'name': 'dep-checker',
          'version': '1.0.0',
          'dependencies': {
            'chalk': '^4.1.2',
            'express': '^4.18.2',
            '@types/node': '^20.0.0',
          },
        }),
      );

      // Create fake node_modules with chalk and @types/node
      final chalkDir = Directory('${projectDir.path}/node_modules/chalk');
      await chalkDir.create(recursive: true);
      final typesNodeDir = Directory(
        '${projectDir.path}/node_modules/@types/node',
      );
      await typesNodeDir.create(recursive: true);

      final report = await service.listDependencies(projectDir.path);
      expect(report.hasPackageJson, isTrue);
      expect(report.installedModules, contains('chalk'));
      expect(report.installedModules, contains('@types/node'));
      expect(report.missingModules, contains('express'));
      expect(report.missingModules.contains('chalk'), isFalse);

      final tree = service.formatDependencyTree(report);
      expect(tree, contains('dep-checker@1.0.0'));
      expect(tree, contains('chalk@^4.1.2 (installed)'));
      expect(tree, contains('@types/node@^20.0.0 (installed)'));
      expect(tree, contains('express@^4.18.2 (UNMET DEPENDENCY)'));
    });

    test('npm doctor returns structured diagnostics', () async {
      final service = NpmPackageService();
      final report = await service.doctor(workingDirectory: projectDir.path);

      expect(report.workingDirectory, equals(projectDir.path));
      expect(report.hasPackageJson, isFalse);
      expect(report.npmStatus, contains('PLANNED'));

      final formatted = report.formatText();
      expect(formatted, contains('=== npm Diagnostics (Doctor) ==='));
      expect(formatted, contains('Node.js Runtime:'));
      expect(formatted, contains('npm Engine:'));
      expect(formatted, contains('NPM_CONFIG_CACHE:'));
      expect(formatted, contains('NPM_CONFIG_PREFIX:'));
      expect(formatted, contains('Milestone: v0.73'));
    });

    test('CommandService runs npm bare and informational commands', () async {
      // Bare npm
      final bare = await commandService.execute('npm');
      expect(bare.output, contains('npm is not installed yet'));
      expect(bare.output, contains('Install authentic upstream npm 10.9.3'));

      // npm-doctor
      final doc = await commandService.execute('npm-doctor');
      expect(doc.output, contains('=== npm Diagnostics (Doctor) ==='));

      // npm-status
      final status = await commandService.execute('npm-status');
      expect(status.output, contains('=== npm Status ==='));
      expect(status.output, contains('Milestone: v0.73'));

      // npm-info
      final info = await commandService.execute('npm-info');
      expect(info.output, contains('=== Runtime Package: npm ==='));
      expect(info.output, contains('Next step: npm-doctor'));
    });

    test('CommandService npm init and npm ls work in workspace', () async {
      final init = await commandService.execute('npm init -y');
      expect(init.output, contains('Wrote to'));
      expect(init.output, contains('package.json'));

      final ls = await commandService.execute('npm ls');
      expect(ls.output, contains('my-node-app@1.0.0'));

      final packageJsonFile = File('${projectDir.path}/package.json');
      expect(packageJsonFile.existsSync(), isTrue);
      expect(packageJsonFile.readAsStringSync(), contains('"name": "my-node-app"'));
    });

    test('CommandService runs npm run scripts', () async {
      final service = NpmPackageService();
      await service.initPackageJson(
        workingDirectory: projectDir.path,
        scripts: {
          'hello': 'echo "hello from npm script"',
          'build': 'echo "building app"',
        },
      );

      final runList = await commandService.execute('npm run');
      expect(runList.output, contains('hello: echo "hello from npm script"'));
      expect(runList.output, contains('build: echo "building app"'));

      final runHello = await commandService.execute('npm run hello');
      expect(runHello.output, contains('hello from npm script'));

      final missing = await commandService.execute('npm run nonexisting');
      expect(missing.output, contains('missing script: "nonexisting"'));
    });

    test('CommandService executes npm with test hook', () async {
      RuntimeBinaryPackageService.npmExecutorForTesting = (args, {workingDirectory}) async {
        if (args.contains('--version')) {
          return NativeCommandResult(
            exitCode: 0,
            stdout: '10.2.4\n',
            stderr: '',
          );
        }
        return NativeCommandResult(
          exitCode: 0,
          stdout: 'executed npm with ${args.join(" ")} in $workingDirectory',
          stderr: '',
        );
      };

      final versionResult = await commandService.execute('npm --version');
      expect(versionResult.output, equals('10.2.4'));

      final runResult = await commandService.execute('npm install lodash');
      expect(runResult.output, contains('executed npm with install lodash'));
    });

    test('CommandService npx outputs guidance when not installed', () async {
      final npxBare = await commandService.execute('npx');
      expect(npxBare.output, contains('npx is not installed yet'));
      expect(npxBare.output, contains('runtime-pkg install npm'));

      final npxDeferred = await commandService.execute('npx prettier');
      expect(npxDeferred.output, contains('npx is not installed yet'));
    });

    test('CommandService executes npx with test hook', () async {
      RuntimeBinaryPackageService.npmExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          exitCode: 0,
          stdout: 'executed npx with ${args.join(" ")}',
          stderr: '',
        );
      };

      final npxRun = await commandService.execute('npx prettier --write .');
      expect(npxRun.output, contains('executed npx with prettier --write .'));
    });

    test('RuntimeArtifactRegistryService validates npm manifest and artifact status', () async {
      final registry = RuntimeArtifactRegistryService();
      final status = await registry.npmArtifactStatus();
      expect(status.status, equals('AVAILABLE'));
      expect(status.installable, isTrue);
      expect(status.version, equals('10.9.3'));
      expect(status.archiveBytes, equals(2890824));
    });

    test('RuntimeBinaryPackageService installs npm when Node is available', () async {
      final pkg = RuntimeBinaryPackageService();

      // When node is NOT installed:
      final failResult = await pkg.install('npm');
      expect(failResult.isError, isTrue);
      expect(failResult.output, contains('Node.js runtime engine must be installed before npm'));

      // Mock node executor active
      RuntimeBinaryPackageService.nodeExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(stdout: 'v24.18.0\n', stderr: '', exitCode: 0);
      };
      RuntimeBinaryPackageService.npmExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(stdout: '10.9.3\n', stderr: '', exitCode: 0);
      };

      final installResult = await pkg.install('npm');
      expect(installResult.isError, isFalse);
      expect(installResult.output, contains('Installed runtime package: npm'));
      expect(installResult.output, contains('10.9.3'));
      expect(await pkg.npmInstalled(), isTrue);
    });

    test('NpmPackageService runScript executes package scripts or fails with clear error', () async {
      final npmService = NpmPackageService();
      
      // Before package.json exists
      final noPkg = await npmService.runScript(
        workingDirectory: projectDir.path,
        scriptName: 'start',
      );
      expect(noPkg.success, isFalse);
      expect(noPkg.output, contains('package.json'));

      // Create package.json
      await npmService.initPackageJson(
        workingDirectory: projectDir.path,
        scripts: {'build': 'echo building app', 'test': 'echo tests pass'},
      );

      // Missing script
      final missing = await npmService.runScript(
        workingDirectory: projectDir.path,
        scriptName: 'deploy',
      );
      expect(missing.success, isFalse);
      expect(missing.output, contains('Missing script: "deploy"'));
      expect(missing.output, contains('npm run build'));

      // Valid script with mock executor
      RuntimeBinaryPackageService.npmExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'running script: ${args.join(" ")}',
          stderr: '',
          exitCode: 0,
        );
      };

      final success = await npmService.runScript(
        workingDirectory: projectDir.path,
        scriptName: 'build',
      );
      expect(success.success, isTrue);
      expect(success.output, contains('running script: run build'));
    });

    test('NpmPackageService cache management methods work properly', () async {
      final npmService = NpmPackageService();
      final homeDir = tempDir.path;

      // cacheStatus when directory does not exist
      final initialStatus = await npmService.cacheStatus(homeDir);
      expect(initialStatus['exists'], isFalse);
      expect(initialStatus['bytes'], equals(0));

      // Create dummy cache file
      final cacheDir = Directory('$homeDir/.npm');
      await cacheDir.create(recursive: true);
      final dummy = File('${cacheDir.path}/test.tar');
      await dummy.writeAsBytes(List.filled(2048, 42));

      final activeStatus = await npmService.cacheStatus(homeDir);
      expect(activeStatus['exists'], isTrue);
      expect(activeStatus['fileCount'], equals(1));
      expect(activeStatus['bytes'], equals(2048));

      // cache clean & verify with test executor
      RuntimeBinaryPackageService.npmExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'cache action: ${args.join(" ")}',
          stderr: '',
          exitCode: 0,
        );
      };

      final cleanRes = await npmService.cacheClean(force: true);
      expect(cleanRes.success, isTrue);
      expect(cleanRes.output, contains('cache action: cache clean --force'));

      final verifyRes = await npmService.cacheVerify();
      expect(verifyRes.success, isTrue);
      expect(verifyRes.output, contains('cache action: cache verify'));
    });

    test('CommandService runs npm-run, npm-cache, and npm-pkg commands', () async {
      final npmService = NpmPackageService();
      await npmService.initPackageJson(
        workingDirectory: projectDir.path,
        scripts: {'test': 'echo test ok', 'start': 'echo start ok'},
      );

      RuntimeBinaryPackageService.npmExecutorForTesting = (args, {workingDirectory}) async {
        return NativeCommandResult(
          stdout: 'npm executed: ${args.join(" ")}',
          stderr: '',
          exitCode: 0,
        );
      };

      // npm-run list scripts
      final runList = await commandService.execute('npm-run');
      expect(runList.output, contains('Scripts available in package.json:'));
      expect(runList.output, contains('npm run test'));
      expect(runList.output, contains('npm run start'));

      // npm-run test
      final runTest = await commandService.execute('npm-run test');
      expect(runTest.output, contains('npm executed: run test'));

      // npm-cache status
      final cacheCmd = await commandService.execute('npm-cache');
      expect(cacheCmd.output, contains('=== npm Cache Status ==='));

      // npm-cache clean
      final cacheClean = await commandService.execute('npm-cache clean');
      expect(cacheClean.output, contains('npm executed: cache clean --force'));

      // npm-pkg list
      final pkgList = await commandService.execute('npm-pkg list');
      expect(pkgList.output, contains('my-node-app@1.0.0'));

      // npm-pkg add
      final pkgAdd = await commandService.execute('npm-pkg add express');
      expect(pkgAdd.output, contains('npm executed: install express'));

      // npm-pkg remove
      final pkgRemove = await commandService.execute('npm-pkg remove express');
      expect(pkgRemove.output, contains('npm executed: uninstall express'));
    });
  });
}
