import 'package:universal_io/io.dart' as io;

/// The detected runtime environment, used by [LogPrinterPresets.automatic]
/// to select the best printer configuration.
///
/// Hierarchy of `final` leaves (extensible — adding a new leaf in a
/// future release is non-breaking for consumers). The built-in
/// leaves are:
///
/// - [GcpEnvironment]: a Google Cloud managed runtime (Cloud Run,
///   App Engine, Cloud Functions). Logs as JSON to stdout — paired
///   with `LogPrinterPresets.gcp`.
/// - [AwsEnvironment]: an AWS managed runtime (Lambda, ECS, Fargate).
///   Logs as JSON to stdout — paired with `LogPrinterPresets.aws`.
/// - [AzureEnvironment]: an Azure managed runtime (App Service,
///   Functions, Container Apps). Logs as JSON to stdout — paired
///   with `LogPrinterPresets.azure`.
/// - [CiEnvironment]: a CI/CD pipeline (GitHub Actions, GitLab CI,
///   Jenkins, etc.). Plain-text grep-friendly output — paired with
///   `LogPrinterPresets.ci`.
/// - [HumanEnvironment]: anything else — terminal, IDE Run Console,
///   piped output, etc. Carries a [TerminalCapabilities] so the preset
///   can compose decorators based on what the target actually
///   supports rather than guessing from a label.
///
/// Round-9 dropped the `sealed` modifier: future versions can add new
/// leaves without breaking consumer pattern-matches that include a
/// `default` arm. Consumers who pattern-match exhaustively without a
/// fallback should be aware that adding leaves is technically
/// non-breaking for compilation but may produce uncovered runtime
/// values.
abstract class RuntimeEnvironment {
  const RuntimeEnvironment();
}

/// Google Cloud managed runtime — Cloud Run (gen 1/2 + jobs), App Engine
/// (standard + flexible), or Cloud Functions (gen 1/2). All ship JSON
/// stdout to Cloud Logging by convention.
final class GcpEnvironment extends RuntimeEnvironment {
  const GcpEnvironment();

  @override
  bool operator ==(Object other) => other is GcpEnvironment;

  @override
  int get hashCode => (GcpEnvironment).hashCode;

  @override
  String toString() => 'GcpEnvironment';
}

/// AWS managed runtime — Lambda, ECS (incl. Fargate), or any container
/// configured to ship stdout to CloudWatch Logs.
final class AwsEnvironment extends RuntimeEnvironment {
  const AwsEnvironment();

  @override
  bool operator ==(Object other) => other is AwsEnvironment;

  @override
  int get hashCode => (AwsEnvironment).hashCode;

  @override
  String toString() => 'AwsEnvironment';
}

/// Azure managed runtime — App Service, Functions, Container Apps.
/// Application Insights ingests stdout JSON with a flexible schema; the
/// paired [LogPrinterPresets.azure] uses a JSON shape compatible with
/// the App Insights `customDimensions` extraction.
final class AzureEnvironment extends RuntimeEnvironment {
  const AzureEnvironment();

  @override
  bool operator ==(Object other) => other is AzureEnvironment;

  @override
  int get hashCode => (AzureEnvironment).hashCode;

  @override
  String toString() => 'AzureEnvironment';
}

/// CI/CD pipeline (GitHub Actions, GitLab CI, Jenkins, CircleCI,
/// Travis, BuildKite, Azure Pipelines, Bitbucket, TeamCity, AWS
/// CodeBuild). Note that AWS CodeBuild also runs as ECS — when both
/// signals are present, [AwsEnvironment] wins because CloudWatch JSON
/// is the better target there.
final class CiEnvironment extends RuntimeEnvironment {
  const CiEnvironment();

  @override
  bool operator ==(Object other) => other is CiEnvironment;

  @override
  int get hashCode => (CiEnvironment).hashCode;

  @override
  String toString() => 'CiEnvironment';
}

/// Anything not matching a cloud or CI environment — interactive
/// terminal, IDE Run Console, piped output, file redirection, etc.
///
/// The accompanying [capabilities] tell the preset what the actual
/// output stream supports so it can compose decorators correctly. A
/// real terminal and an IDE Run Console both deserve color but only
/// the terminal can render box-drawing reliably; both are
/// [HumanEnvironment] but with different [TerminalCapabilities].
final class HumanEnvironment extends RuntimeEnvironment {
  /// Capabilities of the output stream (ANSI, TTY, width).
  final TerminalCapabilities capabilities;

  const HumanEnvironment(this.capabilities);

  @override
  bool operator ==(Object other) =>
      other is HumanEnvironment && other.capabilities == capabilities;

  @override
  int get hashCode => Object.hash(HumanEnvironment, capabilities);

  @override
  String toString() => 'HumanEnvironment($capabilities)';
}

