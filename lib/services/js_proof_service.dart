import 'dart:io';

import 'package:flutter/services.dart';

import 'workspace_service.dart';

class JsProofService {
  static final JsProofService _instance = JsProofService._internal();
  factory JsProofService() => _instance;
  JsProofService._internal();

  static const String channelName = 'com.termode/native_shell';
  static const int maxCodeLength = 4096;
  static const int maxFileSize = 32768;

  static const String unavailable =
      'Native JS proof unavailable.\nRuntime remains limited.';

  Future<Map<String, dynamic>?> _call(
    String command, [
    String args = '',
  ]) async {
    try {
      final dynamic res = await const MethodChannel(
        channelName,
      ).invokeMethod('jsProof', {'command': command, 'args': args});
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
    return '=== JS Proof ===\n'
        'Tiny JS-like evaluator proof through the native bridge.\n'
        'This is not Node.js and not npm.\n\n'
        'Commands:\n'
        '  js-proof help        - Show this help\n'
        '  js-proof info        - Show proof engine status\n'
        '  js-proof eval <code> - Evaluate tiny supported syntax\n'
        '  js-proof file <path> - Evaluate a small safe Termode file\n'
        '  js-proof doctor      - Diagnose bridge/evaluator/errors\n'
        '  js-proof limits      - Show safety limits\n'
        '  js-proof plan        - Show staged JS/runtime plan';
  }

  Future<String> info() async {
    final r = await _call('info');
    if (r == null || r['ok'] != true) return unavailable;
    final sb = StringBuffer();
    sb.writeln('=== JS Proof Info ===');
    sb.writeln('Engine: ${r['engine'] ?? 'tiny-js-proof'}');
    sb.writeln('Mode: ${r['mode'] ?? 'native bridge'}');
    sb.writeln('Node.js: not included');
    sb.writeln('npm: not included');
    sb.writeln('Shell execution: no');
    sb.writeln('QuickJS probe: separate, limited/unavailable via quickjs');
    sb.writeln('Duktape probe: separate, limited/unavailable via duktape');
    sb.write('Status: ${r['status'] ?? 'PROOF'}');
    return sb.toString();
  }

  Future<String> eval(String code) async {
    if (code.trim().isEmpty) {
      return 'Usage: js-proof eval <code>';
    }
    if (code.length > maxCodeLength) {
      return 'Error: JS proof code exceeds $maxCodeLength characters.';
    }
    final r = await _call('eval', code);
    if (r == null) return unavailable;
    if (r['ok'] == true) {
      return 'Result: ${r['result'] ?? ''}';
    }
    return 'Error: ${r['error'] ?? 'Unsupported JS proof syntax.'}\n'
        'This is not Node.js.';
  }

  Future<String> file(String path) async {
    if (path.trim().isEmpty) {
      return 'Usage: js-proof file <path>';
    }
    final File file;
    try {
      file = await WorkspaceService().resolveHostFile(path);
    } on FileSystemException {
      return 'Error: js-proof file path escapes Termode workspace.';
    }
    if (!await file.exists()) {
      return 'Error: JS proof file not found: $path';
    }
    final length = await file.length();
    if (length > maxFileSize) {
      return 'Error: JS proof file exceeds $maxFileSize bytes.';
    }
    final code = await file.readAsString();
    if (code.length > maxCodeLength) {
      return 'Error: JS proof code exceeds $maxCodeLength characters.';
    }
    return eval(code);
  }

  Future<String> doctor() async {
    final r = await _call('doctor');
    final bridgeOk = r != null && r['bridgeOk'] == true;
    final evaluatorOk = r != null && r['evaluatorOk'] == true;
    final errorsOk = r != null && r['errorsOk'] == true;
    final overall = bridgeOk && evaluatorOk && errorsOk
        ? 'HEALTHY'
        : (r == null ? 'UNAVAILABLE' : 'LIMITED');
    final sb = StringBuffer();
    sb.writeln('=== JS Proof Doctor ===');
    sb.writeln('Bridge: ${bridgeOk ? 'OK' : 'FAIL'}');
    sb.writeln('Evaluator: ${evaluatorOk ? 'OK' : 'FAIL'}');
    sb.writeln('Errors: ${errorsOk ? 'OK' : 'FAIL'}');
    sb.writeln('Node.js: not included');
    sb.write('Overall: $overall');
    return sb.toString();
  }

  String limits() {
    return '=== JS Proof Limits ===\n'
        'Max code length: $maxCodeLength\n'
        'Max file size: $maxFileSize\n'
        'Supported: arithmetic/string/boolean subset\n'
        'Unsupported: Node APIs, npm, import, require, filesystem, network, timers';
  }

  String plan() {
    return '=== JS Proof Plan ===\n'
        '1. Tiny JS proof\n'
        '2. Embedded JS engine decision/probe\n'
        '3. QuickJS probe command surface\n'
        '4. Duktape probe/fallback command surface\n'
        '5. Runtime decision freeze\n'
        '6. Node binary strategy later\n'
        '7. npm later\n'
        '8. Vite later';
  }
}
