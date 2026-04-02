import 'package:universal_io/io.dart' as io;

/// The detected runtime environment, used by [LogPrinterPresets.automatic] to
/// select the best printer configuration.
enum RuntimeEnvironment {
  /// Google Cloud Run (or similar containerised environment).
  cloudRun,

  /// CI/CD pipeline (GitHub Actions, GitLab CI, Jenkins, etc.).
  ci,

  /// IDE run console (JetBrains, VS Code, etc.).
  ide,

  /// Native terminal with ANSI escape code support.
  terminal,

  /// Terminal without ANSI support or unknown environment.
  plain,
}

/// Detects the current [RuntimeEnvironment] by inspecting environment variables
/// and stdout capabilities.
///
/// Detection order (first match wins):
/// 1. Cloud Run — `K_SERVICE` is set (Google Cloud Run container).
/// 2. CI — any of the well-known CI env vars are set.
/// 3. IDE — JetBrains or VS Code terminal markers are present.
/// 4. Terminal — stdout has ANSI support.
/// 5. Plain — fallback.
class EnvironmentDetector {
  const EnvironmentDetector();

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
    'CODEBUILD_BUILD_ID', // AWS CodeBuild
  ];

  // Compile-time constant: true when running on the web.
  static const bool _kIsWeb = bool.fromEnvironment('dart.library.js_util');

  /// Returns `true` if the current environment can render ANSI escape codes.
  ///
  /// Detection rules:
  /// - Web is always `false`.
  /// - On Windows: passes if `ANSICON` or `WT_SESSION` (Windows Terminal) env
  ///   vars are set.
  /// - On other platforms: passes when stdout is connected to a real terminal
  ///   AND [stdout.supportsAnsiEscapes] reports true AND the `TERM` environment
  ///   variable is non-empty.
  static bool detectAnsiSupport() {
    if (_kIsWeb) return false;
    try {
      final isTerminal = io.stdioType(io.stdout) == io.StdioType.terminal;
      final term = io.Platform.environment['TERM'] ?? '';
      final isWin = io.Platform.isWindows;
      final winOk =
          isWin &&
          (io.Platform.environment['ANSICON'] != null ||
              io.Platform.environment['WT_SESSION'] != null);
      return (isTerminal || winOk) &&
          (io.stdout.supportsAnsiEscapes || winOk) &&
          term.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Detects the current environment.
  ///
  /// The optional [envOverride] parameter replaces `Platform.environment` for
  /// testing. Similarly [ansiSupportOverride] replaces [detectAnsiSupport].
  RuntimeEnvironment detect({
    Map<String, String>? envOverride,
    bool? ansiSupportOverride,
  }) {
    final env = envOverride ?? _platformEnv();

    // 1. Cloud Run / containerised Google Cloud
    if (env.containsKey('K_SERVICE')) return RuntimeEnvironment.cloudRun;

    // 2. CI/CD
    if (_isCi(env)) return RuntimeEnvironment.ci;

    // 3. IDE
    if (_isIde(env)) return RuntimeEnvironment.ide;

    // 4. Terminal with ANSI
    final ansi = ansiSupportOverride ?? detectAnsiSupport();
    if (ansi) return RuntimeEnvironment.terminal;

    // 5. Fallback
    return RuntimeEnvironment.plain;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static Map<String, String> _platformEnv() {
    try {
      return io.Platform.environment;
    } catch (_) {
      return const {};
    }
  }

  /// Returns `true` if any well-known CI environment variable is set.
  static bool _isCi(Map<String, String> env) {
    for (int i = 0; i < _ciKeys.length; i++) {
      if (env.containsKey(_ciKeys[i])) return true;
    }
    return false;
  }

  /// Returns `true` if the environment looks like an IDE run console.
  static bool _isIde(Map<String, String> env) {
    if (env.containsKey('IDEA_INITIAL_DIRECTORY')) return true;
    if (env.containsKey('JETBRAINS_IDE')) return true;
    if (env['TERM_PROGRAM'] == 'vscode') return true;
    return false;
  }
}
