import 'dart:convert';

import '../model/log_entry.dart';
import '../model/log_level.dart';
import '../model/log_message.dart';
import 'log_printer.dart';

/// A [LogPrinter] that emits one JSON object per log record, compatible with
/// Google Cloud Logging / Cloud Run structured logging.
///
/// Each line is a self-contained JSON object. [format] returns that line (and
/// nothing else) as a single-element [List<String>] for testability, keeping
/// the contract consistent with [ComposablePrinter.format].
///
/// ### Level → severity mapping
/// | LogLevel   | Cloud Logging severity |
/// |------------|------------------------|
/// | trace/debug| DEBUG                  |
/// | info       | INFO                   |
/// | warning    | WARNING                |
/// | error      | ERROR                  |
/// | fatal      | CRITICAL               |
class JsonPrinter implements LogPrinter {
  /// Sink for formatted output. Defaults to [print].
  final LogOutput output;

  const JsonPrinter({this.output = print});

  @override
  void log(LogEntry entry) {
    final lines = format(entry);
    for (int i = 0; i < lines.length; i++) {
      output(lines[i]);
    }
  }

  /// Formats [entry] into a list of output lines (always exactly one line).
  List<String> format(LogEntry entry) {
    final map = <String, Object?>{};

    map['severity'] = _severity(entry.level);

    final object = entry.object;
    if (object is LogMessage) {
      map['message'] = object.message;
      final data = object.data;
      if (data != null) {
        map['data'] = data;
      }
    } else {
      map['message'] = entry.message;
    }

    map['timestamp'] = entry.time.toUtc().toIso8601String();
    map['logger'] = entry.loggerName;

    final error = entry.error;
    if (error != null) {
      map['error'] = error.toString();
    }

    final stackTrace = entry.stackTrace;
    if (stackTrace != null) {
      map['stackTrace'] = stackTrace.toString();
    }

    final encoder = JsonEncoder((o) => o.toString());
    return [encoder.convert(map)];
  }

  /// Maps a [LogLevel] to its Cloud Logging severity string.
  static String _severity(LogLevel level) => switch (level) {
    LogLevel.trace || LogLevel.debug => 'DEBUG',
    LogLevel.info => 'INFO',
    LogLevel.warning => 'WARNING',
    LogLevel.error => 'ERROR',
    LogLevel.fatal => 'CRITICAL',
  };
}