/// Properties of the output stream that drive preset composition.
///
/// Three orthogonal capabilities:
/// - [ansi]: whether the stream supports ANSI escape codes (color,
///   cursor manipulation, etc.).
/// - [tty]: whether the stream is connected to a real terminal. This
///   distinguishes a true terminal (where decorators can rely on a
///   stable line width) from an IDE Run Console (which typically
///   supports ANSI but is a pipe with unknown width) or a file
///   redirection.
/// - [width]: the detected terminal width in columns when the stream
///   is a TTY and the SDK can query it. `null` means width is
///   unknown — usually because [tty] is `false`, occasionally because
///   the underlying VM call threw.
class TerminalCapabilities {
  /// Stream supports ANSI escape codes.
  final bool ansi;

  /// Stream is connected to a real terminal (TTY).
  final bool tty;

  /// Stream's column count, when known. `null` otherwise.
  final int? width;

  const TerminalCapabilities({
    required this.ansi,
    required this.tty,
    this.width,
  });

  @override
  bool operator ==(Object other) =>
      other is TerminalCapabilities &&
      other.ansi == ansi &&
      other.tty == tty &&
      other.width == width;

  @override
  int get hashCode => Object.hash(ansi, tty, width);

  @override
  String toString() =>
      'TerminalCapabilities(ansi: $ansi, tty: $tty, width: $width)';
}

/// Detects the current [RuntimeEnvironment] by inspecting environment
/// variables and stdout capabilities.
///
/// Detection order (first match wins):
/// 1. GCP — `K_SERVICE` (Cloud Run), `GAE_SERVICE` (App Engine),
///    `FUNCTION_NAME` (Cloud Functions gen 1), or `FUNCTION_TARGET`
///    (gen 2).
/// 2. AWS — `AWS_LAMBDA_FUNCTION_NAME` (Lambda) or
///    `ECS_CONTAINER_METADATA_URI[_V4]` (ECS / Fargate).
/// 3. Azure — `WEBSITE_SITE_NAME` (App Service + Functions on
///    `*.azurewebsites.net`), `FUNCTIONS_WORKER_RUNTIME` (any
///    Functions host), or `CONTAINER_APP_NAME` (Container Apps).
/// 4. CI — any of the well-known CI env vars are set.
/// 5. Human — anything else; capabilities derived from stdout
///    introspection plus IDE-launch hints (macOS
///    `__CFBundleIdentifier` matches a JetBrains, Android Studio, or
///    VS Code bundle).
class EnvironmentDetector {
  const EnvironmentDetector();

  /// Per-runtime markers that GCP managed runtimes set in the process
  /// environment. Any one of these constitutes a positive GCP detection.
  static const _gcpKeys = [
    'K_SERVICE', // Cloud Run (gen 1, gen 2, jobs)
    'GAE_SERVICE', // App Engine (standard + flexible)
    'FUNCTION_NAME', // Cloud Functions gen 1
    'FUNCTION_TARGET', // Cloud Functions gen 2 (Cloud Run under the hood)
  ];

  /// Per-runtime markers that AWS managed runtimes set in the process
  /// environment. `AWS_REGION` alone is intentionally NOT used — it's
  /// present in many non-AWS-runtime contexts (e.g. CI runners with AWS
  /// SDK creds) and would over-trigger.
  static const _awsKeys = [
    'AWS_LAMBDA_FUNCTION_NAME', // Lambda
    'ECS_CONTAINER_METADATA_URI_V4', // ECS / Fargate (newer)
    'ECS_CONTAINER_METADATA_URI', // ECS / Fargate (older)
  ];

  /// Per-runtime markers that Azure managed runtimes set in the process
  /// environment.
  static const _azureKeys = [
    'WEBSITE_SITE_NAME', // App Service + Functions (`*.azurewebsites.net`)
    'FUNCTIONS_WORKER_RUNTIME', // Azure Functions (any host)
    'CONTAINER_APP_NAME', // Azure Container Apps
  ];

  static const _ciKeys = [
    'CI',
    'GITHUB_ACTIONS',
    'GITLAB_CI',
    'JENKINS_URL',
    'CIRCLECI',
    'TRAVIS',
    'BUILDKITE',
    'TF_BUILD', // Azure Pipelines
    'BITBUCKET_BUILD_NUMBER',
    'TEAMCITY_VERSION',
    'CODEBUILD_BUILD_ID', // AWS CodeBuild — but ECS markers win first.
  ];

  // Compile-time constant: true when running on the web.
  static const bool _kIsWeb = bool.fromEnvironment('dart.library.js_util');

