import 'dart:convert';

import 'package:meta/meta.dart';

import '../model/log_entry.dart';
import '../model/log_level.dart';
import '../model/log_message.dart';
import 'log_printer.dart';
import 'logger_name_filter.dart';

/// Shared infrastructure for cloud-flavored JSON printers.
///
/// All cloud printers emit one self-contained JSON object per log
/// record. The differences are mostly cosmetic:
///
/// - The level field is named `severity` (GCP), `level` (AWS), or
///   `severityLevel` (Azure) — and Azure's value is numeric while the
///   others are uppercase strings.
/// - User context goes flat at the JSON root (GCP, AWS) or nested
///   under a wrapper key (`customDimensions` for Azure).
/// - Timestamp field names differ (`timestamp` vs Azure's `time`).
///
/// Subclasses configure those points via [levelKey], [levelValue],
/// [reservedKeys], [contextKey], and [timestampKey]. The base class
/// owns the rest of the format (logger-name filtering, error+stack
/// embedding for ERROR/FATAL, JSON encoding, single-line emission).
///
/// Marked [internal]: this is a refactoring base, not a stable
/// extensibility point. Build a custom cloud printer by implementing
/// [LogPrinter] directly if you need a wire format the existing three
/// printers don't cover.
@internal
abstract class CloudJsonPrinterBase implements LogPrinter {
  /// Sink for formatted output. Defaults to [print].
  final LogOutput output;

  const CloudJsonPrinterBase({this.output = print});

  /// JSON key under which the level value is written
  /// (e.g. `'severity'`, `'level'`, `'severityLevel'`).
  String get levelKey;

  /// Value to write under [levelKey] for [level].
  ///
  /// Returns a `String` for GCP/AWS and an `int` for Azure (matching
  /// the Application Insights `severityLevel` enum). Anything JSON-
  /// encodable is acceptable.
  Object levelValue(LogLevel level);

  /// Reserved JSON keys at the root of the emitted object.
  ///
  /// User-supplied context entries whose key collides with one of
  /// these are silently dropped during formatting, so an accidental
  /// `context: {'severity': 'BUG'}` cannot break the cloud parser.
  Set<String> get reservedKeys;

  /// When non-null, user context is nested under this key instead of
  /// being merged at the JSON root.
  ///
  /// GCP and AWS leave context flat at the root (so cloud platforms
  /// auto-discover fields like `traceId` for filtering). Azure puts
  /// context under `customDimensions` to match the Application Insights
  /// data model.
  String? get contextKey => null;

  /// JSON key for the ISO-8601 timestamp.
  ///
  /// Defaults to `'timestamp'` (GCP, AWS). Azure uses `'time'` to match
  /// the AppInsights envelope convention.
  String get timestampKey => 'timestamp';

  /// Single shared encoder. `toEncodable` falls back to `toString()`
  /// for any non-JSON-native value the user passes in `data` or
  /// `context`. Cyclic structures still throw — callers handle that
  /// out-of-band via the surrounding printer's onError.
  static final JsonEncoder _encoder = JsonEncoder((o) => o.toString());

  @override
  void log(LogEntry entry) {
    final lines = format(entry);
    for (int i = 0; i < lines.length; i++) {
      output(lines[i]);
    }
  }

  /// Formats [entry] into a list of output lines (always exactly one
  /// element). The list shape mirrors `ComposablePrinter.format` for
  /// consistency across the printer surface.
  List<String> format(LogEntry entry) => [_formatLine(entry)];

  String _formatLine(LogEntry entry) {
    final map = <String, Object?>{};
    final object = entry.object;

    Map<String, Object?>? userContext;
    if (object is LogMessage) {
      final ctx = object.context;
      if (ctx != null && ctx.isNotEmpty) {
        userContext = <String, Object?>{};
        for (final e in ctx.entries) {
          if (reservedKeys.contains(e.key)) continue;
          userContext[e.key] = e.value;
        }
      }
    }

    // Flat-context strategy (GCP, AWS): merge at root first so the
    // standard fields written below overwrite any collisions.
    final ctxKey = contextKey;
    if (userContext != null && userContext.isNotEmpty && ctxKey == null) {
      map.addAll(userContext);
    }

    // Standard fields.
    map[levelKey] = levelValue(entry.level);
    map[timestampKey] = entry.time.toUtc().toIso8601String();

    // Suppress generic placeholder logger names — when the user calls
    // `HyperLogger.info(...)` without `<T>`, `loggerName` resolves to
    // `'dynamic'` (or `'Object'` / `'Null'`), which surfaces as
    // `"logger":"dynamic"` and looks like the package is broken.
    if (!isGenericLoggerName(entry.loggerName)) {
      map['logger'] = entry.loggerName;
    }

    final error = entry.error;
    final stackTrace = entry.stackTrace;
    final baseMessage = object is LogMessage ? object.message : entry.message;

    // Cloud error tooling (Cloud Error Reporting, CloudWatch Insights,
    // App Insights' search) reads the stack trace out of the `message`
    // field for ERROR/FATAL severity. Embedding it here makes errors
    // discoverable without extra glue. Lower severities keep the bare
    // message; the stack trace is still preserved at root for
    // inspection.
    final isError =
        entry.level == LogLevel.error || entry.level == LogLevel.fatal;
    if (isError && error != null && stackTrace != null) {
      map['message'] = '$baseMessage\n$error\n$stackTrace';
    } else {
      map['message'] = baseMessage;
    }

    if (object is LogMessage) {
      final data = object.data;
      if (data != null) {
        map['data'] = data;
      }
    }

    if (error != null) {
      map['error'] = error.toString();
    }
    if (stackTrace != null) {
      map['stackTrace'] = stackTrace.toString();
    }

    // Nested-context strategy (Azure): apply last so the wrapper key
    // doesn't get overwritten by standard fields.
    if (userContext != null && userContext.isNotEmpty && ctxKey != null) {
      map[ctxKey] = userContext;
    }

    return _encoder.convert(map);
  }

  @override
  void dispose() {
    /* stateless */
  }
}
