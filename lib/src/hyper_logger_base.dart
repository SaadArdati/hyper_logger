import 'dart:async';

import 'package:logging/logging.dart' as logging;

import 'delegates/crash_reporting_delegate.dart';
import 'scoped_logger.dart';
import 'lru_cache.dart';
import 'model/log_entry.dart';
import 'model/log_level.dart';
import 'model/log_message.dart';
import 'model/log_mode.dart';
import 'model/logger_options.dart';
import 'printer/log_printer.dart';
import 'printer/printer_factory.dart';

/// A log filter predicate. Return `true` to allow the entry through,
/// `false` to suppress it.
typedef LogFilter = bool Function(LogEntry entry);

/// The central static logging API for [hyper_logger].
///
/// ### Lifecycle
/// 1. Call [init] once at app startup to wire up the printer and optional
///    filter.
/// 2. Optionally call [attachServices] to wire in a crash-reporting
///    delegate that receives certain log events.
/// 3. Use [info], [debug], [warning], [error], [fatal], [stopwatch], and
///    [trace] to emit log records.
///
/// ### Design decisions
/// - Every public log method is generic (`<T>`) so that the type parameter
///   is forwarded into [LogMessage.type] for prefix rendering.
/// - A per-type-name [logging.Logger] cache avoids repeated allocations.
/// - Delegate calls ([CrashReportingDelegate]) are fire-and-forget: their
///   futures are ignored so that logging never blocks the caller.
/// - [LogMode] controls global behavior: [LogMode.enabled] for normal
///   operation, [LogMode.silent] to suppress printer output (delegates
///   still fire), or [LogMode.disabled] for a complete no-op.
class HyperLogger {
  HyperLogger._();

  // ── private state ──────────────────────────────────────────────────────────

  static bool _initialized = false;
  static LogMode _mode = LogMode.enabled;
  static bool _captureStackTrace = true;
  static LogPrinter? _printer;
  static LogFilter? _logFilter;
  static CrashReportingDelegate? _crashReporting;

  /// Default maximum number of entries in each LRU cache.
  static const int defaultMaxCacheSize = 256;

  /// Cache of [logging.Logger] instances keyed by type name.
  static LruCache<String, logging.Logger> _loggerCache = LruCache(
    defaultMaxCacheSize,
  );

  /// Cache of [ScopedLogger] instances keyed by type name + options.
  static LruCache<String, ScopedLogger> _wrapperCache = LruCache(
    defaultMaxCacheSize,
  );

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
  /// - [mode] controls global logging behavior. See [LogMode].
  /// - [logFilter] is applied to every record before printing.
  /// - [captureStackTrace] when `true` (default), captures [StackTrace.current]
  ///   on every log call that doesn't provide a `method:` parameter, enabling
  ///   automatic caller extraction. Set to `false` to skip the ~700ns overhead.
  /// - [configureLoggingPackage] when `true` (default), sets
  ///   `hierarchicalLoggingEnabled = true` and `Logger.root.level = Level.ALL`
  ///   on the underlying `package:logging`. Set to `false` if another package
  ///   manages the logging configuration and you don't want hyper_logger to
  ///   override it.
  /// - [maxCacheSize] controls the maximum number of entries in the internal
  ///   logger and wrapper LRU caches. Defaults to [defaultMaxCacheSize] (256).
  static void init({
    LogPrinter? printer,
    LogMode mode = LogMode.enabled,
    LogFilter? logFilter,
    bool captureStackTrace = true,
    bool configureLoggingPackage = true,
    int maxCacheSize = defaultMaxCacheSize,
  }) {
    _mode = mode;
    _captureStackTrace = captureStackTrace;
    _printer =
        printer ?? (_initialized ? _printer : null) ?? createDefaultPrinter();
    _logFilter = logFilter;

    if (_loggerCache.maxSize != maxCacheSize) {
      _loggerCache = LruCache(maxCacheSize);
      _wrapperCache = LruCache(maxCacheSize);
    }

    if (!_initialized) {
      _initialized = true;
      if (configureLoggingPackage) {
        logging.hierarchicalLoggingEnabled = true;
        logging.Logger.root.level = logging.Level.ALL;
      }
      _subscription = logging.Logger.root.onRecord.listen(_handleLogRecord);
    }
  }

  /// Attaches the crash-reporting delegate that receives certain log events.
  ///
  /// [crashReporting] receives [warning] messages (via [CrashReportingDelegate.log])
  /// and [error]/[fatal] messages (via [CrashReportingDelegate.recordError]).
  static void attachServices({CrashReportingDelegate? crashReporting}) {
    _crashReporting = crashReporting;
  }

