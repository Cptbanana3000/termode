import 'dart:io';

import 'runtime_capability_service.dart';

class RuntimeCandidate {
  final String id;
  final String title;
  final String status;
  final String riskLevel;
  final String summary;
  final List<String> pros;
  final List<String> cons;
  final String androidConstraints;
  final String apkSizeImpact;
  final String updateStrategy;
  final String securityNotes;
  final String currentStatus;
  final String recommendation;
  final String recommendedNextStep;
  final String docsReference;

  const RuntimeCandidate({
    required this.id,
    required this.title,
    required this.status,
    required this.riskLevel,
    required this.summary,
    required this.pros,
    required this.cons,
    required this.androidConstraints,
    required this.apkSizeImpact,
    required this.updateStrategy,
    required this.securityNotes,
    required this.currentStatus,
    required this.recommendation,
    required this.recommendedNextStep,
    required this.docsReference,
  });
}

class RuntimeResearchDoctorResult {
  final bool nativeBridgeAvailable;
  final String directAppBinExec;
  final bool abiKnown;
  final bool docsPresent;
  final bool scriptPackagesSupported;
  final bool previewLocalhostSupported;

  RuntimeResearchDoctorResult({
    required this.nativeBridgeAvailable,
    required this.directAppBinExec,
    required this.abiKnown,
    required this.docsPresent,
    required this.scriptPackagesSupported,
    required this.previewLocalhostSupported,
  });

  String get overall {
    final ready =
        nativeBridgeAvailable &&
        abiKnown &&
        docsPresent &&
        scriptPackagesSupported &&
        previewLocalhostSupported;
    if (!ready) return 'UNHEALTHY';
    return directAppBinExec == 'allowed' ? 'HEALTHY' : 'LIMITED';
  }
}

class RuntimeCandidateService {
  static const recommendedNextMilestone =
      'v0.31 Tiny Embedded JS Engine Feasibility Probe';

