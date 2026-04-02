import 'package:universal_io/io.dart' as io;

// Compile-time constant: true when running on the web.
const bool _kIsWeb = bool.fromEnvironment('dart.library.js_util');

/// Returns `true` if the current environment can render ANSI escape codes.
///
/// Detection rules:
/// - Web is always `false`.
/// - On Windows: passes if `ANSICON` or `WT_SESSION` (Windows Terminal) env
///   vars are set.
/// - On other platforms: passes when stdout is connected to a real terminal
///   AND [stdout.supportsAnsiEscapes] reports true AND the `TERM` environment
///   variable is non-empty.
bool detectAnsiSupport() {
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
