import 'hyper_logger_base.dart';

/// Convenience mixin that delegates to [HyperLogger] static methods,
/// forwarding the host class's type parameter [T] automatically.
///
/// ```dart
/// class MyService with HyperLoggerMixin<MyService> {
///   void doWork() {
///     logInfo('work started');
///   }
/// }
/// ```
mixin HyperLoggerMixin<T> {
  void logInfo(String msg, {Object? data, String? method}) =>
      HyperLogger.info<T>(msg, data: data, method: method);

  void logDebug(String msg, {Object? data, String? method}) =>
      HyperLogger.debug<T>(msg, data: data, method: method);

  void logWarning(String msg, {Object? data, String? method}) =>
      HyperLogger.warning<T>(msg, data: data, method: method);

  void logError(
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    Object? data,
    String? method,
    bool skipCrashReporting = false,
  }) => HyperLogger.error<T>(
    message,
    exception: exception,
    stackTrace: stackTrace,
    data: data,
    method: method,
    skipCrashReporting: skipCrashReporting,
  );

  void logStopwatch(String message, Stopwatch stopwatch, {String? method}) =>
      HyperLogger.stopwatch<T>(message, stopwatch, method: method);
}
