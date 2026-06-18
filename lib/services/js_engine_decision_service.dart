class JsEngineCandidate {
  final String id;
  final String status;
  final String label;
  final String whatItIs;
  final List<String> pros;
  final List<String> cons;
  final String androidRisk;
  final String apkSizeImpact;
  final String buildComplexity;
  final String securityNotes;
  final String currentStatus;
  final String recommendation;

  const JsEngineCandidate({
    required this.id,
    required this.status,
    required this.label,
    required this.whatItIs,
    required this.pros,
    required this.cons,
    required this.androidRisk,
    required this.apkSizeImpact,
    required this.buildComplexity,
    required this.securityNotes,
    required this.currentStatus,
    required this.recommendation,
  });
}

class JsEngineDecisionService {
  static const recommendedNextMilestone = 'v0.35 Runtime Decision Freeze';

  static const List<JsEngineCandidate> candidates = [
    JsEngineCandidate(
      id: 'current-proof',
      status: 'current',
      label: 'safest',
      whatItIs:
          'The existing js-proof evaluator: a controlled native JS-like syntax proof.',
      pros: [
        'Already works through Dart -> Kotlin -> JNI/native.',
        'Very small and safe.',
        'No filesystem, network, process, require, import, Node.js, or npm.',
      ],
      cons: [
        'Not real JavaScript.',
        'Only proves routing and a tiny expression subset.',
      ],
      androidRisk:
          'Low. It is already compiled into the existing native bridge.',
      apkSizeImpact: 'Tiny; already present.',
      buildComplexity: 'Low; no external engine source or new build system.',
      securityNotes:
          'Best for proof routing. Continue blocking Node-like APIs and long input.',
      currentStatus: 'Available as js-proof.',
      recommendation:
          'Keep as the safe baseline while a real engine is evaluated separately.',
    ),
    JsEngineCandidate(
      id: 'quickjs',
      status: 'possible',
      label: 'promising',
      whatItIs:
          'A small embeddable JavaScript engine with modern JavaScript support for a compact native proof.',
      pros: [
        'Small real JavaScript engine.',
        'Embeddable as C code behind the existing JNI bridge.',
        'Good candidate for a focused v0.33 proof.',
      ],
      cons: [
        'Needs vendored source and build integration.',
        'Needs hard limits for memory, output, and runaway scripts.',
      ],
      androidRisk:
          'Medium. It should work as an APK native library, but crashes and resource limits must be contained.',
      apkSizeImpact:
          'Low to medium depending on ABI count and enabled features.',
      buildComplexity:
          'Medium. Requires source vendoring, CMake wiring, JNI wrappers, and tests.',
      securityNotes:
          'Expose no filesystem/network/process APIs. Enforce length, output, and timeout/interrupt controls.',
      currentStatus:
          'v0.33 command/bridge probe exists, but QuickJS source is not integrated in this build.',
      recommendation:
          'Keep the probe limited unless a small vendored source snapshot and timeout/resource limits are added.',
    ),
    JsEngineCandidate(
      id: 'duktape',
      status: 'possible',
      label: 'simple',
      whatItIs:
          'A mature small embeddable JavaScript engine with simpler integration and older JS support.',
      pros: [
        'Simple embeddable C engine.',
        'Mature and compact.',
        'Good fallback if QuickJS is too much for the first real-engine proof.',
      ],
      cons: [
        'Less modern JavaScript support.',
        'Still needs native crash/resource guardrails.',
      ],
      androidRisk:
          'Medium-low. Simpler native surface, but still native code inside the app process.',
      apkSizeImpact: 'Low to medium.',
      buildComplexity: 'Low to medium compared with QuickJS.',
      securityNotes:
          'Use a sealed global environment. Do not expose host APIs or Node APIs.',
      currentStatus:
          'v0.34 command/bridge probe exists, but Duktape source is not integrated in this build.',
      recommendation:
          'Keep as a limited fallback probe and freeze the runtime decision before adding more engine surfaces.',
    ),
    JsEngineCandidate(
      id: 'javascriptcore',
      status: 'risky',
      label: 'platform-dependent',
      whatItIs:
          'Apple WebKit JavaScriptCore, a capable engine but not naturally available as a simple Android dependency.',
      pros: ['Real JavaScript engine.', 'Proven in other platform contexts.'],
      cons: [
        'Platform-dependent and awkward for Android.',
        'Bundling it safely may be larger than Termode needs now.',
      ],
      androidRisk: 'High unless carefully bundled and maintained.',
      apkSizeImpact: 'Medium to high.',
      buildComplexity: 'High for this stage.',
      securityNotes:
          'Large native dependency surface. Not suitable before smaller engines are tested.',
      currentStatus: 'Not integrated.',
      recommendation: 'Do not pursue for the next proof.',
    ),
    JsEngineCandidate(
      id: 'v8',
      status: 'risky',
      label: 'large',
      whatItIs:
          'Google V8, a powerful production JavaScript engine used by Chrome and Node.js.',
      pros: [
        'Very capable JavaScript engine.',
        'Best compatibility foundation for large JS workloads.',
      ],
      cons: [
        'Huge and complex.',
        'Heavy build, ABI, startup, and APK-size burden.',
      ],
      androidRisk: 'High for early Termode runtime work.',
      apkSizeImpact: 'High.',
      buildComplexity: 'Very high.',
      securityNotes:
          'Large native attack/crash surface and resource management problem.',
      currentStatus: 'Not integrated.',
      recommendation: 'Defer. V8 is not the next practical step.',
    ),
    JsEngineCandidate(
      id: 'node',
      status: 'future',
      label: 'not yet',
      whatItIs:
          'Node.js is a full runtime, not just a JavaScript engine. It brings libuv, process, fs, module loading, npm expectations, and CLI behavior.',
      pros: [
        'Future path toward npm, Vite, and common JavaScript tooling.',
        'Matches developer expectations.',
      ],
      cons: [
        'Large runtime and package compatibility surface.',
        'Requires process, filesystem, npm, scripts, symlinks, and native module decisions.',
      ],
      androidRisk: 'Very high until smaller embedded/runtime proofs succeed.',
      apkSizeImpact: 'High.',
      buildComplexity: 'Very high.',
      securityNotes:
          'npm can fetch and execute code. Do not attempt before runtime isolation is designed.',
      currentStatus: 'Not included.',
      recommendation: 'Do not attempt yet. Prove embedded JS first.',
    ),
    JsEngineCandidate(
      id: 'no-engine-yet',
      status: 'fallback',
      label: 'safest',
      whatItIs:
          'Continue using js-proof and defer real JavaScript engine integration until architecture and resource limits are clearer.',
      pros: [
        'Safest option.',
        'No new native dependency or APK size increase.',
        'Keeps focus on package, workspace, PTY, and runtime stability.',
      ],
      cons: [
        'No real JavaScript execution yet.',
        'Delays validation of embedded engine behavior on Android.',
      ],
      androidRisk: 'Lowest.',
      apkSizeImpact: 'None.',
      buildComplexity: 'None.',
      securityNotes:
          'Avoids new native crash/resource risks while preserving current proof.',
      currentStatus: 'Chosen for v0.32 implementation scope.',
      recommendation:
          'Use as fallback while QuickJS and Duktape remain limited/unavailable.',
    ),
  ];

