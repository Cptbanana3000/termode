import 'runtime_artifact_registry_service.dart';
import 'runtime_binary_package_service.dart';

/// Honest, informational view of the host-side Git NDK build path.
///
/// This service never downloads, compiles, installs, or executes an artifact.
class GitBuildService {
  Future<String> status() async {
    final artifact = await RuntimeArtifactRegistryService().gitArtifactStatus();
    final installed = await RuntimeBinaryPackageService().gitInstalled();
    final ready = artifact.available && artifact.installable && installed;
    return '=== Git Build Status ===\n'
        'Target ABI: arm64-v8a\n'
        'Phase: source/dependency acquisition\n'
        'Selected path: B (toolchain present; acquisition incomplete)\n'
        'Build pipeline: prepared\n'
        'Android SDK/NDK: available from v0.51 host check\n'
        'Perl: missing\n'
        'Trusted source: missing\n'
        'Dependencies: missing\n'
        'Artifact: ${artifact.status.toLowerCase()}\n'
        'Git installed: ${installed ? 'yes' : 'no'}\n'
        'Host detector: tools/git-build/check_build_env.dart\n'
        'Overall: ${ready ? 'READY' : 'PARTIAL'}';
  }

  String plan() {
    return '=== Git Build Plan ===\n'
        '1. Acquire trusted Git source with version, license, and checksum.\n'
        '2. Acquire reviewed dependency sources and record provenance.\n'
        '3. Validate build-inputs.json with host-only checkers.\n'
        '4. Configure the Android NDK arm64-v8a cross compiler.\n'
        '5. Build minimal local Git: --version, init, and status.\n'
        '6. Stage only bin/, lib/, libexec/, and share/ payload files.\n'
        '7. Generate and validate the candidate manifest and SHA-256 hashes.\n'
        '8. Bundle/install, then prove git --version on Android.\n'
        'HTTPS clone/pull/push and credentials are later stages.\n'
        'No source download or compilation occurs inside the Android app.';
  }

  String requirements() {
    return '=== Git Build Requirements ===\n'
        '* Android SDK and NDK\n'
        '* arm64-v8a NDK compiler\n'
        '* make and Perl for the Git build\n'
        '* trusted Git source with license and SHA-256 checksum provenance\n'
        '* reviewed dependency sources (zlib first; HTTPS stack later)\n'
        '* reproducible build scripts and logs\n'
        '* artifact manifest and per-file SHA-256 validation\n'
        '* Android install and git --version smoke test\n'
        'Current host record: SDK/NDK found; Perl and source/dependencies missing.';
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
        'Next: create reviewed Git and dependency inputs from the templates.\n'
        'Run: dart tools/git-build/check_build_inputs.dart\n'
        'Run: dart tools/git-build/verify_git_source.dart\n'
        'Next milestone: v0.53 Git Source + Dependency Preparation.';
  }

  String sourceStatus() {
    return '=== Git Source Status ===\n'
        'Trusted source: missing\n'
        'Version: unknown\n'
        'Checksum: missing\n'
        'Input manifest: project-side build-inputs.json missing\n'
        'Overall: MISSING';
  }

  String sourcePlan() {
    return '=== Git Source Plan ===\n'
        '1. Choose and record a Git version.\n'
        '2. Acquire a trusted upstream archive or project-controlled tree.\n'
        '3. Record license, source URL, provenance, date, and trusted_by.\n'
        '4. Record and verify SHA-256.\n'
        '5. Place it under tools/git-build/sources/.\n'
        '6. Create build-inputs.json from the non-ready example.\n'
        '7. Run check_build_inputs.dart and verify_git_source.dart.\n'
        '8. Continue to the NDK build only after both pass.';
  }

  String dependenciesStatus() {
    return '=== Git Dependency Status ===\n'
        'zlib: required for minimal local Git\n'
        'curl: later for HTTPS\n'
        'openssl/TLS: later for HTTPS\n'
        'expat: planned depending selected features\n'
        'pcre2: optional/planned\n'
        'Dependency sources: missing\n'
        'Overall: PLANNED';
  }

  String dependenciesPlan() {
    return '=== Git Dependency Plan ===\n'
        'Stage 1: build enough for git --version, git init, and git status.\n'
        'Stage 2: validate local add/commit/log operations.\n'
        'Stage 3: add curl plus a reviewed TLS provider for HTTPS remotes.\n'
        'Stage 4: add credential handling and remote workflow polish.\n'
        'Not in the first target: HTTPS clone/push/pull/fetch, SSH, LFS, submodules, or advanced hooks.';
  }

  String inputs() {
    return '=== Git Build Inputs ===\n'
        'Project-side only. Android cannot inspect host build files.\n'
        'Expected: tools/git-build/build-inputs.json\n'
        'Current recorded state: missing\n'
        'Example is template-only and is not build-ready.\n'
        'Run host script: dart tools/git-build/check_build_inputs.dart';
  }

  Future<String> blockers() async {
    final artifact = await RuntimeArtifactRegistryService().gitArtifactStatus();
    final installed = await RuntimeBinaryPackageService().gitInstalled();
    return '=== Git Build Blockers ===\n'
        '* trusted Git source missing\n'
        '* dependency sources missing\n'
        '* Perl missing from the recorded host environment\n'
        '* arm64-v8a artifact: ${artifact.status.toLowerCase()}\n'
        '* Git installed: ${installed ? 'yes' : 'no'}\n'
        'These are development blockers, not beta-fatal app errors.';
  }
}
