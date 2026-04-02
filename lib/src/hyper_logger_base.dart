import 'dart:async';

import 'package:logging/logging.dart' as logging;
import 'package:meta/meta.dart';

import 'delegates/analytics_delegate.dart';
import 'delegates/crash_reporting_delegate.dart';
import 'hyper_logger_wrapper.dart';
import 'lru_cache.dart';
import 'model/log_message.dart';
import 'model/logger_options.dart';
import 'printer/log_printer.dart';
import 'printer/printer_factory.dart';

/// A log filter predicate. Return `true` to allow the record through,
/// `false` to suppress it.
typedef LogFilter = bool Function(logging.LogRecord record);

/// The central static logging API for [hyper_logger].
///
/// ### Lifecycle
/// 1. Call [init] once at app startup to wire up the printer and optional
///    filter.
/// 2. Optionally call [attachServices] to wire in crash-reporting and/or
///    analytics delegates that receive certain log events.
/// 3. Use [info], [debug], [warning], [error], [fatal], [stopwatch], and
///    [trace] to emit log records.
///
/// ### Design decisions
/// - Every public log method is generic (`<T>`) so that the type parameter
///   is forwarded into [LogMessage.type] for prefix rendering.
/// - A per-type-name [logging.Logger] cache avoids repeated allocations.
/// - Delegate calls ([CrashReportingDelegate], [AnalyticsDelegate]) are
///   fire-and-forget: their futures are ignored so that logging never blocks
///   the caller.
/// - [silent] mode suppresses all printer output without tearing down the
///   logger tree, useful for tests that don't want console noise.
class HyperLogger {
  HyperLogger._();

  // ── private state ──────────────────────────────────────────────────────────

  static bool _initialized = false;
  static bool _silent = false;
  static LogPrinter? _printer;
  static LogFilter? _logFilter;
  static CrashReportingDelegate? _crashReporting;
  static AnalyticsDelegate? _analytics;

  /// Default maximum number of entries in each LRU cache.
  static const int defaultMaxCacheSize = 256;

  /// Cache of [logging.Logger] instances keyed by type name.
  static LruCache<String, logging.Logger> _loggerCache =
      LruCache(defaultMaxCacheSize);

  /// Cache of [HyperLoggerWrapper] instances keyed by type name + options.
  static LruCache<String, HyperLoggerWrapper> _wrapperCache =
      LruCache(defaultMaxCacheSize);

  /// Subscription to the root logger's record stream.
  static StreamSubscription<logging.LogRecord>? _subscription;

  // ── initialization ─────────────────────────────────────────────────────────

  /// Configures HyperLogger. Calling this is optional — the logger
  /// auto-initializes with platform defaults on first use.
  ///
  /// Can be called at any point to reconfigure. Each call replaces the
  /// previous configuration.
  ///
  /// - [printer] receives formatted log records. Defaults to the
  ///   platform-appropriate printer ([ComposablePrinter.terminal] on native,
  ///   [WebConsolePrinter] on web).
  /// - [silent] suppresses all printer output. Useful for tests or production.
  /// - [logFilter] is applied to every record before printing. The
  ///   [defaultLogFilter] is a good starting point.
  /// - [maxCacheSize] controls the maximum number of entries in the internal
  ///   logger and wrapper LRU caches. Defaults to [defaultMaxCacheSize] (256).
  static void init({
    LogPrinter? printer,
    bool silent = false,
    LogFilter? logFilter,
    int maxCacheSize = defaultMaxCacheSize,
  }) {
    _silent = silent;
    _printer =
        printer ?? (_initialized ? _printer : null) ?? createDefaultPrinter();
    _logFilter = logFilter;

    if (_loggerCache.maxSize != maxCacheSize) {
      _loggerCache = LruCache(maxCacheSize);
      _wrapperCache = LruCache(maxCacheSize);
    }

    if (!_initialized) {
      _initialized = true;
      logging.hierarchicalLoggingEnabled = true;
      logging.Logger.root.level = logging.Level.ALL;
      _subscription = logging.Logger.root.onRecord.listen(_handleLogRecord);
    }
  }

