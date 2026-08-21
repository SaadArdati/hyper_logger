import 'dart:async';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart' as logging;
import 'package:meta/meta.dart';

import 'delegates/crash_reporting_delegate.dart';
import 'delegates/delegate_safety.dart';
import 'interceptors/redacting_interceptor.dart';
import 'lru_cache.dart';
import 'model/log_entry.dart';
import 'model/log_level.dart';
import 'model/log_message.dart';
import 'model/log_mode.dart';
import 'model/logger_options.dart';
import 'printer/log_printer.dart';
import 'printer/printer_factory.dart';

part 'scoped_logger.dart';

/// Inspects, transforms, or drops a [LogEntry] before it reaches the printer.
///
/// Return the entry (possibly modified) to let it through, or `null` to
/// drop it entirely. Interceptors run in declaration order; the first one
/// to return `null` short-circuits the chain.
///
/// Failure isolation: if an interceptor throws, it is skipped and the
/// previous entry continues through the rest of the chain. One buggy
/// interceptor cannot black-hole the pipeline. To deliberately drop an
/// entry, return `null` rather than throwing.
///
/// Use cases:
/// - Filter: drop high-volume health-check logs
/// - Enrich: attach hostname, build version, request id
/// - Sample: emit only 1-in-N noisy events
///
/// ```dart
/// HyperLogger.init(
///   printer: LogPrinterPresets.automatic(),
///   interceptors: [
///     (entry) => entry.message.contains('/health') ? null : entry,
///   ],
/// );
/// ```
typedef LogInterceptor = LogEntry? Function(LogEntry entry);

