/// A single log entry produced by [HyperLogger].
///
/// Carries the raw [message] string, optional structured [data], the [type]
/// of the caller (for prefixing), an optional [method] name, an optional
/// [callerStackTrace] captured at the call site, and optional [context]
/// key-value pairs that flow from a [ScopedLogger]'s `child(context: ...)`.
class LogMessage {
  /// The primary human-readable log text.
  final String message;

  /// Optional structured payload attached to this log entry.
  final Object? data;

  /// The [Type] of the object that emitted this log entry.
  final Type type;

  /// Optional method name where the log was emitted.
  final String? method;

  /// Optional stack trace captured at the call site.
  final StackTrace? callerStackTrace;

  /// Contextual key-value pairs that travel with the entry.
  ///
  /// Populated by `ScopedLogger.child(context: ...)` for request-scoped
  /// logging — fields like `requestId` or `userId` that should appear on
  /// every log line within a unit of work without restating them per call.
  ///
  /// Cloud-shaped printers ([GcpJsonPrinter], [AwsJsonPrinter]) merge these
  /// into the JSON root so log aggregators can correlate by them. Other
  /// printers may render them inline or ignore them.
  final Map<String, Object?>? context;

  /// Timestamp captured at the call site (via `clock.now()` in the
  /// caller's zone). Set by [HyperLogger]'s static methods.
  ///
  /// Captured at emit time rather than at listener time because
  /// `package:logging` listeners run in the zone where they were
  /// registered — typically `init()`, which is outside any test's
  /// `withClock(...)` zone. Capturing here preserves the caller's zone
  /// so `withClock(...)`-driven tests see the fake time end-to-end.
  ///
  /// Direct construction caveat: if you build a [LogMessage]
  /// yourself (custom printers, tests) and want `withClock(...)` to
  /// flow through, set `time:` to `clock.now()` at the call site.
  /// Otherwise [LogEntry.fromLogRecord] falls back to `record.time`
  /// (real wall clock at the `package:logging` emit time), which is
  /// not affected by `withClock(...)`.
  final DateTime? time;

  /// The tag from `LoggerOptions.tag` if this entry came through a
  /// tagged [ScopedLogger]. Round-9 audit fix (M14/L13): exposed so
  /// interceptors can match on it programmatically without parsing
  /// the `[tag] ` prefix back out of [message].
  final String? scopeTag;

  const LogMessage(
    this.message,
    this.type, {
    this.data,
    this.method,
    this.callerStackTrace,
    this.context,
    this.time,
    this.scopeTag,
  });

  @override
  String toString() => message;
}
