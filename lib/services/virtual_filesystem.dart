class VNode {
  String name;
  final bool isDirectory;
  String content;
  final Map<String, VNode> children;
  VNode? parent;

  VNode({
    required this.name,
    required this.isDirectory,
    this.content = '',
    Map<String, VNode>? children,
    this.parent,
  }) : children = children ?? {};

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'isDirectory': isDirectory,
      'content': content,
      'children': children.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  factory VNode.fromJson(Map<String, dynamic> json, [VNode? parent]) {
    final node = VNode(
      name: json['name'] as String,
      isDirectory: json['isDirectory'] as bool,
      content: json['content'] as String? ?? '',
      parent: parent,
    );
    if (json['children'] != null) {
      final childrenMap = json['children'] as Map<String, dynamic>;
      childrenMap.forEach((key, val) {
        node.children[key] = VNode.fromJson(val as Map<String, dynamic>, node);
      });
    }
    return node;
  }
}

class VirtualFileSystem {
  late final VNode _root;
  late VNode _cwd;

  VirtualFileSystem() {
    _root = VNode(name: '', isDirectory: true);

    // Initial folder structure
    final home = VNode(name: 'home', isDirectory: true, parent: _root);
    final usr = VNode(name: 'usr', isDirectory: true, parent: _root);
    final tmp = VNode(name: 'tmp', isDirectory: true, parent: _root);

    _root.children['home'] = home;
    _root.children['usr'] = usr;
    _root.children['tmp'] = tmp;

    // Start at /home
    _cwd = home;
  }

  VirtualFileSystem.fromJson(Map<String, dynamic> json) {
    _root = VNode.fromJson(json, null);
    _cwd = _root;
  }

  Map<String, dynamic> toJson() {
    return _root.toJson();
  }

  VNode? _resolveNode(String path) {
    if (path.isEmpty) return _cwd;

    VNode current = path.startsWith('/') ? _root : _cwd;
    final segments = path.split('/').where((s) => s.isNotEmpty);

    for (final segment in segments) {
      if (segment == '.') {
        continue;
      } else if (segment == '..') {
        if (current.parent != null) {
          current = current.parent!;
        }
      } else {
        final child = current.children[segment];
        if (child == null) {
          return null; // Path segment not found
        }
        current = child;
      }
    }
    return current;
  }

  MapEntry<VNode?, String> _resolveParentAndName(String path) {
    if (path.isEmpty) return const MapEntry(null, '');

    final isAbsolute = path.startsWith('/');
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    
    if (segments.isEmpty) {
      if (isAbsolute) {
        return MapEntry(_root.parent, ''); // Root has no parent
      }
      return const MapEntry(null, '');
    }

    final name = segments.last;
    final parentSegments = segments.sublist(0, segments.length - 1);

    VNode? parentNode;
    if (parentSegments.isEmpty) {
      parentNode = isAbsolute ? _root : _cwd;
    } else {
      final parentPath = (isAbsolute ? '/' : '') + parentSegments.join('/');
      parentNode = _resolveNode(parentPath);
    }

    return MapEntry(parentNode, name);
  }

  String getAbsolutePath() {
    final List<String> segments = [];
    VNode? current = _cwd;
    while (current != null && current.name.isNotEmpty) {
      segments.add(current.name);
      current = current.parent;
    }
    if (segments.isEmpty) return '/';
    return '/${segments.reversed.join('/')}';
  }

  String getPromptPath() {
    final path = getAbsolutePath();
    if (path == '/home') {
      return '~';
    } else if (path.startsWith('/home/')) {
      return '~${path.substring(5)}';
    }
    return path;
  }

  String ls([String path = '']) {
    final node = path.isEmpty ? _cwd : _resolveNode(path);
    if (node == null) {
      return 'ls: cannot access \'$path\': No such file or directory';
    }
    if (!node.isDirectory) {
      return node.name;
    }
    if (node.children.isEmpty) {
      return '';
    }

    final sortedNames = node.children.keys.toList()..sort();
    return sortedNames.map((name) {
      final child = node.children[name]!;
      return child.isDirectory ? '$name/' : name;
    }).join('  ');
  }

  String? cd(String path) {
    if (path.isEmpty || path == '~') {
      final home = _resolveNode('/home');
      if (home != null) {
        _cwd = home;
        return null;
      }
    }

    final node = _resolveNode(path);
    if (node == null) {
      return 'cd: $path: No such file or directory';
    }
    if (!node.isDirectory) {
      return 'cd: $path: Not a directory';
    }
    _cwd = node;
    return null;
  }

