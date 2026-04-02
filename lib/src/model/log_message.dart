/// A single log entry produced by [HyperLogger].
///
/// Carries the raw [message] string, optional structured [data], the [type]
/// of the caller (for prefixing), an optional [method] name, and an optional
/// [callerStackTrace] captured at the call site.
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

  const LogMessage(
    this.message,
    this.type, {
    this.data,
    this.method,
    this.callerStackTrace,
  });

  @override
  String toString() => message;
}
