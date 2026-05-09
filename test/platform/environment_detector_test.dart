import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

const _humanFallback = TerminalCapabilities(
  ansi: false,
  tty: false,
  width: null,
);

void main() {
  group('EnvironmentDetector.detect', () {
    // ── GCP detection ─────────────────────────────────────────────────────────

    test('detects GCP when K_SERVICE is set (Cloud Run)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'K_SERVICE': 'my-service'},
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const GcpEnvironment());
    });

    test('detects GCP when GAE_SERVICE is set (App Engine)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'GAE_SERVICE': 'frontend'},
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const GcpEnvironment());
    });

    test('detects GCP when FUNCTION_NAME is set (Cloud Functions gen 1)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'FUNCTION_NAME': 'helloHttp'},
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const GcpEnvironment());
    });

    test('detects GCP when FUNCTION_TARGET is set (Cloud Functions gen 2)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'FUNCTION_TARGET': 'helloPubSub'},
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const GcpEnvironment());
    });

    test('GCP takes precedence over CI', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'K_SERVICE': 'svc', 'CI': 'true'},
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const GcpEnvironment());
    });

    // ── AWS detection ─────────────────────────────────────────────────────────

    test('detects AWS when AWS_LAMBDA_FUNCTION_NAME is set (Lambda)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {'AWS_LAMBDA_FUNCTION_NAME': 'my-fn'},
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const AwsEnvironment());
    });

    test('detects AWS via ECS_CONTAINER_METADATA_URI_V4 (Fargate)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {
          'ECS_CONTAINER_METADATA_URI_V4': 'http://169.254.170.2/v4/abc',
        },
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const AwsEnvironment());
    });

    test('detects AWS via ECS_CONTAINER_METADATA_URI (legacy ECS)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {
          'ECS_CONTAINER_METADATA_URI': 'http://169.254.170.2/v3/abc',
        },
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const AwsEnvironment());
    });

    // ── Azure detection ──────────────────────────────────────────────────────

    test('detects Azure via WEBSITE_SITE_NAME (App Service / Functions)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: const {'WEBSITE_SITE_NAME': 'my-app'},
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const AzureEnvironment());
    });

    test('detects Azure via FUNCTIONS_WORKER_RUNTIME', () {
      final env = const EnvironmentDetector().detect(
        envOverride: const {'FUNCTIONS_WORKER_RUNTIME': 'dart'},
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const AzureEnvironment());
    });

    test('detects Azure via CONTAINER_APP_NAME', () {
      final env = const EnvironmentDetector().detect(
        envOverride: const {'CONTAINER_APP_NAME': 'svc-1'},
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const AzureEnvironment());
    });

    test('GCP takes precedence over Azure when both are set', () {
      final env = const EnvironmentDetector().detect(
        envOverride: const {
          'K_SERVICE': 'gcp-svc',
          'WEBSITE_SITE_NAME': 'azure-app',
        },
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const GcpEnvironment());
    });

    test('AWS takes precedence over Azure when both are set', () {
      final env = const EnvironmentDetector().detect(
        envOverride: const {
          'AWS_LAMBDA_FUNCTION_NAME': 'lambda-fn',
          'WEBSITE_SITE_NAME': 'azure-app',
        },
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const AwsEnvironment());
    });

    test('AWS takes precedence over CI (CodeBuild on ECS)', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {
          'ECS_CONTAINER_METADATA_URI_V4': 'http://x',
          'CODEBUILD_BUILD_ID': 'codebuild:abc',
        },
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const AwsEnvironment());
    });

    test('GCP takes precedence over AWS when both signals are set', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {
          'K_SERVICE': 'gcp-svc',
          'AWS_LAMBDA_FUNCTION_NAME': 'lambda-fn',
        },
        capabilitiesOverride: _humanFallback,
      );
      expect(env, const GcpEnvironment());
    });

    // ── CI detection ──────────────────────────────────────────────────────────

    for (final key in const [
      'CI',
      'GITHUB_ACTIONS',
      'GITLAB_CI',
      'JENKINS_URL',
      'CIRCLECI',
      'TRAVIS',
      'BUILDKITE',
      'TF_BUILD',
      'BITBUCKET_BUILD_NUMBER',
      'TEAMCITY_VERSION',
      'CODEBUILD_BUILD_ID',
    ]) {
      test('detects CI via $key', () {
        final env = const EnvironmentDetector().detect(
          envOverride: {key: 'true'},
          capabilitiesOverride: _humanFallback,
        );
        expect(env, const CiEnvironment());
      });
    }

    // ── Human + capability dispatch ───────────────────────────────────────────

    test('falls through to HumanEnvironment with the supplied capabilities',
        () {
      const caps = TerminalCapabilities(ansi: true, tty: true, width: 120);
      final env = const EnvironmentDetector().detect(
        envOverride: {},
        capabilitiesOverride: caps,
      );
      expect(env, const HumanEnvironment(caps));
    });

    test('HumanEnvironment carries no-ansi / no-tty fallback as plain', () {
      final env = const EnvironmentDetector().detect(
        envOverride: {},
        capabilitiesOverride: _humanFallback,
      );
      expect(env, isA<HumanEnvironment>());
      final h = env as HumanEnvironment;
      expect(h.capabilities.ansi, isFalse);
      expect(h.capabilities.tty, isFalse);
      expect(h.capabilities.width, isNull);
    });
  });

  group('EnvironmentDetector.detectCapabilities', () {
    // The static `detectCapabilities` is the live stdio + env hook —
    // most tests above bypass it via `capabilitiesOverride`. These
    // tests pin the env-derived branches that *don't* depend on stdio.

    test(
      'IntelliJ-launched child (macOS __CFBundleIdentifier) is '
      'recognized as ANSI-capable even when stdout is a pipe',
      () {
        // The whole point of the round-8 refactor: IntelliJ Run
        // Configurations are not TTYs, but their Run Console DOES
        // render ANSI. The bundle-ID heuristic kicks in to flip
        // `ansi: true` for known IDE bundles.
        final caps = EnvironmentDetector.detectCapabilities(
          envOverride: const {
            '__CFBundleIdentifier': 'com.jetbrains.intellij',
          },
        );
        // tty depends on the live test runner's stdout; we don't pin
        // that. We DO pin that ansi flipped on for the IntelliJ case.
        if (!caps.tty) {
          expect(caps.ansi, isTrue,
              reason: 'IntelliJ bundle ID without a TTY must enable '
                  'ANSI for the Run Console preset');
        }
      },
    );

    test(
      'Android Studio child (__CFBundleIdentifier match) → ANSI on '
      'in non-TTY contexts',
      () {
        final caps = EnvironmentDetector.detectCapabilities(
          envOverride: const {
            '__CFBundleIdentifier': 'com.google.android.studio',
          },
        );
        if (!caps.tty) {
          expect(caps.ansi, isTrue);
        }
      },
    );

    test(
      'VS Code child (__CFBundleIdentifier match) → ANSI on in '
      'non-TTY contexts',
      () {
        final caps = EnvironmentDetector.detectCapabilities(
          envOverride: const {
            '__CFBundleIdentifier': 'com.microsoft.VSCode',
          },
        );
        if (!caps.tty) {
          expect(caps.ansi, isTrue);
        }
      },
    );

    test(
      'unknown bundle ID without TTY produces no-ANSI capabilities',
      () {
        final caps = EnvironmentDetector.detectCapabilities(
          envOverride: const {
            '__CFBundleIdentifier': 'com.example.SomeOtherApp',
          },
        );
        if (!caps.tty) {
          expect(caps.ansi, isFalse,
              reason: 'unrecognized bundle IDs fall through to the safe '
                  'no-ANSI default — guards against false positives');
        }
      },
    );

    test('empty env without TTY produces flat-false capabilities', () {
      final caps = EnvironmentDetector.detectCapabilities(
        envOverride: const {},
      );
      if (!caps.tty) {
        expect(caps.ansi, isFalse);
        expect(caps.width, isNull);
      }
    });
  });

  group('TerminalCapabilities', () {
    test('value-equals on ansi/tty/width', () {
      expect(
        const TerminalCapabilities(ansi: true, tty: false, width: 80),
        equals(const TerminalCapabilities(ansi: true, tty: false, width: 80)),
      );
      expect(
        const TerminalCapabilities(ansi: true, tty: true),
        isNot(equals(const TerminalCapabilities(ansi: true, tty: false))),
      );
    });

    test('toString surfaces all three fields', () {
      const caps = TerminalCapabilities(ansi: true, tty: false, width: 100);
      expect(caps.toString(), contains('ansi: true'));
      expect(caps.toString(), contains('tty: false'));
      expect(caps.toString(), contains('width: 100'));
    });
  });

  group('RuntimeEnvironment sealed hierarchy', () {
    test('GcpEnvironment is value-equal to itself', () {
      expect(const GcpEnvironment(), equals(const GcpEnvironment()));
    });
    test('AwsEnvironment is value-equal to itself', () {
      expect(const AwsEnvironment(), equals(const AwsEnvironment()));
    });
    test('AzureEnvironment is value-equal to itself', () {
      expect(const AzureEnvironment(), equals(const AzureEnvironment()));
    });
    test('CiEnvironment is value-equal to itself', () {
      expect(const CiEnvironment(), equals(const CiEnvironment()));
    });
    test('HumanEnvironment compares by capabilities', () {
      const a = HumanEnvironment(_humanFallback);
      const b = HumanEnvironment(_humanFallback);
      const c = HumanEnvironment(
        TerminalCapabilities(ansi: true, tty: true),
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
