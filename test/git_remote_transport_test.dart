import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/git_credential_service.dart';
import 'package:termode/services/git_remote_transport_service.dart';
import 'package:termode/services/git_ssh_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/virtual_filesystem.dart';
import 'package:termode/services/terminal_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('termode_git_test_');
    RuntimeBootstrapService().overrideBaseDir = tempDir;
    GitCredentialService().overrideHomeDir = tempDir.path;
    GitSshService().overrideHomeDir = tempDir.path;
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    RuntimeBootstrapService().overrideBaseDir = null;
    GitCredentialService().overrideHomeDir = null;
    GitSshService().overrideHomeDir = null;
  });

  group('Milestone v0.83: Git Credential Management Tests', () {
    test('stores, parses, and erases ~/.git-credentials correctly', () async {
      final credService = GitCredentialService();

      // Initially empty
      final initial = await credService.listCredentials();
      expect(initial, isEmpty);

      // Store GitHub credential
      await credService.store(
        host: 'https://github.com',
        username: 'octocat',
        token: 'ghp_secrettoken1234567890abcdef',
      );

      final creds = await credService.listCredentials();
      expect(creds.length, equals(1));
      expect(creds.first.host, equals('github.com'));
      expect(creds.first.username, equals('octocat'));
      expect(creds.first.token, equals('ghp_secrettoken1234567890abcdef'));
      expect(creds.first.maskedToken, equals('ghp_...cdef'));

      // Retrieve by host
      final fetched = await credService.get(host: 'github.com');
      expect(fetched, isNotNull);
      expect(fetched!.username, equals('octocat'));

      // Format for .git-credentials file
      final file = File('${tempDir.path}/.git-credentials');
      expect(await file.exists(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('https://octocat:ghp_secrettoken1234567890abcdef@github.com'));

      // Erase
      final erased = await credService.erase(host: 'github.com');
      expect(erased, isTrue);
      final remaining = await credService.listCredentials();
      expect(remaining, isEmpty);
    });
  });

  group('Milestone v0.83: Cryptographic Ed25519 SSH Keypair Tests', () {
    test('generates valid OpenSSH format and SHA256 fingerprint', () async {
      final sshService = GitSshService();

      expect(await sshService.hasKeyPair(), isFalse);

      final pair = await sshService.generateKeyPair(
        comment: 'termode-test@android',
        overwrite: true,
      );

      expect(pair.keyType, equals('ED25519'));
      expect(pair.comment, equals('termode-test@android'));
      expect(pair.publicKey, startsWith('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5'));
      expect(pair.publicKey, endsWith('termode-test@android'));
      expect(pair.fingerprint, startsWith('SHA256:'));
      expect(await sshService.hasKeyPair(), isTrue);

      final privFile = File(pair.privateKeyPath);
      expect(await privFile.exists(), isTrue);
      final privContent = await privFile.readAsString();
      expect(privContent, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));
      expect(privContent.trim(), endsWith('-----END OPENSSH PRIVATE KEY-----'));

      // Public key query
      final pubKey = await sshService.getPublicKey();
      expect(pubKey, equals(pair.publicKey));

      final fp = await sshService.getFingerprint();
      expect(fp, equals(pair.fingerprint));

      // Deletion
      final deleted = await sshService.deleteKeyPair();
      expect(deleted, isTrue);
      expect(await sshService.hasKeyPair(), isFalse);
    });
  });

  group('Milestone v0.83: Smart-HTTP Wire Protocol Demux & Helpers Tests', () {
    test('encodes and decodes PKT-LINE correctly', () {
      expect(GitRemoteTransportService.encodePktLine(''), equals('0000'));
      expect(GitRemoteTransportService.encodePktLine(null), equals('0000'));

      const sample = 'want 1234567890123456789012345678901234567890\n';
      final encoded = GitRemoteTransportService.encodePktLine(sample);
      expect(encoded.substring(0, 4), equals((sample.length + 4).toRadixString(16).padLeft(4, '0')));
      expect(encoded.substring(4), equals(sample));

      final decoded = GitRemoteTransportService.decodePktLines(utf8.encode(encoded));
      expect(decoded.length, equals(1));
      expect(decoded.first, equals(sample));
    });

    test('derives repository names cleanly from various URLs', () {
      final transport = GitRemoteTransportService();
      expect(transport.deriveRepoName('https://github.com/octocat/Hello-World.git'), equals('Hello-World'));
      expect(transport.deriveRepoName('https://github.com/user/my-repo'), equals('my-repo'));
      expect(transport.deriveRepoName('https://gitlab.com/group/subgroup/project.git/'), equals('project'));
    });

    test('demultiplexes side-band-64k binary pack data and progress messages', () {
      // Band 1: packfile data [0x01, ...]
      // Band 2: progress message [0x02, ...]
      final transport = GitRemoteTransportService();
      final buf = BytesBuilder();

      // Progress packet: len = 4 + 1 + 10 = 15 = 0x000f
      final progMsg = 'Counting: 5';
      final progPacket = '0010\x02$progMsg'; // 4 + 1 + 11 = 16 = 0x0010
      buf.add(utf8.encode(progPacket));

      // Pack data packet: len = 4 + 1 + 4 = 9 = 0x0009
      final packHeader = [0x50, 0x41, 0x43, 0x4b]; // 'PACK'
      final packLenHex = (4 + 1 + packHeader.length).toRadixString(16).padLeft(4, '0');
      buf.add(utf8.encode(packLenHex));
      buf.addByte(1); // Band 1
      buf.add(packHeader);

      final progressOutput = <String>[];
      final extractedPack = transport.demultiplexSideBandForTesting(
        buf.toBytes(),
        onProgress: (p) => progressOutput.add(p),
      );

      expect(extractedPack, equals(packHeader));
      expect(progressOutput.any((p) => p.contains('Counting: 5')), isTrue);
    });
  });

  group('Milestone v0.83: Termode Command Service Integration Tests', () {
    test('executes termode-git credentials and doctor commands', () async {
      final session = TerminalSessionService().activeSession;
      final vfs = VirtualFileSystem();
      final cmd = CommandService(vfs, session.id);

      final docRes = await cmd.execute('termode-git doctor');
      expect(docRes.output, contains('=== Termode Git Doctor ==='));
      expect(docRes.output, contains('Smart-HTTP Remote Engine: READY'));

      final credsRes = await cmd.execute('termode-git credentials');
      expect(credsRes.output, contains('=== Termode Git Credentials ==='));

      final storeRes = await cmd.execute('termode-git credential-store https://gitlab.com gitlab-user glpat_12345');
      expect(storeRes.output, contains('Stored credential for https://gitlab.com'));

      final credsAfter = await cmd.execute('termode-git credentials');
      expect(credsAfter.output, contains('gitlab.com'));
      expect(credsAfter.output, contains('gitlab-user'));
    });

    test('executes ssh-keygen generating Ed25519 keypair and reading fingerprint', () async {
      final session = TerminalSessionService().activeSession;
      final vfs = VirtualFileSystem();
      final cmd = CommandService(vfs, session.id);

      final genRes = await cmd.execute('ssh-keygen -t ed25519 -C "test@termode.dev"');
      expect(genRes.output, contains('Generating public/private ed25519 key pair.'));
      expect(genRes.output, contains('SHA256:'));
      expect(genRes.output, contains('ED25519 256'));

      final fpRes = await cmd.execute('ssh-keygen -l');
      expect(fpRes.output, contains('256 SHA256:'));
      expect(fpRes.output, contains('ED25519'));

      final pubRes = await cmd.execute('ssh-keygen -y');
      expect(pubRes.output, startsWith('ssh-ed25519 '));
      expect(pubRes.output, contains('test@termode.dev'));
    });
  });
}
