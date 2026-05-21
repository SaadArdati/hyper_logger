part of 'hyper_logger_base.dart';

/// Public API surface for typed logging.
///
/// Mirrors the convenience methods on [HyperLogger] but scoped to a single
/// generic type [T]. Used by [ScopedLogger] and testable in isolation.
abstract interface class ScopedLoggerApi<T> {
  /// Contextual key-value pairs attached to every log entry from this scope.
  ///
  /// Populated via the constructor or [child]. Mutable on the returned
  /// instance; mutating a logger from [HyperLogger.withOptions] is a footgun
  /// because that instance is cached — prefer [child] for context-bearing
  /// loggers.
  Map<String, Object?> get context;

  /// Returns a fresh (uncached) child logger that inherits this scope's
  /// configuration and merges its [context] with the receiver's.
  ///
  /// Keys in the new [context] override keys with the same name from the
  /// parent. The receiver's top-level context is unaffected.
  ///
  /// Shallow copy: the merge is one level deep. A nested mutable
  /// value (a list inside the context map, for example) is shared by
  /// reference between parent and child — mutating it through one
  /// affects the other. Use immutable / freshly-constructed values to
  /// avoid surprises.
  ScopedLoggerApi<T> child({Map<String, Object?>? context});

  /// The current operating mode. Mutable so feature flags can toggle
  /// scoped output at runtime; setting it does not affect the global
  /// [HyperLogger] mode.
  LogMode get mode;
  set mode(LogMode value);

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

/// A cached logger scope returned by [HyperLogger.withOptions], or a fresh
/// child returned by [child] / [HyperLogger.child].
///
/// Behavior is controlled by [options], the mutable [mode], and the mutable
/// [context] map:
/// - [mode] — controls logging behavior at runtime. See [LogMode].
///   Initialized from [LoggerOptions.mode] but can be changed dynamically.
/// - [LoggerOptions.minLevel] — messages below this level are dropped.
/// - [LoggerOptions.tag] — prepended as `[tag] ` to every message.
/// - [LoggerOptions.skipCrashReporting] — default for [error] calls.
/// - [context] — key-value pairs attached to every log entry. Cloud-shaped
///   printers merge these into the JSON root; other printers may render
///   them inline or ignore them.
class ScopedLogger<T> implements ScopedLoggerApi<T> {
  /// The options this scope was created with.
  final LoggerOptions options;

  @override
  LogMode mode;

  @override
  final Map<String, Object?> context;

  ScopedLogger({required this.options, Map<String, Object?>? context})
    : mode = options.mode,
      context = context == null ? <String, Object?>{} : Map.of(context);

  @override
  ScopedLogger<T> child({Map<String, Object?>? context}) {
    final merged = <String, Object?>{...this.context};
    if (context != null) merged.addAll(context);
    final c = ScopedLogger<T>(options: options, context: merged);
    // Inherit the parent's *current* runtime mode, not the original
    // options.mode — so a parent toggled to silent/disabled at runtime
    // produces a child that respects that toggle. Without this, scopes
    // expected to stay suppressed could leak logs.
    c.mode = mode;
    return c;
  }

  /// Applies the [options.tag] prefix to [msg] when a tag is set.
  String _tagged(String msg) {
    final tag = options.tag;
    return tag != null ? '[$tag] $msg' : msg;
  }

  /// The context map to pass to [HyperLogger] statics, or `null` when
  /// empty.
  ///
  /// Returns the live map by reference to avoid a per-emit allocation
  /// on hot logging paths. Printers and interceptors treat the map as
  /// read-only and finish their work synchronously, so the contract
  /// is: mutate [context] before logging, not after. The cached
  /// `HyperLogger.withOptions` instance already documents context
  /// mutation as a footgun; use [child] for per-request context.
  Map<String, Object?>? get _ctx => context.isEmpty ? null : context;

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
    HyperLogger._logScoped<T>(
      LogLevel.trace,
      _tagged(msg),
      data: data,
      method: method,
      context: _ctx,
      scopeTag: options.tag,
    );
  }

  @override
  void debug(String msg, {Object? data, String? method}) {
    if (_suppressed(LogLevel.debug)) return;
    if (mode == LogMode.silent) return;
    HyperLogger._logScoped<T>(
      LogLevel.debug,
      _tagged(msg),
      data: data,
      method: method,
      context: _ctx,
      scopeTag: options.tag,
    );
  }

  @override
  void info(String msg, {Object? data, String? method}) {
    if (_suppressed(LogLevel.info)) return;
    if (mode == LogMode.silent) return;
    HyperLogger._logScoped<T>(
      LogLevel.info,
      _tagged(msg),
      data: data,
      method: method,
      context: _ctx,
      scopeTag: options.tag,
    );
  }

  @override
  void warning(String msg, {Object? data, String? method}) {
    if (_suppressed(LogLevel.warning)) return;
    if (mode == LogMode.silent) {
      // Honor the global mode in the silent path: scoped mode can only
      // be more restrictive than global, never less. When global is
      // `disabled` we must not fire the delegate either.
      if (HyperLogger.mode == LogMode.disabled) return;
      fireDelegateSafely(() => HyperLogger.crashReporting?.log(_tagged(msg)));
      return;
    }
    final tagged = _tagged(msg);
    if (HyperLogger.mode != LogMode.disabled) {
      fireDelegateSafely(() => HyperLogger.crashReporting?.log(tagged));
    }
    HyperLogger._logScoped<T>(
      LogLevel.warning,
      tagged,
      data: data,
      method: method,
      context: _ctx,
      scopeTag: options.tag,
    );
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
      // Honor the global mode (see warning() above for rationale).
      if (HyperLogger.mode == LogMode.disabled) return;
      if (!skip) {
        fireDelegateSafely(
          () => HyperLogger.crashReporting?.recordError(
            exception ?? tagged,
            stackTrace,
            reason: tagged,
          ),
        );
      }
      return;
    }
    if (HyperLogger.mode != LogMode.disabled && !skip) {
      fireDelegateSafely(
        () => HyperLogger.crashReporting?.recordError(
          exception ?? tagged,
          stackTrace,
          reason: tagged,
        ),
      );
    }
    HyperLogger._logScoped<T>(
      LogLevel.error,
      tagged,
      data: data,
      method: method,
      error: exception,
      stackTrace: stackTrace,
      context: _ctx,
      scopeTag: options.tag,
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
      // Honor the global mode (see warning() above for rationale).
      if (HyperLogger.mode == LogMode.disabled) return;
      fireDelegateSafely(
        () => HyperLogger.crashReporting?.recordError(
          exception ?? tagged,
          stackTrace,
          fatal: true,
          reason: tagged,
        ),
      );
      return;
    }
    if (HyperLogger.mode != LogMode.disabled) {
      fireDelegateSafely(
        () => HyperLogger.crashReporting?.recordError(
          exception ?? tagged,
          stackTrace,
          fatal: true,
          reason: tagged,
        ),
      );
    }
    HyperLogger._logScoped<T>(
      LogLevel.fatal,
      tagged,
      data: data,
      method: method,
      error: exception,
      stackTrace: stackTrace,
      context: _ctx,
      scopeTag: options.tag,
    );
  }

  @override
  void stopwatch(String message, Stopwatch stopwatch, {String? method}) {
    if (_suppressed(LogLevel.info)) return;
    if (mode == LogMode.silent) return;
    HyperLogger._logScoped<T>(
      LogLevel.info,
      _tagged('$message took ${stopwatch.elapsedMilliseconds}ms'),
      method: method,
      context: _ctx,
      scopeTag: options.tag,
    );
  }
}
