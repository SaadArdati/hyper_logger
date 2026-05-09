import '../model/log_level.dart';
import 'cloud_json_printer_base.dart';

/// A [LogPrinter] that emits one JSON object per log record in a shape
/// matching the Azure Application Insights `traces` data model.
///
/// Each line is a self-contained JSON object built from the four trace
/// fields the AppInsights ingestion pipeline understands directly:
///
/// - `time` — ISO-8601 timestamp (the Application Insights envelope
///   convention; KQL queries expose this as `timestamp`).
/// - `severityLevel` — numeric `0..4` per the AppInsights enum
///   (Verbose=0, Information=1, Warning=2, Error=3, Critical=4).
/// - `message` — the log message text.
/// - `customDimensions` — a string-to-anything map of user context.
///   Maps to the `customDimensions` column in the `traces` /
///   `AppTraces` table; all KQL queries that filter or project
///   custom fields read from here.
///
/// This shape is what most "send Dart logs to Azure" pipelines expect:
/// a flat JSON line per record, scraped from stdout by Container
/// Insights, the OpenTelemetry log exporter, or a custom-log-file
/// data collector. It does not produce the full nested
/// `{name, time, iKey, tags, data: {baseType, baseData}}` envelope
/// the direct ingestion endpoint requires — that envelope needs an
/// instrumentation key and is the job of an exporter, not a logger.
///
/// ### Level → severityLevel mapping
/// | LogLevel    | severityLevel | AppInsights label |
/// |-------------|---------------|-------------------|
/// | trace/debug | `0`           | Verbose           |
/// | info        | `1`           | Information       |
/// | warning     | `2`           | Warning           |
/// | error       | `3`           | Error             |
/// | fatal       | `4`           | Critical          |
///
/// `trace` and `debug` collapse to Verbose because Application
/// Insights only exposes five severity levels. If you need to
/// distinguish trace from debug post-ingestion, query the `logger`
/// field or stash a marker under context.
///
/// ### Reserved-key precedence
///
/// The fields `time`, `severityLevel`, `message`, `customDimensions`,
/// `logger`, `data`, `error`, and `stackTrace` are reserved at the JSON
/// root. Context entries colliding with these names are silently
/// dropped during formatting so an accidental
/// `context: {'severityLevel': 99}` cannot poison the trace.
///
/// ### Application Insights "magic" properties via customDimensions
///
/// AppInsights surfaces `customDimensions` keys as first-class columns
/// once you query them with KQL — `customDimensions.requestId`,
/// `customDimensions.userId`, etc. Write whatever you'd query later
/// into your scoped logger's `context` (or `child(context: ...)`) and
/// it lands in the right place for the AppInsights UI and KQL
/// shortcuts.
///
/// ### Application Insights error visibility
///
/// AppInsights tracks errors in a separate `exceptions` table via the
/// SDK's `trackException()`. A printer can't synthesize that
/// telemetry from a log line. To make exceptions discoverable from
/// the `traces` table directly, this printer embeds the error and
/// stack trace into `message` for `Error` and `Critical` severity
/// (matching the GCP/AWS conventions). Use AppInsights' search or
/// KQL `where message has "..."` to find them.
///
/// For Google Cloud Logging see `GcpJsonPrinter`; for AWS CloudWatch
/// see `AwsJsonPrinter`.
class AzureJsonPrinter extends CloudJsonPrinterBase {
  const AzureJsonPrinter({super.output});

  @override
  String get levelKey => 'severityLevel';

  /// Returns the numeric AppInsights severity. The base class encodes
  /// it as a JSON integer.
  @override
  int levelValue(LogLevel level) => switch (level) {
    LogLevel.trace || LogLevel.debug => 0, // Verbose
    LogLevel.info => 1, // Information
    LogLevel.warning => 2, // Warning
    LogLevel.error => 3, // Error
    LogLevel.fatal => 4, // Critical
  };

  @override
  String get timestampKey => 'time';

  @override
  String? get contextKey => 'customDimensions';

  @override
  Set<String> get reservedKeys => const {
    'time',
    'severityLevel',
    'message',
    'customDimensions',
    'logger',
    'data',
    'error',
    'stackTrace',
  };
}
