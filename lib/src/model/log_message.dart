/// A single log entry produced by [HyperLogger].
///
/// Carries a mirror of the canonical `LogEntry.message`, optional structured
/// [data], source [type] metadata, an optional [method] name, an optional
/// [callerStackTrace] captured at the call site, and optional [context]
/// key-value pairs that flow from a [ScopedLogger]'s `child(context: ...)`.
/// [reportToCrashReporting] exposes the originating native call's immutable
/// routing hint for custom output policy.
class LogMessage {
  /// A compatibility mirror of the containing `LogEntry.message`.
  ///
  /// Built-in printers use `LogEntry.message` as the canonical value. The
  /// pipeline synchronizes this mirror after each interceptor and sanitizer.
  final String message;

  /// Optional structured payload attached to this log entry.
  final Object? data;

  /// Source [Type] metadata for compatibility and custom tooling.
  ///
  /// Built-in printers use `LogEntry.loggerName` as the canonical display
  /// name so it remains transformable by interceptors and sanitizers.
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
  /// Capturing at emit time preserves the caller's zone so
  /// `withClock(...)`-driven tests see the fake time end-to-end.
  ///
  /// Direct construction caveat: if you build a [LogMessage]
  /// yourself (custom printers, tests) and want `withClock(...)` to
  /// flow through, set `time:` to `clock.now()` at the call site.
  /// Otherwise [LogEntry.fromLogRecord] falls back to `record.time`
  /// (real wall clock at the `package:logging` emit time), which is
  /// not affected by `withClock(...)`.
  final DateTime? time;

  /// The tag from `LoggerOptions.tag` if this entry came through a
  /// tagged [ScopedLogger]. Exposed so interceptors can match on it
  /// programmatically without parsing the `[tag] ` prefix back out
  /// of [message].
  final String? scopeTag;

  /// Whether the originating native call requested crash-reporting dispatch.
  ///
  /// Custom printers can use this immutable metadata to align alert routing
  /// with `skipCrashReporting`. The value mirrors the routing decision made by
  /// `HyperLogger`; changing it in an interceptor or constructing a message
  /// directly does not itself invoke or suppress the crash-reporting delegate.
  final bool reportToCrashReporting;

  const LogMessage(
    this.message,
    this.type, {
    this.data,
    this.method,
    this.callerStackTrace,
    this.context,
    this.time,
    this.scopeTag,
    this.reportToCrashReporting = false,
  });

  /// Returns a transformed message while preserving every omitted field.
  ///
  /// Nullable fields use callbacks so `() => null` can explicitly clear a
  /// value while an omitted callback retains the existing value.
  LogMessage copyWith({
    String? message,
    Type? type,
    Object? Function()? data,
    String? Function()? method,
    StackTrace? Function()? callerStackTrace,
    Map<String, Object?>? Function()? context,
    DateTime? Function()? time,
    String? Function()? scopeTag,
    bool? reportToCrashReporting,
  }) => LogMessage(
    message ?? this.message,
    type ?? this.type,
    data: data == null ? this.data : data(),
    method: method == null ? this.method : method(),
    callerStackTrace: callerStackTrace == null
        ? this.callerStackTrace
        : callerStackTrace(),
    context: context == null ? this.context : context(),
    time: time == null ? this.time : time(),
    scopeTag: scopeTag == null ? this.scopeTag : scopeTag(),
    reportToCrashReporting:
        reportToCrashReporting ?? this.reportToCrashReporting,
  );

  @override
  String toString() => message;
}
