import 'hyper_logger_base.dart';
import 'scoped_logger.dart';

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
    bool skipCrashReporting = false,
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
}