  JsEngineCandidate? byId(String id) {
    final normalized = id.trim().toLowerCase();
    for (final c in candidates) {
      if (c.id == normalized) return c;
    }
    return null;
  }

  String candidatesTable() {
    final sb = StringBuffer();
    sb.writeln('=== JS Engine Candidates ===');
    for (final c in candidates) {
      sb.writeln('${c.id.padRight(17)} ${c.status.padRight(9)} ${c.label}');
    }
    return sb.toString().trimRight();
  }

  String candidateDetails(String id) {
    final c = byId(id);
    if (c == null) {
      return 'Unknown JS engine candidate: $id\n'
          'Usage: js-engine-candidate <${candidates.map((e) => e.id).join('|')}>';
    }
    final sb = StringBuffer();
    sb.writeln('=== JS Engine Candidate: ${c.id} ===');
    sb.writeln('What it is: ${c.whatItIs}');
    sb.writeln('Pros:');
    for (final item in c.pros) {
      sb.writeln('  - $item');
    }
    sb.writeln('Cons:');
    for (final item in c.cons) {
      sb.writeln('  - $item');
    }
    sb.writeln('Android risk: ${c.androidRisk}');
    sb.writeln('APK size impact: ${c.apkSizeImpact}');
    sb.writeln('Build complexity: ${c.buildComplexity}');
    sb.writeln('Security notes: ${c.securityNotes}');
    sb.writeln('Current Termode status: ${c.currentStatus}');
    sb.write('Recommendation: ${c.recommendation}');
    return sb.toString();
  }

  String decision() {
    return '=== JS Engine Decision ===\n'
        'Decision: QuickJS and Duktape remain limited probes because no local source snapshots were available to integrate safely.\n'
        'Chosen path: keep js-proof as the safe current proof and keep quickjs/duktape as unavailable/limited probe surfaces.\n'
        'Recommended next milestone: $recommendedNextMilestone\n\n'
        'Why:\n'
        '  - QuickJS is still promising, but this repo does not contain a vendored source snapshot.\n'
        '  - Duktape is simpler, but this repo also does not contain a vendored source snapshot.\n'
        '  - V8 and JavaScriptCore are too large or platform-dependent for this stage.\n'
        '  - Node.js is a future runtime goal, not this engine probe.\n\n'
        'Node.js included: NO\n'
        'npm included: NO\n'
        'QuickJS source integrated: NO\n'
        'Duktape source integrated: NO';
  }

  String risks() {
    return '=== JS Engine Risks ===\n'
        '  - Infinite loops without timeout/interrupt support\n'
        '  - Memory growth inside the app process\n'
        '  - Native crashes terminating Termode\n'
        '  - Accidentally exposing filesystem, network, process, import, or require APIs\n'
        '  - APK size growth across Android ABIs\n'
        '  - Build complexity and native dependency maintenance\n'
        '  - Confusing embedded JavaScript with Node.js/npm compatibility';
  }

  String next() {
    return '=== JS Engine Next ===\n'
        'Recommended next milestone: $recommendedNextMilestone\n'
        'Scope: freeze the runtime decision: choose js-proof-only for now, or pick one embedded engine path with source, timeout, and safety criteria.\n'
        'Fallback: keep js-proof plus limited quickjs/duktape probes until timeout/resource limits are practical.\n'
        'Safety gate: do not expose loops broadly until timeout or interrupt behavior is proven.\n'
        'Node.js/npm: still not included.';
  }

  String doctor() {
    return '=== JS Engine Doctor ===\n'
        'Decision commands: OK\n'
        'Current proof: js-proof\n'
        'QuickJS probe: limited/unavailable\n'
        'Duktape probe: limited/unavailable\n'
        'Real embedded engine: not integrated\n'
        'Recommended next: runtime decision freeze\n'
        'Fallback candidate: no-engine-yet\n'
        'Node.js included: NO\n'
        'npm included: NO\n'
        'Overall: LIMITED';
  }
}
