import '../model/log_level.dart';
import 'cloud_json_printer_base.dart';

/// A [LogPrinter] that emits one JSON object per log record in
/// Google Cloud Logging's structured format.
///
/// Each line is a self-contained JSON object. [format] returns that line (and
/// nothing else) as a single-element [List<String>] for testability, keeping
/// the contract consistent with [ComposablePrinter.format].
///
/// Cloud Logging picks up the `severity` and `timestamp` fields automatically
/// when output is parsed by Cloud Run, GKE, App Engine, and Cloud Functions.
///
/// ### Reserved-key precedence
///
/// The fields `severity`, `message`, `timestamp`, `logger`, `data`, `error`,
/// and `stackTrace` are reserved — these are written by hyper_logger itself.
/// Context entries with any of these names are silently dropped during
/// formatting so an accidental `context: {'severity': 'BUG'}` cannot break
/// Cloud Logging's parser. (The drop is silent rather than logged so the
/// hot path doesn't recurse — set `onError` on the surrounding printer if
/// you want a signal.)
///
/// ### Cloud Logging "magic" fields flow through context
///
/// Cloud Logging recognizes additional structured fields that map to
/// LogEntry properties. Pass them via context to take advantage of
/// platform features:
///
/// - `httpRequest` — HTTP request metadata
/// - `logging.googleapis.com/labels` — searchable labels map
/// - `logging.googleapis.com/sourceLocation` — `{file, line, function}`
/// - `logging.googleapis.com/trace` — `projects/<id>/traces/<id>`
/// - `logging.googleapis.com/spanId` — 16-char hex span id
/// - `logging.googleapis.com/operation` — group related entries
/// - `logging.googleapis.com/insertId` — dedup key
///
/// Anything else in context is preserved verbatim under `jsonPayload`.
///
/// ### Cloud Error Reporting integration
///
/// For severity `ERROR` and `CRITICAL`, when both an `error` and a
/// `stackTrace` are attached to the entry, the stack trace is also
/// embedded in the `message` field. Cloud Error Reporting picks up
/// errors via the `message` field's stack-trace pattern, so this makes
/// errors show up in the Error Reporting console without extra setup.
///
/// ### Level → severity mapping
/// | LogLevel    | Cloud Logging severity |
/// |-------------|------------------------|
/// | trace/debug | DEBUG                  |
/// | info        | INFO                   |
/// | warning     | WARNING                |
/// | error       | ERROR                  |
/// | fatal       | CRITICAL               |
///
/// For AWS CloudWatch see `AwsJsonPrinter`; for Azure Application
/// Insights see `AzureJsonPrinter`.
class GcpJsonPrinter extends CloudJsonPrinterBase {
  const GcpJsonPrinter({super.output});

  @override
  String get levelKey => 'severity';

  @override
  String levelValue(LogLevel level) => switch (level) {
    LogLevel.trace || LogLevel.debug => 'DEBUG',
    LogLevel.info => 'INFO',
    LogLevel.warning => 'WARNING',
    LogLevel.error => 'ERROR',
    LogLevel.fatal => 'CRITICAL',
  };

  @override
  Set<String> get reservedKeys => const {
    'severity',
    'message',
    'timestamp',
    'logger',
    'data',
    'error',
    'stackTrace',
  };
}