  /// The currently attached crash-reporting delegate, or `null`.
  static CrashReportingDelegate? get crashReporting => _crashReporting;

  /// Detaches all service delegates. Intended for test teardown.
  static void detachServices() {
    _crashReporting = null;
  }

  /// Resets all static state. Intended for test teardown so that each test
  /// starts with a clean slate.
  static void reset() {
    _initialized = false;
    _mode = LogMode.enabled;
    _captureStackTrace = true;
    _printer = null;
    _logFilter = null;
    _crashReporting = null;
    _subscription?.cancel();
    _subscription = null;
    _loggerCache.clear();
    _wrapperCache.clear();
  }

  // ── log level ──────────────────────────────────────────────────────────────

  /// Returns `true` if a log call at [level] would produce output.
  ///
  /// Use to gate expensive argument construction:
  /// ```dart
  /// if (HyperLogger.isEnabled(LogLevel.debug)) {
  ///   final data = computeExpensiveDebugInfo();
  ///   HyperLogger.debug<MyClass>('State dump', data: data);
  /// }
  /// ```
  static bool isEnabled(LogLevel level) {
    if (_mode == LogMode.disabled) return false;
    if (_mode == LogMode.silent) return false;
    _ensureInitialized();
    return logging.Logger.root.level <= level.toLoggingLevel();
  }

  /// Sets the log level on the root logger. Only records at or above this
  /// level will be emitted.
  ///
  /// Child loggers inherit root's level by default, so this call controls
  /// the effective threshold for all loggers.
  static void setLogLevel(LogLevel level) {
    logging.Logger.root.level = level.toLoggingLevel();
  }

  // ── convenience log methods ────────────────────────────────────────────────