  static const List<RuntimeCandidate> candidates = [
    RuntimeCandidate(
      id: 'script-packages',
      title: 'Script Packages Through /system/bin/sh',
      status: 'current',
      riskLevel: 'low',
      summary:
          'The current package system installs shell scripts and runs them through /system/bin/sh helper functions.',
      pros: [
        'Already works in NORMAL and REAL PTY modes.',
        'Small packages with readable source.',
        'Compatible with remote package trust/source guardrails.',
      ],
      cons: [
        'Not enough for Node.js, npm, or complex language runtimes.',
        'Limited by Android shell/tool availability.',
      ],
      androidConstraints:
          'Avoids app-writable executable restrictions because scripts are interpreted by /system/bin/sh.',
      apkSizeImpact: 'None beyond package metadata and scripts.',
      updateStrategy:
          'Local or trusted remote script package indexes; helpers are regenerated after changes.',
      securityNotes:
          'Remote packages remain script-only and source-locked. No native binaries are installed through pkg.',
      currentStatus: 'Current stable package mechanism.',
      recommendation:
          'Keep as the stable lightweight package system even after future runtimes arrive.',
      recommendedNextStep:
          'Continue hardening package trust, helper reload, and script authoring docs.',
      docsReference: 'docs/PACKAGE_AUTHORING.md',
    ),
    RuntimeCandidate(
      id: 'jni-native-tools',
      title: 'JNI Native Tools',
      status: 'current',
      riskLevel: 'low',
      summary:
          'Small audited native capabilities compiled into libtermode_pty.so and exposed through the MethodChannel/JNI bridge.',
      pros: [
        'Proven by native-tool without shelling out.',
        'No app-writable binary execution.',
        'Good for small built-in primitives like hash, ABI, pid, and cwd.',
      ],
      cons: [
        'Not a general package/runtime system.',
        'Every capability must be audited and shipped with the app.',
      ],
      androidConstraints:
          'Uses Android-supported APK native library loading, not direct executable launches.',
      apkSizeImpact:
          'Low for tiny tools; grows with each built-in native feature.',
      updateStrategy: 'Updated only through app releases.',
      securityNotes:
          'Best for narrow built-in capabilities with a fixed command surface and safe env redaction.',
      currentStatus: 'Current v0.29 proof.',
      recommendation:
          'Keep for audited built-in native capabilities, separate from packages; not installable through pkg.',
      recommendedNextStep:
          'Use this bridge to evaluate whether an embedded JS engine can be called safely.',
      docsReference: 'docs/NATIVE_TOOL_PROOF.md',
    ),
    RuntimeCandidate(
      id: 'apk-native-libs',
      title: 'APK Native Libraries',
      status: 'possible',
      riskLevel: 'medium',
      summary:
          'Ship native runtime code as ABI-specific libraries in the APK and call it through JNI.',
      pros: [
        'Android-supported native-code distribution path.',
        'Good for embedded runtimes callable as libraries.',
        'Avoids app-writable exec restrictions.',
      ],
      cons: [
        'Harder when a runtime expects to be a standalone process.',
        'Requires JNI lifecycle, memory, and crash handling.',
      ],
      androidConstraints:
          'Libraries load from APK-managed native locations; runtime must tolerate library-style embedding.',
      apkSizeImpact: 'Medium to high depending on ABI count and runtime size.',
      updateStrategy:
          'Updated through app releases unless a safe plugin model exists later.',
      securityNotes:
          'Safer than downloaded binaries, but native crashes can still terminate the app process.',
      currentStatus: 'Possible path, not implemented as a runtime.',
      recommendation:
          'Research as the safest Android-native route for embedded runtimes.',
      recommendedNextStep:
          'Prototype a tiny embedded JS engine as a native library, not Node first.',
      docsReference: 'docs/NATIVE_RUNTIME_CANDIDATES.md',
    ),
    RuntimeCandidate(
      id: 'bundled-executable',
      title: 'Bundled Executable',
      status: 'risky',
      riskLevel: 'high',
      summary:
          'Ship a standalone executable and attempt to run it from an Android-supported location.',
      pros: [
        'Closer to how Node and CLI tools normally run.',
        'Could support process-like runtime behavior if Android allows it.',
      ],
      cons: [
        'Android app-writable execution is commonly blocked.',
        'Standalone process lifecycle and permissions are fragile.',
      ],
      androidConstraints:
          'Do not rely on files/usr/bin. Needs proof from an Android-supported executable location.',
      apkSizeImpact: 'Medium to high for real runtimes.',
      updateStrategy:
          'Likely app releases only; downloaded executable updates are not acceptable yet.',
      securityNotes:
          'High trust burden. Avoid executing downloaded or app-writable native binaries.',
      currentStatus: 'Risky; needs proof.',
      recommendation:
          'Keep as a later proof only if embedded-library strategies are insufficient.',
      recommendedNextStep:
          'If chosen, test a tiny APK-shipped executable that performs no filesystem writes.',
      docsReference: 'docs/BUNDLED_RUNTIME_PROOF.md',
    ),
    RuntimeCandidate(
      id: 'embedded-js-engine',
      title: 'Embedded JS Engine',
      status: 'possible',
      riskLevel: 'medium',
      summary:
          'Embed a small JavaScript engine as a native library to prove JS evaluation before attempting Node.',
      pros: [
        'Proves JavaScript evaluation without npm complexity.',
        'Smaller and more controllable than Node.',
        'Can use the existing native bridge discipline.',
      ],
      cons: [
        'Not Node-compatible by itself.',
        'No npm, filesystem watchers, or dev server workflow yet.',
      ],
      androidConstraints:
          'Best explored as an APK native library through JNI. Candidate engines to research later include QuickJS, Duktape, JavaScriptCore, and V8.',
      apkSizeImpact: 'Low to medium depending on engine and ABI count.',
      updateStrategy: 'App releases while the proof is small and audited.',
      securityNotes:
          'Must sandbox evaluation, limit exposed APIs, and avoid arbitrary native access.',
      currentStatus: 'Research candidate, not added yet.',
      recommendation:
          'Best next experiment because it proves JS/runtime embedding before Node.',
      recommendedNextStep: recommendedNextMilestone,
      docsReference: 'docs/NATIVE_RUNTIME_CANDIDATES.md',
    ),
    RuntimeCandidate(
      id: 'node-binary',
      title: 'Node Binary',
      status: 'future',
      riskLevel: 'high',
      summary:
          'Ship or provide Node.js for local JavaScript, npm, and dev-server workflows.',
      pros: [
        'Direct path to Vite, Next.js-like tooling, and npm workflows.',
        'Matches developer expectations for JavaScript projects.',
      ],
      cons: [
        'Large binary and dependency footprint.',
        'npm behavior, symlinks, native modules, child processes, and file watching are risky.',
        'Execution model must be proven first.',
      ],
      androidConstraints:
          'ABI-specific builds, Android process constraints, and app-private exec restrictions all need proof.',
      apkSizeImpact: 'High.',
      updateStrategy:
          'Requires a careful app-shipped or trusted update model; no native package downloads yet.',
      securityNotes:
          'High trust surface because npm can run scripts and fetch code.',
      currentStatus: 'Future goal; not included.',
      recommendation:
          'Do not attempt first. Prove embedded JS/runtime strategy before Node.',
      recommendedNextStep:
          'Wait until native-library or executable runtime strategy is proven.',
      docsReference: 'docs/NATIVE_RUNTIME_CANDIDATES.md',
    ),
    RuntimeCandidate(
      id: 'termux-style-prefix',
      title: 'Termux-Style Prefix',
      status: 'future',
      riskLevel: 'high',
      summary:
          'Build a full Unix-like prefix and package ecosystem similar in spirit to Termux.',
      pros: [
        'Powerful if fully built.',
        'Could support many tools beyond JavaScript.',
      ],
      cons: [
        'Huge scope: packages, mirrors, patches, ABIs, security, updates.',
        'Would compete with Termux-level ecosystem maintenance.',
      ],
      androidConstraints:
          'Requires deep Android porting knowledge, patched packages, and reliable prefix execution behavior.',
      apkSizeImpact: 'Very high if bundled; operationally high if remote.',
      updateStrategy: 'Complex repository and mirror model.',
      securityNotes:
          'Large supply-chain surface. Not appropriate before smaller proofs.',
      currentStatus: 'Future/complex.',
      recommendation: 'Do not pursue yet.',
      recommendedNextStep: 'Revisit only after Node/runtime proof succeeds.',
      docsReference: 'docs/NATIVE_RUNTIME_CANDIDATES.md',
    ),
    RuntimeCandidate(
      id: 'remote-only',
      title: 'Remote-Only Execution',
      status: 'fallback',
      riskLevel: 'medium',
      summary:
          'Run builds/dev servers somewhere else and use Termode as a client.',
      pros: [
        'Avoids Android runtime packaging complexity.',
        'Can support heavy workloads earlier.',
      ],
      cons: [
        'Breaks the offline/local IDE goal.',
        'Requires network, accounts, security, and sync design.',
      ],
      androidConstraints:
          'Avoids local exec restrictions but introduces network and auth dependencies.',
      apkSizeImpact: 'Low locally.',
      updateStrategy: 'Server-side updates plus app client compatibility.',
      securityNotes:
          'Requires strong transport, auth, and workspace data protection.',
      currentStatus: 'Fallback idea only.',
      recommendation: 'Keep as a fallback, not the primary path for Termode.',
      recommendedNextStep: 'Prioritize local embedded/runtime proofs first.',
      docsReference: 'docs/NATIVE_RUNTIME_CANDIDATES.md',
    ),
  ];