  /// Attaches optional service delegates that receive certain log events.
  ///
  /// - [crashReporting] receives [warning] messages (via [CrashReportingDelegate.log])
  ///   and [error]/[fatal] messages (via [CrashReportingDelegate.recordError]).
  /// - [analytics] receives [stopwatch] performance events.
  static void attachServices({
    CrashReportingDelegate? crashReporting,
    AnalyticsDelegate? analytics,
  }) {
    _crashReporting = crashReporting;
    _analytics = analytics;
  }

  /// Detaches all service delegates. Intended for test teardown.
  @visibleForTesting
  static void detachServices() {
    _crashReporting = null;
    _analytics = null;
  }

  /// Resets all static state. Intended for test teardown so that each test
  /// starts with a clean slate.
  @visibleForTesting
  static void reset() {
    _initialized = false;
    _silent = false;
    _printer = null;
    _logFilter = null;
    _crashReporting = null;
    _analytics = null;
    _subscription?.cancel();
    _subscription = null;
    _loggerCache.clear();
    _wrapperCache.clear();
  }

  // ── log filtering ──────────────────────────────────────────────────────────

  /// Default filter that suppresses noisy Supabase GoTrue messages.
  ///
  /// Returns `true` to allow the record, `false` to suppress.
  static bool defaultLogFilter(logging.LogRecord record) {
    final name = record.loggerName.toLowerCase();
    if (name.contains('gotrue')) return false;
    if (name.contains('supabase') && name.contains('auth')) return false;
    return true;
  }

  // ── log level ──────────────────────────────────────────────────────────────

  /// Sets the log level on the root logger. Only records at or above this
  /// level will be emitted.
  ///
  /// Child loggers inherit root's level by default, so this call controls
  /// the effective threshold for all loggers.
  static void setLogLevel(logging.Level level) {
    logging.Logger.root.level = level;
  }

  // ── convenience log methods ────────────────────────────────────────────────

  /// Logs at [logging.Level.FINEST]. Useful for very fine-grained diagnostics.
  static void trace<T>(String message, {Object? data, String? method}) {
    _ensureInitialized();
    if (_silent) return;
    _log<T>(logging.Level.FINEST, message, data: data, method: method);
  }

  /// Logs at [logging.Level.FINE]. The standard debug-level.
  static void debug<T>(String message, {Object? data, String? method}) {
    _ensureInitialized();
    if (_silent) return;
    _log<T>(logging.Level.FINE, message, data: data, method: method);
  }

  /// Logs at [logging.Level.INFO].
  static void info<T>(String message, {Object? data, String? method}) {
    _ensureInitialized();
    if (_silent) return;
    _log<T>(logging.Level.INFO, message, data: data, method: method);
  }

  /// Logs at [logging.Level.WARNING]. Also forwards the message to
  /// [CrashReportingDelegate.log] when attached.
  static void warning<T>(String message, {Object? data, String? method}) {
    _ensureInitialized();
    // Delegates fire regardless of silent mode.
    _crashReporting?.log(message).ignore();
    if (_silent) return;
    _log<T>(logging.Level.WARNING, message, data: data, method: method);
  }

