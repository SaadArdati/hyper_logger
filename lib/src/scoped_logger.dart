import 'hyper_logger_base.dart';
import 'model/log_level.dart';
import 'model/log_mode.dart';
import 'model/logger_options.dart';

/// Public API surface for typed logging.
///
/// Mirrors the convenience methods on [HyperLogger] but scoped to a single
/// generic type [T]. Used by [ScopedLogger] and testable in isolation.
abstract interface class ScopedLoggerApi<T> {
  void trace(String msg, {Object? data, String? method});

  void debug(String msg, {Object? data, String? method});

  void info(String msg, {Object? data, String? method});

  void warning(String msg, {Object? data, String? method});

  void error(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
    bool? skipCrashReporting,
  });

  void fatal(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
  });

  void stopwatch(String message, Stopwatch stopwatch, {String? method});
}

/// A cached logger scope returned by [HyperLogger.withOptions].
///
/// Behavior is controlled by [options] and the mutable [mode]:
/// - [mode] — controls logging behavior at runtime. See [LogMode].
///   Initialized from [LoggerOptions.mode] but can be changed dynamically.
/// - [LoggerOptions.minLevel] — messages below this level are dropped.
/// - [LoggerOptions.tag] — prepended as `[tag] ` to every message.
/// - [LoggerOptions.skipCrashReporting] — default for [error] calls.
class ScopedLogger<T> implements ScopedLoggerApi<T> {
  /// The options this scope was created with.
  final LoggerOptions options;

  /// The current operating mode. Initialized from [LoggerOptions.mode]
  /// but can be changed at runtime for feature-flag toggling.
  LogMode mode;

  ScopedLogger({required this.options}) : mode = options.mode;

  /// Fires a delegate call with error swallowing, matching the safety
  /// guarantee of [HyperLogger._fireDelegate].
  static void _fireDelegate(Future<void>? Function() fn) {
    try {
      fn()?.catchError((_) {});
    } catch (_) {}
  }

  /// Applies the [options.tag] prefix to [msg] when a tag is set.
  String _tagged(String msg) {
    final tag = options.tag;
    return tag != null ? '[$tag] $msg' : msg;
  }

  /// Returns `true` if the message should be fully suppressed (no delegates).
  bool _suppressed(LogLevel level) {
    if (mode == LogMode.disabled) return true;
    final min = options.minLevel;
    return min != null && level.index < min.index;
  }

  @override
  void trace(String msg, {Object? data, String? method}) {
    if (_suppressed(LogLevel.trace)) return;
    if (mode == LogMode.silent) return;
    HyperLogger.trace<T>(_tagged(msg), data: data, method: method);
  }

  @override
  void debug(String msg, {Object? data, String? method}) {
    if (_suppressed(LogLevel.debug)) return;
    if (mode == LogMode.silent) return;
    HyperLogger.debug<T>(_tagged(msg), data: data, method: method);
  }

  @override
  void info(String msg, {Object? data, String? method}) {
    if (_suppressed(LogLevel.info)) return;
    if (mode == LogMode.silent) return;
    HyperLogger.info<T>(_tagged(msg), data: data, method: method);
  }

  @override
  void warning(String msg, {Object? data, String? method}) {
    if (_suppressed(LogLevel.warning)) return;
    if (mode == LogMode.silent) {
      _fireDelegate(() => HyperLogger.crashReporting?.log(_tagged(msg)));
      return;
    }
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
    if (_suppressed(LogLevel.error)) return;
    final tagged = _tagged(message);
    final skip = skipCrashReporting ?? options.skipCrashReporting;
    if (mode == LogMode.silent) {
      if (!skip) {
        _fireDelegate(
          () => HyperLogger.crashReporting?.recordError(
            exception ?? tagged,
            stackTrace,
            reason: tagged,
          ),
        );
      }
      return;
    }
    HyperLogger.error<T>(
      tagged,
      exception: exception,
      stackTrace: stackTrace,
      data: data,
      method: method,
      skipCrashReporting: skip,
    );
  }

  @override
  void fatal(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
  }) {
    if (_suppressed(LogLevel.fatal)) return;
    final tagged = _tagged(message);
    if (mode == LogMode.silent) {
      _fireDelegate(
        () => HyperLogger.crashReporting?.recordError(
          exception ?? tagged,
          stackTrace,
          fatal: true,
          reason: tagged,
        ),
      );
      return;
    }
    HyperLogger.fatal<T>(
      tagged,
      exception: exception,
      stackTrace: stackTrace,
      data: data,
      method: method,
    );
  }

  @override
  void stopwatch(String message, Stopwatch stopwatch, {String? method}) {
    if (_suppressed(LogLevel.info)) return;
    if (mode == LogMode.silent) return;
    HyperLogger.stopwatch<T>(_tagged(message), stopwatch, method: method);
  }
}