  /// Detects the current environment.
  ///
  /// - [envOverride]: replaces `Platform.environment` for testing.
  /// - [capabilitiesOverride]: replaces the live stdout-introspecting
  ///   detection with a fixed value (used by the matrix tests for
  ///   [HumanEnvironment]'s capability dispatch).
  RuntimeEnvironment detect({
    Map<String, String>? envOverride,
    TerminalCapabilities? capabilitiesOverride,
  }) {
    final env = envOverride ?? _platformEnv();

    // 1. GCP managed runtimes (Cloud Run, App Engine, Cloud Functions).
    if (_anyKeySet(env, _gcpKeys)) return const GcpEnvironment();

    // 2. AWS managed runtimes (Lambda, ECS, Fargate).
    if (_anyKeySet(env, _awsKeys)) return const AwsEnvironment();

    // 3. Azure managed runtimes (App Service, Functions, Container Apps).
    if (_anyKeySet(env, _azureKeys)) return const AzureEnvironment();

    // 4. CI/CD.
    if (_anyKeySet(env, _ciKeys)) return const CiEnvironment();

    // 4. Human — build capabilities from stdio + env.
    final caps = capabilitiesOverride ?? detectCapabilities(envOverride: env);
    return HumanEnvironment(caps);
  }

  /// Builds [TerminalCapabilities] for the current process by inspecting
  /// stdout + environment variables.
  ///
  /// Exposed as a static so callers who manage their own output stream
  /// (e.g. writing to a file or socket rather than stdout) can build a
  /// preset with hand-rolled capabilities via
  /// `LogPrinterPresets.human(...)`.
  static TerminalCapabilities detectCapabilities({
    Map<String, String>? envOverride,
  }) {
    final env = envOverride ?? _platformEnv();

    // TTY check: stdout connected to a real terminal?
    bool tty;
    if (_kIsWeb) {
      tty = false;
    } else {
      try {
        tty = io.stdioType(io.stdout) == io.StdioType.terminal;
      } catch (_) {
        tty = false;
      }
    }

    // ANSI check.
    //
    // Two paths:
    // 1. We have a TTY → use Dart's `supportsAnsiEscapes` plus a
    //    Windows-specific `ANSICON`/`WT_SESSION` check, gated on a
    //    non-empty `TERM` (the historical signal that a Unix-ish
    //    capability database is reachable).
    // 2. We have NO TTY but the parent process is a known IDE that
    //    pipes ANSI through to its Run Console — override `ansi` to
    //    `true`. This catches IntelliJ Run Configurations and similar
    //    where the integrated terminal would have been a TTY but the
    //    Run Console child process is not.
    bool ansi = false;
    if (tty && !_kIsWeb) {
      final term = env['TERM'] ?? '';
      final isWin = io.Platform.isWindows;
      final winOk =
          isWin && (env['ANSICON'] != null || env['WT_SESSION'] != null);
      try {
        // Round-9 audit fix (M7): on Windows the `TERM` env var is
        // often absent under Windows Terminal even though `WT_SESSION`
        // / `ANSICON` are set and the terminal does support ANSI. The
        // pre-fix predicate `(supportsAnsiEscapes || winOk) &&
        // (term.isNotEmpty || winOk)` collapsed to "must have TERM"
        // when winOk was false, but on Windows we want winOk alone to
        // be sufficient regardless of TERM. Branch the Windows path.
        if (isWin && winOk) {
          ansi = true;
        } else {
          ansi = io.stdout.supportsAnsiEscapes && term.isNotEmpty;
        }
      } catch (_) {
        ansi = winOk;
      }
    } else if (!tty && _isIdeLaunchedConsole(env)) {
      ansi = true;
    }

    // Width: only when the stream is a real TTY.
    int? width;
    if (tty && !_kIsWeb) {
      try {
        if (io.stdout.hasTerminal) {
          width = io.stdout.terminalColumns;
        }
      } catch (_) {
        width = null;
      }
    }

    return TerminalCapabilities(ansi: ansi, tty: tty, width: width);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static Map<String, String> _platformEnv() {
    try {
      return io.Platform.environment;
    } catch (_) {
      return const {};
    }
  }

  /// Returns `true` if any of [keys] is present in [env].
  static bool _anyKeySet(Map<String, String> env, List<String> keys) {
    for (var i = 0; i < keys.length; i++) {
      if (env.containsKey(keys[i])) return true;
    }
    return false;
  }

  /// Returns `true` if stdout is piped from an IDE that supports ANSI in
  /// its Run Console.
  ///
  /// Currently catches macOS hosts: child processes launched by GUI
  /// apps inherit `__CFBundleIdentifier` from the launching app. We
  /// match JetBrains products (`com.jetbrains.*`), Android Studio
  /// (`com.google.android.studio`), and VS Code (`com.microsoft.vscode`
  /// / `com.microsoft.vscodeinsiders`).
  ///
  /// Linux and Windows IDE detection isn't currently wired — those
  /// hosts don't propagate a comparable cross-IDE marker into child
  /// processes' env. Run Configurations there fall back to "no ANSI"
  /// (the safe default for unknown pipe targets).
  static bool _isIdeLaunchedConsole(Map<String, String> env) {
    final cfBundle = (env['__CFBundleIdentifier'] ?? '').toLowerCase();
    if (cfBundle.isEmpty) return false;
    if (cfBundle.contains('jetbrains') ||
        cfBundle.contains('android.studio') ||
        cfBundle.contains('vscode')) {
      return true;
    }
    return false;
  }
}