  /// Logs at [logging.Level.FINEST] — the most verbose level.
  ///
  /// Use for very fine-grained diagnostics you'd only enable when actively
  /// investigating a specific code path. Unlike [debug], trace output is
  /// typically too noisy for day-to-day development.
  ///
  /// ```dart
  /// HyperLogger.trace<JsonParser>('Token buffer state', data: buffer);
  /// ```
  static void trace<T>(String message, {Object? data, String? method}) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    if (_mode == LogMode.silent) return;
    _log<T>(logging.Level.FINEST, message, data: data, method: method);
  }

  /// Logs at [logging.Level.FINE] — the standard debug level.
  ///
  /// Use for information that is helpful during development but should not
  /// appear in production. Good for tracking control flow, intermediate
  /// values, and "I got here" markers.
  ///
  /// ```dart
  /// HyperLogger.debug<AuthService>('Token refreshed', data: claims);
  /// ```
  static void debug<T>(String message, {Object? data, String? method}) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    if (_mode == LogMode.silent) return;
    _log<T>(logging.Level.FINE, message, data: data, method: method);
  }

  /// Logs at [logging.Level.INFO] — notable runtime events.
  ///
  /// Use for milestones that operators or developers would want to see in
  /// normal operation: service started, user signed in, sync completed.
  /// This is the default "interesting things happened" level.
  ///
  /// ```dart
  /// HyperLogger.info<SyncEngine>('Pull completed', data: {'rows': count});
  /// ```
  static void info<T>(String message, {Object? data, String? method}) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    if (_mode == LogMode.silent) return;
    _log<T>(logging.Level.INFO, message, data: data, method: method);
  }

  /// Logs at [logging.Level.WARNING] — something unexpected that the app
  /// can recover from.
  ///
  /// Use when the system hit a degraded path but continued operating:
  /// missing optional config, retryable network failure, deprecated API
  /// usage. Forwards to [CrashReportingDelegate.log] when attached.
  ///
  /// ```dart
  /// HyperLogger.warning<CacheManager>('Stale entry evicted', data: key);
  /// ```
  static void warning<T>(String message, {Object? data, String? method}) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    // Delegates fire in silent mode.
    _fireDelegate(() => _crashReporting?.log(message));
    if (_mode == LogMode.silent) return;
    _log<T>(logging.Level.WARNING, message, data: data, method: method);
  }

  /// Logs at [logging.Level.SEVERE] — a failure the user or operator
  /// should know about.
  ///
  /// Use when an operation failed and could not complete: unhandled
  /// exception, failed HTTP request that exhausted retries, corrupt data.
  /// Forwards to [CrashReportingDelegate.recordError] unless
  /// [skipCrashReporting] is set.
  ///
  /// ```dart
  /// HyperLogger.error<PaymentService>(
  ///   'Charge failed',
  ///   exception: e,
  ///   stackTrace: st,
  ///   data: {'orderId': order.id},
  /// );
  /// ```
  static void error<T>(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
    bool skipCrashReporting = false,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    // Delegates fire in silent mode.
    if (!skipCrashReporting) {
      _fireDelegate(
        () => _crashReporting?.recordError(
          exception ?? message,
          stackTrace,
          reason: message,
        ),
      );
    }
    if (_mode == LogMode.silent) return;
    _log<T>(
      logging.Level.SEVERE,
      message,
      data: data,
      method: method,
      error: exception,
      stackTrace: stackTrace,
    );
  }

  /// Logs at [logging.Level.SHOUT] — an unrecoverable failure that
  /// requires immediate attention.
  ///
  /// Use when the app is about to crash or enter an unusable state:
  /// null-safety violation in a critical path, database corruption,
  /// missing required platform capability. Always forwards to
  /// [CrashReportingDelegate.recordError] with `fatal: true`.
  ///
  /// ```dart
  /// HyperLogger.fatal<AppBootstrap>(
  ///   'Required migration failed — data unreadable',
  ///   exception: e,
  ///   stackTrace: st,
  /// );
  /// ```
  static void fatal<T>(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    // Delegates fire in silent mode.
    _fireDelegate(
      () => _crashReporting?.recordError(
        exception ?? message,
        stackTrace,
        fatal: true,
        reason: message,
      ),
    );
    if (_mode == LogMode.silent) return;
    _log<T>(
      logging.Level.SHOUT,
      message,
      data: data,
      method: method,
      error: exception,
      stackTrace: stackTrace,
    );
  }

  /// Logs the elapsed time of [stopwatch] at [logging.Level.INFO].
  ///
  /// Use to instrument performance-sensitive operations. The elapsed
  /// duration is included in the log message.
  ///
  /// ```dart
  /// final sw = Stopwatch()..start();
  /// await db.query(sql);
  /// sw.stop();
  /// HyperLogger.stopwatch<Database>('Heavy query', sw);
  /// ```
  static void stopwatch<T>(
    String message,
    Stopwatch stopwatch, {
    String? method,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    if (_mode == LogMode.silent) return;
    final elapsed = stopwatch.elapsed;
    final formatted = '$message (${elapsed.inMilliseconds}ms)';
    _log<T>(logging.Level.INFO, formatted, method: method);
  }

  // ── wrapper factory ────────────────────────────────────────────────────────

  /// Returns a cached [ScopedLogger] for type [T] with inline options.
  ///
  /// Cached by type + options — repeated calls with the same arguments
  /// return the same instance.
  ///
  /// ```dart
  /// final log = HyperLogger.withOptions<PaymentService>(tag: 'payments');
  /// ```
  static ScopedLogger<T> withOptions<T>({
    LogMode mode = LogMode.enabled,
    LogLevel? minLevel,
    String? tag,
    bool skipCrashReporting = false,
  }) {
    return _cached<T>(
      LoggerOptions(
        mode: mode,
        minLevel: minLevel,
        tag: tag,
        skipCrashReporting: skipCrashReporting,
      ),
    );
  }

  /// Returns a cached [ScopedLogger] for type [T] from a pre-built
  /// [LoggerOptions] object.
  ///
  /// ```dart
  /// const opts = LoggerOptions(tag: 'billing', minLevel: LogLevel.warning);
  /// final log = HyperLogger.fromOptions<Billing>(opts);
  /// ```
  static ScopedLogger<T> fromOptions<T>(LoggerOptions options) {
    return _cached<T>(options);
  }

  static ScopedLogger<T> _cached<T>(LoggerOptions options) {
    final key = options.cacheKey(T.toString());
    return _wrapperCache.putIfAbsent(
          key,
          () => ScopedLogger<T>(options: options),
        )
        as ScopedLogger<T>;
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
    // provided or when capture is disabled via init(captureStackTrace: false).
    final callerStack = _captureStackTrace && method == null
        ? StackTrace.current
        : null;
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

  /// Fires a delegate call, catching and swallowing any error so that
  /// logging never crashes the app. The returned [Future] (if any) is
  /// awaited with an error handler that also swallows.
  static void _fireDelegate(Future<void>? Function() fn) {
    try {
      fn()?.catchError((_) {});
    } catch (_) {
      // Synchronous throw from the delegate — swallow.
    }
  }

  /// Listener wired to [logging.Logger.root.onRecord].
  static void _handleLogRecord(logging.LogRecord record) {
    if (_mode != LogMode.enabled) return;
    try {
      final entry = LogEntry.fromLogRecord(record);
      if (_logFilter != null && !_logFilter!(entry)) return;
      _printer?.log(entry);
    } catch (_) {
      // Logging should never crash the app.
    }
  }

  /// Auto-initializes with platform defaults if [init] hasn't been called.
  static void _ensureInitialized() {
    if (!_initialized) init();
  }
}
