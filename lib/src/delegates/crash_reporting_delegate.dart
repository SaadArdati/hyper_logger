/// Abstract delegate for crash reporting integration.
///
/// The consuming app implements this with its crash reporting service
/// (e.g., Firebase Crashlytics) and injects it via [HyperLogger.attachServices].
abstract class CrashReportingDelegate {
  Future<void> log(String message);

  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  });
}
