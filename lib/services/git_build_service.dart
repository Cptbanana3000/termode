import 'runtime_artifact_registry_service.dart';
import 'runtime_binary_package_service.dart';

/// Honest, informational view of the host-side Git NDK build path.
///
/// This service never downloads, compiles, installs, or executes an artifact.
class GitBuildService {
  static const selectedGitVersion = '2.44.0';
  static const sourceArchivePath =
      'tools/git-build/sources/git-2.44.0.tar.xz';
  static const sourceTreePath = 'tools/git-build/sources/git-2.44.0/';
  static const dependencyMode = 'minimal-local-git';
  static const minimalTarget = 'git --version, git init, git status';

  Future<String> status() async {
    final artifact = await RuntimeArtifactRegistryService().gitArtifactStatus();
    final installed = await RuntimeBinaryPackageService().gitInstalled();
    final ready = artifact.available && artifact.installable && installed;
    return '=== Git Build Status ===\n'
        'Target ABI: arm64-v8a\n'
        'Selected Git version: $selectedGitVersion\n'
        'Phase: Git Perl Setup / Build Readiness Finalization\n'
        'Selected path: B (prerequisites partial; source/deps staged; Perl still missing)\n'
        'Build pipeline: prepared\n'
        'Android SDK/NDK: available from v0.51 host check\n'
        'Perl: missing\n'
        'Trusted source: staged (archive present)\n'
        'Expected source archive: $sourceArchivePath\n'
        'Expected source tree: $sourceTreePath\n'
        'Dependency mode: $dependencyMode\n'
        'Minimal target: $minimalTarget\n'
        'Dependencies: staged (zlib archive present)\n'
        'Artifact: ${artifact.status.toLowerCase()}\n'
        'Git installed: ${installed ? 'yes' : 'no'}\n'
        'Host detector: tools/git-build/check_build_env.dart\n'
        'Overall: ${ready ? 'READY' : 'PARTIAL'}';
  }

  String plan() {
    return '=== Git Build Plan ===\n'
        'Selected Git version: $selectedGitVersion\n'
        '1. Stage trusted Git source as archive or tree under tools/git-build/sources/.\n'
        '2. Record license, provenance, trusted_by, acquisition date, and SHA-256.\n'
        '3. Resolve host Perl and record the zlib strategy.\n'
        '4. Create real build-inputs.json from the checked-in example.\n'
        '5. Validate build-inputs.json with host-only checkers.\n'
        '6. Configure the Android NDK arm64-v8a cross compiler.\n'
        '7. Build minimal local Git: $minimalTarget.\n'
        '8. Stage only bin/, lib/, libexec/, and share/ payload files.\n'
        '9. Generate and validate the candidate manifest and SHA-256 hashes.\n'
        '10. Bundle/install, then prove git --version on Android.\n'
        'HTTPS clone/pull/push and credentials are later stages.\n'
        'No source download or compilation occurs inside the Android app.';
  }

  String requirements() {
    return '=== Git Build Requirements ===\n'
        '* Android SDK and NDK\n'
        '* arm64-v8a NDK compiler\n'
        '* make and Perl for the Git build\n'
        '* selected Git version: $selectedGitVersion\n'
        '* trusted Git source with GPL-2.0-only license and SHA-256 provenance\n'
        '* reviewed dependency sources or strategy (zlib first; HTTPS stack later)\n'
        '* reproducible build scripts and logs\n'
        '* artifact manifest and per-file SHA-256 validation\n'
        '* Android install and git --version smoke test\n'
        'Current host record: SDK/NDK found; Git/zlib staged; build-inputs.json present; Perl missing.';
  }

  Future<String> next() async {
    final artifact = await RuntimeArtifactRegistryService().gitArtifactStatus();
    if (artifact.available && artifact.installable) {
      return '=== Git Build Next ===\n'
          'Artifact: AVAILABLE\n'
          'Next: run git-artifact bundle-check, then runtime-pkg install git.\n'
          'After install: git-version, git-exec-probe, git-smoke-test.';
    }
    return '=== Git Build Next ===\n'
        'Artifact: ${artifact.status}\n'
        'Selected Git version: $selectedGitVersion\n'
        'Next: resolve Perl on the host environment. Perl is the only remaining blocker since sources, zlib, and build-inputs.json are ready.\n'
        'Run on host: perl --version\n'
        'Then rerun: dart tools/git-build/check_build_env.dart\n'
        'Next milestone: v0.58 Git Perl Setup Follow-up / Build Readiness.';
  }

  String sourceStatus() {
    return '=== Git Source Status ===\n'
        'Selected Git version: $selectedGitVersion\n'
        'Trusted source: staged (archive present)\n'
        'Expected archive: $sourceArchivePath\n'
        'Expected tree: $sourceTreePath\n'
        'Checksum: matched\n'
        'License: GPL-2.0-only (recorded in manifest)\n'
        'Provenance: recorded\n'
        'Input manifest: present\n'
        'Overall: STAGED';
  }

