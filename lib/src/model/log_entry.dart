import 'package:logging/logging.dart' as logging;

import 'log_level.dart';
import 'log_message.dart';

/// A structured log record that flows through the printer pipeline.
///
/// Native calls construct this hyper_logger-owned type directly. The explicit
/// [LogEntry.fromLogRecord] adapter exposes [logging.LogRecord] for inbound
/// `package:logging` integrations; the printer pipeline uses [LogEntry] after
/// that conversion.
class LogEntry {
  /// The severity level of this record.
  final LogLevel level;

  /// The canonical human-readable message used by every built-in printer.
  ///
  /// [LogMessage.message] mirrors this value for compatibility and structured
  /// payload access, but interceptors and sanitizers should transform this
  /// field. HyperLogger synchronizes the mirror after every pipeline stage.
  final String message;

  /// The structured payload object. When the log call originated from
  /// HyperLogger, this is a [LogMessage] instance.
  final Object? object;

  /// The canonical logger name used by every built-in printer (typically the
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
  /// Surfaced as its own field so interceptors and custom printers
  /// can match on tag programmatically; [message] still carries the
  /// `[tag] ` prefix so existing printer formatters that read `message`
  /// directly keep working.
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

  /// Returns a transformed entry while preserving every omitted field.
  ///
  /// Nullable fields use callbacks so `() => null` can explicitly clear a
  /// value while an omitted callback retains the existing value.
  LogEntry copyWith({
    LogLevel? level,
    String? message,
    Object? Function()? object,
    String? loggerName,
    DateTime? time,
    Object? Function()? error,
    StackTrace? Function()? stackTrace,
    String? Function()? tag,
  }) => LogEntry(
    level: level ?? this.level,
    message: message ?? this.message,
    object: object == null ? this.object : object(),
    loggerName: loggerName ?? this.loggerName,
    time: time ?? this.time,
    error: error == null ? this.error : error(),
    stackTrace: stackTrace == null ? this.stackTrace : stackTrace(),
    tag: tag == null ? this.tag : tag(),
  );

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
