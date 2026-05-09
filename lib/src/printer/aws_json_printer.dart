import '../model/log_level.dart';
import 'cloud_json_printer_base.dart';

/// A [LogPrinter] that emits one JSON object per log record in a format
/// suited to AWS CloudWatch Logs and AWS Lambda.
///
/// Each line is a self-contained JSON object with a `level` field (rather
/// than GCP's `severity`) and CloudWatch-conventional level names (`WARN`
/// and `FATAL` — matching the native AWS Lambda JSON log format and
/// SLF4J/Log4j2 conventions). CloudWatch Logs Insights can parse these
/// fields directly: `fields @timestamp, level, message`.
///
/// > Note: AWS Lambda Powertools (a separate AWS-published library) uses
/// > Python's `WARNING`/`CRITICAL`. We match the native Lambda runtime
/// > log format instead, which is the more common convention across AWS
/// > services. If you need Powertools-style names, copy this class and
/// > swap the [levelValue] mapping.
///
/// ### Reserved-key precedence
///
/// The fields `level`, `message`, `timestamp`, `logger`, `data`, `error`,
/// and `stackTrace` are reserved — these are written by hyper_logger
/// itself. Context entries with any of these names are silently dropped
/// during formatting so an accidental `context: {'level': 'BUG'}`
/// cannot break a CloudWatch Insights query. (The drop is silent rather
/// than logged so the hot path doesn't recurse — set `onError` on the
/// surrounding printer if you want a signal.)
///
/// ### Anything else flows through context
///
/// User-supplied context fields are written at the JSON root, where
/// CloudWatch Logs Insights auto-discovers them. Use this for
/// `requestId`, `traceId`, `userId`, etc. — they become first-class
/// fields you can query with Insights.
///
/// ### CloudWatch error visibility
///
/// For severity `ERROR` and `FATAL`, when both an `error` and a
/// `stackTrace` are attached to the entry, the stack trace is also
/// embedded in the `message` field. CloudWatch's text search and Error
/// Insights work on the `message` content, so this makes exceptions
/// show up without extra setup.
///
/// ### Level → level string mapping
/// | LogLevel | CloudWatch level |
/// |----------|------------------|
/// | trace    | TRACE            |
/// | debug    | DEBUG            |
/// | info     | INFO             |
/// | warning  | WARN             |
/// | error    | ERROR            |
/// | fatal    | FATAL            |
///
/// For Google Cloud Logging see `GcpJsonPrinter`; for Azure Application
/// Insights see `AzureJsonPrinter`.
class AwsJsonPrinter extends CloudJsonPrinterBase {
  const AwsJsonPrinter({super.output});

  @override
  String get levelKey => 'level';

  @override
  String levelValue(LogLevel level) => switch (level) {
    LogLevel.trace => 'TRACE',
    LogLevel.debug => 'DEBUG',
    LogLevel.info => 'INFO',
    LogLevel.warning => 'WARN',
    LogLevel.error => 'ERROR',
    LogLevel.fatal => 'FATAL',
  };

  @override
  Set<String> get reservedKeys => const {
    'level',
    'message',
    'timestamp',
    'logger',
    'data',
    'error',
    'stackTrace',
  };
}
