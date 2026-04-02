import 'dart:convert';

import 'package:logging/logging.dart' as logging;

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
/// | dart:logging level   | Cloud Logging severity |
/// |----------------------|------------------------|
/// | FINEST / FINE        | DEBUG                  |
/// | INFO                 | INFO                   |
/// | WARNING              | WARNING                |
/// | SEVERE               | ERROR                  |
/// | SHOUT                | CRITICAL               |
///
/// ### Structured payload
/// When the [logging.LogRecord.object] is a [LogMessage] its [LogMessage.data]
/// field (if present) is merged into the top-level JSON object under the key
/// `"data"`. The [LogMessage.message] overrides [logging.LogRecord.message].
class JsonPrinter implements LogPrinter {
  /// Sink for formatted output. Defaults to [print].
  final void Function(String) output;

  const JsonPrinter({this.output = print});

  @override
  void log(logging.LogRecord record) {
    final lines = format(record);
    for (int i = 0; i < lines.length; i++) {
      output(lines[i]);
    }
  }

  /// Formats [record] into a list of output lines (always exactly one line).
  ///
  /// Returns a single JSON string per invocation.
  List<String> format(logging.LogRecord record) {
    final map = <String, Object?>{};

    // severity — Cloud Logging structured log field.
    map['severity'] = _severity(record.level);

    // message
    final object = record.object;
    if (object is LogMessage) {
      map['message'] = object.message;
      // structured data merged at top level under "data" key
      final data = object.data;
      if (data != null) {
        map['data'] = data;
      }
    } else {
      map['message'] = record.message;
    }

    // timestamp — ISO-8601 UTC
    map['timestamp'] = record.time.toUtc().toIso8601String();

    // logger name
    map['logger'] = record.loggerName;

    // optional error
    final error = record.error;
    if (error != null) {
      map['error'] = error.toString();
    }

    // optional stack trace
    final stackTrace = record.stackTrace;
    if (stackTrace != null) {
      map['stackTrace'] = stackTrace.toString();
    }

    final encoder = JsonEncoder((o) => o.toString());
    return [encoder.convert(map)];
  }

  /// Maps a [logging.Level] to its Cloud Logging severity string.
  static String _severity(logging.Level level) {
    if (level.value <= logging.Level.FINE.value) return 'DEBUG';
    if (level == logging.Level.INFO) return 'INFO';
    if (level == logging.Level.WARNING) return 'WARNING';
    if (level == logging.Level.SEVERE) return 'ERROR';
    // SHOUT and anything above
    return 'CRITICAL';
  }
}
