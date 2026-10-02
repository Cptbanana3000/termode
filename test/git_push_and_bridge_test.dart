import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/git_credential_service.dart';
import 'package:termode/services/git_remote_transport_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/termode_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory repoDir;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = Directory.systemTemp.createTempSync('termode_git_v84_test_');
    repoDir = Directory('${tempDir.path}/repo')..createSync(recursive: true);
    RuntimeBootstrapService().overrideBaseDir = tempDir;
    GitCredentialService().overrideHomeDir = tempDir.path;

    // Create mock .git directory structure
    final gitDir = Directory('${repoDir.path}/.git')..createSync(recursive: true);
    Directory('${gitDir.path}/refs/heads').createSync(recursive: true);
    Directory('${gitDir.path}/refs/remotes/origin').createSync(recursive: true);
    Directory('${gitDir.path}/objects/pack').createSync(recursive: true);

    File('${gitDir.path}/HEAD').writeAsStringSync('ref: refs/heads/main\n');
    File('${gitDir.path}/refs/heads/main')
        .writeAsStringSync('1111111111111111111111111111111111111111\n');
    File('${gitDir.path}/config').writeAsStringSync(
      '[core]\n\trepositoryformatversion = 0\n\tbare = false\n'
      '[remote "origin"]\n\turl = https://github.com/example/repo.git\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n'
      '[branch "main"]\n\tremote = origin\n\tmerge = refs/heads/main\n',
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    RuntimeBootstrapService().overrideBaseDir = null;
    GitCredentialService().overrideHomeDir = null;
    GitRemoteTransportService.httpClientFactoryForTesting = null;
    GitRemoteTransportService.gitExecutorForTesting = null;
    GitRemoteTransportService.gitExecutorWithInputForTesting = null;
    RuntimeBinaryPackageService.gitExecutorForTesting = null;
    RuntimeBinaryPackageService.gitExecutorWithInputForTesting = null;
  });

  group('Milestone v0.84: TermodeGitService Structured Bridge Tests', () {
    test('getStatus parses porcelain status accurately', () async {
      final gitService = TermodeGitService();

      // Hook git executor to return simulated status porcelain output
      RuntimeBinaryPackageService.gitExecutorForTesting = (args, {workingDirectory}) async {
        if (args.contains('--is-inside-work-tree')) {
          return NativeCommandResult(stdout: 'true\n', stderr: '', exitCode: 0);
        }
        if (args.contains('--show-toplevel')) {
          return NativeCommandResult(stdout: '${repoDir.path}\n', stderr: '', exitCode: 0);
        }
        if (args.contains('--git-dir')) {
          return NativeCommandResult(stdout: '${repoDir.path}/.git\n', stderr: '', exitCode: 0);
        }
        if (args.contains('status')) {
          const statusOutput =
              '## main...origin/main [ahead 2, behind 1]\n'
              'M  lib/main.dart\n'
              ' M README.md\n'
              '?? new_file.txt\n'
              'D  deleted.txt\n'
              'R  old.dart -> renamed.dart\n';
          return NativeCommandResult(stdout: statusOutput, stderr: '', exitCode: 0);
        }
        if (args.contains('branch')) {
          return NativeCommandResult(stdout: '* main\n  feature-branch\n', stderr: '', exitCode: 0);
        }
        return NativeCommandResult(stdout: '', stderr: '', exitCode: 0);
      };

      final status = await gitService.getStatus(workingDirectory: repoDir.path);

      expect(status.isRepo, isTrue);
      expect(status.branchName, equals('main'));
      expect(status.upstream, equals('origin/main'));
      expect(status.ahead, equals(2));
      expect(status.behind, equals(1));
      expect(status.isClean, isFalse);
      expect(status.files.length, equals(5));

      // Check lib/main.dart (staged modified)
      final mainEntry = status.files.firstWhere((f) => f.relativePath == 'lib/main.dart');
      expect(mainEntry.kind, equals(TermodeGitFileKind.modified));
      expect(mainEntry.hasStagedChanges, isTrue);
      expect(mainEntry.hasUnstagedChanges, isFalse);
      expect(mainEntry.canStage, isFalse);
      expect(mainEntry.canUnstage, isTrue);

      // Check README.md (unstaged modified)
      final readmeEntry = status.files.firstWhere((f) => f.relativePath == 'README.md');
      expect(readmeEntry.kind, equals(TermodeGitFileKind.modified));
      expect(readmeEntry.hasStagedChanges, isFalse);
      expect(readmeEntry.hasUnstagedChanges, isTrue);
      expect(readmeEntry.canStage, isTrue);

      // Check new_file.txt (untracked)
      final untrackedEntry = status.files.firstWhere((f) => f.relativePath == 'new_file.txt');
      expect(untrackedEntry.kind, equals(TermodeGitFileKind.untracked));
      expect(untrackedEntry.canStage, isTrue);

      // Check branches
      expect(status.branches.length, equals(2));
      expect(status.branches.first.name, equals('main'));
      expect(status.branches.first.isCurrent, isTrue);
      expect(status.branches.last.name, equals('feature-branch'));
      expect(status.branches.last.isCurrent, isFalse);
    });

    test('getDiff retrieves unified diff patch and file text', () async {
      final gitService = TermodeGitService();

      File('${repoDir.path}/hello.txt').writeAsStringSync('line 1\nline 2 modified\n');

      RuntimeBinaryPackageService.gitExecutorForTesting = (args, {workingDirectory}) async {
        if (args.contains('--show-toplevel')) {
          return NativeCommandResult(stdout: '${repoDir.path}\n', stderr: '', exitCode: 0);
        }
        if (args.contains('show')) {
          return NativeCommandResult(stdout: 'line 1\nline 2\n', stderr: '', exitCode: 0);
        }
        if (args.contains('diff')) {
          return NativeCommandResult(
            stdout: '--- a/hello.txt\n+++ b/hello.txt\n@@ -1,2 +1,2 @@\n line 1\n-line 2\n+line 2 modified\n',
            stderr: '',
            exitCode: 0,
          );
        }
        return NativeCommandResult(stdout: '', stderr: '', exitCode: 0);
      };

      final diff = await gitService.getDiff(
        relativePath: 'hello.txt',
        workingDirectory: repoDir.path,
      );

      expect(diff.isSupported, isTrue);
      expect(diff.isBinary, isFalse);
      expect(diff.relativePath, equals('hello.txt'));
      expect(diff.oldText, equals('line 1\nline 2\n'));
      expect(diff.newText, equals('line 1\nline 2 modified\n'));
      expect(diff.patch, contains('+line 2 modified'));
      expect(diff.hasTextPair, isTrue);
    });

    test('stage, unstage, commit, and checkout invoke native plumbing', () async {
      final gitService = TermodeGitService();
      final executed = <List<String>>[];

      RuntimeBinaryPackageService.gitExecutorForTesting = (args, {workingDirectory}) async {
        executed.add(List.from(args));
        return NativeCommandResult(stdout: 'ok\n', stderr: '', exitCode: 0);
      };

      await gitService.stage(['README.md'], workingDirectory: repoDir.path);
      expect(executed.last, equals(['add', '-A', '--', 'README.md']));

      await gitService.stage([], workingDirectory: repoDir.path);
      expect(executed.last, equals(['add', '-A']));

      await gitService.unstage(['README.md'], workingDirectory: repoDir.path);
      expect(executed.last, equals(['restore', '--staged', '--', 'README.md']));

      await gitService.commit('feat: milestone v0.84', workingDirectory: repoDir.path);
      expect(executed.last, equals(['commit', '-m', 'feat: milestone v0.84']));

      await gitService.checkout('feature-new', create: true, workingDirectory: repoDir.path);
      expect(executed.last, equals(['checkout', '-b', 'feature-new']));
    });
  });

  group('Milestone v0.84: Authentic Smart-HTTP Git Push Protocol Tests', () {
    test('reports Everything up-to-date when local and remote SHAs match', () async {
      final transport = GitRemoteTransportService();

      // Configure mock HTTP client for discoverRefs
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        if (request.uri.path.endsWith('/info/refs')) {
          request.response.headers.contentType =
              ContentType('application', 'x-git-receive-pack-advertisement');
          final refAdv =
              '001f# service=git-receive-pack\n'
              '0000'
              '${GitRemoteTransportService.encodePktLine("1111111111111111111111111111111111111111 refs/heads/main\x00report-status\n")}'
              '0000';
          request.response.write(refAdv);
          await request.response.close();
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      });

      // Update config to use mock server URL
      final mockUrl = 'http://localhost:${server.port}/repo.git';
      await File('${repoDir.path}/.git/config').writeAsString(
        '[remote "origin"]\n\turl = $mockUrl\n',
      );

      final result = await transport.push(
        'origin',
        branch: 'main',
        workingDirectory: repoDir.path,
      );

      await server.close();

      expect(result.success, isTrue);
      expect(result.output, contains('Everything up-to-date'));
    });

    test('generates packfile and transmits git-receive-pack Smart-HTTP request successfully', () async {
      final transport = GitRemoteTransportService();
      final localSha = '2222222222222222222222222222222222222222';
      final oldSha = '1111111111111111111111111111111111111111';

      // Update local ref to new commit
      await File('${repoDir.path}/.git/refs/heads/main').writeAsString('$localSha\n');

      var receivedPostRequest = false;
      List<int> postBody = [];

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        if (request.uri.path.endsWith('/info/refs')) {
          request.response.headers.contentType =
              ContentType('application', 'x-git-receive-pack-advertisement');
          final refAdv =
              '001f# service=git-receive-pack\n'
              '0000'
              '${GitRemoteTransportService.encodePktLine("$oldSha refs/heads/main\x00report-status\n")}'
              '0000';
          request.response.write(refAdv);
          await request.response.close();
        } else if (request.uri.path.endsWith('/git-receive-pack')) {
          receivedPostRequest = true;
          postBody = await request.fold<List<int>>([], (acc, c) => acc..addAll(c));

          request.response.headers.contentType =
              ContentType('application', 'x-git-receive-pack-result');
          final pushResult =
              '${GitRemoteTransportService.encodePktLine("unpack ok\n")}'
              '${GitRemoteTransportService.encodePktLine("ok refs/heads/main\n")}'
              '0000';
          request.response.write(pushResult);
          await request.response.close();
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      });

      final mockUrl = 'http://localhost:${server.port}/repo.git';
      await File('${repoDir.path}/.git/config').writeAsString(
        '[remote "origin"]\n\turl = $mockUrl\n',
      );

      // Mock git rev-list and pack-objects
      GitRemoteTransportService.gitExecutorWithInputForTesting = (args, {workingDirectory, stdin, stdinBytes, bool? binaryOutput}) async {
        if (args.contains('rev-parse')) {
          return NativeCommandResult(stdout: '$localSha\n', stderr: '', exitCode: 0);
        }
        if (args.contains('rev-list')) {
          return NativeCommandResult(
            stdout: '$localSha\n3333333333333333333333333333333333333333 README.md\n',
            stderr: '',
            exitCode: 0,
          );
        }
        if (args.contains('pack-objects')) {
          final packHeader = Uint8List.fromList([
            0x50, 0x41, 0x43, 0x4b, // 'PACK'
            0x00, 0x00, 0x00, 0x02, // version 2
            0x00, 0x00, 0x00, 0x02, // 2 objects
            0x12, 0x34, 0x56, 0x78,
          ]);
          return NativeCommandResult(stdout: '', stderr: '', exitCode: 0, stdoutBytes: packHeader);
        }
        return NativeCommandResult(stdout: '', stderr: '', exitCode: 0);
      };

      final progress = <String>[];
      final result = await transport.push(
        'origin',
        branch: 'main',
        workingDirectory: repoDir.path,
        onProgress: (p) => progress.add(p),
      );

      await server.close();

      expect(result.success, isTrue);
      expect(result.output, contains('1111111..2222222'));
      expect(result.output, contains('Remote status: unpack ok.'));
      expect(receivedPostRequest, isTrue);

      final bodyStr = utf8.decode(postBody, allowMalformed: true);
      expect(bodyStr, contains('$oldSha $localSha refs/heads/main'));
      expect(bodyStr, contains('report-status'));

      final trackingRef = File('${repoDir.path}/.git/refs/remotes/origin/main');
      expect(await trackingRef.exists(), isTrue);
      expect((await trackingRef.readAsString()).trim(), equals(localSha));
    });

    test('handles remote push rejection (non-fast-forward) with descriptive failure', () async {
      final transport = GitRemoteTransportService();
      final localSha = '2222222222222222222222222222222222222222';
      final oldSha = '1111111111111111111111111111111111111111';

      await File('${repoDir.path}/.git/refs/heads/main').writeAsString('$localSha\n');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        if (request.uri.path.endsWith('/info/refs')) {
          request.response.headers.contentType =
              ContentType('application', 'x-git-receive-pack-advertisement');
          final refAdv =
              '001f# service=git-receive-pack\n'
              '0000'
              '${GitRemoteTransportService.encodePktLine("$oldSha refs/heads/main\x00report-status\n")}'
              '0000';
          request.response.write(refAdv);
          await request.response.close();
        } else if (request.uri.path.endsWith('/git-receive-pack')) {
          request.response.headers.contentType =
              ContentType('application', 'x-git-receive-pack-result');
          final pushReject =
              '${GitRemoteTransportService.encodePktLine("unpack ok\n")}'
              '${GitRemoteTransportService.encodePktLine("ng refs/heads/main non-fast-forward\n")}'
              '0000';
          request.response.write(pushReject);
          await request.response.close();
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      });

      final mockUrl = 'http://localhost:${server.port}/repo.git';
      await File('${repoDir.path}/.git/config').writeAsString(
        '[remote "origin"]\n\turl = $mockUrl\n',
      );

      GitRemoteTransportService.gitExecutorWithInputForTesting = (args, {workingDirectory, stdin, stdinBytes, bool? binaryOutput}) async {
        if (args.contains('rev-parse')) return NativeCommandResult(stdout: '$localSha\n', stderr: '', exitCode: 0);
        if (args.contains('rev-list')) return NativeCommandResult(stdout: '$localSha\n', stderr: '', exitCode: 0);
        if (args.contains('pack-objects')) return NativeCommandResult(stdout: '', stderr: '', exitCode: 0, stdoutBytes: Uint8List(12));
        return NativeCommandResult(stdout: '', stderr: '', exitCode: 0);
      };

      final result = await transport.push(
        'origin',
        branch: 'main',
        workingDirectory: repoDir.path,
      );

      await server.close();

      expect(result.success, isFalse);
      expect(result.message, contains('fatal: Remote rejected push'));
      expect(result.message, contains('non-fast-forward'));
    });
  });

  group('Milestone v0.84: TermodeEngine Facade Integration Tests', () {
    test('TermodeEngine exposes git service and structured helpers directly', () async {
      final engine = TermodeEngine.instance;

      expect(engine.git, isA<TermodeGitService>());
      expect(engine.gitRemote, isA<GitRemoteTransportService>());

      RuntimeBinaryPackageService.gitExecutorForTesting = (args, {workingDirectory}) async {
        if (args.contains('--is-inside-work-tree')) {
          return NativeCommandResult(stdout: 'true\n', stderr: '', exitCode: 0);
        }
        if (args.contains('--show-toplevel')) {
          return NativeCommandResult(stdout: '${repoDir.path}\n', stderr: '', exitCode: 0);
        }
        if (args.contains('status')) {
          return NativeCommandResult(stdout: '## main\n', stderr: '', exitCode: 0);
        }
        if (args.contains('branch')) {
          return NativeCommandResult(stdout: '* main\n', stderr: '', exitCode: 0);
        }
        return NativeCommandResult(stdout: '', stderr: '', exitCode: 0);
      };

      final status = await engine.getGitStatus(workingDirectory: repoDir.path);
      expect(status.isRepo, isTrue);
      expect(status.branchName, equals('main'));

      final branches = await engine.getGitBranches(workingDirectory: repoDir.path);
      expect(branches.length, equals(1));
      expect(branches.first.name, equals('main'));
      expect(branches.first.isCurrent, isTrue);
    });
  });
}