/// One stage in the final privacy boundary applied after ordinary interceptors
/// and before every output sink.
///
/// Returning `null` drops the record. Unlike an ordinary [LogInterceptor], a
/// thrown sanitizer also drops the record; the previous unsanitized entry is
/// never forwarded. Use [RedactingInterceptor.call] here rather than placing a
/// redactor in the ordinary interceptor list.
///
/// This final-boundary placement follows the [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)
/// guidance to remove, mask, or sanitize credentials before recording them.
/// A sanitizer still needs an application-specific policy for PII, consent,
/// classification, and log-injection risks.
typedef LogSanitizer = LogEntry? Function(LogEntry entry);

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
///   determines the canonical `LogEntry.loggerName` used for prefix rendering.
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
  static List<LogInterceptor> _interceptors = const [];
  static List<LogSanitizer> _sanitizers = const [];
  static CrashReportingDelegate? _crashReporting;

  /// Default maximum number of entries in each LRU cache.
  static const int defaultMaxCacheSize = 256;

  /// Cache of [logging.Logger] instances keyed by type name.
  static LruCache<String, logging.Logger> _loggerCache = LruCache(
    defaultMaxCacheSize,
  );

  /// Cache of [ScopedLogger] instances keyed by type name + options.
  static LruCache<String, ScopedLogger<dynamic>> _wrapperCache = LruCache(
    defaultMaxCacheSize,
  );

  /// Subscription to the root logger's record stream.
  static StreamSubscription<logging.LogRecord>? _subscription;

  // ── initialization ─────────────────────────────────────────────────────────

  /// Configures HyperLogger. Calling this is optional — the logger
  /// auto-initializes with platform defaults on first use.
  ///
  /// Can be called at any point to reconfigure: [printer], [mode],
  /// [interceptors], [sanitizers], [captureStackTrace], and [maxCacheSize] are
  /// applied on every call (the previous printer is disposed on swap).
  /// [configureLoggingPackage] and the inbound third-party listener attachment
  /// to `Logger.root.onRecord` are applied on the first init only —
  /// subsequent calls don't re-attach. Use [reset] to fully tear down.
  ///
  /// - [printer] receives formatted log records. Defaults to the
  ///   platform-appropriate printer (the terminal preset on native,
  ///   `WebConsolePrinter` on web — see `package:hyper_logger/web.dart`).
  /// - [mode] controls global logging behavior. See [LogMode].
  /// - [interceptors] are applied to every record before it reaches the
  ///   sanitizer and output sinks. They run in order; an interceptor returning
  ///   `null` drops the record. See [LogInterceptor] for filtering, enrichment,
  ///   and sampling examples.
  /// - [sanitizers] are the final ordered, fail-closed transformations. They
  ///   run after all ordinary interceptors and before both crash reporting and
  ///   the printer. Any sanitizer returning `null` or throwing drops the record
  ///   from every sink.
  /// - [captureStackTrace] when `true` (default), captures [StackTrace.current]
  ///   on every log call that doesn't provide a `method:` parameter, enabling
  ///   automatic caller extraction. Set to `false` to avoid that
  ///   platform-dependent capture cost.
  /// - [configureLoggingPackage] when `true` (default), sets
  ///   `hierarchicalLoggingEnabled = true` and `Logger.root.level = Level.ALL`
  ///   on the underlying `package:logging` during the first init. Set
  ///   to `false` if another package manages the logging configuration and
  ///   you don't want hyper_logger to override it. Calling [setLogLevel]
  ///   before the first init pre-stages the level so it survives this step.
  /// - [maxCacheSize] controls the maximum number of entries in the internal
  ///   logger and wrapper LRU caches. Defaults to [defaultMaxCacheSize] (256).
  static void init({
    LogPrinter? printer,
    LogMode mode = LogMode.enabled,
    List<LogInterceptor>? interceptors,
    List<LogSanitizer>? sanitizers,
    bool captureStackTrace = true,
    bool configureLoggingPackage = true,
    int maxCacheSize = defaultMaxCacheSize,
  }) {
    if (maxCacheSize < 1) {
      throw ArgumentError.value(
        maxCacheSize,
        'maxCacheSize',
        'must be >= 1; the LRU cache cannot operate with a non-positive '
            'capacity',
      );
    }
    _mode = mode;
    _captureStackTrace = captureStackTrace;
    // Dispose the previous printer before swapping it out, otherwise
    // resources it owns (ThrottledPrinter's drain Timer,
    // RotatingFilePrinter's file handle) leak.
    final newPrinter =
        printer ?? (_initialized ? _printer : null) ?? createDefaultPrinter();
    if (_initialized && _printer != null && !identical(_printer, newPrinter)) {
      try {
        _printer!.dispose();
      } catch (_) {
        // dispose() must not crash init.
      }
    }
    _printer = newPrinter;
    _interceptors = interceptors == null
        ? const []
        : List<LogInterceptor>.unmodifiable(interceptors);
    _sanitizers = sanitizers == null
        ? const []
        : List<LogSanitizer>.unmodifiable(sanitizers);

    if (_loggerCache.maxSize != maxCacheSize) {
      _loggerCache = LruCache(maxCacheSize);
      _wrapperCache = LruCache(maxCacheSize);
    }

    if (!_initialized) {
      _initialized = true;
      if (configureLoggingPackage) {
        logging.hierarchicalLoggingEnabled = true;
        // Honor a level set via setLogLevel before init; otherwise
        // open the gate fully.
        logging.Logger.root.level =
            _pendingLogLevel?.toLoggingLevel() ?? logging.Level.ALL;
      }
      // Always clear the pending level on the init transition. When
      // the user opts out of `package:logging` configuration they're
      // managing `Logger.root.level` themselves; a leftover pending
      // value would otherwise apply on a later default-config init()
      // and silently overwrite their direct setting.
      _pendingLogLevel = null;
      _subscription = logging.Logger.root.onRecord.listen(_handleLogRecord);
    }
  }

  /// A LogLevel set by [setLogLevel] before the first [init] call.
  /// Applied during init's `configureLoggingPackage` block so an early
  /// `setLogLevel` doesn't get silently overwritten by `Level.ALL`.
  static LogLevel? _pendingLogLevel;

  /// Attaches the crash-reporting delegate that receives certain log events.
  ///
  /// [crashReporting] receives [warning] messages (via [CrashReportingDelegate.log])
  /// and [error]/[fatal] messages (via [CrashReportingDelegate.recordError]).
  static void attachServices({CrashReportingDelegate? crashReporting}) {
    _crashReporting = crashReporting;
  }

  /// The currently attached crash-reporting delegate, or `null`.
  ///
  /// Scoped and unscoped calls both reach this delegate through the shared
  /// dispatch pipeline. External callers should generally route through
  /// [warning], [error], and [fatal] rather than holding a long-lived
  /// reference—a later [attachServices] call may replace the delegate.
  @internal
  static CrashReportingDelegate? get crashReporting => _crashReporting;

  /// Detaches all service delegates. Intended for test teardown.
  static void detachServices() {
    _crashReporting = null;
  }

  /// Resets all static state. Intended for test teardown so that each test
  /// starts with a clean slate. The current printer is disposed so its
  /// owned resources (timers, file handles) don't leak across tests.
  ///
  /// The next log call auto-initializes with platform defaults. Use [shutdown]
  /// at application exit when later log calls must remain disabled.
  static void reset() {
    final subscription = _tearDown(nextMode: LogMode.enabled);
    subscription?.cancel();
  }

  /// Tears down the active session and disables implicit re-initialization.
  ///
  /// This method is idempotent. It disposes the active printer, detaches
  /// services, removes interceptors and pipeline handlers, clears caches, and
  /// awaits cancellation of the root logging subscription. Later log calls are
  /// no-ops until an explicit [init] starts a fresh session.
  ///
  /// Printer-specific asynchronous work is outside this contract. Drain or
  /// close a stateful printer before calling this method.
  static Future<void> shutdown() async {
    final subscription = _tearDown(nextMode: LogMode.disabled);
    try {
      await subscription?.cancel();
    } catch (_) {
      // Logging teardown remains best-effort and must not fail app shutdown.
    }
  }

  static StreamSubscription<logging.LogRecord>? _tearDown({
    required LogMode nextMode,
  }) {
    // Gate all global and existing scoped loggers before disposal begins.
    _mode = LogMode.disabled;
    final activePrinter = _printer;
    if (activePrinter != null) {
      try {
        activePrinter.dispose();
      } catch (_) {
        // Teardown is best-effort; a broken printer cannot keep logging alive.
      }
    }
    final activeSubscription = _subscription;
    _initialized = false;
    _mode = nextMode;
    _captureStackTrace = true;
    _printer = null;
    _interceptors = const [];
    _sanitizers = const [];
    _crashReporting = null;
    _pipelineErrorHandler = null;
    _pipelineErrorReportedSources.clear();
    _pendingLogLevel = null;
    _subscription = null;
    _loggerCache.clear();
    _wrapperCache.clear();
    return activeSubscription;
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
  ///
  /// Safe to call before any other [HyperLogger] entry point: when
  /// invoked pre-init the level is buffered and applied during the
  /// first [init] call's `configureLoggingPackage` block, so users
  /// opting out of `package:logging` configuration retain full
  /// control of `Logger.root.level`.
  static void setLogLevel(LogLevel level) {
    if (_initialized) {
      logging.Logger.root.level = level.toLoggingLevel();
    } else {
      _pendingLogLevel = level;
    }
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
  static void trace<T>(
    String message, {
    Object? data,
    String? method,
    Map<String, Object?>? context,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    if (_mode == LogMode.silent) return;
    _log<T>(
      logging.Level.FINEST,
      message,
      data: data,
      method: method,
      context: context,
    );
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
  static void debug<T>(
    String message, {
    Object? data,
    String? method,
    Map<String, Object?>? context,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    if (_mode == LogMode.silent) return;
    _log<T>(
      logging.Level.FINE,
      message,
      data: data,
      method: method,
      context: context,
    );
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
  static void info<T>(
    String message, {
    Object? data,
    String? method,
    Map<String, Object?>? context,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    if (_mode == LogMode.silent) return;
    _log<T>(
      logging.Level.INFO,
      message,
      data: data,
      method: method,
      context: context,
    );
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
  static void warning<T>(
    String message, {
    Object? data,
    String? method,
    Map<String, Object?>? context,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    _log<T>(
      logging.Level.WARNING,
      message,
      data: data,
      method: method,
      context: context,
      reportToCrashReporting: true,
    );
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
    Map<String, Object?>? context,
    bool? skipCrashReporting,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    _log<T>(
      logging.Level.SEVERE,
      message,
      data: data,
      method: method,
      error: exception,
      stackTrace: stackTrace,
      context: context,
      reportToCrashReporting: !(skipCrashReporting ?? false),
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
    Map<String, Object?>? context,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    _log<T>(
      logging.Level.SHOUT,
      message,
      data: data,
      method: method,
      error: exception,
      stackTrace: stackTrace,
      context: context,
      reportToCrashReporting: true,
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
    Map<String, Object?>? context,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    if (_mode == LogMode.silent) return;
    final elapsed = stopwatch.elapsed;
    final formatted = '$message (${elapsed.inMilliseconds}ms)';
    _log<T>(logging.Level.INFO, formatted, method: method, context: context);
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

  /// Returns a fresh (uncached) [ScopedLogger] for type [T] with the given
  /// [context] attached. Every log call from this logger automatically
  /// carries those key-value pairs.
  ///
  /// Use for request-scoped, transaction-scoped, or job-scoped logging where
  /// you want fields like `requestId` or `userId` on every line in that
  /// scope without restating them per call.
  ///
  /// ```dart
  /// void handleRequest(Request req) {
  ///   final log = HyperLogger.child<Handler>(context: {'requestId': req.id});
  ///   log.info('Received');
  /// }
  /// ```
  ///
  /// All [withOptions] knobs are also accepted: pass [tag] to prefix
  /// every line, [minLevel] to drop verbose entries inside this scope,
  /// [mode] to start in `silent`/`disabled`, or pass a complete
  /// [options] object for full control.
  ///
  /// ```dart
  /// final log = HyperLogger.child<Handler>(
  ///   tag: 'api',
  ///   minLevel: LogLevel.info,
  ///   context: {'requestId': req.id},
  /// );
  /// ```
  ///
  /// Precedence: pass either [options] or the inline knobs
  /// ([tag], [minLevel], [mode], [skipCrashReporting]) — not both. In
  /// debug mode, mixing them throws an [AssertionError]; in release
  /// mode, [options] wins and the inline values are silently ignored.
  ///
  /// Carve-out: the assert is value-based, so passing [mode] at its
  /// literal default (`LogMode.enabled`) alongside [options] does not
  /// trip the assert — the runtime can't distinguish "explicit default"
  /// from "not passed". Don't rely on this; treat the default as "not
  /// passed" and only set [mode] explicitly to non-default values.
  ///
  /// Unlike [withOptions], child loggers are not cached — each call
  /// returns a new instance. This is intentional: per-request loggers
  /// shouldn't share identity with later, unrelated requests.
  static ScopedLogger<T> child<T>({
    Map<String, Object?>? context,
    String? tag,
    LogLevel? minLevel,
    LogMode mode = LogMode.enabled,
    bool skipCrashReporting = false,
    LoggerOptions? options,
  }) {
    assert(
      options == null ||
          (tag == null &&
              minLevel == null &&
              mode == LogMode.enabled &&
              !skipCrashReporting),
      'HyperLogger.child<T>: pass either `options` or inline params '
      '(tag/minLevel/mode/skipCrashReporting), not both. When both are '
      'passed, `options` wins and inline values are silently ignored — '
      'usually a bug.',
    );
    final opts =
        options ??
        LoggerOptions(
          tag: tag,
          minLevel: minLevel,
          mode: mode,
          skipCrashReporting: skipCrashReporting,
        );
    return ScopedLogger<T>(options: opts, context: context);
  }

  /// Library-private log-with-tag dispatch used by [ScopedLogger] to
  /// thread `LoggerOptions.tag` through to [LogEntry.tag] without
  /// expanding the public static-method surface with a `tag:` parameter.
  static void _logScoped<T>(
    LogLevel level,
    String message, {
    Object? data,
    String? method,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
    required String? scopeTag,
    bool reportToCrashReporting = false,
    bool suppressPrinter = false,
  }) {
    if (_mode == LogMode.disabled) return;
    _ensureInitialized();
    if (_mode == LogMode.silent && !reportToCrashReporting) return;
    _log<T>(
      level.toLoggingLevel(),
      message,
      data: data,
      method: method,
      error: error,
      stackTrace: stackTrace,
      context: context,
      scopeTag: scopeTag,
      reportToCrashReporting: reportToCrashReporting,
      suppressPrinter: suppressPrinter,
    );
  }

  // ── private helpers ────────────────────────────────────────────────────────

  /// Returns the cached `package:logging` level view for type [T].
  ///
  /// Native records are not published to its stream; the logger is retained
  /// only so package-level hierarchy and [setLogLevel] control filtering.
  static logging.Logger _getLogger<T>() {
    final name = T.toString();
    return _loggerCache.putIfAbsent(name, () => logging.Logger(name));
  }

  /// Core log dispatch. Native calls enter HyperLogger's pipeline directly;
  /// `package:logging` is only an inbound bridge for third-party records.
  ///
  /// [StackTrace.current] is only captured when [method] is null — this avoids
  /// the platform-dependent capture cost when the caller already provides a
  /// method name or when the stack trace would be discarded anyway.
  static void _log<T>(
    logging.Level level,
    String message, {
    Object? data,
    String? method,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
    String? scopeTag,
    bool reportToCrashReporting = false,
    bool suppressPrinter = false,
  }) {
    if (!_hasEligibleSink(
      level,
      reportToCrashReporting: reportToCrashReporting,
      suppressPrinter: suppressPrinter,
    )) {
      return;
    }
    final logger = _getLogger<T>();
    // Gate StackTrace and payload allocation behind the level filter.
    if (!logger.isLoggable(level)) return;
    // Skip the expensive StackTrace.current capture when method is already
    // provided or when capture is disabled via init(captureStackTrace: false).
    final callerStack = _captureStackTrace && method == null
        ? StackTrace.current
        : null;
    final emitTime = clock.now();
    final logMessage = LogMessage(
      message,
      T,
      data: data,
      method: method,
      callerStackTrace: callerStack,
      context: context,
      time: emitTime,
      scopeTag: scopeTag,
      reportToCrashReporting: reportToCrashReporting,
    );
    _handleEntry(
      LogEntry(
        level: LogLevel.fromLoggingLevel(level),
        message: message,
        object: logMessage,
        loggerName: logger.name,
        time: emitTime,
        error: error,
        stackTrace: stackTrace,
        tag: scopeTag,
      ),
      reportToCrashReporting: reportToCrashReporting,
      suppressPrinter: suppressPrinter,
    );
  }

  /// Listener wired to [logging.Logger.root.onRecord].
  ///
  /// Each interceptor runs in its own try/catch: a thrown interceptor is
  /// skipped (the previous entry is preserved) so one buggy hook can't
  /// black-hole the entire pipeline. Returning `null` is the explicit way
  /// to drop a record. Sanitizers then run fail-closed before printer dispatch.
  /// Third-party records are printer-only and never reach the crash-reporting
  /// delegate. The printer call is in its own try/catch so a bad printer never
  /// crashes the app.
  static void _handleLogRecord(logging.LogRecord record) {
    if (_mode == LogMode.disabled) return;
    if (!_hasEligibleSink(
      record.level,
      reportToCrashReporting: false,
      suppressPrinter: false,
    )) {
      return;
    }
    LogEntry entry;
    try {
      entry = LogEntry.fromLogRecord(record);
    } catch (_, st) {
      _reportPipelineError(
        'LogEntry.fromLogRecord',
        StateError('The log record could not be converted.'),
        st,
      );
      return;
    }
    _handleEntry(entry, reportToCrashReporting: false, suppressPrinter: false);
  }

  static void _handleEntry(
    LogEntry entry, {
    required bool reportToCrashReporting,
    required bool suppressPrinter,
  }) {
    for (final interceptor in _interceptors) {
      try {
        final next = interceptor(entry);
        if (next == null) return; // Explicit drop short-circuits the chain.
        entry = _synchronizeLogMessage(next);
      } catch (_, st) {
        // Skip this interceptor; carry the previous entry forward.
        _reportPipelineError(
          'interceptor',
          StateError('The configured interceptor failed.'),
          st,
        );
      }
    }
    for (final sanitizer in _sanitizers) {
      try {
        final sanitized = sanitizer(entry);
        if (sanitized == null) return;
        entry = _synchronizeLogMessage(sanitized);
      } catch (_, st) {
        _reportPipelineError(
          'sanitizer',
          StateError('The configured sanitizer failed.'),
          st,
        );
        return;
      }
    }
    if (reportToCrashReporting) {
      _dispatchCrashReporting(entry);
    }
    if (_mode == LogMode.silent || suppressPrinter) return;
    try {
      _printer?.log(entry);
    } catch (e, st) {
      // Logging should never crash the app.
      _reportPipelineError('printer.log', e, st);
    }
  }

  /// Whether a record can reach at least one configured output sink.
  ///
  /// This check deliberately precedes [LogMessage] and [LogEntry] allocation
  /// as well as interceptor/sanitizer traversal. Silent and scoped-suppressed
  /// calls therefore remain genuinely cheap even with expensive sanitizers.
  static bool _hasEligibleSink(
    logging.Level level, {
    required bool reportToCrashReporting,
    required bool suppressPrinter,
  }) {
    if (_mode == LogMode.disabled) return false;
    if (_mode == LogMode.enabled && !suppressPrinter && _printer != null) {
      return true;
    }
    return reportToCrashReporting &&
        _crashReporting != null &&
        level >= logging.Level.WARNING;
  }

  static void _dispatchCrashReporting(LogEntry entry) {
    switch (entry.level) {
      case LogLevel.trace || LogLevel.debug || LogLevel.info:
        return;
      case LogLevel.warning:
        fireDelegateSafely(() => _crashReporting?.log(entry.message));
        return;
      case LogLevel.error || LogLevel.fatal:
        fireDelegateSafely(
          () => _crashReporting?.recordError(
            entry.error ?? entry.message,
            entry.stackTrace,
            fatal: entry.level == LogLevel.fatal,
            reason: entry.message,
          ),
        );
    }
  }

  /// Keeps [LogMessage.message] as a compatibility mirror of the canonical
  /// [LogEntry.message] between pipeline stages and before custom printers.
  static LogEntry _synchronizeLogMessage(LogEntry entry) {
    final object = entry.object;
    if (object is! LogMessage || object.message == entry.message) return entry;
    return entry.copyWith(
      object: () => object.copyWith(message: entry.message),
    );
  }

  /// Reports a pipeline error via [_pipelineErrorHandler] when set, with
  /// rate limiting (one report per source per session) so a buggy
  /// printer can't itself spam. Sources are coarse-grained tags like
  /// `printer.log`, `interceptor`, `LogEntry.fromLogRecord` — enough for
  /// production observability without surfacing internal detail.
  static void _reportPipelineError(
    String source,
    Object error,
    StackTrace stackTrace,
  ) {
    final handler = _pipelineErrorHandler;
    if (handler == null) return;
    if (_pipelineErrorReportedSources.contains(source)) return;
    _pipelineErrorReportedSources.add(source);
    try {
      handler(source, error, stackTrace);
    } catch (_) {
      // The handler itself failed. Silently swallow — recursing here
      // would be worse than dropping.
    }
  }

  static final Set<String> _pipelineErrorReportedSources = <String>{};

  static void Function(String source, Object error, StackTrace stackTrace)?
  _pipelineErrorHandler;

  /// Sets a callback invoked when an internal pipeline component throws
  /// during log processing — currently `LogEntry.fromLogRecord`,
  /// interceptors, sanitizers, or `printer.log`.
  ///
  /// The callback is rate-limited to one invocation per failure
  /// source per session to avoid feedback loops. This is intended for
  /// production observability: wire it into stderr or a separate
  /// telemetry sink so silent log drops are detectable.
  ///
  /// Pass `null` to disable.
  static void setPipelineErrorHandler(
    void Function(String source, Object error, StackTrace stackTrace)? handler,
  ) {
    _pipelineErrorHandler = handler;
    if (handler == null) {
      _pipelineErrorReportedSources.clear();
    }
  }

  /// Auto-initializes with platform defaults if [init] hasn't been called.
  static void _ensureInitialized() {
    if (!_initialized) init();
  }
}
