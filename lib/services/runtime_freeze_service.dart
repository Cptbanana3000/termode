import 'dart:io';

import 'runtime_capability_service.dart';

class RuntimeFreezeService {
  static const nextMilestone =
      'v0.36 Product Stabilization / Beta Readiness Pass';

  static const supportedRuntimeDirection = [
    'script packages through /system/bin/sh',
    'built-in native tools through JNI',
    'js-proof controlled evaluator',
    'localhost/preview workflow',
  ];

  static const deferredItems = [
    'QuickJS integration',
    'Duktape integration',
    'Node.js',
    'npm',
    'Python',
    'Git',
    'native binary package installs',
  ];

  String help() {
    return '=== Runtime Freeze ===\n'
        'Runtime direction is frozen for product stabilization.\n\n'
        'Commands:\n'
        '  runtime-freeze status   - Show compact freeze status\n'
        '  runtime-freeze decision - Explain the frozen runtime direction\n'
        '  runtime-freeze deferred - List deferred runtimes and package types\n'
        '  runtime-freeze why      - Explain why real runtimes are deferred\n'
        '  runtime-freeze next     - Show the next product milestone\n'
        '  runtime-freeze doctor   - Check freeze docs and plan status';
  }

  String status() {
    return '=== Runtime Freeze Status ===\n'
        'Decision: frozen\n'
        'Current JS path: js-proof\n'
        'QuickJS: deferred\n'
        'Duktape: deferred\n'
        'Node.js: deferred\n'
        'npm: deferred\n'
        'Next focus: product stability\n'
        'Overall: FROZEN';
  }

  String decision() {
    return '=== Runtime Freeze Decision ===\n'
        'Decision: Termode keeps the current supported runtime direction and stops adding runtime surfaces for now.\n\n'
        'Current supported direction:\n'
        '  - script packages through /system/bin/sh\n'
        '  - built-in native tools through JNI\n'
        '  - js-proof controlled evaluator\n'
        '  - localhost/preview workflow\n\n'
        'js-proof remains the active built-in JS-like proof.\n'
        'quickjs and duktape remain probe surfaces only.\n'
        'Real embedded engines are deferred.\n'
        'Node.js and npm are future goals, not current runtime work.';
  }

  String deferred() {
    final sb = StringBuffer();
    sb.writeln('=== Runtime Freeze Deferred ===');
    for (final item in deferredItems) {
      sb.writeln('  - $item');
    }
    sb.write('Remote packages remain script-only.');
    return sb.toString();
  }

  String why() {
    return '=== Runtime Freeze Why ===\n'
        '  - No clean source/vendor policy exists yet for real embedded engines.\n'
        '  - Engine sandboxing needs careful design.\n'
        '  - Timeout and infinite-loop handling are unresolved.\n'
        '  - Node/npm are significantly more complex than JS eval.\n'
        '  - Product stability matters first.';
  }

  String next() {
    return '=== Runtime Freeze Next ===\n'
        'Recommended next milestone:\n'
        '$nextMilestone\n\n'
        'Focus:\n'
        '  - docs/help cleanup\n'
        '  - onboarding\n'
        '  - command discoverability\n'
        '  - device QA\n'
        '  - bug bash\n'
        '  - package polish\n'
        '  - workspace polish\n'
        '  - terminal UX polish';
  }

  String doctor() {
    final docsOk = File('docs/RUNTIME_DECISION_FREEZE.md').existsSync();
    final plan = RuntimeCapabilityService().plan();
    final planOk =
        plan.contains('11. Runtime decision freeze') &&
        plan.contains('12. Product stabilization');
    final overall = docsOk && planOk ? 'HEALTHY' : 'LIMITED';
    return '=== Runtime Freeze Doctor ===\n'
        'js-proof: healthy\n'
        'QuickJS: deferred\n'
        'Duktape: deferred\n'
        'Node.js: not included\n'
        'npm: not included\n'
        'Decision docs: ${docsOk ? 'OK' : 'MISSING'}\n'
        'Runtime plan: ${planOk ? 'OK' : 'MISSING'}\n'
        'Overall: $overall';
  }
}
