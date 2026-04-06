import 'package:logging/logging.dart' as logging;

/// Log severity levels for [HyperLogger].
///
/// Provides a clean public API without exposing the `logging` package's
/// [logging.Level] type. Each value maps 1:1 to a [logging.Level] constant.
enum LogLevel implements Comparable<LogLevel> {
  /// Very fine-grained diagnostics. Maps to [logging.Level.FINEST].
  trace,

  /// Standard debug output. Maps to [logging.Level.FINE].
  debug,

  /// Notable runtime events. Maps to [logging.Level.INFO].
  info,

  /// Unexpected but recoverable situations. Maps to [logging.Level.WARNING].
  warning,

  /// Operation failures. Maps to [logging.Level.SEVERE].
  error,

  /// Unrecoverable failures. Maps to [logging.Level.SHOUT].
  fatal;

  /// Short, human-readable severity name for display (e.g. timestamps, JSON).
  String get label => switch (this) {
    trace => 'TRACE',
    debug => 'DEBUG',
    info => 'INFO',
    warning => 'WARN',
    error => 'ERROR',
    fatal => 'FATAL',
  };

  /// Default emoji prefix for this level. Empty string means no emoji.
  String get emoji => switch (this) {
    trace => '',
    debug => '🐛',
    info => '💡',
    warning => '⚠️',
    error => '⛔',
    fatal => '👾',
  };

  /// Converts this [LogLevel] to the corresponding [logging.Level].
  logging.Level toLoggingLevel() => switch (this) {
    trace => logging.Level.FINEST,
    debug => logging.Level.FINE,
    info => logging.Level.INFO,
    warning => logging.Level.WARNING,
    error => logging.Level.SEVERE,
    fatal => logging.Level.SHOUT,
  };

  /// Converts a [logging.Level] to the closest [LogLevel].
  static LogLevel fromLoggingLevel(logging.Level level) {
    if (level <= logging.Level.FINER) return trace;
    if (level <= logging.Level.FINE) return debug;
    if (level <= logging.Level.INFO) return info;
    if (level <= logging.Level.WARNING) return warning;
    if (level <= logging.Level.SEVERE) return error;
    return fatal;
  }

  @override
  int compareTo(LogLevel other) => index.compareTo(other.index);
}
