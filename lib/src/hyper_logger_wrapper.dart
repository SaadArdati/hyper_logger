import 'package:logging/logging.dart' as logging;

import 'hyper_logger_base.dart';
import 'model/logger_options.dart';

/// Public API surface for typed logging.
///
/// Mirrors the convenience methods on [HyperLogger] but scoped to a single
/// generic type [T]. Used by [HyperLoggerWrapper] and testable in isolation.
abstract interface class HyperLoggerApi<T> {
  void info(String msg, {Object? data, String? method});

  void debug(String msg, {Object? data, String? method});

  void warning(String msg, {Object? data, String? method});

  void error(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
    bool? skipCrashReporting,
  });

  void stopwatch(String message, Stopwatch stopwatch, {String? method});
}

/// A cached, optionally disabled logger wrapper returned by
/// [HyperLogger.withOptions].
///
/// Behavior is controlled by [options]:
/// - [LoggerOptions.disabled] — every method becomes a no-op.
/// - [LoggerOptions.minLevel] — messages below this level are dropped.
/// - [LoggerOptions.tag] — prepended as `[tag] ` to every message.
/// - [LoggerOptions.skipCrashReporting] — default for [error] calls.
/// - [LoggerOptions.printer] — per-wrapper printer override (not yet wired
///   to HyperLogger's dispatch — reserved for future use).
class HyperLoggerWrapper<T> implements HyperLoggerApi<T> {
  /// The options this wrapper was created with.
  final LoggerOptions options;

  HyperLoggerWrapper({required this.options});

  /// Applies the [options.tag] prefix to [msg] when a tag is set.
  String _tagged(String msg) {
    final tag = options.tag;
    return tag != null ? '[$tag] $msg' : msg;
  }

  /// Returns `true` if the message should be suppressed.
  bool _suppressed(logging.Level level) {
    if (options.disabled) return true;
    final min = options.minLevel;
    return min != null && level < min;
  }

  @override
  void info(String msg, {Object? data, String? method}) {
    if (_suppressed(logging.Level.INFO)) return;
    HyperLogger.info<T>(_tagged(msg), data: data, method: method);
  }

  @override
  void debug(String msg, {Object? data, String? method}) {
    if (_suppressed(logging.Level.FINE)) return;
    HyperLogger.debug<T>(_tagged(msg), data: data, method: method);
  }

  @override
  void warning(String msg, {Object? data, String? method}) {
    if (_suppressed(logging.Level.WARNING)) return;
    HyperLogger.warning<T>(_tagged(msg), data: data, method: method);
  }

  @override
  void error(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
    bool? skipCrashReporting,
  }) {
    if (_suppressed(logging.Level.SEVERE)) return;
    HyperLogger.error<T>(
      _tagged(message),
      exception: exception,
      stackTrace: stackTrace,
      data: data,
      method: method,
      // Caller override wins, otherwise fall back to options default.
      skipCrashReporting: skipCrashReporting ?? options.skipCrashReporting,
    );
  }

  @override
  void stopwatch(String message, Stopwatch stopwatch, {String? method}) {
    if (_suppressed(logging.Level.INFO)) return;
    HyperLogger.stopwatch<T>(_tagged(message), stopwatch, method: method);
  }
}
