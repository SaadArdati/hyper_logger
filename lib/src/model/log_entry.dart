import 'package:logging/logging.dart' as logging;

import 'log_level.dart';
import 'log_message.dart';

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

  /// The scope tag from `LoggerOptions.tag`, if a [ScopedLogger] with a
  /// non-null tag emitted this record.
  ///
  /// Round-9 audit fix (M14/L13): previously the tag was only baked
  /// into the `message` string as `[tag] message`, which meant
  /// interceptors and custom printers had to parse the prefix back
  /// out. The tag is now also surfaced as its own field so consumers
  /// can match on it programmatically.
  ///
  /// `message` still includes the `[tag] ` prefix for backwards
  /// compatibility with existing printer formatters; this field
  /// duplicates the value for cleaner consumption.
  final String? tag;

  const LogEntry({
    required this.level,
    required this.message,
    this.object,
    required this.loggerName,
    required this.time,
    this.error,
    this.stackTrace,
    this.tag,
  });

  /// Creates a [LogEntry] from a [logging.LogRecord].
  ///
  /// Timestamp source, in order of preference:
  /// 1. `LogMessage.time` — set by [HyperLogger] at the emit site, in
  ///    the caller's zone, so test-scoped `withClock(...)` is preserved.
  /// 2. `record.time` — set by `package:logging` synchronously inside
  ///    the caller's zone for foreign callers (more accurate than reading
  ///    the clock at listener time, since listeners run in the zone they
  ///    were registered in — typically `init()`'s zone, not the caller's).
  ///
  /// `record.time` is always populated by `package:logging`, so a third
  /// `clock.now()` fallback is unnecessary.
  factory LogEntry.fromLogRecord(logging.LogRecord record) {
    final obj = record.object;
    final emitTime = obj is LogMessage ? obj.time : null;
    final tag = obj is LogMessage ? obj.scopeTag : null;
    return LogEntry(
      level: LogLevel.fromLoggingLevel(record.level),
      message: record.message,
      object: record.object,
      loggerName: record.loggerName,
      time: emitTime ?? record.time,
      error: record.error,
      stackTrace: record.stackTrace,
      tag: tag,
    );
  }
}
