/// Abstract delegate for analytics integration.
///
/// The consuming app implements this with its analytics service
/// (e.g., Firebase Analytics) and injects it via [HyperLogger.attachServices].
abstract class AnalyticsDelegate {
  Future<void> logPerformance(String name, Duration duration, {String? source});
}