  RuntimeCandidate? byId(String id) {
    final normalized = id.trim().toLowerCase();
    for (final candidate in candidates) {
      if (candidate.id == normalized) return candidate;
    }
    return null;
  }

  String candidatesTable() {
    final sb = StringBuffer();
    sb.writeln('=== Runtime Candidates ===');
    for (final c in candidates) {
      sb.writeln(
        '${c.id.padRight(22)} ${c.status.padRight(9)} ${_compactRisk(c)}',
      );
    }
    return sb.toString().trimRight();
  }

  String candidateDetails(String id) {
    final c = byId(id);
    if (c == null) {
      return 'Unknown runtime candidate: $id\n'
          'Usage: runtime-candidate <${candidates.map((e) => e.id).join('|')}>';
    }
    final sb = StringBuffer();
    sb.writeln('=== Runtime Candidate: ${c.id} ===');
    sb.writeln('Title: ${c.title}');
    sb.writeln('Status: ${c.status}');
    sb.writeln('Risk: ${c.riskLevel}');
    sb.writeln('What it is: ${c.summary}');
    sb.writeln('Pros:');
    for (final item in c.pros) {
      sb.writeln('  - $item');
    }
    sb.writeln('Cons:');
    for (final item in c.cons) {
      sb.writeln('  - $item');
    }
    sb.writeln('Android risk: ${c.androidConstraints}');
    sb.writeln('APK size impact: ${c.apkSizeImpact}');
    sb.writeln('Update story: ${c.updateStrategy}');
    sb.writeln('Security/trust notes: ${c.securityNotes}');
    sb.writeln('Current Termode status: ${c.currentStatus}');
    sb.writeln('Recommendation: ${c.recommendation}');
    sb.writeln('Recommended next step: ${c.recommendedNextStep}');
    sb.write('Docs: ${c.docsReference}');
    return sb.toString();
  }

