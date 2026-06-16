import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  group('VirtualFileSystem Tests', () {
    late VirtualFileSystem vfs;

    setUp(() {
      vfs = VirtualFileSystem();
    });

    test('Initial directory structure', () {
      expect(vfs.getAbsolutePath(), '/home');
      expect(vfs.getPromptPath(), '~');
      
      // Root folder structure validation
      final rootContents = vfs.ls('/');
      expect(rootContents, contains('home/'));
      expect(rootContents, contains('usr/'));
      expect(rootContents, contains('tmp/'));
    });

    test('Create directory (mkdir) and list (ls)', () {
      final mkdirErr = vfs.mkdir('projects');
      expect(mkdirErr, isNull);
      
      final lsResult = vfs.ls();
      expect(lsResult, contains('projects/'));
    });

    test('Navigate directories (cd)', () {
      vfs.mkdir('projects');
      final cdErr = vfs.cd('projects');
      expect(cdErr, isNull);
      expect(vfs.getAbsolutePath(), '/home/projects');
      expect(vfs.getPromptPath(), '~/projects');
      
      vfs.cd('..');
      expect(vfs.getAbsolutePath(), '/home');
      expect(vfs.getPromptPath(), '~');
      
      vfs.cd('/usr');
      expect(vfs.getAbsolutePath(), '/usr');
      expect(vfs.getPromptPath(), '/usr');
    });

    test('Create file (touch) and read (cat)', () {
      vfs.touch('notes.txt', 'Hello virtual filesystem');
      final content = vfs.cat('notes.txt');
      expect(content, 'Hello virtual filesystem');
    });

    test('Delete files and directories (rm)', () {
      vfs.touch('file.txt', 'test');
      expect(vfs.ls(), contains('file.txt'));
      
      vfs.rm('file.txt');
      expect(vfs.ls(), isNot(contains('file.txt')));
      
      vfs.mkdir('folder');
      // rm directory without -r should fail
      final err = vfs.rm('folder', recursive: false);
      expect(err, isNotNull);
      
      // rm directory with -r should succeed
      final success = vfs.rm('folder', recursive: true);
      expect(success, isNull);
    });

    test('Copy (cp) and Move (mv) operations', () {
      vfs.touch('file.txt', 'source data');
      
      // Copy file
      final cpErr = vfs.cp('file.txt', 'copy.txt');
      expect(cpErr, isNull);
      expect(vfs.cat('copy.txt'), 'source data');
      
      // Move/Rename file
      final mvErr = vfs.mv('copy.txt', 'moved.txt');
      expect(mvErr, isNull);
      expect(vfs.cat('moved.txt'), 'source data');
      expect(vfs.ls(), isNot(contains('copy.txt')));
    });
  });
}