  /// Logs at [logging.Level.SEVERE]. Also forwards to
  /// [CrashReportingDelegate.recordError] unless [skipCrashReporting].
  static void error<T>(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
    bool skipCrashReporting = false,
  }) {
    _ensureInitialized();
    // Delegates fire regardless of silent mode.
    if (!skipCrashReporting) {
      _crashReporting
          ?.recordError(exception ?? message, stackTrace, reason: message)
          .ignore();
    }
    if (_silent) return;
    _log<T>(
      logging.Level.SEVERE,
      message,
      data: data,
      method: method,
      error: exception,
      stackTrace: stackTrace,
    );
  }

  /// Logs at [logging.Level.SHOUT]. Also forwards to
  /// [CrashReportingDelegate.recordError] with `fatal: true`.
  static void fatal<T>(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
  }) {
    _ensureInitialized();
    // Delegates fire regardless of silent mode.
    _crashReporting
        ?.recordError(
          exception ?? message,
          stackTrace,
          fatal: true,
          reason: message,
        )
        .ignore();
    if (_silent) return;
    _log<T>(
      logging.Level.SHOUT,
      message,
      data: data,
      method: method,
      error: exception,
      stackTrace: stackTrace,
    );
  }

  /// Logs the elapsed time of [stopwatch] at [logging.Level.FINE] and
  /// forwards the duration to [AnalyticsDelegate.logPerformance].
  static void stopwatch<T>(
    String message,
    Stopwatch stopwatch, {
    String? method,
  }) {
    _ensureInitialized();
    // Analytics fires regardless of silent mode.
    final elapsed = stopwatch.elapsed;
    _analytics?.logPerformance(message, elapsed, source: T.toString()).ignore();
    if (_silent) return;
    final formatted = '$message (${elapsed.inMilliseconds}ms)';
    _log<T>(logging.Level.INFO, formatted, method: method);
  }

  // ── wrapper factory ────────────────────────────────────────────────────────

  /// Returns a cached [HyperLoggerWrapper] for type [T] with the given
  /// [options].
  ///
  /// The wrapper is cached by a key derived from the type name and options,
  /// so repeated calls with the same arguments return the same instance.
  ///
  /// Accepts either a full [LoggerOptions] object or individual parameters
  /// for convenience. When [options] is provided, all other parameters are
  /// ignored.
  static HyperLoggerWrapper<T> withOptions<T>({
    LoggerOptions? options,
    bool disabled = false,
    logging.Level? minLevel,
    String? tag,
    bool skipCrashReporting = false,
    LogPrinter? printer,
  }) {
    final resolved =
        options ??
        LoggerOptions(
          disabled: disabled,
          minLevel: minLevel,
          tag: tag,
          skipCrashReporting: skipCrashReporting,
          printer: printer,
        );
    final key = resolved.cacheKey(T.toString());
    return _wrapperCache.putIfAbsent(
          key,
          () => HyperLoggerWrapper<T>(options: resolved),
        )
        as HyperLoggerWrapper<T>;
  }

  // ── private helpers ────────────────────────────────────────────────────────

  /// Returns a [logging.Logger] for type [T], creating and caching it on
  /// first access. Child loggers inherit root's level so that
  /// [setLogLevel] controls the threshold globally.
  static logging.Logger _getLogger<T>() {
    final name = T.toString();
    return _loggerCache.putIfAbsent(name, () => logging.Logger(name));
  }

  /// Core log dispatch. Creates a [LogMessage], wraps it in a
  /// [logging.LogRecord] via the per-type [logging.Logger], and publishes.
  ///
  /// [StackTrace.current] is only captured when [method] is null — this avoids
  /// the ~700ns overhead on every log call when the caller already provides a
  /// method name or when the stack trace would be discarded anyway.
  static void _log<T>(
    logging.Level level,
    String message, {
    Object? data,
    String? method,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Skip the expensive StackTrace.current capture when method is already
    // provided — the caller extractor won't be invoked anyway.
    final callerStack = method == null ? StackTrace.current : null;
    final logMessage = LogMessage(
      message,
      T,
      data: data,
      method: method,
      callerStackTrace: callerStack,
    );
    final logger = _getLogger<T>();
    // Pass logMessage as the message parameter (Object?). The logging package
    // will set record.object = logMessage and record.message = logMessage.toString().
    logger.log(level, logMessage, error, stackTrace);
  }

  /// Listener wired to [logging.Logger.root.onRecord].
  static void _handleLogRecord(logging.LogRecord record) {
    if (_silent) return;
    if (_logFilter != null && !_logFilter!(record)) return;
    _printer?.log(record);
  }

  /// Auto-initializes with platform defaults if [init] hasn't been called.
  static void _ensureInitialized() {
    if (!_initialized) init();
  }
}
