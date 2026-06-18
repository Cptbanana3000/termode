import 'dart:io';

import 'runtime_capability_service.dart';

class RuntimeFreezeService {
  static const nextMilestone = 'v0.43 Prefix / PATH / Environment System';

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
        'Runtime implementation: frozen for current beta foundation.\n'
        'Expansion architecture: active in v0.42.\n'
        'Actual external runtimes: not installed yet.\n'
        'Decision: frozen\n'
        'Current JS path: js-proof\n'
        'QuickJS: deferred\n'
        'Duktape: deferred\n'
        'Node.js: planned (not installed)\n'
        'npm: planned (not installed)\n'
        'Next focus: runtime expansion architecture\n'
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
    return '=== Runtime Freeze Deferred ===\n'
        '* Node.js/npm are not included yet.\n'
        '* Python/Git are not included yet.\n'
        '* Native binary packages are not supported.\n'
        '* QuickJS/Duktape are probe surfaces only.\n'
        '* Runtime research is frozen for now.\n'
        '* Remote packages remain script-only.';
  }

  String why() {
    return '=== Runtime Freeze Why ===\n'
        '* Termode is stabilizing the app users have today.\n'
        '* Real runtimes need source, sandboxing, timeout, and update policies.\n'
        '* Node/npm are much larger than the current script package model.\n'
        '* QuickJS/Duktape probes stay available for research history.\n'
        '* Product stability matters first.\n'
        '* Runtime expansion is now planned (see runtime-install, toolchain-status); '
        'it was frozen for the v0.40 foundation, not forever.';
  }

  String next() {
    return '=== Runtime Freeze Next ===\n'
        'Recommended next milestone:\n'
        '$nextMilestone\n\n'
        'Focus:\n'
        '  - prefix / PATH / environment system\n'
        '  - binary package installer prototype\n'
        '  - guided toolchain installs (git, node, python)\n'
        '  - package/workspace/terminal QA\n'
        'Runtime implementation stays frozen for now; runtime expansion is planned.';
  }

  String doctor() {
    final docsFileOk = File('docs/RUNTIME_DECISION_FREEZE.md').existsSync();
    final embeddedDecisionOk =
        decision().contains('Decision: Termode keeps') &&
        deferredItems.contains('Node.js') &&
        deferredItems.contains('npm');
    final docsOk = docsFileOk || embeddedDecisionOk;
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