  String? mkdir(String path) {
    if (path.isEmpty) {
      return 'mkdir: missing operand';
    }

    final resolved = _resolveParentAndName(path);
    final parent = resolved.key;
    final name = resolved.value;

    if (parent == null) {
      return 'mkdir: cannot create directory \'$path\': No such file or directory';
    }
    if (!parent.isDirectory) {
      return 'mkdir: cannot create directory \'$path\': Not a directory';
    }
    if (parent.children.containsKey(name)) {
      return 'mkdir: cannot create directory \'$path\': File exists';
    }

    final newDir = VNode(name: name, isDirectory: true, parent: parent);
    parent.children[name] = newDir;
    return null;
  }

  String? touch(String path, [String content = '']) {
    if (path.isEmpty) {
      return 'touch: missing file operand';
    }

    final resolved = _resolveParentAndName(path);
    final parent = resolved.key;
    final name = resolved.value;

    if (parent == null) {
      return 'touch: cannot touch \'$path\': No such file or directory';
    }
    if (!parent.isDirectory) {
      return 'touch: cannot touch \'$path\': Not a directory';
    }

    final existing = parent.children[name];
    if (existing != null) {
      if (existing.isDirectory) {
        return 'touch: cannot touch \'$path\': Is a directory';
      }
      if (content.isNotEmpty) {
        existing.content = content;
      }
      return null;
    }

    final newFile = VNode(
      name: name,
      isDirectory: false,
      content: content,
      parent: parent,
    );
    parent.children[name] = newFile;
    return null;
  }

  String cat(String path) {
    if (path.isEmpty) {
      return 'cat: missing file operand';
    }
    final node = _resolveNode(path);
    if (node == null) {
      return 'cat: $path: No such file or directory';
    }
    if (node.isDirectory) {
      return 'cat: $path: Is a directory';
    }
    return node.content;
  }

  String? rm(String path, {bool recursive = false}) {
    if (path.isEmpty) {
      return 'rm: missing operand';
    }

    final node = _resolveNode(path);
    if (node == null) {
      return 'rm: cannot remove \'$path\': No such file or directory';
    }

    if (node == _root) {
      return 'rm: cannot remove root directory \'/\'';
    }

    if (node.isDirectory && !recursive) {
      return 'rm: cannot remove \'$path\': Is a directory';
    }

    final parent = node.parent;
    if (parent != null) {
      parent.children.remove(node.name);
      return null;
    }
    return 'rm: cannot remove \'$path\': Permission denied';
  }

  VNode _cloneNode(VNode node, VNode newParent, String newName) {
    final clone = VNode(
      name: newName,
      isDirectory: node.isDirectory,
      content: node.content,
      parent: newParent,
    );
    if (node.isDirectory) {
      for (final childName in node.children.keys) {
        clone.children[childName] = _cloneNode(
          node.children[childName]!,
          clone,
          childName,
        );
      }
    }
    return clone;
  }

  String? cp(String srcPath, String destPath, {bool recursive = false}) {
    if (srcPath.isEmpty || destPath.isEmpty) {
      return 'cp: missing file operand';
    }

    final srcNode = _resolveNode(srcPath);
    if (srcNode == null) {
      return 'cp: cannot stat \'$srcPath\': No such file or directory';
    }

    if (srcNode.isDirectory && !recursive) {
      return 'cp: -r not specified; omitting directory \'$srcPath\'';
    }

    final destResolved = _resolveParentAndName(destPath);
    var destParent = destResolved.key;
    var destName = destResolved.value;

    final destNode = _resolveNode(destPath);
    if (destNode != null && destNode.isDirectory) {
      destParent = destNode;
      destName = srcNode.name;
    }

    if (destParent == null) {
      return 'cp: cannot create \'$destPath\': No such file or directory';
    }
    if (!destParent.isDirectory) {
      return 'cp: cannot create \'$destPath\': Not a directory';
    }

    final cloned = _cloneNode(srcNode, destParent, destName);
    destParent.children[destName] = cloned;
    return null;
  }

  String? mv(String srcPath, String destPath) {
    if (srcPath.isEmpty || destPath.isEmpty) {
      return 'mv: missing file operand';
    }

    final srcNode = _resolveNode(srcPath);
    if (srcNode == null) {
      return 'mv: cannot stat \'$srcPath\': No such file or directory';
    }

    if (srcNode == _root) {
      return 'mv: cannot move root directory \'/\'';
    }

    final destResolved = _resolveParentAndName(destPath);
    var destParent = destResolved.key;
    var destName = destResolved.value;

    final destNode = _resolveNode(destPath);
    if (destNode != null && destNode.isDirectory) {
      destParent = destNode;
      destName = srcNode.name;
    }

    if (destParent == null) {
      return 'mv: cannot move to \'$destPath\': No such file or directory';
    }
    if (!destParent.isDirectory) {
      return 'mv: cannot move to \'$destPath\': Not a directory';
    }

    // Remove from original parent
    final originalParent = srcNode.parent;
    if (originalParent != null) {
      originalParent.children.remove(srcNode.name);
    }

    // Reassign details
    srcNode.name = destName;
    srcNode.parent = destParent;
    destParent.children[destName] = srcNode;

    return null;
  }
}