  String sourcePlan() {
    return '=== Git Source Plan ===\n'
        'Selected Git version: $selectedGitVersion\n'
        '1. Obtain the reviewed Git $selectedGitVersion source archive or tree.\n'
        '2. Place archive at $sourceArchivePath or tree at $sourceTreePath.\n'
        '3. Record license, source URL, provenance, date, and trusted_by.\n'
        '4. Record and verify SHA-256.\n'
        '5. Create build-inputs.json from the non-ready example.\n'
        '6. Run check_build_inputs.dart and verify_git_source.dart.\n'
        '7. Continue to the NDK build only after both pass.';
  }

  String dependenciesStatus() {
    return '=== Git Dependency Status ===\n'
        'Dependency mode: $dependencyMode\n'
        'zlib: required for minimal local Git\n'
        'curl: later for HTTPS\n'
        'openssl/TLS: later for HTTPS\n'
        'expat: planned depending selected features\n'
        'pcre2: optional/planned\n'
        'Dependency sources: staged (zlib archive present)\n'
        'Overall: STAGED';
  }

  String dependenciesPlan() {
    return '=== Git Dependency Plan ===\n'
        'Stage 1 target: $minimalTarget.\n'
        'Stage 1 dependency: zlib strategy/source if the reviewed build requires it.\n'
        'Stage 2: validate local add/commit/log operations.\n'
        'Stage 3: add curl plus a reviewed TLS provider for HTTPS remotes.\n'
        'Stage 4: add credential handling and remote workflow polish.\n'
        'Not in the first target: HTTPS clone/push/pull/fetch, SSH, LFS, submodules, or advanced hooks.';
  }

  String inputs() {
    return '=== Git Build Inputs ===\n'
        'Project-side only. Android cannot inspect host build files.\n'
        'Expected: tools/git-build/build-inputs.json\n'
        'Selected Git version: $selectedGitVersion\n'
        'Source archive: $sourceArchivePath\n'
        'Source tree: $sourceTreePath\n'
        'Dependency mode: $dependencyMode\n'
        'Current recorded state: present\n'
        'build-inputs.json is promoted and verified.\n'
        'Run host script: dart tools/git-build/check_build_inputs.dart';
  }

  Future<String> blockers() async {
    final artifact = await RuntimeArtifactRegistryService().gitArtifactStatus();
    final installed = await RuntimeBinaryPackageService().gitInstalled();
    return '=== Git Build Blockers ===\n'
        '* selected Git version: $selectedGitVersion\n'
        '* Perl missing from the recorded host environment\n'
        '* arm64-v8a artifact: ${artifact.status.toLowerCase()}\n'
        '* Git installed: ${installed ? 'yes' : 'no'}\n'
        'These are development blockers, not beta-fatal app errors.';
  }

  String perlStatus() {
    return '=== Git Perl Status ===\n'
        'Role: host build prerequisite\n'
        'Bundled in app: no\n'
        'Detected: no (last recorded host check: missing)\n'
        'Blocks Git build: yes\n'
        'Blocks Termode beta: no\n'
        'Run on host: perl --version';
  }

  String sourceVersion() {
    return '=== Git Source Version ===\n'
        'Selected Git version: $selectedGitVersion\n'
        'Source staged: yes\n'
        'Expected archive: $sourceArchivePath\n'
        'Expected tree: $sourceTreePath\n'
        'License: GPL-2.0-only must be recorded\n'
        'Checksum: matched\n'
        'Git available: no\n'
        'Note: Git remains unavailable until a validated artifact exists and git --version works.';
  }

  String sourceChecklist() {
    return '=== Git Source Checklist ===\n'
        '1. choose Git version ($selectedGitVersion)\n'
        '2. obtain trusted source\n'
        '3. record checksum\n'
        '4. record license/provenance\n'
        '5. prepare build-inputs.json\n'
        '6. run host checkers\n'
        '7. build arm64 artifact';
  }

  String dependenciesMinimal() {
    return '=== Git Minimal Dependencies ===\n'
        'Stage 1 target: $minimalTarget\n'
        'zlib: required now or documented as provided by the build\n'
        'libcurl: later for HTTPS clone/fetch/push/pull\n'
        'OpenSSL/TLS: later with HTTPS\n'
        'expat: evaluate later\n'
        'pcre2: optional/evaluate later\n'
        'gettext/iconv: avoid if possible for minimal build\n'
        'Perl: host build prerequisite only, not bundled in app';
  }

  String buildNextSteps() {
    return '=== Git Build Next Steps ===\n'
        '1. Install or locate Perl on the host.\n'
        '2. Rerun check_build_env.dart, check_build_inputs.dart,\n'
        '   verify_git_source.dart, check_dependencies.dart.\n'
        '3. Rerun print_build_readiness.dart to verify overall status.\n'
        '4. Attempt the arm64-v8a build using build_git_arm64.dart only after Perl and compiler checks pass.\n'
        'No artifact yet. Git remains unavailable.';
  }

  String buildReadiness() {
    return '=== Git Build Readiness ===\n'
        'Git source: READY\n'
        'zlib: READY\n'
        'build-inputs.json: READY\n'
        'NDK: READY\n'
        'Perl: MISSING\n'
        'Overall: PARTIAL\n'
        'Next: Install or locate Perl on host, then run: perl --version. See docs/GIT_PERL_SETUP_WINDOWS.md';
  }
}
