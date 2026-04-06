import 'package:logging/logging.dart' as logging;

import 'log_level.dart';

/// A structured log record that flows through the printer pipeline.
///
/// This is hyper_logger's own record type, decoupling the public API from
/// the `logging` package's [logging.LogRecord]. Created internally from
/// [logging.LogRecord] in [HyperLogger._handleLogRecord].
class LogEntry {
  /// The severity level of this record.
  final LogLevel level;

  /// The formatted log message string.
  final String message;

  /// The structured payload object. When the log call originated from
  /// HyperLogger, this is a [LogMessage] instance.
  final Object? object;

  /// The name of the logger that produced this record (typically the
  /// stringified type parameter from the log call).
  final String loggerName;

  /// When this record was created.
  final DateTime time;

  /// The error object attached to this record, if any.
  final Object? error;

  /// The stack trace attached to this record, if any.
  final StackTrace? stackTrace;

  const LogEntry({
    required this.level,
    required this.message,
    this.object,
    required this.loggerName,
    required this.time,
    this.error,
    this.stackTrace,
  });

  /// Creates a [LogEntry] from a [logging.LogRecord].
  factory LogEntry.fromLogRecord(logging.LogRecord record) => LogEntry(
    level: LogLevel.fromLoggingLevel(record.level),
    message: record.message,
    object: record.object,
    loggerName: record.loggerName,
    time: record.time,
    error: record.error,
    stackTrace: record.stackTrace,
  );
}
