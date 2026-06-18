import 'dart:io';

import 'package:flutter/services.dart';

import 'workspace_service.dart';

class QuickJsService {
  static final QuickJsService _instance = QuickJsService._internal();
  factory QuickJsService() => _instance;
  QuickJsService._internal();

  static const String channelName = 'com.termode/native_shell';
  static const int maxCodeLength = 4096;
  static const int maxFileSize = 32768;
  static const int maxOutputLength = 8192;

  static const String unavailable =
      'QuickJS bridge unavailable.\nRuntime remains limited.';

  Future<Map<String, dynamic>?> _call(
    String command, [
    String args = '',
  ]) async {
    try {
      final dynamic res = await const MethodChannel(
        channelName,
      ).invokeMethod('quickJs', {'command': command, 'args': args});
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  String help() {
    return '=== QuickJS Probe ===\n'
        'Real embedded JavaScript engine probe command surface.\n'
        'This is not Node.js and not npm.\n\n'
        'Commands:\n'
        '  quickjs help        - Show this help\n'
        '  quickjs info        - Show QuickJS probe status\n'
        '  quickjs eval <code> - Evaluate code if the engine is available\n'
        '  quickjs file <path> - Evaluate a small safe Termode file\n'
        '  quickjs limits      - Show safety limits\n'
        '  quickjs doctor      - Diagnose the QuickJS bridge/engine\n'
        '  quickjs plan        - Show staged QuickJS/runtime plan';
  }

  Future<String> info() async {
    final r = await _call('info');
    if (r == null) return unavailable;
    final sb = StringBuffer();
    sb.writeln('=== QuickJS Probe Info ===');
    sb.writeln('Engine: ${r['engine'] ?? 'QuickJS'}');
    sb.writeln('Mode: ${r['mode'] ?? 'native embedded engine'}');
    sb.writeln('Node.js: not included');
    sb.writeln('npm: not included');
    sb.writeln('Filesystem API: disabled');
    sb.writeln('Network API: disabled');
    sb.write(
      'Status: ${r['status'] ?? (r['ok'] == true ? 'PROBE' : 'UNAVAILABLE')}',
    );
    return sb.toString();
  }

  Future<String> eval(String code) async {
    final validation = _validateCode(code);
    if (validation != null) return validation;
    final r = await _call('eval', code);
    if (r == null) return unavailable;
    if (r['ok'] == true) {
      final value = _limitOutput(r['result']?.toString() ?? '');
      return 'Engine: ${r['engine'] ?? 'QuickJS'}\nResult: $value';
    }
    final error = r['error']?.toString() ?? 'QuickJS evaluation failed.';
    if (_isNodeApiError(error)) {
      return 'Error: Node APIs are not available.\n'
          'This is embedded JavaScript, not Node.js.';
    }
    return 'Error: $error';
  }

  Future<String> file(String path) async {
    if (path.trim().isEmpty) {
      return 'Usage: quickjs file <path>';
    }
    final File file;
    try {
      file = await WorkspaceService().resolveHostFile(path);
    } on FileSystemException {
      return 'Error: quickjs file path escapes Termode workspace.';
    }
    if (!await file.exists()) {
      return 'Error: QuickJS file not found: $path';
    }
    final length = await file.length();
    if (length > maxFileSize) {
      return 'Error: QuickJS file exceeds $maxFileSize bytes.';
    }
    final code = await file.readAsString();
    return eval(code);
  }

  String limits() {
    return '=== QuickJS Limits ===\n'
        'Max inline code length: $maxCodeLength chars\n'
        'Max file size: $maxFileSize bytes\n'
        'Max output length: $maxOutputLength chars\n'
        'Filesystem: disabled\n'
        'Network: disabled\n'
        'Node APIs: disabled\n'
        'npm: unavailable\n'
        'Timeout: not supported yet\n'
        'Loop guard: obvious while(true) and for(;;) patterns are blocked';
  }

  Future<String> doctor() async {
    final r = await _call('doctor');
    if (r == null) return unavailable;
    final bridgeOk = r['bridgeOk'] == true;
    final engineOk = r['engineOk'] == true;
    final evalOk = r['evalOk'] == true;
    final errorsOk = r['errorsOk'] != false;
    final overall = bridgeOk && engineOk && evalOk && errorsOk
        ? 'HEALTHY'
        : (bridgeOk ? 'LIMITED' : 'UNAVAILABLE');
    final sb = StringBuffer();
    sb.writeln('=== QuickJS Doctor ===');
    sb.writeln('Bridge: ${bridgeOk ? 'OK' : 'FAIL'}');
    sb.writeln('Engine: ${engineOk ? 'OK' : 'LIMITED'}');
    sb.writeln('Eval: ${evalOk ? 'OK' : 'LIMITED'}');
    sb.writeln('Errors: ${errorsOk ? 'OK' : 'FAIL'}');
    sb.writeln('Node APIs: disabled');
    sb.write('Overall: ${r['overall'] ?? overall}');
    return sb.toString();
  }

  String plan() {
    return '=== QuickJS Plan ===\n'
        '1. QuickJS probe\n'
        '2. QuickJS safety hardening\n'
        '3. Optional JS script package bridge later\n'
        '4. Node strategy later\n'
        '5. npm later\n'
        '6. Vite later';
  }

  String? _validateCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return 'Usage: quickjs eval <code>';
    }
    if (code.length > maxCodeLength) {
      return 'Error: QuickJS code exceeds $maxCodeLength characters.';
    }
    final lower = code.toLowerCase();
    if (RegExp(r'\b(require|import|process|fs|http|eval)\b').hasMatch(lower)) {
      return 'Error: Node APIs are not available.\n'
          'This is embedded JavaScript, not Node.js.';
    }
    if (lower.contains('while(true)') || lower.contains('for(;;)')) {
      return 'Error: QuickJS execution timed out.';
    }
    return null;
  }

  String _limitOutput(String value) {
    if (value.length <= maxOutputLength) return value;
    return '${value.substring(0, maxOutputLength)}\n'
        '[Output truncated: exceeded $maxOutputLength characters]';
  }

  bool _isNodeApiError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('node api') ||
        lower.contains('require') ||
        lower.contains('import') ||
        lower.contains('process') ||
        lower.contains('fs') ||
        lower.contains('http');
  }
}
