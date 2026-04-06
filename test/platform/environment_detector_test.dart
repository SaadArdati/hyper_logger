import 'package:hyper_logger/src/platform/environment_detector.dart';
import 'package:test/test.dart';

void main() {
  group('EnvironmentDetector.detect', () {
    test('detects Cloud Run when K_SERVICE is set', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'K_SERVICE': 'my-service'},
        ansiSupportOverride: true,
      );
      expect(env, RuntimeEnvironment.cloudRun);
    });

    test('Cloud Run takes precedence over CI', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'K_SERVICE': 'svc', 'CI': 'true'},
        ansiSupportOverride: true,
      );
      expect(env, RuntimeEnvironment.cloudRun);
    });

    test('Cloud Run takes precedence over IDE', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'K_SERVICE': 'svc', 'IDEA_INITIAL_DIRECTORY': '/home'},
        ansiSupportOverride: true,
      );
      expect(env, RuntimeEnvironment.cloudRun);
    });

    // ── CI detection ──────────────────────────────────────────────────────────

    test('detects CI when CI env var is set', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'CI': 'true'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('detects CI via GITHUB_ACTIONS', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'GITHUB_ACTIONS': 'true'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('detects CI via GITLAB_CI', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'GITLAB_CI': 'true'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('detects CI via JENKINS_URL', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'JENKINS_URL': 'http://jenkins'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('detects CI via CIRCLECI', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'CIRCLECI': 'true'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('detects CI via TRAVIS', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'TRAVIS': 'true'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('detects CI via BUILDKITE', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'BUILDKITE': 'true'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('detects CI via TF_BUILD (Azure Pipelines)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'TF_BUILD': 'True'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('detects CI via BITBUCKET_BUILD_NUMBER', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'BITBUCKET_BUILD_NUMBER': '42'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('detects CI via TEAMCITY_VERSION', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'TEAMCITY_VERSION': '2024.1'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('detects CI via CODEBUILD_BUILD_ID', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'CODEBUILD_BUILD_ID': 'build-123'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    test('CI takes precedence over IDE', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'CI': 'true', 'IDEA_INITIAL_DIRECTORY': '/home'},
        ansiSupportOverride: true,
      );
      expect(env, RuntimeEnvironment.ci);
    });

    // ── IDE detection ─────────────────────────────────────────────────────────

    test('detects IDE via IDEA_INITIAL_DIRECTORY (JetBrains)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'IDEA_INITIAL_DIRECTORY': '/home/user/project'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ide);
    });

    test('detects IDE via JETBRAINS_IDE', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'JETBRAINS_IDE': 'IntelliJ IDEA'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ide);
    });

    test('detects IDE via TERM_PROGRAM=vscode', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'TERM_PROGRAM': 'vscode'},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.ide);
    });

    test('TERM_PROGRAM != vscode does not trigger IDE', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'TERM_PROGRAM': 'iTerm.app'},
        ansiSupportOverride: true,
      );
      expect(env, isNot(RuntimeEnvironment.ide));
    });

    // ── Terminal detection ─────────────────────────────────────────────────────

    test('detects terminal when ANSI is supported', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {},
        ansiSupportOverride: true,
      );
      expect(env, RuntimeEnvironment.terminal);
    });

    // ── Plain fallback ────────────────────────────────────────────────────────

    test('falls back to plain when nothing detected', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {},
        ansiSupportOverride: false,
      );
      expect(env, RuntimeEnvironment.plain);
    });
  });

  group('RuntimeEnvironment', () {
    test('has all expected values', () {
      expect(RuntimeEnvironment.values, hasLength(5));
      expect(
        RuntimeEnvironment.values.map((e) => e.name).toList(),
        containsAll(['cloudRun', 'ci', 'ide', 'terminal', 'plain']),
      );
    });
  });
}