  String decision() {
    return '=== Runtime Decision ===\n'
        '1. Keep script packages as stable package system.\n'
        '2. Keep JNI native tools for audited built-in capabilities.\n'
        '3. Research APK-native-library based runtime embedding.\n'
        '4. Test tiny embedded JS engine before Node.\n'
        '5. Only attempt Node after executable/runtime strategy is proven.\n\n'
        'Recommended path: script packages + JNI tools now, embedded JS engine next, Node later.';
  }

  String risks() {
    return '=== Runtime Risks ===\n'
        '  - Android app-writable exec restrictions\n'
        '  - ABI differences\n'
        '  - large APK size\n'
        '  - runtime updates\n'
        '  - package trust\n'
        '  - native crash risk\n'
        '  - localhost/dev-server complexity\n'
        '  - npm package compatibility\n'
        '  - storage/workspace permissions';
  }

  String next() {
    return '=== Runtime Next ===\n'
        'Recommended next milestone: $recommendedNextMilestone\n'
        'Reason: a tiny embedded JS engine can prove JavaScript evaluation through the APK/native-library path without Node.js, npm, package downloads, or app-writable binary execution.\n'
        'Fallback if embedding blocks: v0.31 Tiny APK Native Executable Probe.';
  }

  Future<String> researchDoctor(String sessionId) async {
    final report = await RuntimeCapabilityService().probe(sessionId);
    final docsPresent = _docsPresent();
    final result = RuntimeResearchDoctorResult(
      nativeBridgeAvailable: report.nativeBridgeOk,
      directAppBinExec: report.directAppBinExec,
      abiKnown:
          (report.details['abi']?.isNotEmpty ?? false) &&
          report.details['abi'] != 'unknown',
      docsPresent: docsPresent,
      scriptPackagesSupported: report.scriptsViaShOk,
      previewLocalhostSupported: true,
    );
    final sb = StringBuffer();
    sb.writeln('=== Runtime Research Doctor ===');
    sb.writeln(
      'Native bridge available: ${result.nativeBridgeAvailable ? 'YES' : 'NO'}',
    );
    sb.writeln('Direct app-bin exec status: ${result.directAppBinExec}');
    sb.writeln('ABI known: ${result.abiKnown ? 'YES' : 'NO'}');
    sb.writeln('Docs present: ${result.docsPresent ? 'YES' : 'NO'}');
    sb.writeln(
      'Script packages supported: ${result.scriptPackagesSupported ? 'YES' : 'NO'}',
    );
    sb.writeln(
      'Preview/localhost supported: ${result.previewLocalhostSupported ? 'YES' : 'NO'}',
    );
    sb.writeln('Recommended next proof: $recommendedNextMilestone');
    sb.writeln('Node.js included: NO');
    sb.write('Overall readiness: ${result.overall}');
    return sb.toString();
  }

  bool _docsPresent() {
    const docs = [
      'docs/RUNTIME_STRATEGY.md',
      'docs/BUNDLED_RUNTIME_PROOF.md',
      'docs/NATIVE_TOOL_PROOF.md',
      'docs/PACKAGE_AUTHORING.md',
      'docs/NATIVE_RUNTIME_CANDIDATES.md',
    ];
    return docs.every((path) => File(path).existsSync());
  }

  String _compactRisk(RuntimeCandidate c) {
    if (c.id == 'script-packages') return 'safe';
    if (c.id == 'jni-native-tools') return 'safe';
    if (c.id == 'apk-native-libs') return 'likely';
    if (c.id == 'bundled-executable') return 'needs proof';
    if (c.id == 'embedded-js-engine') return 'research';
    if (c.id == 'node-binary') return 'high risk';
    if (c.id == 'termux-style-prefix') return 'complex';
    if (c.id == 'remote-only') return 'limited';
    return c.riskLevel;
  }
}
