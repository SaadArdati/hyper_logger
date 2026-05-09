import 'hyper_logger_base.dart';
import 'model/log_level.dart';
import 'model/log_mode.dart';
import 'model/logger_options.dart';

/// Convenience mixin that delegates to a [ScopedLoggerApi] when provided,
/// falling back to [HyperLogger] static methods.
///
/// Override [scopedLogger] to use a scoped logger with tag, mode, and
/// level filtering:
///
/// ```dart
/// class PaymentService with HyperLoggerMixin<PaymentService> {
///   @override
///   final scopedLogger = HyperLogger.withOptions<PaymentService>(
///     tag: 'payments',
///   );
///
///   void process() {
///     logInfo('Processing payment');
///     // Output: 💡 [PaymentService.process] [payments] Processing payment
///   }
/// }
/// ```
///
/// Without overriding, methods delegate directly to [HyperLogger]:
///
/// ```dart
/// class SimpleService with HyperLoggerMixin<SimpleService> {
///   void doWork() {
///     logInfo('work started');
///   }
/// }
/// ```
mixin HyperLoggerMixin<T> {
  /// Override to provide a [ScopedLogger] that takes priority over the
  /// global [HyperLogger] static methods.
  ScopedLoggerApi<T>? get scopedLogger => null;

  void logTrace(String msg, {Object? data, String? method}) {
    final s = scopedLogger;
    s != null
        ? s.trace(msg, data: data, method: method)
        : HyperLogger.trace<T>(msg, data: data, method: method);
  }

  void logDebug(String msg, {Object? data, String? method}) {
    final s = scopedLogger;
    s != null
        ? s.debug(msg, data: data, method: method)
        : HyperLogger.debug<T>(msg, data: data, method: method);
  }

  void logInfo(String msg, {Object? data, String? method}) {
    final s = scopedLogger;
    s != null
        ? s.info(msg, data: data, method: method)
        : HyperLogger.info<T>(msg, data: data, method: method);
  }

  void logWarning(String msg, {Object? data, String? method}) {
    final s = scopedLogger;
    s != null
        ? s.warning(msg, data: data, method: method)
        : HyperLogger.warning<T>(msg, data: data, method: method);
  }

  void logError(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
    bool? skipCrashReporting,
  }) {
    final s = scopedLogger;
    s != null
        ? s.error(
            message,
            exception: exception,
            stackTrace: stackTrace,
            data: data,
            method: method,
            skipCrashReporting: skipCrashReporting,
          )
        : HyperLogger.error<T>(
            message,
            exception: exception,
            stackTrace: stackTrace,
            data: data,
            method: method,
            skipCrashReporting: skipCrashReporting,
          );
  }

  void logFatal(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
  }) {
    final s = scopedLogger;
    s != null
        ? s.fatal(
            message,
            exception: exception,
            stackTrace: stackTrace,
            data: data,
            method: method,
          )
        : HyperLogger.fatal<T>(
            message,
            exception: exception,
            stackTrace: stackTrace,
            data: data,
            method: method,
          );
  }

  void logStopwatch(String message, Stopwatch stopwatch, {String? method}) {
    final s = scopedLogger;
    s != null
        ? s.stopwatch(message, stopwatch, method: method)
        : HyperLogger.stopwatch<T>(message, stopwatch, method: method);
  }

  /// Returns a request-scoped child logger with [context] attached to every
  /// log entry it produces.
  ///
  /// When [scopedLogger] is overridden (the host owns its config):
  /// only [context] is forwarded to `scopedLogger.child(context: ...)`.
  /// Passing inline knobs ([tag], [minLevel], [mode],
  /// [skipCrashReporting], [options]) in this case is almost always a
  /// bug — the host's own configuration would silently win over them —
  /// so they are rejected via `assert` in debug mode.
  ///
  /// When [scopedLogger] is `null`: builds a fresh [ScopedLogger]
  /// via `HyperLogger.child<T>(...)` using the inline knobs and/or
  /// [options]. Mixing [options] with the other inline knobs throws an
  /// `AssertionError` in debug mode (mirrors `HyperLogger.child<T>`).
  ///
  /// ```dart
  /// class UserService with HyperLoggerMixin<UserService> {
  ///   void handleRequest(Request req) {
  ///     final log = child(context: {'requestId': req.id});
  ///     log.info('Processing');
  ///   }
  /// }
  /// ```
  ScopedLoggerApi<T> child({
    Map<String, Object?>? context,
    String? tag,
    LogLevel? minLevel,
    LogMode mode = LogMode.enabled,
    bool skipCrashReporting = false,
    LoggerOptions? options,
  }) {
    final s = scopedLogger;
    if (s != null) {
      assert(
        tag == null &&
            minLevel == null &&
            mode == LogMode.enabled &&
            !skipCrashReporting &&
            options == null,
        'HyperLoggerMixin.child(): inline knobs (tag/minLevel/mode/'
        'skipCrashReporting/options) are ignored when scopedLogger is '
        'overridden — the host owns its own configuration. Pass `context` '
        'only, or remove the scopedLogger override.',
      );
      return s.child(context: context);
    }
    return HyperLogger.child<T>(
      context: context,
      tag: tag,
      minLevel: minLevel,
      mode: mode,
      skipCrashReporting: skipCrashReporting,
      options: options,
    );
  }
}
